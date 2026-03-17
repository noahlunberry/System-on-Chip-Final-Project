module config_manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS = 3,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS = 8,
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

  localparam logic INPUT_RD_BYTES = (MAX_PARALLEL_INPUTS) / 8;
  localparam logic THRESH_RD_BYTES = (THRESHOLD_DATA_WIDTH) / 8;
  localparam logic LAYER1_BYTES = (PARALLEL_NEURONS[0]) / 8;
  localparam logic LAYER2_BYTES = (PARALLEL_NEURONS[1]) / 8;

  logic empty;
  logic w_empty;
  logic t_empty;
  assign empty = w_empty && t_empty;

  logic fifo_wr_en_r;
  logic msg_type_r;
  logic [1:0] layer_id_r;
  logic [31:0] total_bytes_r;

  // Parser controller module is responsible for writing vlaid datato the FIFO and communicating with the AXI stream.
  // The FSM parses valid header/payload data from the config stream. Once the entire payload is written, it
  // deasserts valid pausing data until the buffers are empty(all read from the config manager FSM)
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
        // decode message type and layer id to find the correct amount of reads neccessary.
        if (msg_type_r == 0) begin
          case (layer_id_r)
            0: begin
              next_rd_count = (total_bytes_r + INPUT_RD_BYTES - 1) / INPUT_RD_BYTES;
            end
            1: begin
              next_rd_count = (total_bytes_r + LAYER1_BYTES - 1) / LAYER1_BYTES;
            end
            2: begin
              next_rd_count = (total_bytes_r + LAYER2_BYTES - 1) / LAYER2_BYTES;
            end
          endcase
        end else begin
          next_rd_count = (total_bytes_r + THRESH_RD_BYTES - 1) / THRESH_RD_BYTES;
        end

        // Continuously read while the buffer is not empty. Also assert enable for the layer side controller
        // to direct the data to the appropriate BRAMs
        if (!empty) begin
          next_count = count_r + 1'b1;
          next_fifo_rd_en = 1;
          next_ram_wr_en = 1;
          if (count_r == rd_count_r - 1) begin
            next_state = DRAIN;
            next_count = '0;
            next_ram_wr_en = 0;
          end
        end
      end

      DRAIN: begin
        next_fifo_rd_en = 1;
        next_ram_wr_en = 0;
        if (empty) next_state = READ;
      end
    endcase
  end

  logic w_rd_en;
  logic w_wr_en;
  logic t_rd_en;
  logic t_wr_en;

  assign w_rd_en = ram_wr_en_r && !msg_type_r;
  assign t_rd_en = ram_wr_en_r && msg_type_r;
  assign w_wr_en = fifo_wr_en_r && !msg_type_r;
  assign t_wr_en = fifo_wr_en_r && msg_type_r;

  assign weight_ram_wr_en[0] = msg_type_r &&


  fifo_vr #(
      .N(BUS_WIDTH),            // write config_data_in
      .M(MAX_PARALLEL_INPUTS),  // READ config_data_in
      .P(32)                  // DEPTH (calculate later)
  ) fifo_weights (
      .clk            (clk),
      .rst            (rst),
      .rd_en          (w_rd_en),
      .wr_en          (w_wr_en),
      .wr_data        (config_data_in),
      .alm_full_thresh(w_alm_full_thresh),
      .alm_full       (w_alm_full),
      .full           (w_full),
      .empty          (w_empty),
      .rd_data        (weight_ram_wr_data)
  );

  fifo_vr #(
      .N(BUS_WIDTH),            // write config_data_in
      .M(THRESHOLD_DATA_WIDTH),  // READ config_data_in
      .P(32)                  // DEPTH: size of addresses (calculate later)
  ) fifo_thresholds (
      .clk            (clk),
      .rst            (rst),
      .rd_en          (t_rd_en),
      .wr_en          (t_wr_en),
      .wr_data        (config_data_in),
      .alm_full_thresh(t_alm_full_thresh),
      .alm_full       (t_alm_full),
      .full           (t_full),
      .empty          (t_empty),
      .rd_data        (threshold_ram_wr_data)
  );

endmodule
