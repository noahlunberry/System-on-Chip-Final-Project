// This is the top level compute block for the binary neural net.
module bnn_layer #(
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int MAX_INPUTS = 784,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_NEURONS = 256,
    parameter int TOTAL_INPUTS = 256,
    parameter int LAST_LAYER = 0,
    localparam int W_RAM_ADDR_W = $clog2(
        (TOTAL_NEURONS / PARALLEL_NEURONS) * (TOTAL_INPUTS / PARALLEL_INPUTS) + 1
    ),
    localparam int T_RAM_ADDR_W = $clog2((TOTAL_NEURONS / PARALLEL_NEURONS) + 1),
    localparam int THRESHOLD_DATA_WIDTH = $clog2(MAX_INPUTS + 1),
    localparam int ACC_WIDTH = 1 + $clog2(PARALLEL_INPUTS)

) (
    input logic clk,
    input logic rst,

    // Communicate with input side layer
    input  logic [PARALLEL_INPUTS-1:0] data_in,
    input  logic                       valid_in,
    output logic                       ready_in,

    // Config Manager Interface
    input logic                            weight_wr_en,
    input logic                            threshold_wr_en,
    input logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data,
    input logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,

    // Communication with output side layer
    output logic                            valid_out,                   // write enable to the output buffer
    output logic [    PARALLEL_NEURONS-1:0] data_out,
    output logic [THRESHOLD_DATA_WIDTH-1:0] count_out[PARALLEL_NEURONS],

    input logic ready_out  // comes from the output buffers not full signal


);

  initial begin
    if (TOTAL_INPUTS % PARALLEL_INPUTS)
      $fatal(1, "layer requires TOTAL_INPUTS to be a multiple of PARRALEL_INPUTS");
  end

  // TOTAL_INPUTS = 832 (padded), but real inputs = MAX_INPUTS (784)
  localparam int REMAINDER = MAX_INPUTS % PARALLEL_INPUTS;  // 784 % 64 = 16
  localparam logic [PARALLEL_INPUTS-1:0] W_PAD_MASK = 
    (REMAINDER == 0) ? '0 : ({PARALLEL_INPUTS{1'b1}} << REMAINDER);



  // Each BRAM has its own write enable and write address, since data is entering serially.
  logic [    PARALLEL_NEURONS-1:0] w_wr_en;
  logic [        W_RAM_ADDR_W-1:0] w_wr_addr;

  logic [    PARALLEL_NEURONS-1:0] t_wr_en;
  logic [        T_RAM_ADDR_W-1:0] t_wr_addr;

  // The rd address and enable can be combined into one array, since data is read in parallel
  // They each have their own rd data and rd addresses, since data will be read in parallel
  logic                            w_rd_en;
  logic [        W_RAM_ADDR_W-1:0] w_rd_addr;
  logic [     PARALLEL_INPUTS-1:0] w_rd_data       [PARALLEL_NEURONS];

  logic                            t_rd_en;
  logic [        T_RAM_ADDR_W-1:0] t_rd_addr;
  logic [THRESHOLD_DATA_WIDTH-1:0] t_rd_data       [PARALLEL_NEURONS];

  // Input buffer signals
  logic [     PARALLEL_INPUTS-1:0] buffer_rd_data;
  logic                            buffer_empty;
  logic                            buffer_full;
  logic                            buffer_not_full;

  logic                            config_done;

  assign ready_in = config_done && buffer_not_full && ready_out;


  localparam int REUSE_CYCLES = TOTAL_NEURONS / PARALLEL_NEURONS;
  localparam int REPLAY_WIDTH = TOTAL_INPUTS / PARALLEL_INPUTS;

  replay_buffer #(
      .ELEMENT_WIDTH(PARALLEL_INPUTS),
      .NUM_ELEMENTS (REPLAY_WIDTH),
      .REUSE_CYCLES (REUSE_CYCLES)
  ) u_input_buffer (
      .clk     (clk),
      .rst     (rst),
      .wr_en   (valid_in),
      .rd_en   (w_rd_en),
      .wr_data (data_in),
      .rd_data (buffer_rd_data),
      .empty   (buffer_empty),
      .not_full(buffer_not_full),
      .full    (buffer_full)
  );


  // config controller : communicates with config manager and streams data into the rams
  // send valid in to the neuron processor
  // outputs the enables to write into the BRAMS

  config_controller #(
      .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
      .PARALLEL_NEURONS   (PARALLEL_NEURONS),
      .TOTAL_NEURONS      (TOTAL_NEURONS),
      .TOTAL_INPUTS       (TOTAL_INPUTS),
      .T_RAM_DATA_W       (THRESHOLD_DATA_WIDTH),
      .W_RAM_ADDR_W       (W_RAM_ADDR_W),
      .T_RAM_ADDR_W       (T_RAM_ADDR_W),
      .LAST_LAYER         (LAST_LAYER)
  ) u_cfc (
      .clk(clk),
      .rst(rst),

      .weight_wr_en   (weight_wr_en),
      .threshold_wr_en(threshold_wr_en),

      .ram_weight_wr_en   (w_wr_en),
      .ram_threshold_wr_en(t_wr_en),
      .weight_addr_out    (w_wr_addr),
      .threshold_addr_out (t_wr_addr),
      .done               (config_done),
      .w_last_addr        (w_last_addr)
  );

  // Padded weight data - only affects the last word per neuron
  logic [MAX_PARALLEL_INPUTS-1:0] padded_weight_wr_data;
  assign padded_weight_wr_data = w_last_addr
    ? (weight_wr_data[PARALLEL_INPUTS-1:0] | W_PAD_MASK)
    : weight_wr_data[PARALLEL_INPUTS-1:0];

  logic np_valid;
  logic np_last;
  logic valid_data;
  // Only begin producing new data if downstream interface is ready
  assign valid_data = buffer_full && ready_out;

  neuron_controller #(
      .PARALLEL_INPUTS (PARALLEL_INPUTS),
      .PARALLEL_NEURONS(PARALLEL_NEURONS),
      .TOTAL_INPUTS    (TOTAL_INPUTS),
      .TOTAL_NEURONS   (TOTAL_NEURONS),
      .W_RAM_ADDR_W    (W_RAM_ADDR_W),
      .T_RAM_ADDR_W    (T_RAM_ADDR_W)
  ) u_nc (
      .clk       (clk),
      .rst       (rst),
      .go        (config_done),
      .valid_data(valid_data),

      // from the brams delayed rd_en, signifies when valid data is ready to enter the NPs
      .valid_in  (np_valid),
      .last      (np_last),
      .layer_done(),          // to the buffer

      // fanout read lanes
      .weight_rd_en  (w_rd_en),
      .weight_rd_addr(w_rd_addr),

      .threshold_rd_en  (t_rd_en),
      .threshold_rd_addr(t_rd_addr)
  );


  genvar gi;
  generate
    for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : gen_np_mems

      // Weights RAM (one per NP)
      ram_sdp #(
          .DATA_WIDTH (MAX_PARALLEL_INPUTS),
          .ADDR_WIDTH (W_RAM_ADDR_W),
          .REG_RD_DATA(1'b0),
          .WRITE_FIRST(1'b0),
          .STYLE      ("block")
      ) u_w_ram (
          .clk    (clk),
          .rd_en  (w_rd_en),
          .rd_addr(w_rd_addr),
          .rd_data(w_rd_data[gi]),
          .wr_en  (w_wr_en[gi]),
          .wr_addr(w_wr_addr),
          .wr_data(padded_weight_wr_data)
      );

      // Threshold RAM (one per NP)
      ram_sdp #(
          .DATA_WIDTH (THRESHOLD_DATA_WIDTH),
          .ADDR_WIDTH (T_RAM_ADDR_W),
          .REG_RD_DATA(1'b0),
          .WRITE_FIRST(1'b0),
          .STYLE      ("block")
      ) u_t_ram (
          .clk    (clk),
          .rd_en  (t_rd_en),
          .rd_addr(t_rd_addr),
          .rd_data(t_rd_data[gi]),
          .wr_en  (t_wr_en[gi]),
          .wr_addr(t_wr_addr),
          .wr_data(threshold_wr_data)
      );

    end
  endgenerate

  // neuron processors : instantiates and streams data into the neuron processors

  logic [PARALLEL_NEURONS-1:0] np_y;
  logic [PARALLEL_NEURONS-1:0] y_valid;
  assign data_out  = np_y;
  assign valid_out = y_valid[0];

  generate
    for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : gen_nps
      neuron_processor #(
          .P_WIDTH        (PARALLEL_INPUTS),
          .THRESHOLD_WIDTH(THRESHOLD_DATA_WIDTH)
      ) u_np (
          .clk      (clk),
          .rst      (rst),
          .valid_in (np_valid),
          .last     (np_last),
          .x        (buffer_rd_data),
          .w        (w_rd_data[gi]),
          .threshold(t_rd_data[gi]),
          .y        (np_y[gi]),
          .count_out(count_out[gi]),
          .y_valid  (y_valid[gi])
      );
    end

  endgenerate
endmodule

