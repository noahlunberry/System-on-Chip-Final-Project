// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// MODULE: bnn_fcc_uvm_tb
//
// DESCRIPTION:
// UVM top-level module for the binary neural net (bnn) fully connected classifier (fcc).
// Maps to: IMPLEMENTATION_PLAN.md - "UVM architecture and integration"
// 
// This module provides the UVM skeleton. It instantiates the BNN FCC DUT along with three
// standard AXI4-Stream interfaces (config, input, and output). It uses the `uvm_config_db`
// to pass virtual interface handles into the UVM object hierarchy, allowing drivers and monitors
// to interact with the DUT without hardcoded static references.
//
// It also provides the ability to pass the trained or custom topology configurations to the 
// tests directly via the config DB so that the base test can populate the reference models.

`timescale 1ns / 100ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import bnn_fcc_pkg::*;

module bnn_fcc_uvm_tb #(
    // Testbench and DUT topology parameters ported from the basic TB for 1-to-1 parity
    parameter int      USE_CUSTOM_TOPOLOGY                      = 1'b0,
    parameter int      CUSTOM_LAYERS                            = 4,
    parameter int      CUSTOM_TOPOLOGY          [CUSTOM_LAYERS] = '{8, 8, 8, 8},
    parameter int      NUM_TEST_IMAGES                          = 50,
    parameter string   BASE_DIR                                 = "../python",
    parameter realtime CLK_PERIOD                               = 10ns,
    parameter int      CONFIG_BUS_WIDTH                         = 64,
    parameter int      INPUT_BUS_WIDTH                          = 64,
    parameter int      OUTPUT_BUS_WIDTH                         = 8,
    parameter int      INPUT_DATA_WIDTH                         = 8,
    parameter int      OUTPUT_DATA_WIDTH                        = 4,
    localparam int     TRAINED_LAYERS                           = 4,
    localparam int     TRAINED_TOPOLOGY[TRAINED_LAYERS]         = '{784, 256, 256, 10},
    localparam int     NON_INPUT_LAYERS                         = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS - 1 : TRAINED_LAYERS - 1,
    parameter int      PARALLEL_INPUTS                          = 8,
    parameter int      PARALLEL_NEURONS[NON_INPUT_LAYERS]       = '{8, 8, 10}
);
    // Determine which topology setup is being instantiated for the reference models.
    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS;
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] = USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY;

    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

    logic clk = 1'b0;
    logic rst_n;
    logic rst;

    initial begin
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    // Standard AXI4-Stream Interfaces reused from uvm_reference
    axi4_stream_if #(CONFIG_BUS_WIDTH) cfg_if(clk, rst_n);
    axi4_stream_if #(INPUT_BUS_WIDTH)  in_if(clk, rst_n);
    axi4_stream_if #(OUTPUT_BUS_WIDTH) out_if(clk, rst_n);

    // DUT instantiation. Maps standard config parameters to match the basic TB flow
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
    ) DUT (
        .clk(clk),
        .rst(rst),
        .config_valid(cfg_if.tvalid),
        .config_ready(cfg_if.tready),
        .config_data (cfg_if.tdata),
        .config_keep (cfg_if.tkeep),
        .config_last (cfg_if.tlast),

        .data_in_valid(in_if.tvalid),
        .data_in_ready(in_if.tready),
        .data_in_data (in_if.tdata),
        .data_in_keep (in_if.tkeep),
        .data_in_last (in_if.tlast),

        .data_out_valid(out_if.tvalid),
        .data_out_ready(out_if.tready),
        .data_out_data (out_if.tdata),
        .data_out_keep (out_if.tkeep),
        .data_out_last (out_if.tlast)
    );

    // Provide strobe equivalent mapping, per standard AXI rules if required by DUT.
    assign cfg_if.tstrb = cfg_if.tkeep;
    assign in_if.tstrb  = in_if.tkeep;
    assign out_if.tstrb = out_if.tkeep;

    // Reset sequence injected prior to UVM starting properly.
    initial begin
        rst <= 1'b1;
        rst_n <= 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        rst_n <= 1'b1;
    end

    // Configuration DB wiring for UVM references
    initial begin
        // Mount interfaces for Agent Drivers and Monitors
        uvm_config_db#(virtual axi4_stream_if #(CONFIG_BUS_WIDTH))::set(null, "*", "cfg_vif", cfg_if);
        uvm_config_db#(virtual axi4_stream_if #(INPUT_BUS_WIDTH))::set(null, "*", "in_vif", in_if);
        uvm_config_db#(virtual axi4_stream_if #(OUTPUT_BUS_WIDTH))::set(null, "*", "out_vif", out_if);
        
        // Pass essential environment parameters downward instead of hardcoding macros 
        uvm_config_db#(int)::set(null, "*", "num_test_images", NUM_TEST_IMAGES);
        uvm_config_db#(int)::set(null, "*", "use_custom_topology", USE_CUSTOM_TOPOLOGY);
        uvm_config_db#(string)::set(null, "*", "base_dir", BASE_DIR);

        // UVM configuration DB doesn't support complex dynamic arrays directly 
        // without an object wrapper, hence we map ACTUAL_TOPOLOGY this way.
        begin
            int dyn_top[];
            dyn_top = new[ACTUAL_TOTAL_LAYERS];
            for(int i=0; i<ACTUAL_TOTAL_LAYERS; i++) dyn_top[i] = ACTUAL_TOPOLOGY[i];
            uvm_config_db#(int_q_wrapper)::set(null, "*", "bnn_topology", new(dyn_top));
        end

        run_test();
    end

    // Object wrapper class to support passing the topology across boundaries.
    class int_q_wrapper;
        int arr[];
        function new(int a[]); arr = a; endfunction
    endclass

    // =========================================================================
    // AXI4-Stream Protocol Hold Assertions
    // Maps to: IMPLEMENTATION_PLAN.md §"Debug/trace hooks" R24
    //
    // Rule: once TVALID is asserted, it must remain asserted until TREADY
    // is seen (handshake completes). These are both correctness checks and
    // coverage dimensions.
    // =========================================================================
    property axi4s_valid_hold(logic valid, logic ready, logic aclk, logic aresetn);
        @(posedge aclk) disable iff (!aresetn)
            (valid && !ready) |=> valid;
    endproperty

    // Config interface: master must hold TVALID until TREADY
    assert property (axi4s_valid_hold(cfg_if.tvalid, cfg_if.tready, clk, rst_n))
    else `uvm_error("AXI_HOLD", "Config TVALID dropped before handshake")

    // Input interface: master must hold TVALID until TREADY
    assert property (axi4s_valid_hold(in_if.tvalid, in_if.tready, clk, rst_n))
    else `uvm_error("AXI_HOLD", "Input TVALID dropped before handshake")

    // Output interface: DUT must hold TVALID until TREADY
    assert property (axi4s_valid_hold(out_if.tvalid, out_if.tready, clk, rst_n))
    else `uvm_error("AXI_HOLD", "Output TVALID dropped before handshake")

    // =========================================================================
    // Simulation timeout (safety net)
    // =========================================================================
    initial begin
        #10ms;
        $fatal(1, "Simulation timeout at 10ms");
    end

endmodule
