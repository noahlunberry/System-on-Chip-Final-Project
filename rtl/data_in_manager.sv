// -----------------------------------------------------------------------------
// data_in_manager
// -----------------------------------------------------------------------------
// Converts the AXI image stream into fixed-width binary words for `bnn`.
//
// Flow:
// 1. Compact valid bytes from each accepted beat.
// 2. Count bytes in the current frame.
// 3. Add zero padding after the last real beat so the frame length is a
//    multiple of `PARALLEL_INPUTS`.
// 4. Repack into fixed-width words with `vw_buffer`.
// 5. Binarize each byte and queue the result for the BNN.
//
// `tkeep_byte_compactor` is registered, so `compact_last_r` delays TLAST to
// stay aligned with `compact_*`.
//
// `vw_buffer` has no read handshake, so its output is pushed into an internal
// FIFO. Backpressure is based on that FIFO, with headroom for in-flight words.
module data_in_manager #(
    parameter int INPUT_DATA_WIDTH    = 8,
    parameter int INPUT_BUS_WIDTH     = 64,
    parameter int TOTAL_INPUTS        = 784,
    parameter int PARALLEL_INPUTS     = 8
) (
    input  logic                           clk,
    input  logic                           rst,

    // Match the top-level gating used in bnn_fcc.
    input  logic                           config_ready,
    input  logic                           config_valid,

    // AXI-style image input
    input  logic                           data_in_valid,
    output logic                           data_in_ready,
    input  logic [  INPUT_BUS_WIDTH-1:0]   data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0]   data_in_keep,
    input  logic                           data_in_last,

    // BNN-side flow control
    input  logic                           bnn_ready,
    input  logic                           bnn_en,

    // BNN input
    output logic [PARALLEL_INPUTS-1:0]     bnn_data_in,
    output logic                           bnn_data_in_valid
);

  localparam int INPUT_BUS_BYTES = INPUT_BUS_WIDTH / 8;
  localparam int COUNT_W         = $clog2(INPUT_BUS_BYTES + 1);
  localparam int PAD_W           = (PARALLEL_INPUTS <= 1) ? 1 : $clog2(PARALLEL_INPUTS + 1);
  localparam int FRAME_CNT_W     = $clog2(TOTAL_INPUTS + INPUT_BUS_BYTES + 1);
  localparam int INPUT_BINARIZATION_THRESHOLD = 1 << (INPUT_DATA_WIDTH - 1);

  // Reserve space for words still in flight after upstream throttling starts.
  localparam int BIN_FIFO_DEPTH_LOG2 = 4;

  // Keep room for one word in `vw_buffer`, one in the local pipeline, and one
  // still coming out of the registered compactor.
  localparam int BIN_FIFO_ALM_FULL_THRESH = 3;

  initial begin
    if (BIN_FIFO_DEPTH_LOG2 < 4) begin
      $fatal(1,
             "data_in_manager requires BIN_FIFO_DEPTH_LOG2 to be at least 4, got %0d.",
             BIN_FIFO_DEPTH_LOG2);
    end

    if (BIN_FIFO_ALM_FULL_THRESH < 3) begin
      $fatal(1,
             "data_in_manager requires BIN_FIFO_ALM_FULL_THRESH to be at least 3, got %0d.",
             BIN_FIFO_ALM_FULL_THRESH);
    end

    // The compactor and vw_buffer operate on bytes.
    if (INPUT_DATA_WIDTH != 8) begin
      $fatal(1,
             "data_in_manager currently assumes INPUT_DATA_WIDTH == 8, got %0d.",
             INPUT_DATA_WIDTH);
    end

    // A zero-sized frame would make the padding logic meaningless.
    if (TOTAL_INPUTS <= 0) begin
      $fatal(1, "data_in_manager requires TOTAL_INPUTS to be greater than 0.");
    end
  end


  // Registered compactor output for the previously accepted beat.
  logic                       compact_wr_en;
  logic [INPUT_BUS_WIDTH-1:0] compact_wr_data;
  logic [COUNT_W-1:0]         compact_total_bytes;

  // Delayed TLAST aligned with `compact_*`.
  logic                       compact_last_r;

  // Real bytes seen so far in the current frame.
  logic [FRAME_CNT_W-1:0]     frame_byte_count_r;

  // Padding state after the last real beat.
  logic                       padding_r;
  logic [PAD_W-1:0]           pad_remaining_r;

  // Current frame/padding bookkeeping.
  logic [FRAME_CNT_W-1:0]     frame_total_bytes;
  logic [PAD_W-1:0]           pad_bytes_needed;
  logic [COUNT_W-1:0]         pad_chunk_bytes;

  // Write side of `vw_buffer`.
  logic                       vw_issue_en;
  logic [INPUT_BUS_WIDTH-1:0] vw_issue_data;
  logic [COUNT_W-1:0]         vw_issue_total_bytes;
  logic                       vw_wr_en_r;
  logic [INPUT_BUS_WIDTH-1:0] vw_wr_data_r;
  logic [COUNT_W-1:0]         vw_total_bytes_r;

  // `vw_buffer` output before binarization.
  logic                       vw_rd_en;
  logic [INPUT_BUS_WIDTH-1:0] vw_rd_data;

  // Binary FIFO between packing and the BNN.
  logic [INPUT_BUS_BYTES-1:0]     bin_fifo_wr_data;
  logic [PARALLEL_INPUTS-1:0]     bin_fifo_rd_data;
  logic                           bin_fifo_full;
  logic                           bin_fifo_empty;
  logic                           bin_fifo_alm_full;
  logic                           bin_fifo_rd_en;
  logic                           bin_fifo_data_valid_r;
  logic                           bin_fifo_word_accepted;
  logic                           input_accept;

  assign input_accept = data_in_valid && data_in_ready;


  // The compactor only sees accepted beats, and its output appears one cycle
  // later.
  tkeep_byte_compactor #(
      .INPUT_BUS_WIDTH(INPUT_BUS_WIDTH)
  ) tkeep_byte_compactor_i (
      .clk          (clk),
      .rst          (rst),
      .data_in_valid(input_accept),
      .data_in_data (data_in_data),
      .data_in_keep (data_in_keep),
      .wr_en        (compact_wr_en),
      .wr_data      (compact_wr_data),
      .total_bytes  (compact_total_bytes)
  );

  always_comb begin
    // Frame size after applying the current compacted beat.
    frame_total_bytes = frame_byte_count_r + compact_total_bytes;

    // Zero bytes needed to round the frame up to `PARALLEL_INPUTS`.
    if ((frame_total_bytes % PARALLEL_INPUTS) == 0)
      pad_bytes_needed = '0;
    else
      pad_bytes_needed = PAD_W'(PARALLEL_INPUTS - (frame_total_bytes % PARALLEL_INPUTS));

    // Limit each padding write to one input-bus word.
    if (pad_remaining_r > INPUT_BUS_BYTES)
      pad_chunk_bytes = COUNT_W'(INPUT_BUS_BYTES);
    else
      pad_chunk_bytes = COUNT_W'(pad_remaining_r);
  end

  always_comb begin
    // Default to no write.
    vw_issue_en         = 1'b0;
    vw_issue_data       = '0;
    vw_issue_total_bytes = '0;

    if (padding_r) begin
      // Inject zero bytes while padding. Pause if the binary FIFO is nearly
      // full; locally generated padding can wait.
      if (!bin_fifo_alm_full) begin
        vw_issue_en         = 1'b1;
        vw_issue_data       = '0;
        vw_issue_total_bytes = pad_chunk_bytes;
      end
    end
    else begin
      // Otherwise forward the compacted beat unchanged.
      vw_issue_en         = compact_wr_en;
      vw_issue_data       = compact_wr_data;
      vw_issue_total_bytes = compact_total_bytes;
    end
  end

  // Register the merged real-data/padding stream before `vw_buffer`.
  always_ff @(posedge clk) begin
    if (rst) begin
      vw_wr_en_r       <= 1'b0;
      vw_wr_data_r     <= '0;
      vw_total_bytes_r <= '0;
    end else begin
      vw_wr_en_r       <= vw_issue_en;
      vw_wr_data_r     <= vw_issue_data;
      vw_total_bytes_r <= vw_issue_total_bytes;
    end
  end

  // Accept input only after config is done, while padding is idle, while the
  // FIFO still has headroom, and after the last accepted beat has cleared the
  // registered compactor.
  assign data_in_ready =
      config_ready      &&
      !config_valid   &&
      !bin_fifo_alm_full &&
      !padding_r        &&
      !compact_last_r;

  vw_buffer #(
      .MAX_WR_BYTES(INPUT_BUS_BYTES),
      .RD_BYTES    (INPUT_BUS_BYTES)
  ) vw_buffer_i (
      .clk       (clk),
      .rst       (rst),
      .wr_en     (vw_wr_en_r),
      .wr_data   (vw_wr_data_r),
      .total_bytes(vw_total_bytes_r),
      .rd_en     (vw_rd_en),
      .rd_data   (vw_rd_data)
  );

  always_comb begin
    // Binarize each byte.
    for (int i = 0; i < INPUT_BUS_BYTES; i++) begin
      bin_fifo_wr_data[i] = (vw_rd_data[i*8 +: 8] >= INPUT_BINARIZATION_THRESHOLD);
    end
  end

  fifo_vr #(
      .N(INPUT_BUS_BYTES),
      .M(PARALLEL_INPUTS),
      .P(BIN_FIFO_DEPTH_LOG2),
      .FWFT(1'b0),
      .ALM_FULL_THRESH(BIN_FIFO_ALM_FULL_THRESH),
      .ALM_EMPTY_THRESH(0)
  ) bin_fifo (
      .clk             (clk),
      .rst             (rst),
      .wr_en           (vw_rd_en),
      .wr_data         (bin_fifo_wr_data),
      .rd_en           (bin_fifo_rd_en),
      .rd_data         (bin_fifo_rd_data),
      .alm_full        (bin_fifo_alm_full),
      .alm_empty       (),
      .full            (bin_fifo_full),
      .empty           (bin_fifo_empty)
  );

  // Hold FIFO output valid until the BNN accepts it.
  assign bin_fifo_word_accepted = bin_fifo_data_valid_r && bnn_ready && bnn_en;
  assign bin_fifo_rd_en = !bin_fifo_empty && (!bin_fifo_data_valid_r || bin_fifo_word_accepted);

  assign bnn_data_in       = bin_fifo_rd_data;
  assign bnn_data_in_valid = bin_fifo_data_valid_r && bnn_en;

  always_ff @(posedge clk) begin
    if (rst) begin
      compact_last_r     <= 1'b0;
      frame_byte_count_r <= '0;
      padding_r          <= 1'b0;
      pad_remaining_r    <= '0;
      bin_fifo_data_valid_r <= 1'b0;
    end
    else begin
      if (bin_fifo_rd_en) begin
        bin_fifo_data_valid_r <= 1'b1;
      end
      else if (bin_fifo_word_accepted) begin
        bin_fifo_data_valid_r <= 1'b0;
      end

      // Delay TLAST to match the registered compactor output.
      compact_last_r <= input_accept && data_in_last;

      if (padding_r) begin
        // Consume one padding chunk whenever padding can advance.
        if (!bin_fifo_alm_full) begin
          if (pad_remaining_r <= pad_chunk_bytes) begin
            padding_r       <= 1'b0;
            pad_remaining_r <= '0;
          end
          else begin
            pad_remaining_r <= pad_remaining_r - pad_chunk_bytes;
          end
        end
      end
      else if (compact_wr_en) begin
        if (compact_last_r) begin
          // Last real beat of the frame: either start padding or finish.
          frame_byte_count_r <= '0;

          if (pad_bytes_needed != 0) begin
            padding_r       <= 1'b1;
            pad_remaining_r <= pad_bytes_needed;
          end
        end
        else begin
          // Intermediate beat: keep counting real bytes.
          frame_byte_count_r <= frame_total_bytes;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    // `vw_buffer` has no read handshake, so this should never overflow.
    if (!rst && vw_rd_en) begin
      assert (!bin_fifo_full)
        else $fatal(1,
          "data_in_manager overflow: vw_buffer emitted data while bin_fifo was full.");
    end
  end

endmodule
