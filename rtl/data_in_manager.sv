// -----------------------------------------------------------------------------
// data_in_manager
// -----------------------------------------------------------------------------
// This module owns the entire "image input stream -> BNN input vector" path
// that sits in front of `bnn`.
//
// High-level flow:
// 1. Accept AXI-style image beats from `bnn_fcc`.
// 2. Pass each accepted beat through the registered `tkeep_byte_compactor` so
//    only valid bytes are kept and packed contiguously.
// 3. Count how many real bytes have arrived for the current image frame.
// 4. After the last real beat, inject zero-valued padding bytes so the total
//    byte count is a multiple of `MAX_PARALLEL_INPUTS`.
// 5. Feed the compacted/padded byte stream into `vw_buffer`, which repacks the
//    variable-size writes into fixed-width `INPUT_BUS_BYTES`-byte words.
// 6. Binarize each emitted byte word into `INPUT_BUS_BYTES` bits.
// 7. Push those fixed-width binary words into an internal `fifo_vr`, which
//    width-converts them into `MAX_PARALLEL_INPUTS`-bit words for the BNN.
// 8. Let the BNN consume from that FIFO, so BNN-side stalls are absorbed by the
//    FIFO instead of feeding directly back into `vw_buffer`.
//
// Important timing detail:
// `tkeep_byte_compactor` is intentionally registered. That means the accepted
// AXI beat and the corresponding compacted output are separated by one cycle.
// This module therefore tracks `data_in_last` in `compact_last_r` so the
// frame-end marker stays aligned with the registered compacted data.
//
// Important contract with `vw_buffer`:
// `vw_buffer` auto-asserts `rd_en` whenever a full output word is buffered.
// Because that interface has no read handshake, this module immediately writes
// each emitted word into an internal FIFO. Upstream backpressure is then based
// on that FIFO's occupancy, with a little headroom reserved for in-flight data
// that may still emerge from the compactor/vw_buffer path after AXI input has
// been throttled.
module data_in_manager #(
    parameter int INPUT_DATA_WIDTH    = 8,
    parameter int INPUT_BUS_WIDTH     = 64,
    parameter int TOTAL_INPUTS        = 784,
    parameter int MAX_PARALLEL_INPUTS = 8
) (
    input  logic                           clk,
    input  logic                           rst,

    // Preserve the same top-level gating style used in bnn_fcc.
    input  logic                           config_ready,
    input  logic                           config_last,

    // AXI-stream-like image input
    input  logic                           data_in_valid,
    output logic                           data_in_ready,
    input  logic [  INPUT_BUS_WIDTH-1:0]   data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0]   data_in_keep,
    input  logic                           data_in_last,

    // Downstream BNN-side control
    input  logic                           bnn_ready,
    input  logic                           bnn_en,

    // To BNN
    output logic [MAX_PARALLEL_INPUTS-1:0] bnn_data_in,
    output logic                           bnn_data_in_valid
);

  localparam int INPUT_BUS_BYTES = INPUT_BUS_WIDTH / 8;
  localparam int COUNT_W         = $clog2(INPUT_BUS_BYTES + 1);
  localparam int PAD_W           = (MAX_PARALLEL_INPUTS <= 1) ? 1 : $clog2(MAX_PARALLEL_INPUTS + 1);
  localparam int FRAME_CNT_W     = $clog2(TOTAL_INPUTS + INPUT_BUS_BYTES + 1);
  localparam int INPUT_BINARIZATION_THRESHOLD = 1 << (INPUT_DATA_WIDTH - 1);

  // Match the original top-level bin FIFO depth.
  localparam int BIN_FIFO_DEPTH_LOG2 = 4;

  // Reserve two FIFO entries so one word already buffered in `vw_buffer` plus
  // one more word caused by the final in-flight compacted beat can still drain
  // safely after AXI input is throttled.
  localparam int BIN_FIFO_ALM_FULL_THRESH = 2;

  initial begin
    // This manager currently assumes byte-granular image inputs because the
    // compactor and vw_buffer path operate in bytes.
    if (INPUT_DATA_WIDTH != 8) begin
      $fatal(1,
             "data_in_manager currently assumes INPUT_DATA_WIDTH == 8, got %0d.",
             INPUT_DATA_WIDTH);
    end

    // TOTAL_INPUTS is used for frame-accounting sanity and to size the frame
    // byte counter. A zero-sized frame would make the padding logic meaningless.
    if (TOTAL_INPUTS <= 0) begin
      $fatal(1, "data_in_manager requires TOTAL_INPUTS to be greater than 0.");
    end
  end


  // Registered outputs of the TKEEP compactor. These correspond to the beat
  // accepted on the previous cycle.
  logic                       compact_wr_en;
  logic [INPUT_BUS_WIDTH-1:0] compact_wr_data;
  logic [COUNT_W-1:0]         compact_total_bytes;

  // `compact_last_r` is the delayed copy of `data_in_last` aligned to the
  // registered compacted outputs above.
  logic                       compact_last_r;

  // Tracks how many real image bytes have been accumulated so far in the
  // current frame, excluding any synthetic zero-padding bytes.
  logic [FRAME_CNT_W-1:0]     frame_byte_count_r;

  // When `padding_r` is high, the manager is no longer consuming upstream AXI
  // beats. Instead, it is writing zero bytes into the vw_buffer until the
  // frame length has been rounded up to a multiple of MAX_PARALLEL_INPUTS.
  logic                       padding_r;
  logic [PAD_W-1:0]           pad_remaining_r;

  // Combinational bookkeeping for the current compacted beat or padding write.
  logic [FRAME_CNT_W-1:0]     frame_total_bytes;
  logic [PAD_W-1:0]           pad_bytes_needed;
  logic [COUNT_W-1:0]         pad_chunk_bytes;

  // Write-side signals into the variable-write / fixed-read buffer.
  logic                       vw_wr_en;
  logic [INPUT_BUS_WIDTH-1:0] vw_wr_data;
  logic [COUNT_W-1:0]         vw_total_bytes;

  // Output word from the vw_buffer before binarization.
  logic                       vw_rd_en;
  logic [INPUT_BUS_WIDTH-1:0] vw_rd_data;

  // Internal binary FIFO signals. This FIFO is the actual elastic boundary
  // between the input packing path and the BNN.
  logic [INPUT_BUS_BYTES-1:0]     bin_fifo_wr_data;
  logic [MAX_PARALLEL_INPUTS-1:0] bin_fifo_rd_data;
  logic                           bin_fifo_full;
  logic                           bin_fifo_empty;
  logic                           bin_fifo_alm_full;
  logic                           input_accept;

  assign input_accept = data_in_valid && data_in_ready;


  // The compactor only sees accepted beats. Because it is registered, its
  // outputs appear one cycle later and are handled below.
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
    // If the current registered compacted beat belongs to this frame, this is
    // what the real frame size would become after accepting it.
    frame_total_bytes = frame_byte_count_r + compact_total_bytes;

    // Compute how many zero bytes must be appended after the last real beat so
    // the vw_buffer can eventually emit full MAX_PARALLEL_INPUTS-byte words.
    if ((frame_total_bytes % MAX_PARALLEL_INPUTS) == 0)
      pad_bytes_needed = '0;
    else
      pad_bytes_needed = PAD_W'(MAX_PARALLEL_INPUTS - (frame_total_bytes % MAX_PARALLEL_INPUTS));

    // Padding may need multiple writes if the upstream bus is wider than the
    // number of bytes still left to inject.
    if (pad_remaining_r > INPUT_BUS_BYTES)
      pad_chunk_bytes = COUNT_W'(INPUT_BUS_BYTES);
    else
      pad_chunk_bytes = COUNT_W'(pad_remaining_r);
  end

  always_comb begin
    // Default to "no write". One of the branches below enables a write either
    // for real compacted data or for synthetic zero-padding.
    vw_wr_en       = 1'b0;
    vw_wr_data     = '0;
    vw_total_bytes = '0;

    if (padding_r) begin
      // While padding, inject a block of zero bytes. These later binarize to 0
      // and behave like padded-off image inputs.
      //
      // Padding writes are paused when the downstream binary FIFO is almost
      // full. Real compacted data cannot be paused at this point, but padding
      // is locally generated and can safely wait.
      if (!bin_fifo_alm_full) begin
        vw_wr_en       = 1'b1;
        vw_wr_data     = '0;
        vw_total_bytes = pad_chunk_bytes;
      end
    end
    else begin
      // Otherwise forward the registered compacted beat unchanged.
      vw_wr_en       = compact_wr_en;
      vw_wr_data     = compact_wr_data;
      vw_total_bytes = compact_total_bytes;
    end
  end

  // Upstream can only send a new beat when:
  // - configuration is complete enough to allow data streaming,
  // - the internal binary FIFO still has enough reserved space,
  // - we are not in the middle of padding,
  // - and we are not sitting on the one-cycle "last beat is in compactor"
  //   bubble where accepting another beat would misalign frames.
  assign data_in_ready =
      config_ready      &&
      config_last       &&
      !bin_fifo_alm_full &&
      !padding_r        &&
      !compact_last_r;

  vw_buffer #(
      .MAX_WR_BYTES(INPUT_BUS_BYTES),
      .RD_BYTES    (INPUT_BUS_BYTES)
  ) vw_buffer_i (
      .clk       (clk),
      .rst       (rst),
      .wr_en     (vw_wr_en),
      .wr_data   (vw_wr_data),
      .total_bytes(vw_total_bytes),
      .rd_en     (vw_rd_en),
      .rd_data   (vw_rd_data)
  );

  always_comb begin
    // Convert each emitted byte to a single binary activation bit. Pixels at or
    // above the threshold map to 1; lower pixels map to 0.
    for (int i = 0; i < INPUT_BUS_BYTES; i++) begin
      bin_fifo_wr_data[i] = (vw_rd_data[i*8 +: 8] >= INPUT_BINARIZATION_THRESHOLD);
    end
  end

  fifo_vr #(
      .N(INPUT_BUS_BYTES),
      .M(MAX_PARALLEL_INPUTS),
      .P(BIN_FIFO_DEPTH_LOG2)
  ) bin_fifo (
      .clk             (clk),
      .rst             (rst),
      .wr_en           (vw_rd_en),
      .wr_data         (bin_fifo_wr_data),
      .rd_en           (!bin_fifo_empty && bnn_ready && bnn_en),
      .rd_data         (bin_fifo_rd_data),
      .alm_full_thresh (BIN_FIFO_ALM_FULL_THRESH),
      .alm_empty_thresh('0),
      .alm_full        (bin_fifo_alm_full),
      .alm_empty       (),
      .full            (bin_fifo_full),
      .empty           (bin_fifo_empty)
  );

  // Preserve the original top-level style: the BNN sees a word whenever the
  // FIFO is non-empty and layer 1 is ready, but the actual dequeue is still
  // gated by bnn_en so output-path backpressure can pause advancement.
  assign bnn_data_in       = bin_fifo_rd_data;
  assign bnn_data_in_valid = !bin_fifo_empty && bnn_ready;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      compact_last_r     <= 1'b0;
      frame_byte_count_r <= '0;
      padding_r          <= 1'b0;
      pad_remaining_r    <= '0;
    end
    else begin
      // Delay TLAST so it lines up with the registered compacted beat. When
      // compact_last_r is 1, compact_* refers to the final real data beat of
      // the current frame.
      compact_last_r <= input_accept && data_in_last;

      if (padding_r) begin
        // Consume one zero-padding chunk each cycle that padding writes are
        // allowed to proceed.
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
          // The current registered compacted beat is the last real beat of the
          // frame, so either enter padding mode or finish the frame cleanly.
          frame_byte_count_r <= '0;

          if (pad_bytes_needed != 0) begin
            padding_r       <= 1'b1;
            pad_remaining_r <= pad_bytes_needed;
          end
        end
        else begin
          // Intermediate real beat: accumulate the number of valid bytes so far.
          frame_byte_count_r <= frame_total_bytes;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    // `vw_buffer` can emit without a handshake, so it must never do so when
    // the downstream FIFO is truly full. If this fires, the reserved headroom
    // above is not sufficient for the actual traffic pattern.
    if (!rst && vw_rd_en) begin
      assert (!bin_fifo_full)
        else $fatal(1,
          "data_in_manager overflow: vw_buffer emitted data while bin_fifo was full.");
    end
  end

endmodule
