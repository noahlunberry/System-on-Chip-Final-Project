// Greg Stitt
// University of Florida
//
// Shared helper for small directed output-coverage tests. Each derived test
// provides a scripted image order and optionally overrides the output-ready
// policy when it needs deterministic backpressure around a specific class.

`ifndef _BNN_FCC_OUTPUT_DIRECTED_BASE_SVH_
`define _BNN_FCC_OUTPUT_DIRECTED_BASE_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_output_directed_base_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_output_directed_base_test)

    function new(string name = "bnn_fcc_output_directed_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function string get_scenario_name();
        return "directed output coverage";
    endfunction

    protected virtual function void build_image_indices(ref int image_indices[$]);
        image_indices.delete();
        `uvm_fatal("NO_DIRECTED_IMAGES",
                   $sformatf("%s did not override build_image_indices().", get_type_name()))
    endfunction

    protected virtual task coordinate_output_ready();
        // Most directed tests can use the top-level random TREADY policy as-is.
    endtask

    protected task wait_for_output_handshake();
        @(posedge env.out_vif.aclk iff (env.out_vif.tvalid && env.out_vif.tready));
    endtask

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence cfg_seq;
        bnn_fcc_image_scripted_packet_sequence img_seq;
        int image_indices[$];
        int expected_outputs;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  $sformatf("Starting %s test.", get_scenario_name()),
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        build_image_indices(image_indices);
        expected_outputs = image_indices.size();

        if (expected_outputs <= 0)
            `uvm_fatal("EMPTY_DIRECTED_IMAGES",
                       $sformatf("%s built an empty directed image list.", get_type_name()))

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("cfg_seq");
        run_config_sequence(cfg_seq, model, $sformatf("%s full configuration", get_scenario_name()));

        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", expected_outputs);

        img_seq = bnn_fcc_image_scripted_packet_sequence::type_id::create("img_seq");
        img_seq.set_indices(image_indices);

        fork
            begin
                coordinate_output_ready();
            end
            begin
                img_seq.start(env.in_agent.sequencer);
            end
        join

        wait ((env.scoreboard.passed + env.scoreboard.failed) == expected_outputs);
        repeat (5) @(posedge env.in_vif.aclk);

        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", num_test_images);

        phase.drop_objection(this);
    endtask
endclass

`endif
