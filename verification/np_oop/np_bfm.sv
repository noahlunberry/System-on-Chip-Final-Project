// Greg Stitt
// University of Florida

// The bfm is an interface that hides low level implementation details from other
// parts of the testbench. It instead places them in methods.
interface np_bfm #(
    parameter int P_WIDTH,
    parameter int TOTAL_INPUTS,
    parameter int ACC_WIDTH
) (
    input logic clk
);
  logic rst, valid_in, last, y_valid;
  logic [P_WIDTH-1:0] x, w;
  logic signed [ACC_WIDTH-1:0] y;

  // signal when valid output is ready
  task automatic wait_for_done();
    @(posedge clk iff (y_valid == 1'b0));
    @(posedge clk iff (y_valid == 1'b1));
  endtask

  task automatic reset(int cycles);
    rst      <= 1'b1;
    valid_in <= 1'b1;
    x        <= '0;
    w        <= '0;
    for (int i = 0; i < cycles; i++) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
    @(posedge clk);
  endtask

  task automatic start(input logic [P_WIDTH-1:0] x, input logic [P_WIDTH-1:0] w);
    x        <= x_;
    w        <= w_;
    valid_in <= 1'b1;
  endtask  // start

  // Helper code to detect when the DUT starts executing. This task internally
  // tracks the active status of the DUT and sends an event every time it
  // becomes active. With this strategy, the implementation specific details
  // are limited to the BFM and are hidden from the testbench.
  event active_event;
  task automatic monitor();
    logic is_active;
    is_active = 1'b0;

    forever begin
      @(posedge clk);
      if (rst) is_active = 1'b0;
      else begin
        if (valid_in) begin
          is_active = 1'b1;
          // The event is needed because there will be times in the
          // simulation where go and done are asserted at the same time.
          // If the code simply used @(posedge is_active) to detect the
          // start of a test, it would miss these instances because 
          // there wouldn't be a rising edge on is_active. It would simply
          // remain active between two consecutive tests.
          ->active_event;
        end
      end
    end
  endtask  // monitor

  localparam int NUM_BEATS = (TOTAL_INPUTS + P_WIDTH - 1) / P_WIDTH;
  int valid_beat_count = 0;

  task automatic drive_beat(input logic [P_WIDTH-1:0] x_in, input logic [P_WIDTH-1:0] w_in,
                            input logic valid_in);
    x        <= x_in;
    w        <= w_in;
    valid_in <= valid_in;

    // We only count this cycle as a "beat" if valid_in is actually high.
    if (valid_in == 1'b1) begin
      valid_beat_count++;

      // If we hit the final valid beat, assert 'last' and reset our counter
      if (valid_beat_count == NUM_BEATS) begin
        last <= 1'b1;
        valid_beat_count = 0;
      end else begin
        last <= 1'b0;
      end

    end else begin
      last <= 1'b0;
    end

    // Consume time so the generator loop can call this sequentially
    @(posedge clk);
  endtask
endinterface
