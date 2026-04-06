// Greg Stitt
// University of Florida
//
// Exercises a partial-layer reconfiguration with mixed message ordering.

`ifndef _BNN_FCC_PARTIAL_RECONFIG_TEST_SVH_
`define _BNN_FCC_PARTIAL_RECONFIG_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_partial_reconfig_test extends bnn_fcc_reconfig_base_test;
    `uvm_component_utils(bnn_fcc_partial_reconfig_test)

    localparam int PRE_IMAGES  = 3;
    localparam int POST_IMAGES = 5;

    function new(string name = "bnn_fcc_partial_reconfig_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence cfg_seq;
        bnn_fcc_config_packet_sequence re_cfg_seq;
        bnn_fcc_image_packet_sequence pre_img_seq;
        bnn_fcc_image_packet_sequence post_img_seq;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) rand_model;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) expected_model;
        int selected_layers[$];
        int total_images;

        phase.raise_objection(this);

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        total_images = PRE_IMAGES + POST_IMAGES;

        // Baseline full configuration followed by a short pre-reconfig image run.
        publish_model_handle(model);

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("cfg_seq");
        run_config_sequence(cfg_seq, model, "initial full configuration");

        set_runtime_num_images(PRE_IMAGES);
        pre_img_seq = bnn_fcc_image_packet_sequence::type_id::create("pre_img_seq");
        pre_img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(PRE_IMAGES);

        // Touch one early layer and, when available, the last layer so this
        // test exercises a non-contiguous subset rather than a trivial prefix.
        selected_layers.push_back(0);
        if (model.num_layers > 1)
            selected_layers.push_back(model.num_layers - 1);

        // expected_model represents what the DUT should look like after only
        // the selected layers have been updated.
        rand_model = make_random_model_like(model);
        expected_model = model.clone();
        expected_model.update_layers_from(rand_model, selected_layers, 1'b1, 1'b1);

        publish_model_handle(rand_model);
        re_cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("re_cfg_seq");
        re_cfg_seq.include_weights = 1'b1;
        re_cfg_seq.include_thresholds = 1'b1;
        re_cfg_seq.order_mode = bnn_fcc_uvm_pkg::BNN_CFG_ORDER_THRESH_THEN_WEIGHTS;
        re_cfg_seq.select_layers(selected_layers);
        run_config_sequence(re_cfg_seq, expected_model, "partial-layer reconfiguration");

        // Post-reconfig image phase checked against the partially updated model.
        publish_model_handle(expected_model);
        set_runtime_num_images(POST_IMAGES);
        post_img_seq = bnn_fcc_image_packet_sequence::type_id::create("post_img_seq");
        post_img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(total_images);

        set_runtime_num_images(num_test_images);

        phase.drop_objection(this);
    endtask

endclass

`endif
