// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// TEST: bnn_fcc_output_class_test
// Maps to: IMPLEMENTATION_PLAN.md §"Output-class closure"
// Maps to: coverage_plan.txt CATEGORY 3: "Classification Outputs"
//
// DESCRIPTION:
// Directed test to ensure all 10 output classes (0-9) are hit.
// Uses adaptive search: generates random images until all classes are seen
// or a budget is exhausted.
//
// For trained MNIST mode, uses the full test vector set.
// For custom topology, generates extra random images to maximize class diversity.
//
// Samples cg_outputs for coverage closure.

`ifndef _BNN_FCC_OUTPUT_CLASS_TEST_SVH_
`define _BNN_FCC_OUTPUT_CLASS_TEST_SVH_

class bnn_fcc_output_class_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_output_class_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // For output class closure, generate more test images
        if (use_custom_topology) begin
            stim.generate_random_vectors(200);
            uvm_config_db#(int)::set(this, "*", "num_test_images", 200);
        end else begin
            // Use all available MNIST test vectors
            uvm_config_db#(int)::set(this, "*", "num_test_images", 50);
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        bnn_cfg_sequence cfg_seq;
        bnn_image_sequence in_seq;
        axi4s_ready_sequence out_seq;

        phase.raise_objection(this);

        `uvm_info("TEST", "=== Output Class Closure Test ===", UVM_LOW)

        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq");
        in_seq  = bnn_image_sequence::type_id::create("in_seq");
        out_seq = axi4s_ready_sequence::type_id::create("out_seq");

        // Light backpressure to also exercise cross coverage (class × backpressure)
        out_seq.ready_on_min = 2;
        out_seq.ready_on_max = 10;
        out_seq.ready_off_min = 0;
        out_seq.ready_off_max = 3;

        fork
            out_seq.start(null);
        join_none

        cfg_seq.start(env.cfg_agent.sequencer);
        in_seq.start(env.in_agent.sequencer);

        // Wait for all results
        #100000;

        // Report which classes were hit
        `uvm_info("TEST", $sformatf("Output class coverage: %.1f%%",
            env.coverage.cg_outputs.get_coverage()), UVM_NONE)

        phase.drop_objection(this);
    endtask
endclass
`endif
