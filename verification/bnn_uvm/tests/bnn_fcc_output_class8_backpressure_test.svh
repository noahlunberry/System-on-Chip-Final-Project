// Pawin Ruangkanit
// University of Florida
//
// Drives the lone class-8 image twice while temporarily forcing TREADY so the
// output-coverage cross sees both "none" and "heavy" backpressure buckets.

`ifndef _BNN_FCC_OUTPUT_CLASS8_BACKPRESSURE_TEST_SVH_
`define _BNN_FCC_OUTPUT_CLASS8_BACKPRESSURE_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_output_class8_backpressure_test extends bnn_fcc_output_directed_base_test;
    `uvm_component_utils(bnn_fcc_output_class8_backpressure_test)

    function new(string name = "bnn_fcc_output_class8_backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function string get_scenario_name();
        return "class-8 backpressure coverage";
    endfunction

    protected virtual function void build_image_indices(ref int image_indices[$]);
        image_indices.delete();
        image_indices.push_back(84);
        image_indices.push_back(84);
        image_indices.push_back(3);
    endfunction

    protected virtual task coordinate_output_ready();
        // Keep the first class-8 output unstalled so it lands in the "none"
        // backpressure bucket.
        ctrl_vif.force_output_ready(1'b1);
        wait_for_output_handshake();
        @(posedge env.out_vif.aclk);
        ctrl_vif.release_output_ready();

        // Hold off the second output long enough to classify it as heavy
        // backpressure, then release it for one clean transfer.
        wait (env.out_vif.tvalid == 1'b1);
        ctrl_vif.force_output_ready(1'b0);
        repeat (6) @(posedge env.out_vif.aclk);
        ctrl_vif.force_output_ready(1'b1);
        wait_for_output_handshake();
        @(posedge env.out_vif.aclk);
        ctrl_vif.release_output_ready();
    endtask
endclass

`endif
