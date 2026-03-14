// Greg Stitt
// University of Florida

`include "test.svh"

module np_tb;

  localparam TOTAL_INPUTS = 788;
  localparam P_WIDTH = 64;
  localparam ACC_WIDTH = 16;

  localparam NUM_RANDOM_TESTS = 1000;
  localparam NUM_CONSECUTIVE_TESTS = 200;
  localparam NUM_REPEATS = 4;
  logic clk;

  np_bfm #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) bfm (
      .clk(clk)
  );

  neuron_processor #(
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) DUT (
      .clk(clk),
      .rst(bfm.rst),
      .valid_in(bfm.valid_in),
      .last(bfm.last),
      .x(bfm.x),
      .w(bfm.w),
      .threshold(bfm.threshold),
      .y(bfm.y),
      .y_valid(bfm.y_valid)
  );

  random_test #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) test_random = new(bfm, "Random Test");

  consecutive_test #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) test_consecutive = new(bfm, "Consecutive Test");

  initial begin : generate_clock
    clk = 1'b0;
    while (1) #5 clk = ~clk;
  end

  initial begin
    $timeformat(-9, 0, " ns");
    // test_random.run(NUM_RANDOM_TESTS, NUM_REPEATS);
    test_consecutive.run(NUM_CONSECUTIVE_TESTS, NUM_REPEATS);
    // test_random.report_status();
    test_consecutive.report_status();
    disable generate_clock;
  end

  assert property (@(posedge bfm.clk) disable iff (bfm.rst) bfm.y_valid |-> $past(bfm.valid_in && bfm.last));

endmodule
