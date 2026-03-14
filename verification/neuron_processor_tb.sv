`timescale 1ns / 10ps

module np_tb_no_hierarchy #(
    parameter int NUM_TESTS = 200,
    parameter int TOTAL_INPUTS = 8,
    parameter int P_WIDTH = 8,
    parameter int ACC_WIDTH = 16,
    parameter bit CONSECUTIVE_INPUTS = 1'b1,
    parameter bit WAIT_FOR_DONE_EACH_FRAME = 1'b1,
    parameter int MIN_CYCLES_BETWEEN_FRAMES = 0,
    parameter int MAX_CYCLES_BETWEEN_FRAMES = 0,
    parameter bit LOG_INPUT_MONITOR = 1'b0,
    parameter bit LOG_DONE_MONITOR = 1'b0
);

  localparam int BEATS_PER_TEST = (TOTAL_INPUTS + P_WIDTH - 1) / P_WIDTH;
  localparam int TREE_LATENCY   = 1 + $clog2(P_WIDTH);

  logic clk = 1'b0;
  logic rst, valid_in, last;
  logic [P_WIDTH-1:0] x, w;
  logic [ACC_WIDTH-1:0] threshold;
  logic y, y_valid;

  int passed, failed;

  neuron_processor #(
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) DUT (
      .clk(clk),
      .rst(rst),
      .valid_in(valid_in),
      .last(last),
      .x(x),
      .w(w),
      .threshold(threshold),
      .y(y),
      .y_valid(y_valid)
  );

  mailbox driver_mailbox            = new;
  mailbox scoreboard_data_mailbox   = new;
  mailbox scoreboard_result_mailbox = new;

  class np_item;
    rand bit [P_WIDTH-1:0] x, w;
    bit                    valid_in;
    bit                    last;
    bit [ACC_WIDTH-1:0]    threshold;
    bit                    y, y_valid;
  endclass

  function automatic int beat_sum(bit [P_WIDTH-1:0] x_, bit [P_WIDTH-1:0] w_);
    int sum = 0;
    for (int i = 0; i < P_WIDTH; i++) begin
      sum += (x_[i] == w_[i]);
    end
    return sum;
  endfunction

  function automatic bit model_last_beat(
      bit [P_WIDTH-1:0] x_,
      bit [P_WIDTH-1:0] w_,
      bit [ACC_WIDTH-1:0] threshold_,
      int acc_so_far
  );
    return ((acc_so_far + beat_sum(x_, w_)) >= threshold_);
  endfunction

  function automatic logic [ACC_WIDTH-1:0] threshold_for_frame(input int frame_idx);
    case (frame_idx % 3)
      0:       return ACC_WIDTH'(TOTAL_INPUTS / 4);
      1:       return ACC_WIDTH'((TOTAL_INPUTS + 1) / 2);
      default: return ACC_WIDTH'((3 * TOTAL_INPUTS) / 4);
    endcase
  endfunction

  initial begin : generate_clock
    forever #5 clk <= ~clk;
  end

  initial begin : initialization
    $timeformat(-9, 0, " ns", 0);

    assert (MIN_CYCLES_BETWEEN_FRAMES <= MAX_CYCLES_BETWEEN_FRAMES)
    else $fatal(1, "MIN_CYCLES_BETWEEN_FRAMES must be <= MAX_CYCLES_BETWEEN_FRAMES");

    rst       <= 1'b1;
    valid_in  <= 1'b0;
    last      <= 1'b0;
    x         <= '0;
    w         <= '0;
    threshold <= '0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
  end

  initial begin : generator
    np_item item;
    bit [P_WIDTH-1:0] x_seed = '0;
    bit [P_WIDTH-1:0] w_seed = '0;
    logic [ACC_WIDTH-1:0] frame_threshold;

    for (int test_idx = 0; test_idx < NUM_TESTS; test_idx++) begin
      if (CONSECUTIVE_INPUTS) begin
        frame_threshold = threshold_for_frame(test_idx);
      end else begin
        frame_threshold = ACC_WIDTH'($urandom_range(TOTAL_INPUTS, 0));
      end

      for (int beat_idx = 0; beat_idx < BEATS_PER_TEST; beat_idx++) begin
        item = new();

        if (CONSECUTIVE_INPUTS) begin
          item.x = x_seed;
          item.w = w_seed;
          x_seed++;
          w_seed++;
        end else begin
          assert (item.randomize())
          else $fatal(1, "Failed to randomize np_item");
        end

        item.valid_in  = 1'b1;
        item.last      = (beat_idx == BEATS_PER_TEST - 1);
        item.threshold = frame_threshold;

        driver_mailbox.put(item);
      end
    end
  end

  // This is really a beat monitor, because the scoreboard needs every valid beat.
  initial begin : input_monitor
    np_item item;

    forever begin
      @(posedge clk iff (!rst && valid_in));
      item = new();
      item.x         = x;
      item.w         = w;
      item.valid_in  = valid_in;
      item.last      = last;
      item.threshold = threshold;
      scoreboard_data_mailbox.put(item);

      if (LOG_INPUT_MONITOR) begin
        $display("[%0t] input_monitor: x=%h w=%h threshold=%0d last=%0b",
                 $realtime, x, w, threshold, last);
      end
    end
  end

  initial begin : done_monitor
    np_item item;

    forever begin
      @(posedge clk iff (!rst && y_valid));
      item = new();
      item.y       = y;
      item.y_valid = y_valid;
      scoreboard_result_mailbox.put(item);

      if (LOG_DONE_MONITOR) begin
        $display("[%0t] done_monitor: y=%0b", $realtime, y);
      end
    end
  end

  initial begin : driver
    np_item item;

    @(posedge clk iff !rst);

    forever begin
      driver_mailbox.get(item);

      x         <= item.x;
      w         <= item.w;
      threshold <= item.threshold;
      valid_in  <= item.valid_in;
      last      <= item.last;

      @(posedge clk);
      valid_in <= 1'b0;
      last     <= 1'b0;

      if (WAIT_FOR_DONE_EACH_FRAME && item.valid_in && item.last) begin
        @(posedge clk iff (y_valid == 1'b0));
        @(posedge clk iff (y_valid == 1'b1));
      end

      if (item.valid_in && item.last) begin
        repeat ($urandom_range(MIN_CYCLES_BETWEEN_FRAMES, MAX_CYCLES_BETWEEN_FRAMES)) begin
          @(posedge clk);
        end
      end
    end
  end

  initial begin : scoreboard
    np_item in_item;
    np_item out_item;
    int acc;
    bit reference;

    passed = 0;
    failed = 0;
    acc    = 0;

    for (int test_idx = 0; test_idx < NUM_TESTS; test_idx++) begin
      do begin
        scoreboard_data_mailbox.get(in_item);

        if (!in_item.valid_in) continue;

        if (in_item.last) begin
          reference = model_last_beat(in_item.x, in_item.w, in_item.threshold, acc);
          acc       = 0;
        end else begin
          acc += beat_sum(in_item.x, in_item.w);
        end
      end while (!(in_item.valid_in && in_item.last));

      scoreboard_result_mailbox.get(out_item);

      if (out_item.y == reference) begin
        $display("Time %0t [Scoreboard] Test %0d passed.", $time, test_idx);
        passed++;
      end else begin
        $display("Time %0t [Scoreboard] Test %0d failed: y=%0b expected=%0b.",
                 $time, test_idx, out_item.y, reference);
        failed++;
      end
    end

    $display("Tests completed: %0d passed, %0d failed", passed, failed);
    disable generate_clock;
  end

  // The OOP tb used $past(..., 1), but the DUT delays last/valid by TREE_LATENCY.
  assert property (
    @(posedge clk) disable iff (rst)
    y_valid |-> $past(valid_in && last, TREE_LATENCY)
  );

endmodule
