module bnn #(
    parameter int LAYERS = 3,
    parameter int NUM_INPUTS = 784,
    parameter int NUM_NEURONS[LAYERS] = '{0: 256, 1: 256, 2: 10, default: 0},
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int THRESHOLD_DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic rst,
    input  logic en,
    output logic ready,

    input logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data,
    input logic [              LAYERS-1:0] weight_wr_en,
    input logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,
    input logic [              LAYERS-1:0] threshold_wr_en,

    input  logic [           PARALLEL_INPUTS-1:0] data_in,
    input  logic                                  data_in_valid,
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0] data_out,
    output logic [      THRESHOLD_DATA_WIDTH-1:0] count_out     [PARALLEL_NEURONS[LAYERS-1]],
    output logic                                  data_out_valid
);

  logic [MAX_PARALLEL_INPUTS-1:0] layer_data_in         [LAYERS];
  logic                           layer_data_in_valid   [LAYERS];
  logic                           layer_ready_in        [LAYERS];

  logic [MAX_PARALLEL_INPUTS-1:0] layer_data_out        [LAYERS];
  logic                           layer_valid_out       [LAYERS];
  logic                           layer_ready_out       [LAYERS];

  logic [MAX_PARALLEL_INPUTS-1:0] layer_config_data     [LAYERS];
  logic                           layer_config_rd_en    [LAYERS];
  logic [                   15:0] layer_total_bytes     [LAYERS];
  logic [                    7:0] layer_bytes_per_neuron[LAYERS];
  logic                           layer_msg_type        [LAYERS];
  logic                           layer_payload_done    [LAYERS];

  genvar gi;
  generate
    for (gi = 0; gi < LAYERS; gi++) begin : gen_layers
      localparam int LAYER_PARALLEL_INPUTS = (gi == 0) ? PARALLEL_INPUTS : PARALLEL_NEURONS[gi-1];
      localparam int LAYER_TOTAL_INPUTS = (gi == 0) ? NUM_INPUTS : NUM_NEURONS[gi-1];

      bnn_layer #(
          .PARALLEL_INPUTS  (LAYER_PARALLEL_INPUTS),
          .PARALLEL_NEURONS (PARALLEL_NEURONS[gi]),
          .MANAGER_BUS_WIDTH(MAX_PARALLEL_INPUTS),
          .TOTAL_INPUTS     (LAYER_TOTAL_INPUTS)
      ) u_bnn_layer (
          .clk             (clk),
          .rst             (rst),
          .data_in         (layer_data_in[gi][LAYER_PARALLEL_INPUTS-1:0]),
          .valid_in        (layer_data_in_valid[gi]),
          .ready_in        (layer_ready_in[gi]),
          .config_data     (layer_config_data[gi][PARALLEL_NEURONS[gi]-1:0]),
          .config_rd_en    (layer_config_rd_en[gi]),
          .total_bytes     (layer_total_bytes[gi]),
          .bytes_per_neuron(layer_bytes_per_neuron[gi]),
          .msg_type        (layer_msg_type[gi]),
          .payload_done    (layer_payload_done[gi]),
          .valid_out       (layer_valid_out[gi]),
          .data_out        (layer_data_out[gi][PARALLEL_NEURONS[gi]-1:0]),
          .ready_out       (layer_ready_out[gi])
      );
    end
  endgenerate

endmodule
