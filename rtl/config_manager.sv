module config_manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS = 3,
    parameter int PARALLEL_INPUTS = 8,
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
  logic              msg_type;
  logic [       7:0] layer_id;
  logic [      15:0] layer_inputs;
  logic [      15:0] num_neurons;
  logic [      15:0] bytes_per_neuron;
  logic [      31:0] total_bytes;
  logic              header_done;
  logic [LAYERS-1:0] layer_payload_done;
  logic [LAYERS-1:0] layer_config_done;

  assign weight_ram_wr_data = config_data_in[MAX_PARALLEL_INPUTS-1:0];
  assign threshold_ram_wr_data = config_data_in[THRESHOLD_DATA_WIDTH-1:0];

  // Parser Controler Module
  parser_controller #(
      .CONFIG_BUS_WIDTH(BUS_WIDTH),
      .PARALLEL_INPUTS (PARALLEL_INPUTS),
      .FIFO_RD_WIDTH   (64)
  ) parser_controller (
      .clk             (clk),
      .en              (config_valid),
      .rst             (rst),
      .data            (config_data_in),
      .done            (layer_payload_done),
      .ready           (config_ready),
      .header_done     (header_done),
      .msg_type        (msg_type),
      .layer_id        (layer_id),
      .layer_inputs    (layer_inputs),
      .num_neurons     (num_neurons),
      .bytes_per_neuron(bytes_per_neuron),
      .total_bytes     (total_bytes)
  );

endmodule
