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
    parameter bit TOGGLE_DATA_OUT_READY = 1'b1,
    parameter real CONFIG_VALID_PROBABILITY = 1.0,
    parameter real DATA_IN_VALID_PROBABILITY = 0.95,
    parameter time TIMEOUT = 100ms,
    parameter time CLK_PERIOD = 10ns,
    parameter bit DEBUG = 1'b0,

    // ----------------------------
    // Bus configuration
    // ----------------------------
    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int INPUT_BUS_WIDTH  = 1024,
    parameter int OUTPUT_BUS_WIDTH = 8,

    // ----------------------------
    // App configuration
    // ----------------------------
    parameter int INPUT_DATA_WIDTH  = 8,
    parameter int OUTPUT_DATA_WIDTH = 4,

    // ----------------------------
    // DUT configuration
    // ----------------------------
    localparam int TRAINED_LAYERS = 4,
    localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10},

    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS,
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] =
        USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY,

    localparam int NON_INPUT_LAYERS = ACTUAL_TOTAL_LAYERS - 1,

    parameter int PARALLEL_INPUTS = 128,
    parameter int PARALLEL_NEURONS[NON_INPUT_LAYERS] = '{256, 64, 10}
);

  // ---------------------------------
  // Clock / Reset
  // ---------------------------------
  logic clk = 1'b0;

  localparam time HALF_CLK_PERIOD = CLK_PERIOD / 2;

  initial begin : generate_clock
    forever #HALF_CLK_PERIOD clk <= ~clk;
  end

  initial begin
    ctrl_if.rst = 1'b1;
    repeat (5) @(posedge clk);
    ctrl_if.rst = 1'b0;
  end

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
    if (!TOGGLE_DATA_OUT_READY) data_out_if.tready <= 1'b1;
    else begin
      forever begin
        data_out_if.tready <= $urandom();
        @(posedge clk);
      end
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

    // Store the virtual interfaces.
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

    // Optional timeout for the whole test.
    uvm_top.set_timeout(TIMEOUT);

  end

  initial begin 
    run_test();
  end

  // Verify that the output doesn't change if the DUT is waiting on the ready flag. 
    // NOTE: AXI is a little weird and prohibits transmitters from waiting on tready
    // to assert tvalid. Normally, a transmitter treats a ready signal as an enable,
    // but that practice is not AXI-compliant.
    assert property (@(posedge clk) disable iff (ctrl_if.rst) !data_out_if.tready && data_out_if.tvalid |=> $stable(data_out_if.tdata))
    else `uvm_error("ASSERT", "Output changed with tready disabled.");

    assert property (@(posedge clk) disable iff (ctrl_if.rst) !data_out_if.tready && data_out_if.tvalid |=> $stable(data_out_if.tvalid))
    else `uvm_error("ASSERT", "Valid changed with tready disabled.");
endmodule
