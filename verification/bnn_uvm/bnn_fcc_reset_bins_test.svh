// Greg Stitt
// University of Florida
//
// Accumulates multiple mid-test resets with increasing workload sizes so the
// reachable reset count/workload/post-reset bins are covered deterministically.

`ifndef _BNN_FCC_RESET_BINS_TEST_SVH_
`define _BNN_FCC_RESET_BINS_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_reset_bins_test extends bnn_fcc_reconfig_base_test;
    `uvm_component_utils(bnn_fcc_reset_bins_test)

    function new(string name = "bnn_fcc_reset_bins_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected task run_full_cfg(input string seq_name, input string tag);
        bnn_fcc_config_packet_sequence cfg_seq;

        publish_model_handle(model);
        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create(seq_name);
        run_config_sequence(cfg_seq, model, tag);
    endtask

    protected task run_scripted_images(
        input string seq_name,
        ref int image_indices[$],
        input int expected_total
    );
        bnn_fcc_image_scripted_packet_sequence img_seq;

        set_runtime_num_images(image_indices.size());
        img_seq = bnn_fcc_image_scripted_packet_sequence::type_id::create(seq_name);
        img_seq.set_indices(image_indices);
        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(expected_total);
    endtask

    task run_phase(uvm_phase phase);
        int few_images[$];
        int some_images[$];
        int many_images[$];
        int total_outputs;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting reset count/workload directed coverage test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        total_outputs = 0;

        // Baseline configuration, then reset before any input traffic so the
        // reset covergroup sees workload zero and same-config post-reset behavior.
        run_full_cfg("cfg_before_zero_reset", "initial full configuration");
        pulse_reset(5, 1'b1);

        // Reconfigure with the same model and launch a small repeated-class-3
        // phase before the second reset so count=few and workload=few are hit.
        run_full_cfg("cfg_before_few_reset", "post-reset same full configuration");
        few_images.push_back(18);
        few_images.push_back(30);
        few_images.push_back(0);
        total_outputs += few_images.size();
        run_scripted_images("few_img_seq", few_images, total_outputs);
        pulse_reset(5, 1'b1);

        // A medium workload keeps the test realistic while contributing the
        // already-covered "some" workload bucket on the third reset.
        run_full_cfg("cfg_before_some_reset", "same full configuration after second reset");
        for (int i = 0; i < 8; i++)
            some_images.push_back(i);
        total_outputs += some_images.size();
        run_scripted_images("some_img_seq", some_images, total_outputs);
        pulse_reset(5, 1'b1);

        // Finally, push past the 21-image threshold so reset_count reaches the
        // "many" bucket and workload_before_reset reaches "many" as well.
        run_full_cfg("cfg_before_many_reset", "same full configuration after third reset");
        for (int i = 0; i < 24; i++)
            many_images.push_back(i % 100);
        total_outputs += many_images.size();
        run_scripted_images("many_img_seq", many_images, total_outputs);
        pulse_reset(5, 1'b1);

        set_runtime_num_images(num_test_images);

        phase.drop_objection(this);
    endtask
endclass

`endif
