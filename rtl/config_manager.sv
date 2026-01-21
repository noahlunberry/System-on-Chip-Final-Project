module config_manager #(
    parameter int CONFIG_BUS_WIDTH = 32,

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
    input  logic                          config_last
);
  // Parser Controler Module
  parser_controller parser_controller (
      .clk (clk),
      .rst (rst),
      .go  (config_valid),
      .data(config_data),
      .done(done_layer)
  );

  // FIFO

  // Counter

  // Address Generator(s)

  // Weight BRAM(s)

endmodule
;
