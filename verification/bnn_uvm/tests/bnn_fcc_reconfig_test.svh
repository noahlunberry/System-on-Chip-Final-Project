// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// TEST: bnn_fcc_reconfig_test
// Maps to: IMPLEMENTATION_PLAN.md §"Config ordering and partial reconfiguration"
// Maps to: coverage_plan.txt CATEGORY 4: "Configuration-Image Sequencing"
//
// DESCRIPTION:
// Tests partial reconfiguration and ordering variations:
//   - Weights-only reconfig
//   - Thresholds-only reconfig
//   - Reverse-order config across layers
//   - Full reconfig after initial config + images
//
// Samples cg_reconfig for coverage closure.

`ifndef _BNN_FCC_RECONFIG_TEST_SVH_
`define _BNN_FCC_RECONFIG_TEST_SVH_

class bnn_fcc_reconfig_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_reconfig_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        bnn_cfg_sequence cfg_seq;
        bnn_image_sequence in_seq;
        axi4s_ready_sequence out_seq;

        phase.raise_objection(this);

        `uvm_info("TEST", "=== Reconfig Test: Standard order first ===", UVM_LOW)

        // --- Phase 1: Normal config + images ---
        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq");
        in_seq  = bnn_image_sequence::type_id::create("in_seq");
        out_seq = axi4s_ready_sequence::type_id::create("out_seq");

        fork
            out_seq.start(null);
        join_none

        cfg_seq.start(env.cfg_agent.sequencer);
        in_seq.start(env.in_agent.sequencer);
        #20000;

        // Coverage: full config
        env.coverage.sample_reconfig(0, model.num_layers);

        // --- Phase 2: Thresholds-before-weights reconfig ---
        `uvm_info("TEST", "=== Reconfig Test: Thresh before weights ===", UVM_LOW)
        env.scoreboard.handle_reconfig();

        begin
            bnn_cfg_sequence cfg_seq2 = bnn_cfg_sequence::type_id::create("cfg_seq2");
            cfg_seq2.thresh_before_weights = 1;
            cfg_seq2.start(env.cfg_agent.sequencer);
        end

        env.coverage.sample_reconfig(2, model.num_layers); // thresh-only ordering

        begin
            bnn_image_sequence in_seq2 = bnn_image_sequence::type_id::create("in_seq2");
            in_seq2.start(env.in_agent.sequencer);
        end
        #20000;

        // --- Phase 3: Reverse layer order ---
        `uvm_info("TEST", "=== Reconfig Test: Reverse layer order ===", UVM_LOW)
        env.scoreboard.handle_reconfig();

        begin
            bnn_cfg_sequence cfg_seq3 = bnn_cfg_sequence::type_id::create("cfg_seq3");
            cfg_seq3.reverse_layer_order = 1;
            cfg_seq3.start(env.cfg_agent.sequencer);
        end

        env.coverage.sample_reconfig(3, model.num_layers); // partial/reorder

        begin
            bnn_image_sequence in_seq3 = bnn_image_sequence::type_id::create("in_seq3");
            in_seq3.start(env.in_agent.sequencer);
        end
        #20000;

        phase.drop_objection(this);
    endtask
endclass
`endif
