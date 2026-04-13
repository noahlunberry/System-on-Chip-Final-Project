// Pawin Ruangkanit
// University of Florida
//
// Coverage-directed test that runs a long packet-level image stream with small
// deterministic inter-image gaps to target the input workload and spacing bins.

`ifndef _BNN_FCC_INPUT_STRESS_TEST_SVH_
`define _BNN_FCC_INPUT_STRESS_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_input_stress_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_input_stress_test)

    localparam int STRESS_IMAGES = 120;

    function new(string name = "bnn_fcc_input_stress_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        // Packet-level scripted images plus a small post-packet driver delay
        // give this test intentional short gaps between images.
        uvm_config_db#(int)::set(uvm_root::get(), "*", "in_min_driver_delay", 2);
        uvm_config_db#(int)::set(uvm_root::get(), "*", "in_max_driver_delay", 3);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence cfg_seq;
        bnn_fcc_image_scripted_packet_sequence img_seq;
        int image_indices[$];

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting input stress coverage test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("cfg_seq");
        run_config_sequence(cfg_seq, model, "stress-test full configuration");

        // Start from a class-3 image so this test contributes a different
        // first-output class than the baseline runs, then cycle through the
        // dataset until the workload reaches the stress bucket.
        image_indices.push_back(18);
        for (int i = 1; i < STRESS_IMAGES; i++)
            image_indices.push_back((i - 1) % 100);

        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", image_indices.size());

        img_seq = bnn_fcc_image_scripted_packet_sequence::type_id::create("img_seq");
        img_seq.set_indices(image_indices);
        img_seq.start(env.in_agent.sequencer);

        wait ((env.scoreboard.passed + env.scoreboard.failed) == image_indices.size());
        repeat (5) @(posedge env.in_vif.aclk);

        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", num_test_images);

        phase.drop_objection(this);
    endtask
endclass

`endif
