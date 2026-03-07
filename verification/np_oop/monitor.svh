// Greg Stitt
// University of Florida

`ifndef _MONITOR_SVH_
`define _MONITOR_SVH_

`include "np_item.svh"

virtual class base_monitor #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
);
  virtual np_bfm #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) bfm;

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm
  );
    this.bfm = bfm;
  endfunction  // new

  pure virtual task run();
endclass


class done_monitor #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
) extends base_monitor #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);
  mailbox scoreboard_result_mailbox;

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm,
      mailbox _scoreboard_result_mailbox
  );
    super.new(bfm);
    scoreboard_result_mailbox = _scoreboard_result_mailbox;
  endfunction  // new

  virtual task run();
    $display("Time %0t [Monitor]: Monitor starting.", $time);

    forever begin
      np_item #(
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) item = new;
      bfm.wait_for_done();
      item.y = bfm.y;
      item.y_valid = bfm.y_valid;
      $display("Time %0t [Monitor]: Monitor detected y=%0d.", $time, bfm.y);
      scoreboard_result_mailbox.put(item);
    end
  endtask
endclass


class start_monitor #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
) extends base_monitor #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);
  mailbox scoreboard_data_mailbox;

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm,
      mailbox _scoreboard_data_mailbox
  );
    super.new(bfm);
    scoreboard_data_mailbox = _scoreboard_data_mailbox;
  endfunction  // new

  virtual task run();
    fork
      // Start the BFM monitor to track the active status.
      bfm.monitor();
      detect_start();
    join_any
  endtask

  task detect_start();
    forever begin
      np_item #(
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) item = new;

      // Wait until the DUT becomes active.
      @(bfm.active_event);
      item.x         = bfm.x;
      item.w         = bfm.w;
      item.valid_in  = bfm.valid_in;
      item.last      = bfm.last;
      item.threshold = bfm.threshold;
      $display("Time %0t [start_monitor]: Sending beat x=h%h w=h%h last=%0b.",
               $time, item.x, item.w, item.last);
      scoreboard_data_mailbox.put(item);
    end
  endtask
endclass

`endif
