module config_manager #(
    parameter int BUS_WIDTH                    = 64,
    parameter int LAYERS                       = 3,
    parameter int PARALLEL_INPUTS              = 8,
    parameter int PARALLEL_NEURONS    [LAYERS] = '{default: 8},
    parameter int WEIGHT_BYTES_PER_NEURON[LAYERS] = '{default: 1},
    parameter int WEIGHT_BYTES_PER_WORD  [LAYERS] = '{default: 1},
    parameter int WEIGHT_TOTAL_BYTES     [LAYERS] = '{default: 1},
    parameter int THRESHOLD_TOTAL_BYTES  [LAYERS] = '{default: 4},
    parameter int MAX_PARALLEL_INPUTS          = 8,
    parameter int THRESHOLD_DATA_WIDTH         = 32
) (
    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                    config_valid,
    output logic                    config_ready,
    input  logic [    BUS_WIDTH-1:0] config_data_in,
    input  logic [BUS_WIDTH/8-1:0]   config_keep,
    input  logic                    config_last,

    // RAM Write Interfaces
    output logic [ MAX_PARALLEL_INPUTS-1:0] weight_ram_wr_data,
    output logic [              LAYERS-1:0] weight_ram_wr_en,
    output logic [THRESHOLD_DATA_WIDTH-1:0] threshold_ram_wr_data,
    output logic [              LAYERS-1:0] threshold_ram_wr_en
);

  // =========================================================================
  // Local Parameters
  // =========================================================================
  function automatic int get_max_payload_bytes();
    int max_v;
    begin
      max_v = 1;
      for (int i = 0; i < LAYERS; i++) begin
        if (WEIGHT_TOTAL_BYTES[i] > max_v) max_v = WEIGHT_TOTAL_BYTES[i];
        if (THRESHOLD_TOTAL_BYTES[i] > max_v) max_v = THRESHOLD_TOTAL_BYTES[i];
      end
      return max_v;
    end
  endfunction

  localparam int BUS_BYTES = BUS_WIDTH / 8;
  localparam int THRESH_WORD_BYTES = 4;
  localparam int MAX_PAYLOAD_BYTES = get_max_payload_bytes();
  localparam int PAYLOAD_COUNT_W = (MAX_PAYLOAD_BYTES > 1) ? $clog2(MAX_PAYLOAD_BYTES + 1) : 1;
  localparam int CONFIG_BYTE_FIFO_DEPTH_LOG2 = 6;
  localparam int CONFIG_BYTE_FIFO_DEPTH = 1 << CONFIG_BYTE_FIFO_DEPTH_LOG2;
  localparam int CONFIG_BYTE_FIFO_WRITE_CAPACITY = CONFIG_BYTE_FIFO_DEPTH / BUS_BYTES;
  localparam int CONFIG_BYTE_FIFO_INFLIGHT_WRITE_WORDS = 3;
  // After `config_ready` deasserts there can still be up to three whole write
  // words on the way to `fifo_config_bytes`:
  // 1. one word already buffered inside `vw_buffer`,
  // 2. one word sitting in the local write pipeline below, and
  // 3. one more word still emerging from the registered TKEEP compactor.
  //
  // `fifo_vr` tracks fill in bits, not rounded write words, while the parser
  // drains only one byte per cycle. To guarantee those three whole writes still
  // fit after throttling, assert `alm_full` one write slot earlier.
  localparam int CONFIG_BYTE_FIFO_ALM_FULL_THRESH =
      CONFIG_BYTE_FIFO_INFLIGHT_WRITE_WORDS + 1;

  // FIFO sizing
  localparam int WEIGHT_FIFO_DEPTH = 64;
  localparam int THRESH_FIFO_DEPTH = 64;

  // =========================================================================
  // Signal Declarations
  // =========================================================================
  // Parser & Config
  logic empty;
  logic msg_type_r;
  logic [1:0] layer_id_r;
  logic compact_wr_en;
  logic [BUS_WIDTH-1:0] compact_wr_data;
  logic [$clog2(BUS_BYTES+1)-1:0] compact_total_bytes;
  logic                       cfg_vw_wr_en_r;
  logic [BUS_WIDTH-1:0]       cfg_vw_wr_data_r;
  logic [$clog2(BUS_BYTES+1)-1:0] cfg_vw_total_bytes_r;
  logic cfg_byte_rd_en;
  logic cfg_byte_empty;
  logic cfg_byte_alm_full;
  logic cfg_vw_rd_en;
  logic cfg_byte_full;
  logic [BUS_WIDTH-1:0] cfg_vw_rd_data;
  logic [7:0] cfg_byte_data;
  logic payload_byte_valid;
  logic [7:0] payload_byte_data;
  logic payload_start;

  // FIFO Status
  logic w_fifo_empty;
  logic t_fifo_empty;
  logic w_stream_empty;
  logic t_stream_empty;
  logic w_drained;
  logic t_drained;
  logic w_full;
  logic t_full;
  logic w_rd_en;
  logic w_wr_en;
  logic t_rd_en;
  logic t_wr_en;
  logic w_fetch_en;
  logic t_fetch_en;
  logic w_data_valid_r;
  logic t_data_valid_r;

  logic [LAYERS-1:0] packer_empty;
  logic [LAYERS-1:0] packer_has_data;
  logic [LAYERS-1:0] packer_fetch_en;
  logic [LAYERS-1:0] packer_stage_valid_r;
  logic [LAYERS-1:0] packer_fifo_empty;
  logic all_packers_empty;
  logic active_stream_empty;
  logic [LAYERS-1:0] weight_ram_wr_en_r;
  logic [MAX_PARALLEL_INPUTS-1:0] weight_ram_wr_data_r;

  // Control/Data Routing
  logic pad_fsm_in_read_state;
  logic pad_fsm_stall;
  logic buffer_wr_en;
  logic fifo_rd_en;

  logic [7:0] data;
  logic [7:0] w_byte_data;
  logic [31:0] threshold_fifo_rd_data;

  // Register one cycle of weight-byte traffic before writing into the packers.
  // This breaks the long combinational path from fifo_weights_bytes show-ahead
  // data into the downstream packer memories.
  logic packer_wr_valid_r;
  logic [7:0] packer_wr_data_r;
  logic [1:0] packer_wr_layer_r;

  // =========================================================================
  // Combinational Assignments & Top-Level Logic
  // =========================================================================
  assign w_stream_empty      = !w_data_valid_r;
  assign t_stream_empty      = !t_data_valid_r;
  assign w_drained           = !w_data_valid_r && w_fifo_empty;
  assign t_drained           = !t_data_valid_r && t_fifo_empty;
  assign all_packers_empty   = &packer_empty;
  assign active_stream_empty = msg_type_r ? t_stream_empty : w_stream_empty;

  // The config FSM waits for all downstream FIFOs and packers to finish the
  // current message before starting the next one.
  assign empty = w_drained && t_drained && all_packers_empty && !packer_wr_valid_r
                 && !(|weight_ram_wr_en_r)
                 && pad_fsm_in_read_state;
  assign config_ready        = !cfg_byte_alm_full;
  assign weight_ram_wr_en    = weight_ram_wr_en_r;
  assign weight_ram_wr_data  = weight_ram_wr_data_r;

  assign w_rd_en             = fifo_rd_en && !msg_type_r && !w_stream_empty;
  assign t_rd_en             = fifo_rd_en && msg_type_r && !t_stream_empty;
  assign w_wr_en             = payload_byte_valid && !msg_type_r;
  assign t_wr_en             = payload_byte_valid && msg_type_r;
  assign w_fetch_en          = !w_fifo_empty && (!w_data_valid_r || w_rd_en);
  assign t_fetch_en          = !t_fifo_empty && (!t_data_valid_r || t_rd_en);

  // Compact every accepted config beat first so fragmented headers and payload
  // bytes are converted into one contiguous byte stream.
  tkeep_byte_compactor #(
      .INPUT_BUS_WIDTH(BUS_WIDTH)
  ) config_tkeep_byte_compactor_i (
      .clk          (clk),
      .rst          (rst),
      .data_in_valid(config_valid && config_ready),
      .data_in_data (config_data_in),
      .data_in_keep (config_keep),
      .wr_en        (compact_wr_en),
      .wr_data      (compact_wr_data),
      .total_bytes  (compact_total_bytes)
  );

  initial begin
    if ((CONFIG_BYTE_FIFO_DEPTH % BUS_BYTES) != 0) begin
      $fatal(1,
             "config_manager requires CONFIG_BYTE_FIFO_DEPTH (%0d) to be divisible by BUS_BYTES (%0d).",
             CONFIG_BYTE_FIFO_DEPTH, BUS_BYTES);
    end

    if (CONFIG_BYTE_FIFO_WRITE_CAPACITY <= CONFIG_BYTE_FIFO_ALM_FULL_THRESH) begin
      $fatal(1,
             "config_manager requires config byte FIFO write capacity (%0d words) to exceed the almost-full reserve (%0d words).",
             CONFIG_BYTE_FIFO_WRITE_CAPACITY, CONFIG_BYTE_FIFO_ALM_FULL_THRESH);
    end
  end

  // Register one extra write stage before `vw_buffer` so the compactor output
  // does not directly feed the circular-byte write steering cone.
  always_ff @(posedge clk) begin
    if (rst) begin
      cfg_vw_wr_en_r       <= 1'b0;
      cfg_vw_wr_data_r     <= '0;
      cfg_vw_total_bytes_r <= '0;
    end else begin
      cfg_vw_wr_en_r       <= compact_wr_en;
      cfg_vw_wr_data_r     <= compact_wr_data;
      cfg_vw_total_bytes_r <= compact_total_bytes;
    end
  end

  // First repack the compacted stream into full BUS_BYTES chunks. This keeps
  // the variable-size AXI/TKEEP handling localized to the vw_buffer.
  vw_buffer #(
      .MAX_WR_BYTES(BUS_BYTES),
      .RD_BYTES    (BUS_BYTES)
  ) config_vw_buffer_i (
      .clk       (clk),
      .rst       (rst),
      .wr_en     (cfg_vw_wr_en_r),
      .wr_data   (cfg_vw_wr_data_r),
      .total_bytes(cfg_vw_total_bytes_r),
      .rd_en     (cfg_vw_rd_en),
      .rd_data   (cfg_vw_rd_data)
  );

  // Then serialize those full words into bytes for the header/payload parser.
  // Use the non-FWFT mode here so the parser sees a registered byte output
  // instead of the FIFO's internal show-ahead decode cone.
  fifo_vr #(
      .N(BUS_WIDTH),
      .M(8),
      .P(CONFIG_BYTE_FIFO_DEPTH_LOG2),
      .FWFT(1'b0),
      .ALM_FULL_THRESH(CONFIG_BYTE_FIFO_ALM_FULL_THRESH),
      .ALM_EMPTY_THRESH(0)
  ) fifo_config_bytes (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (cfg_byte_rd_en),
      .wr_en           (cfg_vw_rd_en && !cfg_byte_full),
      .wr_data         (cfg_vw_rd_data),
      .alm_full        (cfg_byte_alm_full),
      .alm_empty       (),
      .full            (cfg_byte_full),
      .empty           (cfg_byte_empty),
      .rd_data         (cfg_byte_data)
  );

  // Parse the staged byte stream one byte at a time. This keeps header
  // handling simple while still allowing randomized TKEEP to split headers
  // across arbitrary beat boundaries.
  config_manager_parser #(
      .LAYERS               (LAYERS),
      .PAYLOAD_COUNT_W      (PAYLOAD_COUNT_W),
      .WEIGHT_TOTAL_BYTES   (WEIGHT_TOTAL_BYTES),
      .THRESHOLD_TOTAL_BYTES(THRESHOLD_TOTAL_BYTES)
  ) config_manager_parser_i (
      .clk               (clk),
      .rst               (rst),
      .cfg_byte_valid    (!cfg_byte_empty),
      .cfg_byte_data     (cfg_byte_data),
      .empty             (empty),
      .stall             (pad_fsm_stall),
      .cfg_byte_rd_en    (cfg_byte_rd_en),
      .payload_byte_valid(payload_byte_valid),
      .payload_byte_data (payload_byte_data),
      .msg_type          (msg_type_r),
      .layer_id          (layer_id_r),
      .payload_start     (payload_start)
  );

  // Keep the weight-byte read/drain/pad control isolated from the rest of the
  // datapath so config_manager now just wires the controller to the FIFOs.
  config_manager_pad_fsm #(
      .LAYERS                (LAYERS),
      .PAYLOAD_COUNT_W       (PAYLOAD_COUNT_W),
      .WEIGHT_TOTAL_BYTES    (WEIGHT_TOTAL_BYTES),
      .THRESHOLD_TOTAL_BYTES (THRESHOLD_TOTAL_BYTES),
      .WEIGHT_BYTES_PER_NEURON(WEIGHT_BYTES_PER_NEURON),
      .WEIGHT_BYTES_PER_WORD (WEIGHT_BYTES_PER_WORD)
  ) config_manager_pad_fsm_i (
      .clk               (clk),
      .rst               (rst),
      .payload_start     (payload_start),
      .msg_type          (msg_type_r),
      .layer_id          (layer_id_r),
      .active_stream_empty(active_stream_empty),
      .w_byte_data       (w_byte_data),
      .in_read_state     (pad_fsm_in_read_state),
      .stall             (pad_fsm_stall),
      .fifo_rd_en        (fifo_rd_en),
      .buffer_wr_en      (buffer_wr_en),
      .data              (data)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      packer_wr_valid_r <= 1'b0;
      packer_wr_data_r  <= '0;
      packer_wr_layer_r <= '0;
    end else begin
      packer_wr_valid_r <= buffer_wr_en && !msg_type_r;

      if (buffer_wr_en && !msg_type_r) begin
        packer_wr_data_r  <= data;
        packer_wr_layer_r <= layer_id_r;
      end
    end
  end

  // =========================================================================
  // Datapath & FIFOs
  // =========================================================================

  // Weight bytes already arrive one at a time from the parser, so a regular
  // byte-wide FIFO is enough to decouple parsing from the padding/packer path.
  fifo_vr #(
      .N(8),
      .M(8),
      .P(2),
      .FWFT(1'b0),
      .ALM_FULL_THRESH(0),
      .ALM_EMPTY_THRESH(0)
  ) fifo_weights_bytes (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (w_fetch_en),
      .wr_en           (w_wr_en),
      .wr_data         (payload_byte_data),
      .alm_full        (),
      .alm_empty       (),
      .full            (w_full),
      .empty           (w_fifo_empty),
      .rd_data         (w_byte_data)
  );

  // Packer FIFOs: Unpack bytes into dynamically parameterized output interfaces
  logic [             LAYERS-1:0] packer_rd_en;
  logic [MAX_PARALLEL_INPUTS-1:0] packer_rd_data[LAYERS];

  genvar i;
  generate
    for (i = 0; i < LAYERS; i++) begin : gen_packer
      localparam int LAYER_WIDTH = (i == 0) ? PARALLEL_INPUTS : PARALLEL_NEURONS[i-1];
      logic [LAYER_WIDTH-1:0] packer_layer_data;

      fifo_vr #(
          .N(8),                               // Write byte
          .M(LAYER_WIDTH),                     // Read aligned bus width
          .P(1),  // Depth
          .FWFT(1'b0),
          .ALM_FULL_THRESH(0),
          .ALM_EMPTY_THRESH(0)
      ) fifo_packer (
          .clk             (clk),
          .rst             (rst),
          .rd_en           (packer_fetch_en[i]),
          .wr_en           (packer_wr_valid_r && (packer_wr_layer_r == i)),
          .wr_data         (packer_wr_data_r),
          .alm_full        (),
          .alm_empty       (),
          .full            (),
          .empty           (packer_fifo_empty[i]),
          .rd_data         (packer_layer_data)
      );

      // Pad remainder up to MAX_PARALLEL_INPUTS
      assign packer_rd_data[i] = {{(MAX_PARALLEL_INPUTS - LAYER_WIDTH) {1'b0}}, packer_layer_data};
    end
  endgenerate

  // Threshold bytes also arrive one at a time, so use a fixed-width FIFO that
  // repacks four incoming bytes into one threshold word on the read side.
  fifo_vr #(
      .N(8),
      .M(THRESH_WORD_BYTES * 8),
      .P(2),
      .FWFT(1'b0),
      .ALM_FULL_THRESH(0),
      .ALM_EMPTY_THRESH(0)
  ) fifo_thresholds (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (t_fetch_en),
      .wr_en           (t_wr_en),
      .wr_data         (payload_byte_data),
      .alm_full        (),
      .alm_empty       (),
      .full            (t_full),
      .empty           (t_fifo_empty),
      .rd_data         (threshold_fifo_rd_data)
  );

  assign threshold_ram_wr_data = threshold_fifo_rd_data[THRESHOLD_DATA_WIDTH-1:0];

  // =========================================================================
  // Layer RAM Output Alignment
  // =========================================================================
  always_comb begin
    threshold_ram_wr_en = '0;
    packer_rd_en        = '0;

    // Thresholds output directly controlled by the main FSM
    if (t_rd_en && msg_type_r && (layer_id_r < LAYERS)) begin
      threshold_ram_wr_en[layer_id_r] = 1'b1;
    end

    // Weights automatically drain out of the specific packers when sequences
    // arise. The selected word is registered below before leaving this module.
    for (int j = 0; j < LAYERS; j++) begin
      if (packer_has_data[j] && (layer_id_r == 2'(j))) begin
        packer_rd_en[j] = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      w_data_valid_r       <= 1'b0;
      t_data_valid_r       <= 1'b0;
      packer_stage_valid_r <= '0;
      weight_ram_wr_en_r   <= '0;
      weight_ram_wr_data_r <= '0;
    end else begin
      if (w_fetch_en) begin
        w_data_valid_r <= 1'b1;
      end else if (w_rd_en) begin
        w_data_valid_r <= 1'b0;
      end

      if (t_fetch_en) begin
        t_data_valid_r <= 1'b1;
      end else if (t_rd_en) begin
        t_data_valid_r <= 1'b0;
      end

      for (int j = 0; j < LAYERS; j++) begin
        if (packer_fetch_en[j]) begin
          packer_stage_valid_r[j] <= 1'b1;
        end else if (packer_rd_en[j]) begin
          packer_stage_valid_r[j] <= 1'b0;
        end
      end

      weight_ram_wr_en_r <= '0;

      // Register one more stage at the config_manager output so the long
      // packer -> layer write-data route is cut before it crosses modules.
      for (int j = 0; j < LAYERS; j++) begin
        if (packer_rd_en[j]) begin
          weight_ram_wr_en_r[j] <= 1'b1;
          weight_ram_wr_data_r  <= packer_rd_data[j];
        end
      end

      if (cfg_vw_rd_en) begin
        assert (!cfg_byte_full)
          else $fatal(1,
                      "config_manager overflow: config byte serializer fifo rejected a vw_buffer word.");
      end

      if (w_wr_en) begin
        assert (!w_full)
          else $fatal(1,
                      "config_manager overflow: weight fifo_vr rejected a payload byte.");
      end

      if (t_wr_en) begin
        assert (!t_full)
          else $fatal(1,
                      "config_manager overflow: threshold fifo_vr rejected a payload byte.");
      end
    end
  end

  generate
    for (i = 0; i < LAYERS; i++) begin : gen_packer_stage_ctrl
      assign packer_has_data[i] = packer_stage_valid_r[i];
      assign packer_empty[i] = !packer_stage_valid_r[i] && packer_fifo_empty[i];
      assign packer_fetch_en[i] = !packer_fifo_empty[i] && (!packer_stage_valid_r[i] || packer_rd_en[i]);
    end
  endgenerate

endmodule
