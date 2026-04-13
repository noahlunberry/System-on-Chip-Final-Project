// Greg Stitt
// University of Florida
//
// Coverage-directed test that programs deterministic weight-density patterns
// into the default topology, then runs a repeated-image workload to target the
// long output-repeat bin.

`ifndef _BNN_FCC_DENSITY_EXTREMES_TEST_SVH_
`define _BNN_FCC_DENSITY_EXTREMES_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_density_extremes_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_density_extremes_test)

    function new(string name = "bnn_fcc_density_extremes_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        // This test deliberately rewrites the model, so the Python cross-check
        // against the trained MNIST reference no longer applies.
        uvm_config_db#(bit)::set(uvm_root::get(), "*", "verify_model", 1'b0);
        super.build_phase(phase);
    endfunction

    protected function automatic int sparse_target(input int fan_in);
        if (fan_in <= 0)
            return 0;
        if (fan_in < 10)
            return 1;
        return fan_in / 10;
    endfunction

    protected function automatic int threshold_low_target(input int fan_in);
        if (fan_in <= 0)
            return 0;
        if (fan_in < 4)
            return 1;
        return fan_in / 4;
    endfunction

    protected function automatic int threshold_mid_target(input int fan_in);
        if (fan_in <= 0)
            return 0;
        if (fan_in < 2)
            return 1;
        return fan_in / 2;
    endfunction

    protected function void apply_density_extremes();
        foreach (model.weight[layer_idx]) begin
            int fan_in;
            int n_neurons;

            fan_in = model.topology[layer_idx];
            n_neurons = model.weight[layer_idx].size();

            for (int neuron_idx = 0; neuron_idx < n_neurons; neuron_idx++) begin
                int target_ones;

                case ((layer_idx + neuron_idx) % 5)
                    0: target_ones = 0;
                    1: target_ones = sparse_target(fan_in);
                    2: target_ones = fan_in / 2;
                    3: target_ones = fan_in - sparse_target(fan_in);
                    default: target_ones = fan_in;
                endcase

                for (int bit_idx = 0; bit_idx < fan_in; bit_idx++)
                    model.weight[layer_idx][neuron_idx][bit_idx] = (bit_idx < target_ones);

                if (layer_idx < model.num_layers - 1) begin
                    case ((layer_idx + neuron_idx) % 4)
                        0: model.threshold[layer_idx][neuron_idx] = 0;
                        1: model.threshold[layer_idx][neuron_idx] = threshold_low_target(fan_in);
                        2: model.threshold[layer_idx][neuron_idx] = threshold_mid_target(fan_in);
                        default: model.threshold[layer_idx][neuron_idx] = fan_in + 8;
                    endcase
                end
                else begin
                    model.threshold[layer_idx][neuron_idx] = 0;
                end
            end
        end

        model.outputs_valid = 1'b0;
        model.layer_outputs = new[0];
        model.last_input = new[0];
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence cfg_seq;
        bnn_fcc_image_scripted_packet_sequence img_seq;
        int image_indices[$];
        int expected_outputs;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting density-extremes coverage test.",
                  UVM_LOW)

        apply_density_extremes();

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("cfg_seq");
        run_config_sequence(cfg_seq, model, "density-extremes full configuration");

        for (int i = 0; i < 12; i++)
            image_indices.push_back(3);
        image_indices.push_back(1);

        expected_outputs = image_indices.size();
        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", expected_outputs);

        img_seq = bnn_fcc_image_scripted_packet_sequence::type_id::create("img_seq");
        img_seq.set_indices(image_indices);
        img_seq.start(env.in_agent.sequencer);

        wait ((env.scoreboard.passed + env.scoreboard.failed) == expected_outputs);
        repeat (5) @(posedge env.in_vif.aclk);

        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", num_test_images);

        phase.drop_objection(this);
    endtask
endclass

`endif
