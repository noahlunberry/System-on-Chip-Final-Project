// Greg Stitt
// University of Florida

`ifndef _DRIVER_SVH_
`define _DRIVER_SVH_

`include "np_item.svh"

// virtual is a template
virtual class base_driver #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
);
  virtual np_bfm #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) bfm;
  mailbox driver_mailbox;
  event driver_done_event;

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm
  );
    this.bfm       = bfm;
    driver_mailbox = new;
  endfunction  // new

  pure virtual task run();
endclass  // base_driver


class nonblocking_driver #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
) extends base_driver #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm
  );
    super.new(bfm);
  endfunction  // new

  virtual task run();
    np_item #(
        .P_WIDTH(P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) item;
    $display("Time %0t [Driver]: Driver starting.", $time);

    forever begin
      driver_mailbox.get(item);
      bfm.drive_beat(item.x, item.w, item.threshold, item.valid_in, item.last);
      ->driver_done_event;
    end
  endtask
endclass


class blocking_driver #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
) extends base_driver #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm
  );
    super.new(bfm);
  endfunction  // new

  task run();
    np_item #(
        .P_WIDTH(P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) item;
    $display("Time %0t [Driver]: Driver starting.", $time);

    forever begin
      driver_mailbox.get(item);
      bfm.drive_beat(item.x, item.w, item.threshold, item.valid_in, item.last);
      if (item.valid_in && item.last) begin
        bfm.wait_for_done();
        $display("Time %0t [Driver]: Detected done.", $time);
      end
      ->driver_done_event;
    end
  endtask
endclass

`endif
