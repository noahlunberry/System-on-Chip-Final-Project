// Pawin Ruangkanit
// University of Florida
//
// Exercises a full weights-only reconfiguration between two image phases.

`ifndef _BNN_FCC_WEIGHTS_ONLY_RECONFIG_TEST_SVH_
`define _BNN_FCC_WEIGHTS_ONLY_RECONFIG_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_weights_only_reconfig_test extends bnn_fcc_reconfig_base_test;
    `uvm_component_utils(bnn_fcc_weights_only_reconfig_test)

    localparam int PRE_IMAGES  = 4;
    localparam int POST_IMAGES = 4;

    function new(string name = "bnn_fcc_weights_only_reconfig_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_beat_sequence cfg_seq;
        bnn_fcc_config_beat_sequence re_cfg_seq;
        bnn_fcc_image_beat_sequence pre_img_seq;
        bnn_fcc_image_beat_sequence post_img_seq;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) rand_model;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) expected_model;
        int touched_layers[$];
        int total_images;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting weights-only reconfiguration test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        total_images = PRE_IMAGES + POST_IMAGES;

        // Phase 1: load the DUT with the baseline model and verify a small set
        // of images against that known-good starting point.
        publish_model_handle(model);

        cfg_seq = bnn_fcc_config_beat_sequence::type_id::create("cfg_seq");
        run_config_sequence(cfg_seq, model, "initial full configuration");

        set_runtime_num_images(PRE_IMAGES);
        pre_img_seq = bnn_fcc_image_beat_sequence::type_id::create("pre_img_seq");
        pre_img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(PRE_IMAGES);

        // Phase 2: build a random replacement model. The config stream will be
        // generated from rand_model, but the scoreboard needs a merged model
        // that keeps the original thresholds and replaces only the weights.
        rand_model = make_random_model_like(model);
        expected_model = model.clone();
        expected_model.update_layers_from(rand_model, touched_layers, 1'b1, 1'b0);

        publish_model_handle(rand_model);
        re_cfg_seq = bnn_fcc_config_beat_sequence::type_id::create("re_cfg_seq");
        re_cfg_seq.include_weights = 1'b1;
        re_cfg_seq.include_thresholds = 1'b0;
        re_cfg_seq.order_mode = bnn_fcc_uvm_pkg::BNN_CFG_ORDER_WEIGHTS_THEN_THRESH;
        run_config_sequence(re_cfg_seq, expected_model, "weights-only reconfiguration");

        // Phase 3: send more images and expect behavior from the post-reconfig
        // merged model, not from either original handle alone.
        publish_model_handle(expected_model);
        set_runtime_num_images(POST_IMAGES);
        post_img_seq = bnn_fcc_image_beat_sequence::type_id::create("post_img_seq");
        post_img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(total_images);

        set_runtime_num_images(num_test_images);

        phase.drop_objection(this);
    endtask

endclass

`endif
