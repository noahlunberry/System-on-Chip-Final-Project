// Pawin Ruangkanit
// University of Florida
//
// Coverage-directed test that programs explicit signed threshold extremes into
// the hidden layers. This targets threshold_abs_cp, whose current auto-bin
// ranges span the full signed-int space.

`ifndef _BNN_FCC_THRESHOLD_ABS_EXTREMES_TEST_SVH_
`define _BNN_FCC_THRESHOLD_ABS_EXTREMES_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_threshold_abs_extremes_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_threshold_abs_extremes_test)

    function new(string name = "bnn_fcc_threshold_abs_extremes_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected function automatic int choose_extreme_threshold(input int idx);
        case (idx % 8)
            0: return -2000000000;
            1: return -1400000000;
            2: return  -800000000;
            3: return          -1;
            4: return           0;
            5: return   700000000;
            6: return  1400000000;
            default: return 2000000000;
        endcase
    endfunction

    protected function void apply_threshold_abs_extremes();
        for (int layer_idx = 0; layer_idx < model.num_layers - 1; layer_idx++) begin
            for (int neuron_idx = 0; neuron_idx < model.threshold[layer_idx].size(); neuron_idx++)
                model.threshold[layer_idx][neuron_idx] =
                    choose_extreme_threshold(layer_idx * model.threshold[layer_idx].size() + neuron_idx);
        end

        model.outputs_valid = 1'b0;
        model.layer_outputs = new[0];
        model.last_input = new[0];
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence cfg_seq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting threshold-absolute extremes coverage test.",
                  UVM_LOW)

        apply_threshold_abs_extremes();

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("cfg_seq");
        run_config_sequence(cfg_seq, model, "threshold-absolute extremes configuration");

        repeat (5) @(posedge env.in_vif.aclk);
        phase.drop_objection(this);
    endtask
endclass

`endif
