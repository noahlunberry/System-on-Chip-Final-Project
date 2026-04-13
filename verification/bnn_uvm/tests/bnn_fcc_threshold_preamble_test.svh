// Pawin Ruangkanit
// University of Florida
//
// Coverage-directed test that sends a few intentional "preamble"
// reconfiguration packets before the normal full configuration. The goal is to
// exercise missing config-order and threshold-coverage bins without needing a
// separate DUT topology.

`ifndef _BNN_FCC_THRESHOLD_PREAMBLE_TEST_SVH_
`define _BNN_FCC_THRESHOLD_PREAMBLE_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_threshold_preamble_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_threshold_preamble_test)

    function new(string name = "bnn_fcc_threshold_preamble_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence thresh_layer1_seq;
        bnn_fcc_config_packet_sequence weight_layer0_seq;
        bnn_fcc_config_packet_sequence thresh_layer0_seq;
        bnn_fcc_config_packet_sequence weight_layer2_seq;
        bnn_fcc_config_packet_sequence full_cfg_seq;
        bnn_fcc_image_scripted_packet_sequence img_seq;
        int layer_sel[$];
        int image_indices[$];
        int expected_outputs;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting threshold-preamble coverage test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        // 1. Thresholds-only on a hidden layer before any weights for that
        // layer so threshold coverage can observe the unknown-ratio case.
        layer_sel.delete();
        layer_sel.push_back(1);
        thresh_layer1_seq = bnn_fcc_config_packet_sequence::type_id::create("thresh_layer1_seq");
        thresh_layer1_seq.include_weights = 1'b0;
        thresh_layer1_seq.include_thresholds = 1'b1;
        thresh_layer1_seq.select_layers(layer_sel);
        run_config_sequence(thresh_layer1_seq, model, "threshold-only preamble on layer 1");

        // 2. Move backwards in layer order while switching message type.
        layer_sel.delete();
        layer_sel.push_back(0);
        weight_layer0_seq = bnn_fcc_config_packet_sequence::type_id::create("weight_layer0_seq");
        weight_layer0_seq.include_weights = 1'b1;
        weight_layer0_seq.include_thresholds = 1'b0;
        weight_layer0_seq.select_layers(layer_sel);
        run_config_sequence(weight_layer0_seq, model, "weights-only preamble on layer 0");

        // 3. Return to thresholds on the same layer.
        thresh_layer0_seq = bnn_fcc_config_packet_sequence::type_id::create("thresh_layer0_seq");
        thresh_layer0_seq.include_weights = 1'b0;
        thresh_layer0_seq.include_thresholds = 1'b1;
        thresh_layer0_seq.select_layers(layer_sel);
        run_config_sequence(thresh_layer0_seq, model, "threshold-only preamble on layer 0");

        // 4. Jump forward to the output-layer weights. This also gives
        // reconfig_coverage a one-layer example and produces a medium-sized
        // configuration packet on the default topology.
        layer_sel.delete();
        layer_sel.push_back(model.num_layers - 1);
        weight_layer2_seq = bnn_fcc_config_packet_sequence::type_id::create("weight_layer2_seq");
        weight_layer2_seq.include_weights = 1'b1;
        weight_layer2_seq.include_thresholds = 1'b0;
        weight_layer2_seq.select_layers(layer_sel);
        run_config_sequence(weight_layer2_seq, model, "weights-only preamble on output layer");

        // 5. Finish with a normal full configuration before any images are
        // checked so the DUT and scoreboard are back in a known-good state.
        full_cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("full_cfg_seq");
        run_config_sequence(full_cfg_seq, model, "final full configuration");

        // Start from a class-5 image and repeat it once so output coverage can
        // see both a first and repeated classification for a class other than
        // the default index-0 image.
        image_indices = '{15, 15, 7};
        expected_outputs = image_indices.size();
        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", expected_outputs);

        img_seq = bnn_fcc_image_scripted_packet_sequence::type_id::create("img_seq");
        img_seq.set_indices(image_indices);
        img_seq.start(env.in_agent.sequencer);

        wait ((env.scoreboard.passed + env.scoreboard.failed) == expected_outputs);
        repeat (5) @(posedge env.in_vif.aclk);

        // Restore the default in case later helper code consults the test-wide
        // image count again.
        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", num_test_images);

        phase.drop_objection(this);
    endtask
endclass

`endif
