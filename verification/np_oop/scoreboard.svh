// Greg Stitt
// University of Florida

`ifndef _SCOREBOARD_SVH_
`define _SCOREBOARD_SVH_

`include "np_item.svh"

class scoreboard #(
    int P_WIDTH,
    int TOTAL_INPUTS,
    int ACC_WIDTH
);
  mailbox scoreboard_result_mailbox;
  mailbox scoreboard_data_mailbox;
  int     passed, failed;
  int     acc;
  bit     reference;

  function new(mailbox scoreboard_data_mailbox, mailbox scoreboard_result_mailbox);
    this.scoreboard_data_mailbox   = scoreboard_data_mailbox;
    this.scoreboard_result_mailbox = scoreboard_result_mailbox;

    passed                         = 0;
    failed                         = 0;
    acc                            = 0;
  endfunction

  function int beat_sum(bit [P_WIDTH-1:0] x, bit [P_WIDTH-1:0] w);
    int sum = 0;
    for (int i = 0; i < P_WIDTH; i++) begin
      sum += (x[i] == w[i]);
    end
    return sum;
  endfunction

  function bit model_last_beat(bit [P_WIDTH-1:0] x, bit [P_WIDTH-1:0] w,
                               bit [ACC_WIDTH-1:0] threshold);
    int next_acc;
    next_acc = acc + beat_sum(x, w);
    return (next_acc >= threshold);
  endfunction

  task run(int num_tests);
    np_item #(
        .P_WIDTH(P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) in_item;
    np_item #(
        .P_WIDTH(P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) out_item;

    for (int i = 0; i < num_tests; i++) begin
      do begin
        scoreboard_data_mailbox.get(in_item);
        if (!in_item.valid_in) continue;
        if (in_item.last) begin
          reference = model_last_beat(in_item.x, in_item.w, in_item.threshold);
          acc       = 0;
        end else begin
          acc += beat_sum(in_item.x, in_item.w);
        end
      end while (!(in_item.valid_in && in_item.last));

      scoreboard_result_mailbox.get(out_item);
      if (out_item.y == reference) begin
        $display("Time %0t [Scoreboard] Test passed.", $time);
        passed++;
      end else begin
        $display("Time %0t [Scoreboard] Test failed: y=%0d expected=%0d.", $time, out_item.y, reference);
        failed++;
      end
    end

    while (scoreboard_data_mailbox.try_get(in_item));
    while (scoreboard_result_mailbox.try_get(out_item));
  endtask

  function void report_status();
    $display("Test status: %0d passed, %0d failed", passed, failed);
  endfunction

endclass

`endif
