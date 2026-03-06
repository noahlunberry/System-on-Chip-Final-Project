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
  .P_WIDTH(P_WIDTH),
  .ACC_WIDTH(ACC_WIDTH)
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
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);

  function new(
  base_driver#(
  .TOTAL_INPUTS(TOTAL_INPUTS),
  .P_WIDTH(P_WIDTH),
  .ACC_WIDTH(ACC_WIDTH)
               ) driver_h);
    super.new(driver_h);
  endfunction  // new

  virtual task run();
    np_item #(
        .P_WIDTH  (P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) item;

    // Calculate how many valid beats we need to complete a full 788-bit transaction
    // (788 + 64 - 1) / 64 = 13 beats
    int num_beats = (TOTAL_INPUTS + P_WIDTH - 1) / P_WIDTH;
    int valid_beat_count = 0;

    forever begin
      item = new;
      if (!item.randomize()) $display("Randomize failed");

      // We only count this cycle as a "beat" if valid_in is actually high.
      if (item.valid_in == 1'b1) begin
        valid_beat_count++;

        // If we hit the final valid beat, assert 'last' and reset our counter
        if (valid_beat_count == num_beats) begin
          item.last        = 1'b1;
          valid_beat_count = 0;
        end else begin
          item.last = 1'b0;
        end

      end else begin
        // If it's not a valid cycle, it cannot be the last cycle.
        item.last = 1'b0;
      end

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
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);

  function new(
  base_driver#(
  .TOTAL_INPUTS(TOTAL_INPUTS),
  .P_WIDTH(P_WIDTH),
  .ACC_WIDTH(ACC_WIDTH)
               ) driver_h);
    super.new(driver_h);
  endfunction  // new

  task run();
    np_item #(
        .P_WIDTH  (P_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) item;
    int num_beats = (TOTAL_INPUTS + P_WIDTH - 1) / P_WIDTH;
    int valid_beat_count = 0;

    // We keep track of our consecutive data state
    bit [P_WIDTH-1:0] current_x = '0;
    bit [P_WIDTH-1:0] current_w = '0;

    forever begin
      item           = new;

      // For a consecutive test, we usually force valid_in to 1 so it runs fast without bubbles
      item.valid_in  = 1'b1;
      item.x         = current_x;
      item.w         = current_w;
      item.threshold = 10;  // Fixed threshold for consecutive testing

      current_x++;
      current_w++;

      valid_beat_count++;

      if (valid_beat_count == num_beats) begin
        item.last        = 1'b1;
        valid_beat_count = 0;
      end else begin
        item.last = 1'b0;
      end

      driver_mailbox.put(item);
      @(driver_done_event);
    end
  endtask
endclass

`endif
