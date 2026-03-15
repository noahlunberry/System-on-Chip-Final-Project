// This is the top level compute block for the binary neural net.
module bnn_layer #(
    parameter int PARALLEL_INPUTS = 32,
    parameter int PARALLEL_NEURONS = 32,
    parameter int MANAGER_BUS_WIDTH = 8,
    parameter int TOTAL_INPUTS = 256,
    parameter int OUTPUT_BUS_WIDTH,
    localparam int ACC_WIDTH    = 1 + $clog2(PARALLEL_INPUTS)

) (
    input logic clk,
    input logic rst,

    // Communicate with input side layer
    input  logic [TOTAL_INPUTS-1:0] data_in,
    input  logic                    valid_in,
    output logic                    ready_in,

    // Config Manager Interface
    input  logic [PARALLEL_NEURONS-1:0] config_data,
    input  logic                        config_rd_en,
    input  logic [                15:0] total_bytes,
    input  logic [                 7:0] bytes_per_neuron,
    output logic                        payload_done,

    // Communication with output side layer
    input  logic                        valid_out,
    output logic [OUTPUT_BUS_WIDTH-1:0] data_out,
    output logic                        ready_out


);

  localparam int W_RAM_DATA_W = PARALLEL_INPUTS;  // example: store Pw weights per write
  localparam int W_RAM_ADDR_W = 12;  // example
  localparam int T_RAM_DATA_W = ACC_WIDTH;
  localparam int T_RAM_ADDR_W = 8;  // example

  // Each BRAM has its own write enable and write address, since data is entering serially.
  logic                    w_wr_en   [PARALLEL_NEURONS];
  logic [W_RAM_ADDR_W-1:0] w_wr_addr [PARALLEL_NEURONS];
  logic [W_RAM_DATA_W-1:0] w_wr_data;

  logic                    t_wr_en   [PARALLEL_NEURONS];
  logic [T_RAM_ADDR_W-1:0] t_wr_addr [PARALLEL_NEURONS];
  logic [T_RAM_DATA_W-1:0] t_wr_data;

  // The rd address and enable can be combined into one array, since data is read in parallel
  // They each have their own rd data and rd addresses, since data will be read in parallel
  logic                    w_rd_en;
  logic [W_RAM_ADDR_W-1:0] w_rd_addr;
  logic [W_RAM_DATA_W-1:0] w_rd_data [PARALLEL_NEURONS];

  logic                    t_rd_en;
  logic [T_RAM_ADDR_W-1:0] t_rd_addr;
  logic [T_RAM_DATA_W-1:0] t_rd_data [PARALLEL_NEURONS];

  logic [T_RAM_ADDR_W-1:0] addr_out;
  // inputs from binarization module

  // config controller : communicates with config manager and streams data into the rams
  // send valid in to the neuron processor
  // outputs the enables to write into the BRAMS
  config_controller #(
      .MANAGER_BUS_WIDTH(MANAGER_BUS_WIDTH),
      .PARALLEL_NEURONS(PARALLEL_NEURONS),
      .W_RAM_DATA_W(W_RAM_DATA_W),
      .W_RAM_ADDR_W(W_RAM_ADDR_W),
      .T_RAM_ADDR_W(T_RAM_ADDR_W)
  ) u_cfc (
      .clk(clk),
      .rst(rst),

      .config_rd_en(config_rd_en),
      .msg_type(msg_type),
      .total_bytes(total_bytes),
      .bytes_per_neuron(bytes_per_neuron),
      .payload_done(payload_done),

      // fanout write lanes
      .weight_wr_en(w_wr_en),
      .threshold_wr_en(t_wr_en),
      .addr_out(addr_out)
  );

  logic np_valid;
  logic np_last;

  neuron_controller #(
      .PARALLEL_INPUTS(PARALLEL_INPUTS),
      .PARALLEL_NEURONS(PARALLEL_NEURONS),
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .W_RAM_ADDR_W(W_RAM_ADDR_W),
      .T_RAM_ADDR_W(T_RAM_ADDR_W)
  ) u_nc (
      .clk(clk),
      .rst(rst),
      .go (nc_go),

      .valid_in(np_valid), // from the brams delayed rd_en
      .last(np_last), 
      .layer_done(), // to the buffer

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
          .DATA_WIDTH(W_RAM_DATA_W),
          .ADDR_WIDTH(W_RAM_ADDR_W),
          .REG_RD_DATA(1'b0),
          .WRITE_FIRST(1'b0),
          .STYLE("block")
      ) u_w_ram (
          .clk    (clk),
          .rd_en  (w_rd_en),
          .rd_addr(w_rd_addr),
          .rd_data(w_rd_data[gi]),
          .wr_en  (w_wr_en[gi]),
          .wr_addr(addr_out),
          .wr_data(config_data)
      );

      // Threshold RAM (one per NP)
      ram_sdp #(
          .DATA_WIDTH(ACC_WIDTH),
          .ADDR_WIDTH(T_RAM_ADDR_W),
          .REG_RD_DATA(1'b0),
          .WRITE_FIRST(1'b0),
          .STYLE("block")
      ) u_t_ram (
          .clk    (clk),
          .rd_en  (t_rd_en),
          .rd_addr(t_rd_addr),
          .rd_data(t_rd_data[gi]),
          .wr_en  (t_wr_en[gi]),
          .wr_addr(addr_out),
          .wr_data(config_data)
      );

    end
  endgenerate

  // neuron processors : instantiates and streams data into the neuron processors

  logic [PARALLEL_NEURONS-1:0] np_y;

  logic [ PARALLEL_INPUTS-1:0] x_chunk;  // Pw bits per cycle, broadcast to all NPs
  generate
    for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : gen_nps
      neuron_processor #(
          .P_WIDTH(PARALLEL_INPUTS)
      ) u_np (
          .clk     (clk),
          .rst     (rst),
          .valid_in(np_valid),
          .last    (np_last),
          .x       (x_chunk),
          .w       (w_rd_data[gi]),
          .threshold  (t_rd_data[gi]),
          .y       (np_y[gi])
      );
    end

  endgenerate

  // parallel to serial shift register to buffer the outputs

  // outputs the results for next module


endmodule
;
