// This module instantiates all of the layers for the binary neural network.
// It is completely parameterized.
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
    output logic ready, // last layer config done

    input logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data,
    input logic [              LAYERS-1:0] weight_wr_en,
    input logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,
    input logic [              LAYERS-1:0] threshold_wr_en,

    input  logic [       MAX_PARALLEL_INPUTS-1:0] data_in,
    input  logic                                  data_in_valid,
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0] data_out,
    output logic [      THRESHOLD_DATA_WIDTH-1:0] count_out     [PARALLEL_NEURONS[LAYERS-1]],
    output logic                                  data_out_valid
);

  // layer 1 -> layer 2 boundary
  logic [PARALLEL_NEURONS[0]-1:0] layer_1_data_out;
  logic                           layer_1_valid_out;
  logic                           layer_1_ready_out;

  // layer 2 -> layer 3 boundary
  logic [PARALLEL_NEURONS[1]-1:0] layer_2_data_out;
  logic                           layer_2_valid_out;
  logic                           layer_2_ready_out;


  bnn_layer #(
      .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
      .PARALLEL_INPUTS    (MAX_PARALLEL_INPUTS),
      .PARALLEL_NEURONS   (PARALLEL_NEURONS[0]),
      .TOTAL_NEURONS      (NUM_NEURONS[0]),
      .TOTAL_INPUTS       (NUM_INPUTS)
  ) u_layer_1 (
      .clk              (clk),
      .rst              (rst),
      .data_in          (data_in),
      .valid_in         (data_in_valid),
      .ready_in         (ready),
      .weight_wr_en     (weight_wr_en[0]),
      .threshold_wr_en  (threshold_wr_en[0]),
      .weight_wr_data   (weight_wr_data),
      .threshold_wr_data(threshold_wr_data),
      .valid_out        (layer_1_valid_out),
      .data_out         (layer_1_data_out),
      .ready_out        (layer_1_ready_out)
  );

  bnn_layer #(
      .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
      .PARALLEL_INPUTS    (PARALLEL_NEURONS[0]),
      .PARALLEL_NEURONS   (PARALLEL_NEURONS[1]),
      .TOTAL_NEURONS      (NUM_NEURONS[1]),
      .TOTAL_INPUTS       (NUM_NEURONS[0])
  ) u_layer_2 (
      .clk              (clk),
      .rst              (rst),
      .data_in          (layer_1_data_out),
      .valid_in         (layer_1_valid_out),
      .ready_in         (layer_1_ready_out),
      .weight_wr_en     (weight_wr_en[1]),
      .threshold_wr_en  (threshold_wr_en[1]),
      .weight_wr_data   (weight_wr_data),
      .threshold_wr_data(threshold_wr_data),
      .valid_out        (layer_2_valid_out),
      .data_out         (layer_2_data_out),
      .ready_out        (layer_2_ready_out)
  );

  bnn_layer #(
      .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
      .PARALLEL_INPUTS    (PARALLEL_NEURONS[1]),
      .PARALLEL_NEURONS   (PARALLEL_NEURONS[2]),
      .TOTAL_NEURONS      (NUM_NEURONS[2]),
      .TOTAL_INPUTS       (NUM_NEURONS[1])
  ) u_layer_3 (
      .clk              (clk),
      .rst              (rst),
      .data_in          (layer_2_data_out),
      .valid_in         (layer_2_valid_out),
      .ready_in         (layer_2_ready_out),
      .weight_wr_en     (weight_wr_en[2]),
      .threshold_wr_en  (threshold_wr_en[2]),
      .weight_wr_data   (weight_wr_data),
      .threshold_wr_data(threshold_wr_data),
      .valid_out        (data_out_valid),
      .data_out         (data_out),
      .ready_out        (1'b1)
  );

endmodule
