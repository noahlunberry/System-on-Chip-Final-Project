`timescale 1ns / 100ps

module bnn_layer_tb #(
    // DUT configuration
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int MAX_INPUTS = 784,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_NEURONS = 256,
    parameter int TOTAL_INPUTS = 256,
    localparam int W_RAM_ADDR_W = $clog2(
        (TOTAL_NEURONS / PARALLEL_NEURONS) * (TOTAL_INPUTS / PARALLEL_INPUTS) + 1
    ),
    localparam int T_RAM_ADDR_W = $clog2((TOTAL_NEURONS / PARALLEL_NEURONS) + 1),
    localparam int THRESHOLD_DATA_WIDTH = $clog2(MAX_INPUTS + 1),
    localparam int ACC_WIDTH = 1 + $clog2(PARALLEL_INPUTS)
);

  localparam int TOTAL_WEIGHTS = TOTAL_NEURONS * TOTAL_INPUTS;

  // DUT Signals
  logic                            clk = 1'b0;
  logic                            rst;
  logic                            weight_wr_en;
  logic [     PARALLEL_INPUTS-1:0] data_in;
  logic                            valid_in;
  logic                            ready_in;
  logic                            threshold_wr_en;
  logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data;
  logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data;
  logic                            valid_out;
  logic [    PARALLEL_NEURONS-1:0] data_out;
  logic [THRESHOLD_DATA_WIDTH-1:0] count_out         [PARALLEL_NEURONS];

  bnn_layer #(
      .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
      .MAX_INPUTS         (MAX_INPUTS),
      .PARALLEL_INPUTS    (PARALLEL_INPUTS),
      .PARALLEL_NEURONS   (PARALLEL_NEURONS),
      .TOTAL_NEURONS      (TOTAL_NEURONS)
  ) DUT (
      .clk              (clk),
      .rst              (rst),
      .data_in          (data_in),
      .valid_in         (valid_in),
      .ready_in         (ready_in),
      .weight_wr_en     (weight_wr_en),
      .threshold_wr_en  (threshold_wr_en),
      .weight_wr_data   (weight_wr_data),
      .threshold_wr_data(threshold_wr_data),
      .valid_out        (valid_out),
      .data_out         (data_out),
      .count_out        (count_out)
  );



  // Stream in weights/thresholds and verify that data is routed to the correct BRAM/addresses
  initial begin : l_sequencer_and_driver
    $timeformat(-9, 0, " ns", 0);

    rst <= 1'b1;
    

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
    repeat (5) @(posedge clk);
    // Stream in all of the weights and thresholds as if they were already parsed by the configuration manager
    // First, all of the weights 
    $display("[%0t] Streaming weights.", $realtime);
    for (int i = 0; i < TOTAL_WEIGHTS - 1; i++) begin
      weight_wr_en <= 1'b1;

    end
  end



endmodule
