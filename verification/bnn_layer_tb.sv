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

    logic clk = 1'b0;
    logic rst;
    bnn_layer #(
        .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
        .MAX_INPUTS         (MAX_INPUTS),
        .PARALLEL_INPUTS    (PARALLEL_INPUTS),
        .PARALLEL_NEURONS   (PARALLEL_NEURONS),
        .TOTAL_NEURONS      (TOTAL_NEURONS)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .data_in(),
        .valid_in(),
        .ready_in(),
        .weight_wr_en(),
        .threshold_wr_en(),
        .weight_wr_data(),
        .threshold_wr_data(),
        .valid_out(),
        .data_out(),
        .count_out()
    );


endmodule
