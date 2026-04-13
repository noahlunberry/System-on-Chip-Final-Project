// Greg Stitt
// University of Florida
//
// Shared helpers for the reconfiguration/reset-focused UVM tests.

`ifndef _BNN_FCC_RECONFIG_BASE_TEST_SVH_
`define _BNN_FCC_RECONFIG_BASE_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_reconfig_base_test extends bnn_fcc_base_test;

    function new(string name = "bnn_fcc_reconfig_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected function void publish_model_handle(
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model_h
    );
        // The config sequences build their byte stream from model_h in
        // config_db. Reconfiguration tests temporarily swap that handle so the
        // next configuration phase can be sourced from a different model.
        if (model_h == null)
            `uvm_fatal("NULL_MODEL", "publish_model_handle() received a null model handle.")

        if (!model_h.is_loaded)
            `uvm_fatal("UNLOADED_MODEL", "publish_model_handle() received an unloaded model handle.")

        uvm_config_db#(BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::set(
            uvm_root::get(), "*", "model_h", model_h
        );
    endfunction

    protected function void set_runtime_num_images(int count);
        // Image sequences also pull their image count from config_db at start
        // time, so multi-phase tests use this helper before each image phase.
        if (count <= 0)
            `uvm_fatal("BAD_NUM_IMAGES",
                       $sformatf("set_runtime_num_images() requires a positive count, got %0d.", count))

        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", count);
    endfunction

    protected task wait_for_scoreboard_total(int expected_total);
        // Multi-phase tests often care about "have we checked N images so far?"
        // instead of "have we checked the original test-wide default count?"
        wait ((env.scoreboard.passed + env.scoreboard.failed) >= expected_total);
        repeat (5) @(posedge env.in_vif.aclk);
    endtask

    protected function automatic BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) make_random_model_like(
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) src
    );
        // Create a same-topology replacement model that can be used as the
        // source for a reconfiguration phase.
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) rand_model;

        if (src == null)
            `uvm_fatal("NULL_SRC_MODEL", "make_random_model_like() requires a non-null source model.")

        rand_model = new();
        rand_model.create_random(src.topology);
        return rand_model;
    endfunction

    protected function automatic void build_hidden_layer_list(output int layer_list[$]);
        // Threshold messages are only meaningful for hidden layers, so tests
        // that target threshold-only reconfiguration share this helper.
        layer_list.delete();

        for (int layer_idx = 0; layer_idx < model.num_layers - 1; layer_idx++)
            layer_list.push_back(layer_idx);
    endfunction

endclass

`endif
