// Greg Stitt
// University of Florida

`ifndef _DRIVER_SVH_
`define _DRIVER_SVH_

`include "np_item.svh"

// virtual is a template
virtual class base_driver #(
    int TOTAL_INPUTS
);
  virtual np_bfm #(.TOTAL_INPUTS(TOTAL_INPUTS)) bfm;
  mailbox driver_mailbox;
  event driver_done_event;

  function new(virtual np_bfm #(.TOTAL_INPUTS(TOTAL_INPUTS)) bfm);
    this.bfm       = bfm;
    driver_mailbox = new;
  endfunction  // new

  pure virtual task run();
endclass  // base_driver


class nonblocking_driver #(
    int TOTAL_INPUTS
) extends base_driver #(
    .TOTAL_INPUTS(TOTAL_INPUTS)
);

  function new(virtual np_bfm #(.TOTAL_INPUTS(TOTAL_INPUTS)) bfm);
    super.new(bfm);
  endfunction  // new

  virtual task run();
    np_item #(.TOTAL_INPUTS(TOTAL_INPUTS)) item;
    $display("Time %0t [Driver]: Driver starting.", $time);

    forever begin
      driver_mailbox.get(item);
      //$display("Time %0t [Driver]: Driving data=h%h, go=%0b.", $time, item.data, item.go);  
      bfm.data = item.data;
      bfm.go   = item.go;
      @(posedge bfm.clk);
      ->driver_done_event;
    end
  endtask
endclass


class blocking_driver #(
    int TOTAL_INPUTS
) extends base_driver #(
    .TOTAL_INPUTS(TOTAL_INPUTS)
);

  function new(virtual np_bfm #(.TOTAL_INPUTS(TOTAL_INPUTS)) bfm);
    super.new(bfm);
  endfunction  // new

  task run();
    np_item #(.TOTAL_INPUTS(TOTAL_INPUTS)) item;
    $display("Time %0t [Driver]: Driver starting.", $time);

    forever begin
      driver_mailbox.get(item);
      bfm.start(item.data);
      bfm.wait_for_done();
      $display("Time %0t [Driver]: Detected done.", $time);
      ->driver_done_event;
    end
  endtask
endclass

`endif
