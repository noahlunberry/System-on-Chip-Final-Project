`timescale 1ns / 100ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_uvm_pkg::*;  // package should include your test/env/agent classes

module bnn_fcc_uvm_tb #(
    // ----------------------------
    // Test/runtime configuration
    // ----------------------------
    parameter int USE_CUSTOM_TOPOLOGY = 1'b0,
    parameter int CUSTOM_LAYERS = 4,
    parameter int CUSTOM_TOPOLOGY[CUSTOM_LAYERS] = '{256, 64, 64, 8},
    parameter int NUM_TEST_IMAGES = 50,
    parameter bit VERIFY_MODEL = 1,
    parameter string BASE_DIR = "/home/UFAD/ruangkanitpawin/Projects/bnn_fcc_contest/python",
    parameter bit TOGGLE_DATA_OUT_READY = 1'b0,
    parameter real CONFIG_VALID_PROBABILITY = 0.6,
    parameter real DATA_IN_VALID_PROBABILITY = 1.0,
    parameter time TIMEOUT = 100ms,
    parameter time CLK_PERIOD = 10ns,
    parameter bit DEBUG = 1'b0,
    parameter string DEFAULT_UVM_TESTNAME = "",

    // ----------------------------
    // Bus configuration
    // ----------------------------
    parameter int CONFIG_BUS_WIDTH = bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH,
    parameter int INPUT_BUS_WIDTH  = bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH,
    parameter int OUTPUT_BUS_WIDTH = bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH,

    // ----------------------------
    // App configuration
    // ----------------------------
    parameter int INPUT_DATA_WIDTH  = bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH,
    parameter int OUTPUT_DATA_WIDTH = bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH,

    // ----------------------------
    // DUT configuration
    // ----------------------------
    localparam int TRAINED_LAYERS = bnn_fcc_uvm_pkg::TRAINED_LAYERS,
    localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = bnn_fcc_uvm_pkg::TRAINED_TOPOLOGY,

    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS,
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] =
        USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY,

    localparam int NON_INPUT_LAYERS = ACTUAL_TOTAL_LAYERS - 1,

    parameter int PARALLEL_INPUTS = bnn_fcc_uvm_pkg::PARALLEL_INPUTS,
    parameter int PARALLEL_NEURONS[NON_INPUT_LAYERS] = bnn_fcc_uvm_pkg::PARALLEL_NEURONS
);

  // ---------------------------------
  // Clock / Reset
  // ---------------------------------
  logic clk = 1'b0;

  localparam time HALF_CLK_PERIOD = CLK_PERIOD / 2;

  initial begin : generate_clock
    forever #HALF_CLK_PERIOD clk <= ~clk;
  end

  // Power-on reset is now driven through ctrl_if so UVM tests can reuse the
  // exact same reset signal for mid-test reset scenarios.
  initial begin
    ctrl_if.rst = 1'b1;
    ctrl_if.out_ready_force_en = 1'b0;
    ctrl_if.out_ready_force_val = 1'b1;
    repeat (5) @(posedge clk);
    ctrl_if.rst = 1'b0;
  end

  // Shared control interface for reset-only coordination between the top TB,
  // tests, scoreboard, and coverage components.
  bnn_fcc_ctrl_if ctrl_if (
      .clk(clk)
  );

  // ---------------------------------
  // Interfaces
  // ---------------------------------
  axi4_stream_if #(
      .DATA_WIDTH(CONFIG_BUS_WIDTH)
  ) config_in_if (
      .aclk   (clk),
      .aresetn(!ctrl_if.rst)
  );

  axi4_stream_if #(
      .DATA_WIDTH(INPUT_BUS_WIDTH)
  ) data_in_if (
      .aclk   (clk),
      .aresetn(!ctrl_if.rst)
  );

  axi4_stream_if #(
      .DATA_WIDTH(OUTPUT_BUS_WIDTH)
  ) data_out_if (
      .aclk   (clk),
      .aresetn(!ctrl_if.rst)
  );

  // Match your old TB behavior
  assign config_in_if.tstrb = config_in_if.tkeep;
  assign data_in_if.tstrb   = data_in_if.tkeep;

  // Match the original TB backpressure behavior by driving TREADY directly
  // from the top-level testbench. The output agent is monitor-only.
  initial begin
    forever begin
      if (ctrl_if.out_ready_force_en)
        data_out_if.tready <= ctrl_if.out_ready_force_val;
      else if (!TOGGLE_DATA_OUT_READY)
        data_out_if.tready <= 1'b1;
      else
        data_out_if.tready <= $urandom();

      @(posedge clk);
    end
  end

  // ---------------------------------
  // DUT
  // ---------------------------------
  bnn_fcc #(
      .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
      .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
      .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
      .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH),
      .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
      .TOTAL_LAYERS     (ACTUAL_TOTAL_LAYERS),
      .TOPOLOGY         (ACTUAL_TOPOLOGY),
      .PARALLEL_INPUTS  (PARALLEL_INPUTS),
      .PARALLEL_NEURONS (PARALLEL_NEURONS)
  ) dut (
      .clk(clk),
      .rst(ctrl_if.rst),

      .config_valid(config_in_if.tvalid),
      .config_ready(config_in_if.tready),
      .config_data (config_in_if.tdata),
      .config_keep (config_in_if.tkeep),
      .config_last (config_in_if.tlast),

      .data_in_valid(data_in_if.tvalid),
      .data_in_ready(data_in_if.tready),
      .data_in_data (data_in_if.tdata),
      .data_in_keep (data_in_if.tkeep),
      .data_in_last (data_in_if.tlast),

      .data_out_valid(data_out_if.tvalid),
      .data_out_ready(data_out_if.tready),
      .data_out_data (data_out_if.tdata),
      .data_out_keep (data_out_if.tkeep),
      .data_out_last (data_out_if.tlast)
  );

  // ---------------------------------
  // UVM config
  // ---------------------------------

  // These typedefs make config_db calls less ugly

  initial begin
    bnn_fcc_uvm_pkg::bnn_fcc_topology_cfg topology_cfg_h;

    $timeformat(-9, 0, " ns", 0);

    topology_cfg_h = new();
    topology_cfg_h.custom_layers = CUSTOM_LAYERS;
    topology_cfg_h.custom_topology = new[CUSTOM_LAYERS];
    foreach (CUSTOM_TOPOLOGY[i])
      topology_cfg_h.custom_topology[i] = CUSTOM_TOPOLOGY[i];

    // Store the virtual interfaces. ctrl_vif is the new piece that lets UVM
    // code observe and drive reset without reaching into this top module.
    uvm_config_db#(virtual axi4_stream_if #(CONFIG_BUS_WIDTH))::set(uvm_root::get(), "*", "cfg_vif",
                                                                    config_in_if);
    uvm_config_db#(virtual axi4_stream_if #(CONFIG_BUS_WIDTH))::set(uvm_root::get(), "*", "config_vif",
                                                                    config_in_if);
    uvm_config_db#(virtual axi4_stream_if #(INPUT_BUS_WIDTH))::set(uvm_root::get(), "*", "in_vif",
                                                                   data_in_if);
    uvm_config_db#(virtual axi4_stream_if #(INPUT_BUS_WIDTH))::set(uvm_root::get(), "*", "data_in_vif",
                                                                   data_in_if);
    uvm_config_db#(virtual axi4_stream_if #(OUTPUT_BUS_WIDTH))::set(uvm_root::get(), "*", "out_vif",
                                                                    data_out_if);
    uvm_config_db#(virtual axi4_stream_if #(OUTPUT_BUS_WIDTH))::set(uvm_root::get(), "*", "data_out_vif",
                                                                    data_out_if);
    uvm_config_db#(virtual bnn_fcc_ctrl_if)::set(uvm_root::get(), "*", "ctrl_vif", ctrl_if);

    // Store general test configuration.
    uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", NUM_TEST_IMAGES);
    uvm_config_db#(bit)::set(uvm_root::get(), "*", "verify_model", VERIFY_MODEL);
    uvm_config_db#(string)::set(uvm_root::get(), "*", "base_dir", BASE_DIR);
    uvm_config_db#(bit)::set(uvm_root::get(), "*", "debug", DEBUG);
    uvm_config_db#(bit)::set(uvm_root::get(), "*", "use_custom_topology", USE_CUSTOM_TOPOLOGY);
    uvm_config_db#(bnn_fcc_uvm_pkg::bnn_fcc_topology_cfg)::set(uvm_root::get(), "*", "custom_topology_cfg_h",
                                                                topology_cfg_h);

    // Store handshake configuration.
    uvm_config_db#(real)::set(uvm_root::get(), "*", "config_valid_probability", CONFIG_VALID_PROBABILITY);
    uvm_config_db#(real)::set(uvm_root::get(), "*", "data_in_valid_probability", DATA_IN_VALID_PROBABILITY);
    uvm_config_db#(real)::set(uvm_root::get(), "*", "clock_period_ns", CLK_PERIOD);

    // Optional timeout for the whole test.
    uvm_top.set_timeout(TIMEOUT);

  end

  initial begin
    if (DEFAULT_UVM_TESTNAME != "")
      run_test(DEFAULT_UVM_TESTNAME);
    else
      run_test();
  end

  // Verify that the output doesn't change if the DUT is waiting on the ready flag. 
    // NOTE: AXI is a little weird and prohibits transmitters from waiting on tready
    // to assert tvalid. Normally, a transmitter treats a ready signal as an enable,
    // but that practice is not AXI-compliant.
    // Disable these checks during reset because the DUT is allowed to change
    // interface state while being reinitialized.
    assert property (@(posedge clk) disable iff (ctrl_if.rst) !data_out_if.tready && data_out_if.tvalid |=> $stable(data_out_if.tdata))
    else `uvm_error("ASSERT", "Output changed with tready disabled.");

    assert property (@(posedge clk) disable iff (ctrl_if.rst) !data_out_if.tready && data_out_if.tvalid |=> $stable(data_out_if.tvalid))
    else `uvm_error("ASSERT", "Valid changed with tready disabled.");
endmodule
