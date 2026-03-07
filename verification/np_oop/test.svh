// Greg Stitt
// University of Florida

`ifndef _TEST_SVH_
`define _TEST_SVH_

`include "environment.svh"

virtual class base_test #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
);

  virtual np_bfm #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) bfm;
  string name;
  environment #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) env_h;

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm,
      string name = "default_test_name"
  );

    // Ideally we would also create the environment here, but we don't
    // have all the parameters we need for the constructor yet.
    // TODO: Find a cleaner way of doing this.
    this.bfm  = bfm;
    this.name = name;
  endfunction  // new

  virtual function void report_status();
    $display("Results for Test %0s", name);
    env_h.report_status();
  endfunction

  virtual task run(int num_tests, int num_repeats = 0);
    $display("Time %0t [Test]: Starting test %0s.", $time, name);

    for (int i = 0; i < num_repeats + 1; i++) begin
      if (i > 0) $display("Time %0t [Test]: Repeating test %0s (pass %0d).", $time, name, i + 1);
      bfm.reset(5);
      env_h.run(num_tests);
      @(posedge bfm.clk);
    end
    $display("Time %0t [Test]: Test completed.", $time);
  endtask
endclass


class random_test #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
) extends base_test #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);

  nonblocking_driver #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) drv_h;
  random_generator #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) gen_h;

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm,
      string name
  );
    super.new(bfm, name);

    // These should really be passed to the base constructor, but super.new
    // must be called first in the constructor, which makes it impossible
    // to create the generator and driver before calling super.new().
    // So, we use this workaround. 
    drv_h = new(bfm);
    gen_h = new(drv_h);
    env_h = new(bfm, gen_h, drv_h);
  endfunction  // new   

endclass

class consecutive_test #(
    int TOTAL_INPUTS,
    int P_WIDTH,
    int ACC_WIDTH
) extends base_test #(
    .TOTAL_INPUTS(TOTAL_INPUTS),
    .P_WIDTH(P_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
);

  blocking_driver #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) drv_h;
  consecutive_generator #(
      .TOTAL_INPUTS(TOTAL_INPUTS),
      .P_WIDTH(P_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) gen_h;

  function new(
      virtual np_bfm #(
          .TOTAL_INPUTS(TOTAL_INPUTS),
          .P_WIDTH(P_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
      ) bfm,
      string name
  );
    super.new(bfm, name);

    // These should really be passed to the base constructor, but super.new
    // must be called first in the constructor, which makes it impossible
    // to create the generator and driver before calling super.new().
    // So, we use this workaround.
    // This is also non-ideal because now we have repeated code in the
    // constructors for both derived classes. There is almost always a
    // better way when this situation occurs.
    // TODO: Find a cleaner approach.
    drv_h = new(bfm);
    gen_h = new(drv_h);
    env_h = new(bfm, gen_h, drv_h);
  endfunction  // new   

endclass


`endif
