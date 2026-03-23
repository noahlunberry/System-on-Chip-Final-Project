module config_manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS = 3,
    parameter int PARALLEL_INPUTS = 64,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS = 64,
    parameter int THRESHOLD_DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                 config_valid,
    output logic                 config_ready,
    input  logic [BUS_WIDTH-1:0] config_data_in,
    input  logic                 config_keep,
    input  logic                 config_last,

    output logic [ MAX_PARALLEL_INPUTS-1:0] weight_ram_wr_data,
    output logic [              LAYERS-1:0] weight_ram_wr_en,
    output logic [THRESHOLD_DATA_WIDTH-1:0] threshold_ram_wr_data,
    output logic [              LAYERS-1:0] threshold_ram_wr_en

);

  // Per-layer read widths: layer 0 reads PARALLEL_INPUTS bits,
  // subsequent layers read PARALLEL_NEURONS[i-1] bits (output of previous layer).
  function automatic int get_layer_rd_width(int layer_idx);
    if (layer_idx == 0) return PARALLEL_INPUTS;
    else return PARALLEL_NEURONS[layer_idx-1];
  endfunction

  // Bytes per FIFO read for each layer's weight data
  localparam int LAYER_RD_BYTES[LAYERS] = '{
      0: get_layer_rd_width(0) / 8,
      1: get_layer_rd_width(1) / 8,
      2: get_layer_rd_width(2) / 8,
      default: 1
  };

  localparam int THRESH_RD_BYTES = (THRESHOLD_DATA_WIDTH) / 8;

  logic empty;
  logic w_empty;
  logic t_empty;
  assign empty = w_empty && t_empty;

  logic fifo_wr_en_r;
  logic msg_type_r;
  logic [1:0] layer_id_r;
  logic [31:0] total_bytes_r;

  // Parser controller module is responsible for writing valid data to the FIFO and communicating with the AXI stream.
  // The FSM parses valid header/payload data from the config stream. Once the entire payload is written, it
  // deasserts valid pausing data until the buffers are empty (all read from the config manager FSM)
  parser_controller #(
      .CONFIG_BUS_WIDTH(BUS_WIDTH)
  ) parser_controller (
      .clk        (clk),
      .valid      (config_valid),
      .rst        (rst),
      .data       (config_data_in),
      .empty      (empty),
      .ready      (config_ready),
      .wr_en      (fifo_wr_en_r),
      .msg_type   (msg_type_r),
      .layer_id   (layer_id_r),
      .total_bytes(total_bytes_r)
  );

  // Manager controller. Controls reading from the FIFO to the config controller within the layers
  // FSM is in the read state when the FIFO is not empty, it continuously reads until all valid
  // bytes of the payload are read into the layer BRAMs. Then moves to the drain state, where the buffer
  // is read until empty, re-enabling the parser controller to assert valid and take new data from the
  // configuration stream.

  typedef enum logic [0:0] {
    READ,
    DRAIN
  } state_t;
  state_t state_r, next_state;
  logic [31:0] rd_count_r, next_rd_count;
  logic [31:0] count_r, next_count;
  logic ram_wr_en_r, next_ram_wr_en;
  logic fifo_rd_en_r, next_fifo_rd_en;

  always_ff @(posedge clk) begin
    state_r      <= next_state;
    rd_count_r   <= next_rd_count;
    count_r      <= next_count;
    ram_wr_en_r  <= next_ram_wr_en;
    fifo_rd_en_r <= next_fifo_rd_en;
    if (rst) begin
      state_r      <= READ;
      rd_count_r   <= '0;
      count_r      <= '0;
      ram_wr_en_r  <= 0;
      fifo_rd_en_r <= 0;
    end
  end

  always_comb begin
    next_state      = state_r;
    next_rd_count   = rd_count_r;
    next_count      = count_r;
    next_ram_wr_en  = ram_wr_en_r;
    next_fifo_rd_en = fifo_rd_en_r;

    case (state_r)
      READ: begin
        // decode message type and layer id to find the correct amount of reads necessary.
        if (msg_type_r == 0) begin
          // Use per-layer read width to calculate number of FIFO reads
          case (layer_id_r)
            0: next_rd_count = (total_bytes_r + LAYER_RD_BYTES[0] - 1) / LAYER_RD_BYTES[0];
            1: next_rd_count = (total_bytes_r + LAYER_RD_BYTES[1] - 1) / LAYER_RD_BYTES[1];
            2: next_rd_count = (total_bytes_r + LAYER_RD_BYTES[2] - 1) / LAYER_RD_BYTES[2];
            default: next_rd_count = total_bytes_r;
          endcase
        end else begin
          next_rd_count = (total_bytes_r) / 4;
        end

        // Continuously read while the buffer is not empty. Also assert enable for the layer side controller
        // to direct the data to the appropriate BRAMs
        if (!empty) begin
          next_count = count_r + 1'b1;
          next_fifo_rd_en = 1;
          next_ram_wr_en = 1;
          if (count_r == rd_count_r) begin
            next_state = DRAIN;
            next_count = '0;
          end
        end else begin
          next_fifo_rd_en = 0;
          next_ram_wr_en  = 0;
        end
      end

      DRAIN: begin
        next_fifo_rd_en = 1;
        next_ram_wr_en  = 0;
        if (empty) next_state = READ;
      end
    endcase
  end

  // ── Per-layer weight FIFO read enables and data ──────────────────────────
  logic w_rd_en;
  logic w_wr_en;
  logic t_rd_en;
  logic t_wr_en;

  assign w_rd_en = fifo_rd_en_r && !msg_type_r && !empty;
  assign t_rd_en = fifo_rd_en_r && msg_type_r && !empty;
  assign w_wr_en = fifo_wr_en_r && !msg_type_r;
  assign t_wr_en = fifo_wr_en_r && msg_type_r;

  // Per-layer weight FIFO write enables (route based on layer_id)
  logic [LAYERS-1:0] w_fifo_wr_en;
  logic [LAYERS-1:0] w_fifo_rd_en;
  logic [LAYERS-1:0] w_fifo_empty;

  always_comb begin
    w_fifo_wr_en = '0;
    w_fifo_rd_en = '0;
    if (layer_id_r < LAYERS) begin
      w_fifo_wr_en[layer_id_r] = w_wr_en;
      w_fifo_rd_en[layer_id_r] = w_rd_en;
    end
  end

  // Combined weight empty: only the active layer's FIFO matters
  always_comb begin
    w_empty = 1'b1;
    if (layer_id_r < LAYERS) begin
      w_empty = w_fifo_empty[layer_id_r];
    end
  end

  always_comb begin
    weight_ram_wr_en    = '0;
    threshold_ram_wr_en = '0;

    // !empty signal essential to guard edge case where fifo is emptying, and no valid data is being produced
    if (ram_wr_en_r && (layer_id_r < LAYERS) && !empty) begin
      if (msg_type_r) threshold_ram_wr_en[layer_id_r] = 1'b1;
      else weight_ram_wr_en[layer_id_r] = 1'b1;
    end
  end

  // ── Per-layer weight FIFOs ───────────────────────────────────────────────
  // Each FIFO writes at BUS_WIDTH and reads at the layer's PARALLEL_INPUTS width.
  // The read data is zero-extended to MAX_PARALLEL_INPUTS for the shared output bus.

  logic [MAX_PARALLEL_INPUTS-1:0] w_fifo_rd_data[LAYERS];

  // Layer 0: reads at PARALLEL_INPUTS width (e.g. 64)
  localparam int L0_RD_W = get_layer_rd_width(0);
  logic [L0_RD_W-1:0] w_fifo_rd_data_l0;

  fifo_vr #(
      .N(BUS_WIDTH),
      .M(L0_RD_W),
      .P(17)
  ) fifo_weights_l0 (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (w_fifo_rd_en[0]),
      .wr_en           (w_fifo_wr_en[0]),
      .wr_data         (config_data_in),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (),
      .empty           (w_fifo_empty[0]),
      .rd_data         (w_fifo_rd_data_l0)
  );
  assign w_fifo_rd_data[0] = {{(MAX_PARALLEL_INPUTS - L0_RD_W) {1'b0}}, w_fifo_rd_data_l0};

  // Layer 1: reads at PARALLEL_NEURONS[0] width (e.g. 32)
  localparam int L1_RD_W = get_layer_rd_width(1);
  logic [L1_RD_W-1:0] w_fifo_rd_data_l1;

  fifo_vr #(
      .N(BUS_WIDTH),
      .M(L1_RD_W),
      .P(17)
  ) fifo_weights_l1 (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (w_fifo_rd_en[1]),
      .wr_en           (w_fifo_wr_en[1]),
      .wr_data         (config_data_in),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (),
      .empty           (w_fifo_empty[1]),
      .rd_data         (w_fifo_rd_data_l1)
  );
  assign w_fifo_rd_data[1] = {{(MAX_PARALLEL_INPUTS - L1_RD_W) {1'b0}}, w_fifo_rd_data_l1};

  // Layer 2: reads at PARALLEL_NEURONS[1] width (e.g. 8)
  localparam int L2_RD_W = get_layer_rd_width(2);
  logic [L2_RD_W-1:0] w_fifo_rd_data_l2;

  fifo_vr #(
      .N(BUS_WIDTH),
      .M(L2_RD_W),
      .P(17)
  ) fifo_weights_l2 (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (w_fifo_rd_en[2]),
      .wr_en           (w_fifo_wr_en[2]),
      .wr_data         (config_data_in),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (),
      .empty           (w_fifo_empty[2]),
      .rd_data         (w_fifo_rd_data_l2)
  );
  assign w_fifo_rd_data[2] = {{(MAX_PARALLEL_INPUTS - L2_RD_W) {1'b0}}, w_fifo_rd_data_l2};

  // Mux weight data output based on active layer
  always_comb begin
    weight_ram_wr_data = '0;
    if (layer_id_r < LAYERS) begin
      weight_ram_wr_data = w_fifo_rd_data[layer_id_r];
    end
  end

  // ── Threshold FIFO (shared across all layers, always 32-bit read) ──────
  logic [31:0] threshold_fifo_rd_data;

  fifo_vr #(
      .N(BUS_WIDTH),
      .M(32),
      .P(12)
  ) fifo_thresholds (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (t_rd_en),
      .wr_en           (t_wr_en),
      .wr_data         (config_data_in),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (),
      .empty           (t_empty),
      .rd_data         (threshold_fifo_rd_data)
  );

  assign threshold_ram_wr_data = threshold_fifo_rd_data[THRESHOLD_DATA_WIDTH-1:0];

endmodule
