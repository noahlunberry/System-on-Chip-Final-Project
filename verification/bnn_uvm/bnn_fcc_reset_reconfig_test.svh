// Greg Stitt
// University of Florida
//
// Exercises a reset followed by a full reconfiguration to a different model.

`ifndef _BNN_FCC_RESET_RECONFIG_TEST_SVH_
`define _BNN_FCC_RESET_RECONFIG_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_reset_reconfig_test extends bnn_fcc_reconfig_base_test;
    `uvm_component_utils(bnn_fcc_reset_reconfig_test)

    localparam int PRE_IMAGES  = 6;
    localparam int POST_IMAGES = 4;

    function new(string name = "bnn_fcc_reset_reconfig_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_beat_sequence init_cfg_seq;
        bnn_fcc_config_packet_sequence post_reset_cfg_seq;
        bnn_fcc_image_packet_sequence pre_img_seq;
        bnn_fcc_image_packet_sequence post_img_seq;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) post_reset_model;
        int scoreboard_total_before_reset;
        int wait_cycles;

        phase.raise_objection(this);

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        // Phase 1: configure the DUT normally and launch a small batch of images.
        publish_model_handle(model);

        init_cfg_seq = bnn_fcc_config_beat_sequence::type_id::create("init_cfg_seq");
        run_config_sequence(init_cfg_seq, model, "initial full configuration");

        set_runtime_num_images(PRE_IMAGES);
        pre_img_seq = bnn_fcc_image_packet_sequence::type_id::create("pre_img_seq");
        pre_img_seq.start(env.in_agent.sequencer);

        // Wait briefly for output-side activity so the reset is more likely to
        // land during a live workload instead of trivially during idle time.
        wait_cycles = 0;
        while ((wait_cycles < 50) && !env.out_vif.tvalid) begin
            @(posedge env.out_vif.aclk);
            wait_cycles++;
        end

        // Snapshot the number of results already checked. After reset, the
        // scoreboard deliberately drops any pre-reset expectations, so the
        // post-reset phase only adds POST_IMAGES more checked outputs.
        scoreboard_total_before_reset = env.scoreboard.passed + env.scoreboard.failed;
        pulse_reset(5, 1'b0);

        // Phase 2: treat reset as a fresh start and load a completely new model.
        post_reset_model = make_random_model_like(model);
        publish_model_handle(post_reset_model);

        post_reset_cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("post_reset_cfg_seq");
        run_config_sequence(post_reset_cfg_seq, post_reset_model, "post-reset full reconfiguration");

        // Verify that fresh traffic after reset is checked against the new,
        // post-reset configuration epoch.
        set_runtime_num_images(POST_IMAGES);
        post_img_seq = bnn_fcc_image_packet_sequence::type_id::create("post_img_seq");
        post_img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(scoreboard_total_before_reset + POST_IMAGES);

        set_runtime_num_images(num_test_images);

        phase.drop_objection(this);
    endtask

endclass

`endif
