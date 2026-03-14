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
  logic [ACC_WIDTH-1:0] threshold;
  logic  y;
  localparam int BEATS_PER_TEST = (TOTAL_INPUTS + P_WIDTH - 1) / P_WIDTH;

  int policy_beat_idx;
  int policy_frame_idx;

  // signal when valid output is ready
  task automatic wait_for_done();
    @(posedge clk iff (y_valid == 1'b0));
    @(posedge clk iff (y_valid == 1'b1));
  endtask

  task automatic reset(int cycles);
    rst      <= 1'b1;
    valid_in <= 1'b0;
    last     <= 1'b0;
    x        <= '0;
    w        <= '0;
    threshold <= '0;
    policy_beat_idx = 0;
    policy_frame_idx = 0;
    for (int i = 0; i < cycles; i++) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
    @(posedge clk);
  endtask

  task automatic start(input logic [P_WIDTH-1:0] x_in, input logic [P_WIDTH-1:0] w_in,
                       input logic [ACC_WIDTH-1:0] threshold_in, input logic valid_in_in,
                       input logic last_in);
    x        <= x_in;
    w        <= w_in;
    threshold <= threshold_in;
    valid_in <= valid_in_in;
    last     <= last_in;
    @(posedge clk);
    valid_in <= 1'b0;
    last     <= 1'b0;
  endtask  // start

  function automatic logic [ACC_WIDTH-1:0] threshold_for_frame(input int frame_idx);
    case (frame_idx % 3)
      0: return ACC_WIDTH'(TOTAL_INPUTS / 4);
      1: return ACC_WIDTH'((TOTAL_INPUTS + 1) / 2);
      default: return ACC_WIDTH'((3 * TOTAL_INPUTS) / 4);
    endcase
  endfunction

  // Drives one beat using a deterministic control policy:
  // valid_in=1 every beat, last asserted on final beat of each frame,
  // threshold held constant for all beats in a frame and cycled by frame.
  task automatic start_with_policy(input logic [P_WIDTH-1:0] x_in, input logic [P_WIDTH-1:0] w_in);
    logic [ACC_WIDTH-1:0] threshold_in;
    logic last_in;

    threshold_in = threshold_for_frame(policy_frame_idx);
    last_in      = (policy_beat_idx == BEATS_PER_TEST - 1);

    start(x_in, w_in, threshold_in, 1'b1, last_in);

    if (last_in) begin
      policy_beat_idx = 0;
      policy_frame_idx++;
    end else begin
      policy_beat_idx++;
    end
  endtask

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

endinterface
