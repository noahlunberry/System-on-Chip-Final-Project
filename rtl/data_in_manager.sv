module data_in_manager #(
    parameter int INPUT_DATA_WIDTH   = 8,
    parameter int INPUT_BUS_WIDTH    = 64,
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int VW_DEPTH_BYTES     = 2 * MAX_PARALLEL_INPUTS
) (
    input  logic                         clk,
    input  logic                         rst,

    // Preserve the same top-level gating style used in bnn_fcc.
    input  logic                         config_ready,
    input  logic                         config_last,

    // AXI-stream-like image input
    input  logic                         data_in_valid,
    output logic                         data_in_ready,
    input  logic [INPUT_BUS_WIDTH-1:0]   data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0] data_in_keep,
    input  logic                         data_in_last,

    // Downstream BNN-side control
    input  logic                         bnn_ready,
    input  logic                         bnn_en,

    // To BNN
    output logic [MAX_PARALLEL_INPUTS-1:0] bnn_data_in,
    output logic                           bnn_data_in_valid
);

  localparam int INPUT_BUS_BYTES = INPUT_BUS_WIDTH / 8;
  localparam int COUNT_W         = $clog2(INPUT_BUS_BYTES + 1);
  localparam int PAD_W           = $clog2(MAX_PARALLEL_INPUTS + 1);
  localparam int FRAME_CNT_W     = $clog2(INPUT_BUS_WIDTH + MAX_PARALLEL_INPUTS + 1);
  localparam int INPUT_BINARIZATION_THRESHOLD = 1 << (INPUT_DATA_WIDTH - 1);

  // --------------------------------------------------------------------------
  // Parameter checks
  // --------------------------------------------------------------------------
  initial begin
    if (INPUT_DATA_WIDTH != 8) begin
      $fatal(1,
             "data_in_manager currently assumes INPUT_DATA_WIDTH == 8, got %0d.",
             INPUT_DATA_WIDTH);
    end
  end

  // --------------------------------------------------------------------------
  // Accepted input beat
  // --------------------------------------------------------------------------
  logic input_accept;

  assign input_accept = data_in_valid && data_in_ready;

  // --------------------------------------------------------------------------
  // Registered compactor outputs
  // --------------------------------------------------------------------------
  logic                         compact_wr_en;
  logic [INPUT_BUS_WIDTH-1:0]   compact_wr_data;
  logic [COUNT_W-1:0]           compact_total_bytes;

  // One-cycle delayed marker aligned with the registered compactor outputs.
  // When this is 1, compact_* corresponds to the last real beat of the frame.
  logic                         compact_last_r;

  tkeep_byte_compactor_reg #(
      .INPUT_BUS_WIDTH(INPUT_BUS_WIDTH)
  ) tkeep_byte_compactor_reg_i (
      .clk        (clk),
      .rst        (rst),
      .data_in_valid(input_accept),
      .data_in_data (data_in_data),
      .data_in_keep (data_in_keep),
      .wr_en      (compact_wr_en),
      .wr_data    (compact_wr_data),
      .total_bytes(compact_total_bytes)
  );

  // --------------------------------------------------------------------------
  // Frame accounting / padding control
  // --------------------------------------------------------------------------
  logic [FRAME_CNT_W-1:0] frame_byte_count_r;

  // padding_r means the manager is currently injecting zero bytes into the
  // vw_buffer to round the frame up to a multiple of MAX_PARALLEL_INPUTS.
  logic                   padding_r;
  logic [PAD_W-1:0]       pad_remaining_r;

  logic [FRAME_CNT_W-1:0] frame_total_bytes;
  logic [PAD_W-1:0]       pad_bytes_needed;
  logic [COUNT_W-1:0]     pad_chunk_bytes;

  always_comb begin
    frame_total_bytes = frame_byte_count_r + compact_total_bytes;

    if ((frame_total_bytes % MAX_PARALLEL_INPUTS) == 0)
      pad_bytes_needed = '0;
    else
      pad_bytes_needed = MAX_PARALLEL_INPUTS - (frame_total_bytes % MAX_PARALLEL_INPUTS);

    if (pad_remaining_r > INPUT_BUS_BYTES)
      pad_chunk_bytes = COUNT_W'(INPUT_BUS_BYTES);
    else
      pad_chunk_bytes = COUNT_W'(pad_remaining_r);
  end

  // --------------------------------------------------------------------------
  // Write mux into vw_buffer
  // --------------------------------------------------------------------------
  logic                       vw_wr_en;
  logic [INPUT_BUS_WIDTH-1:0] vw_wr_data;
  logic [COUNT_W-1:0]         vw_total_bytes;

  always_comb begin
    vw_wr_en      = 1'b0;
    vw_wr_data    = '0;
    vw_total_bytes = '0;

    if (padding_r) begin
      vw_wr_en       = 1'b1;
      vw_wr_data     = '0;
      vw_total_bytes = pad_chunk_bytes;
    end
    else begin
      vw_wr_en       = compact_wr_en;
      vw_wr_data     = compact_wr_data;
      vw_total_bytes = compact_total_bytes;
    end
  end

  // --------------------------------------------------------------------------
  // Upstream ready
  // --------------------------------------------------------------------------
  // Stall the upstream while:
  // - padding is being injected
  // - the accepted last beat is still in the compactor pipeline
  //
  // This mirrors the intent of the original "stall on last beat / pad beats"
  // logic so the next frame cannot sneak in before padding is resolved.
  assign data_in_ready =
      config_ready &&
      config_last  &&
      bnn_en       &&
      !padding_r   &&
      !compact_last_r;

  // --------------------------------------------------------------------------
  // vw_buffer
  // --------------------------------------------------------------------------
  logic                           vw_rd_en;
  logic [MAX_PARALLEL_INPUTS*8-1:0] vw_rd_data;

  vw_buffer #(
      .MAX_WR_BYTES(INPUT_BUS_BYTES),
      .RD_BYTES    (MAX_PARALLEL_INPUTS),
      .DEPTH_BYTES (VW_DEPTH_BYTES)
  ) vw_buffer_i (
      .clk       (clk),
      .rst       (rst),
      .wr_en     (vw_wr_en),
      .wr_data   (vw_wr_data),
      .total_bytes(vw_total_bytes),
      .rd_en     (vw_rd_en),
      .rd_data   (vw_rd_data)
  );

  // --------------------------------------------------------------------------
  // Binarize vw_buffer output bytes into MAX_PARALLEL_INPUTS bits for the BNN
  // --------------------------------------------------------------------------
  always_comb begin
    for (int i = 0; i < MAX_PARALLEL_INPUTS; i++) begin
      bnn_data_in[i] = (vw_rd_data[i*8 +: 8] >= INPUT_BINARIZATION_THRESHOLD);
    end
  end

  // Keep the same "fire when both sides are good" style your old path used.
  assign bnn_data_in_valid = vw_rd_en && bnn_ready && bnn_en;

  // --------------------------------------------------------------------------
  // Sequential control/state
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      compact_last_r     <= 1'b0;
      frame_byte_count_r <= '0;
      padding_r          <= 1'b0;
      pad_remaining_r    <= '0;
    end
    else begin
      // Align the frame-last marker with the registered compactor outputs.
      compact_last_r <= input_accept && data_in_last;

      // Default: hold state unless changed below.
      if (padding_r) begin
        if (pad_remaining_r <= pad_chunk_bytes) begin
          padding_r       <= 1'b0;
          pad_remaining_r <= '0;
        end
        else begin
          pad_remaining_r <= pad_remaining_r - pad_chunk_bytes;
        end
      end
      else if (compact_wr_en) begin
        if (compact_last_r) begin
          frame_byte_count_r <= '0;

          if (pad_bytes_needed != 0) begin
            padding_r       <= 1'b1;
            pad_remaining_r <= pad_bytes_needed;
          end
        end
        else begin
          frame_byte_count_r <= frame_total_bytes;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Assumption check for current vw_buffer semantics
  // --------------------------------------------------------------------------
  // vw_buffer auto-consumes as soon as it has RD_BYTES buffered, so this path
  // only works correctly if the BNN side is ready whenever vw_buffer produces
  // a word.
  always_ff @(posedge clk) begin
    if (!rst && vw_rd_en) begin
      assert (bnn_ready && bnn_en)
        else $fatal(1,
          "data_in_manager requires bnn_ready && bnn_en whenever vw_buffer emits data.");
    end
  end

endmodule