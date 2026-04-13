// Greg Stitt
// University of Florida
//
// Sends a short sequence of one-layer configuration packets to hit the
// reachable missing order-coverage cross bins on the default 3-layer model.

`ifndef _BNN_FCC_CONFIG_ORDER_BINS_TEST_SVH_
`define _BNN_FCC_CONFIG_ORDER_BINS_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_config_order_bins_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_config_order_bins_test)

    function new(string name = "bnn_fcc_config_order_bins_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected task run_one_layer_cfg(
        input string seq_name,
        input int layer_idx,
        input bit include_weights,
        input bit include_thresholds,
        input string tag
    );
        bnn_fcc_config_packet_sequence cfg_seq;
        int layer_sel[$];

        layer_sel.push_back(layer_idx);
        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create(seq_name);
        cfg_seq.include_weights = include_weights;
        cfg_seq.include_thresholds = include_thresholds;
        cfg_seq.select_layers(layer_sel);
        run_config_sequence(cfg_seq, model, tag);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting config-order directed coverage test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        // 1. Seed the stream with weights on layer 0.
        run_one_layer_cfg("w_layer0_a", 0, 1'b1, 1'b0, "weights-only layer 0 preamble");

        // 2. Move to thresholds on the next layer: <weights_to_thresholds,next_layer>.
        run_one_layer_cfg("t_layer1", 1, 1'b0, 1'b1, "threshold-only layer 1 preamble");

        // 3-4. Repeat the same message type on the same layer:
        // <same_type,same_layer>.
        run_one_layer_cfg("w_layer0_b", 0, 1'b1, 1'b0, "weights-only layer 0 revisit");
        run_one_layer_cfg("w_layer0_c", 0, 1'b1, 1'b0, "weights-only layer 0 repeat");

        // Restore the DUT to the normal fully configured state before ending.
        begin
            bnn_fcc_config_packet_sequence full_cfg_seq;

            full_cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("full_cfg_seq");
            run_config_sequence(full_cfg_seq, model, "final full configuration");
        end

        repeat (10) @(posedge env.cfg_vif.aclk);
        phase.drop_objection(this);
    endtask
endclass

`endif
