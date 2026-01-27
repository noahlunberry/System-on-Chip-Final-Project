module config_manager #(
    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int PARALLEL_INPUTS  = 32,

    parameter int TOTAL_LAYERS = 4,  // Includes input, hidden, and output
    parameter int TOPOLOGY[TOTAL_LAYERS] = '{
        0: 784,
        1: 256,
        2: 256,
        3: 10,
        default: 0
    },  // 0: input, TOTAL_LAYERS-1: output

    parameter bit PARALLELIZE_LAYERS = 1'b0,
    parameter int PARALLEL_NEURONS   = 1,
    parameter int PARALLEL_INPUTS    = 32
) (
    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                          config_valid,
    output logic                          config_ready,
    input  logic [  CONFIG_BUS_WIDTH-1:0] config_data,
    input  logic [CONFIG_BUS_WIDTH/8-1:0] config_keep,
    input  logic                          config_last,

    // Layer Arch Interface
    output  logic [PARALLEL_INPUTS-1:0] config_data,
    output  logic                       config_rd_en,
    output  logic [               15:0] total_bytes,
    output  logic [                7:0] bytes_per_neuron,
    input logic                       payload_done

);

  // Parser Controler Module
  parser_controller #(
      .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
      .PARALLEL_INPUTS (PARALLEL_INPUTS),
      .FIFO_RD_WIDTH(64)
  ) parser_controller (
      .clk(clk),
      .en(config_valid),
      .rst(rst),
      .data(config_data),
      .done(done_layer),
      .ready(config_ready),
      .header_done(header_done)
  );

  // FIFO 64 x 8


endmodule
;
