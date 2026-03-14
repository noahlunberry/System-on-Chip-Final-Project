// Greg Stitt
// University of Florida

`ifndef _GENERATOR_SVH_
`define _GENERATOR_SVH_

`include "driver.svh"

// -----------------------------------------------------------------
// Base Generator
// -----------------------------------------------------------------
virtual class base_generator #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
);
  mailbox driver_mailbox;
  event   driver_done_event;

  // Notice we must update the driver handle to match our new parameters
  function new(
  base_driver#(
  .TOTAL_INPUTS(TOTAL_INPUTS),
  .P_WIDTH     (P_WIDTH),
  .ACC_WIDTH   (ACC_WIDTH)
  ) driver_h);
    this.driver_mailbox    = driver_h.driver_mailbox;
    this.driver_done_event = driver_h.driver_done_event;
  endfunction  // new

  pure virtual task run();
endclass

// Random Generator
class random_generator #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
) extends base_generator #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH     (P_WIDTH),
    .ACC_WIDTH   (ACC_WIDTH)
);

  function new(
  base_driver#(
  .TOTAL_INPUTS(TOTAL_INPUTS),
  .P_WIDTH     (P_WIDTH),
  .ACC_WIDTH   (ACC_WIDTH)
  ) driver_h);
    super.new(driver_h);
  endfunction  // new

  virtual task run();
    np_item #(
        .P_WIDTH  (P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) item;

    bit [P_WIDTH-1:0] x,w = '0;

    forever begin
      item = new;
      if (!item.randomize()) $display("Randomize failed");
      driver_mailbox.put(item);
      @(driver_done_event);
    end
  endtask
endclass

// Consecutive Generator
class consecutive_generator #(
    int TOTAL_INPUTS = 788,
    int P_WIDTH      = 64,
    int ACC_WIDTH    = 16
) extends base_generator #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH     (P_WIDTH),
    .ACC_WIDTH   (ACC_WIDTH)
);

  function new(
  base_driver#(
  .TOTAL_INPUTS(TOTAL_INPUTS),
  .P_WIDTH     (P_WIDTH),
  .ACC_WIDTH   (ACC_WIDTH)
  ) driver_h);
    super.new(driver_h);
  endfunction  // new

  task run();
    np_item #(
        .P_WIDTH  (P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) item;
    bit [P_WIDTH-1:0] x,w = '0;

    forever begin
      item   = new;
      item.x = x;
      item.w = w;
      x++;
      w++;
      driver_mailbox.put(item);
      @(driver_done_event);
    end
  endtask
endclass

`endif
