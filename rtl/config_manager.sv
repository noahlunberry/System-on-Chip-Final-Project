module config_manager #(
    parameter int BUS_WIDTH                    = 64,
    parameter int LAYERS                       = 3,
    parameter int PARALLEL_INPUTS              = 8,
    parameter int PARALLEL_NEURONS    [LAYERS] = '{default: 8},
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
  localparam int BUS_BYTES         = BUS_WIDTH / 8;
  localparam int THRESH_WORD_BYTES = 4;

  // FIFO sizing
  localparam int WEIGHT_FIFO_DEPTH = 64;
  localparam int THRESH_FIFO_DEPTH = 64;

  // =========================================================================
  // Signal Declarations
  // =========================================================================
  // Parser & Config
  logic              parser_ready;
  logic              empty;
  logic              fifo_wr_en_r;
  logic              msg_type_r;
  logic [       1:0] layer_id_r;
  logic [      31:0] total_bytes_r;
  logic [      15:0] bytes_per_neuron_r;
  logic              payload_accept;
  logic              compact_wr_en;
  logic [BUS_WIDTH-1:0] compact_wr_data;
  logic [$clog2(BUS_BYTES+1)-1:0] compact_total_bytes;
  logic              compact_inflight;

  // FIFO Status
  logic              w_empty;
  logic              t_empty;
  logic              w_alm_full;
  logic              t_alm_full;
  logic              w_wr_ready;
  logic              t_wr_ready;
  logic              w_rd_en;
  logic              w_wr_en;
  logic              t_rd_en;
  logic              t_wr_en;

  logic [LAYERS-1:0] packer_empty;
  logic              all_packers_empty;
  logic              active_stream_empty;

  // FSM Control Signals
  typedef enum logic [1:0] {
    READ,
    DRAIN,
    PAD
  } state_t;

  state_t state_r, next_state;

  logic [31:0] rd_count_r, next_rd_count;
  logic [31:0] count_r, next_count;
  logic [8:0] byte_idx_r, next_byte_idx;
  logic [7:0] pad_count_r, next_pad_count;
  logic last_rd_r, next_last_rd;

  logic       buffer_wr_en;
  logic       fifo_rd_en;

  // Data Routing & Padding
  logic [7:0] data;
  logic [7:0] w_byte_data;
  logic [31:0] threshold_fifo_rd_data;
  logic [7:0] bytes_per_word;
  logic [7:0] pad_remainder;
  logic [7:0] bytes_to_pad;
  logic       pad_en;

  // =========================================================================
  // Combinational Assignments & Top-Level Logic
  // =========================================================================
  assign payload_accept     = fifo_wr_en_r;
  assign compact_inflight   = payload_accept || compact_wr_en;
  assign all_packers_empty   = &packer_empty;
  assign active_stream_empty = msg_type_r ? t_empty : w_empty;

  // The config FSM waits for all underlying FIFOs to process their stream and
  // for the one-cycle compactor pipeline to go idle after the final payload beat.
  assign empty               = w_empty && t_empty && all_packers_empty && (state_r == READ)
                             && !compact_inflight;
  assign config_ready        = !w_alm_full && !t_alm_full && parser_ready;

  assign w_rd_en             = fifo_rd_en && !msg_type_r && !w_empty;
  assign t_rd_en             = fifo_rd_en && msg_type_r && !t_empty;
  assign w_wr_en             = compact_wr_en && !msg_type_r;
  assign t_wr_en             = compact_wr_en && msg_type_r;

  // =========================================================================
  // Padding Calculation (Dynamic per-layer)
  // =========================================================================
  always_comb begin
    bytes_per_word = MAX_PARALLEL_INPUTS / 8;  // layer 0 default
    for (int k = 0; k < LAYERS; k++) begin
      if (layer_id_r == 2'(k)) begin
        if (k == 0) bytes_per_word = MAX_PARALLEL_INPUTS / 8;
        else bytes_per_word = PARALLEL_NEURONS[k-1] / 8;
      end
    end
  end

  assign pad_remainder = bytes_per_neuron_r[7:0] & (bytes_per_word - 8'd1);
  assign bytes_to_pad  = (pad_remainder == 0) ? 8'd0 : (bytes_per_word - pad_remainder);
  assign pad_en        = (bytes_to_pad != 0);

  // =========================================================================
  // Configuration Parsing
  // =========================================================================
  parser_controller #(
      .CONFIG_BUS_WIDTH(BUS_WIDTH)
  ) parser_controller_inst (
      .clk             (clk),
      .rst             (rst),
      .valid           (config_valid && config_ready),
      .data            (config_data_in),
      .empty           (empty),
      .payload_count_valid(compact_wr_en),
      .payload_count_bytes(compact_total_bytes),
      .ready           (parser_ready),
      .wr_en           (fifo_wr_en_r),
      .msg_type        (msg_type_r),
      .layer_id        (layer_id_r),
      .total_bytes     (total_bytes_r),
      .bytes_per_neuron(bytes_per_neuron_r)
  );

  // Compact only accepted payload beats so partial final beats respect TKEEP
  // before entering the variable-write FIFOs.
  tkeep_byte_compactor #(
      .INPUT_BUS_WIDTH(BUS_WIDTH)
  ) config_tkeep_byte_compactor_i (
      .clk          (clk),
      .rst          (rst),
      .data_in_valid(payload_accept),
      .data_in_data (config_data_in),
      .data_in_keep (config_keep),
      .wr_en        (compact_wr_en),
      .wr_data      (compact_wr_data),
      .total_bytes  (compact_total_bytes)
  );

  // =========================================================================
  // Control FSM
  // =========================================================================
  always_ff @(posedge clk) begin
    if (rst) begin
      state_r     <= READ;
      rd_count_r  <= '0;
      count_r     <= '0;
      byte_idx_r  <= '0;
      pad_count_r <= '0;
      last_rd_r   <= 1'b0;
    end else begin
      state_r     <= next_state;
      rd_count_r  <= next_rd_count;
      count_r     <= next_count;
      byte_idx_r  <= next_byte_idx;
      pad_count_r <= next_pad_count;
      last_rd_r   <= next_last_rd;
    end
  end

  always_comb begin
    // Default Assignments
    next_state     = state_r;
    next_rd_count  = rd_count_r;
    next_count     = count_r;
    next_byte_idx  = byte_idx_r;
    next_pad_count = pad_count_r;
    next_last_rd   = last_rd_r;

    buffer_wr_en   = 1'b0;
    fifo_rd_en     = 1'b0;
    data           = w_byte_data;  // Use live payload byte dynamically

    case (state_r)
      READ: begin
        // Decode message type to find the correct read count
        if (msg_type_r == 0) begin
          next_rd_count = total_bytes_r;  // bytes for weights
        end else begin
          next_rd_count = total_bytes_r / THRESH_WORD_BYTES;  // 32-bit words for thresholds
        end

        // Give the final scheduled read one cycle to retire before entering
        // DRAIN, so the last byte/word is fully handed off downstream first.
        if (last_rd_r) begin
          next_state   = DRAIN;
          next_last_rd = 1'b0;
        end
        // Continuously read while buffer is not empty
        else if (!active_stream_empty) begin
          next_count   = count_r + 1'b1;
          fifo_rd_en   = 1'b1;
          buffer_wr_en = 1'b1;

          if (msg_type_r == 0) begin
            if (byte_idx_r == (bytes_per_neuron_r - 1)) begin
              next_byte_idx = '0;
              if (pad_en) begin
                next_state = PAD;
              end
            end else begin
              next_byte_idx = byte_idx_r + 1'b1;
            end
          end

          // Trigger exactly on the cycle we schedule the last byte read
          if (next_count == rd_count_r) begin
            next_count   = '0;
            next_last_rd = 1'b1;
          end
        end
      end

      PAD: begin
        // Inject 1's padding sequence (0xFF) to the buffer
        data           = 8'hFF;
        fifo_rd_en     = 1'b0;
        buffer_wr_en   = 1'b1;
        next_pad_count = pad_count_r + 1'b1;

        if (pad_count_r == (bytes_to_pad - 1)) begin
          next_pad_count = '0;
          // After padding the last neuron, drain remaining FIFO data
          if (last_rd_r) begin
            next_state   = DRAIN;
            next_last_rd = 1'b0;
          end else begin
            next_state = READ;
          end
        end
      end

      DRAIN: begin
        fifo_rd_en   = 1'b1;
        buffer_wr_en = 1'b0;
        next_count = '0;
        next_last_rd = '0;
        if (active_stream_empty) begin
          next_state = READ;
        end
      end

      default: next_state = READ;
    endcase
  end

  // =========================================================================
  // Datapath & FIFOs
  // =========================================================================

  // Weight byte FIFO: compact payload bytes are written in variable-length
  // chunks and read back one byte at a time for the existing padding/packer path.
  fifo_vw #(
      .MAX_WR_BYTES(BUS_BYTES),
      .RD_BYTES    (1),
      .N           ($clog2(WEIGHT_FIFO_DEPTH))
  ) fifo_weights_bytes (
      .clk       (clk),
      .rst       (rst),
      .wr_en     (w_wr_en),
      .wr_data   (compact_wr_data),
      .total_bytes(compact_total_bytes),
      .wr_ready  (w_wr_ready),
      .rd_en     (w_rd_en),
      .rd_valid  (),
      .rd_data   (w_byte_data),
      .alm_full  (w_alm_full),
      .full      (),
      .alm_empty (),
      .empty     (w_empty)
  );

  // Packer FIFOs: Unpack bytes into dynamically parameterized output interfaces
  logic [             LAYERS-1:0] packer_rd_en;
  logic [MAX_PARALLEL_INPUTS-1:0] packer_rd_data[LAYERS];

  genvar i;
  generate
    for (i = 0; i < LAYERS; i++) begin : gen_packer
      localparam int LAYER_WIDTH = (i == 0) ? MAX_PARALLEL_INPUTS : PARALLEL_NEURONS[i-1];
      logic [LAYER_WIDTH-1:0] packer_layer_data;

      fifo_vr #(
          .N(8),                               // Write byte
          .M(LAYER_WIDTH),                     // Read aligned bus width
          .P(3)  // Depth
      ) fifo_packer (
          .clk             (clk),
          .rst             (rst),
          .rd_en           (packer_rd_en[i]),
          .wr_en           (buffer_wr_en && !msg_type_r && (layer_id_r == i)),
          .wr_data         (data),
          .alm_full_thresh ('0),
          .alm_empty_thresh('0),
          .alm_full        (),
          .alm_empty       (),
          .full            (),
          .empty           (packer_empty[i]),
          .rd_data         (packer_layer_data)
      );

      // Pad remainder up to MAX_PARALLEL_INPUTS
      assign packer_rd_data[i] = {{(MAX_PARALLEL_INPUTS - LAYER_WIDTH) {1'b0}}, packer_layer_data};
    end
  endgenerate

  // Thresholds FIFO: compact payload bytes are written in variable-length
  // chunks and emitted directly as 32-bit threshold words.
  fifo_vw #(
      .MAX_WR_BYTES(BUS_BYTES),
      .RD_BYTES    (THRESH_WORD_BYTES),
      .N           ($clog2(THRESH_FIFO_DEPTH))
  ) fifo_thresholds (
      .clk       (clk),
      .rst       (rst),
      .wr_en     (t_wr_en),
      .wr_data   (compact_wr_data),
      .total_bytes(compact_total_bytes),
      .wr_ready  (t_wr_ready),
      .rd_en     (t_rd_en),
      .rd_valid  (),
      .rd_data   (threshold_fifo_rd_data),
      .alm_full  (t_alm_full),
      .full      (),
      .alm_empty (),
      .empty     (t_empty)
  );

  assign threshold_ram_wr_data = threshold_fifo_rd_data[THRESHOLD_DATA_WIDTH-1:0];

  // =========================================================================
  // Layer RAM Output Alignment
  // =========================================================================
  always_comb begin
    weight_ram_wr_en    = '0;
    threshold_ram_wr_en = '0;
    packer_rd_en        = '0;
    weight_ram_wr_data  = '0;

    // Thresholds output directly controlled by the main FSM
    if (t_rd_en && msg_type_r && (layer_id_r < LAYERS)) begin
      threshold_ram_wr_en[layer_id_r] = 1'b1;
    end

    // Weights automatically drain out of the specific packers when sequences arise
    for (int j = 0; j < LAYERS; j++) begin
      if (!packer_empty[j] && (layer_id_r == 2'(j))) begin
        packer_rd_en[j]     = 1'b1;
        weight_ram_wr_en[j] = 1'b1;
        weight_ram_wr_data  = packer_rd_data[j];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst && w_wr_en) begin
      assert (w_wr_ready)
        else $fatal(1,
                    "config_manager overflow: weight fifo_vw rejected a compacted payload beat.");
    end

    if (!rst && t_wr_en) begin
      assert (t_wr_ready)
        else $fatal(1,
                    "config_manager overflow: threshold fifo_vw rejected a compacted payload beat.");
    end
  end

endmodule
