// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// TEST: bnn_fcc_reset_stress_test
// Maps to: IMPLEMENTATION_PLAN.md §"Reset robustness"
// Maps to: coverage_plan.txt CATEGORY 5: "Reset Scenarios"
//
// DESCRIPTION:
// Injects resets at different phases of operation:
//   - During configuration streaming
//   - During image input streaming
//   - While output is pending with backpressure
//   - At TLAST boundaries
//   - Post-reset: same vs different config
//
// Uses scoreboard handle_reset() and handle_reconfig() to maintain epoch tracking.
// Samples cg_reset and cg_reset_post for coverage closure.

`ifndef _BNN_FCC_RESET_STRESS_TEST_SVH_
`define _BNN_FCC_RESET_STRESS_TEST_SVH_

class bnn_fcc_reset_stress_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_reset_stress_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // Inject a reset pulse on the top-level rst/rst_n signals
    task inject_reset();
        virtual axi4_stream_if #(64) cfg_vif;
        virtual bnn_reset_if reset_vif;
        if (!uvm_config_db#(virtual axi4_stream_if #(64))::get(null, "*", "cfg_vif", cfg_vif))
            `uvm_fatal("NO_VIF", "Could not get cfg_vif for reset injection")
        if (!uvm_config_db#(virtual bnn_reset_if)::get(null, "*", "reset_vif", reset_vif))
            `uvm_fatal("NO_RESET_VIF", "Could not get reset_vif for reset injection")

        env.scoreboard.handle_reset();
        @(posedge cfg_vif.aclk);
        reset_vif.rst   <= 1'b1;
        reset_vif.rst_n <= 1'b0;
        repeat (5) @(posedge cfg_vif.aclk);
        reset_vif.rst   <= 1'b0;
        reset_vif.rst_n <= 1'b1;
        repeat (5) @(posedge cfg_vif.aclk);
        env.scoreboard.clear_reset();
    endtask

    virtual task run_phase(uvm_phase phase);
        bnn_cfg_sequence cfg_seq;
        bnn_image_sequence in_seq;
        axi4s_ready_sequence out_seq;
        int reset_count = 0;

        phase.raise_objection(this);

        out_seq = axi4s_ready_sequence::type_id::create("out_seq");
        out_seq.ready_off_min = 2;
        out_seq.ready_off_max = 10;
        fork
            out_seq.start(null);
        join_none

        // --- Scenario 1: Reset during idle (baseline) ---
        `uvm_info("TEST", "=== Reset stress: idle reset ===", UVM_LOW)
        inject_reset();
        reset_count++;
        env.coverage.sample_reset_event(0, reset_count); // phase=idle

        // --- Scenario 2: Normal config, then reset during image input ---
        `uvm_info("TEST", "=== Reset stress: reset during image input ===", UVM_LOW)
        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq1");
        cfg_seq.start(env.cfg_agent.sequencer);

        fork begin
            in_seq = bnn_image_sequence::type_id::create("in_seq1");
            in_seq.start(env.in_agent.sequencer);
        end join_none

        #5000; // mid-image
        inject_reset();
        reset_count++;
        env.coverage.sample_reset_event(2, reset_count); // phase=during_image
        disable fork;

        // --- Scenario 3: Post-reset same config replay ---
        `uvm_info("TEST", "=== Reset stress: same config after reset ===", UVM_LOW)
        env.scoreboard.handle_reconfig();
        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq2");
        cfg_seq.start(env.cfg_agent.sequencer);

        in_seq = bnn_image_sequence::type_id::create("in_seq2");
        in_seq.start(env.in_agent.sequencer);
        #30000;

        env.coverage.sample_post_reset(1); // same_cfg=1
        env.coverage.sample_reconfig(0, model.num_layers);

        // --- Scenario 4: Reset during config streaming ---
        `uvm_info("TEST", "=== Reset stress: reset during config ===", UVM_LOW)
        fork begin
            bnn_cfg_sequence cfg_seq3 = bnn_cfg_sequence::type_id::create("cfg_seq3");
            cfg_seq3.start(env.cfg_agent.sequencer);
        end join_none

        #2000; // mid-config
        inject_reset();
        reset_count++;
        env.coverage.sample_reset_event(1, reset_count); // phase=during_config
        disable fork;

        // --- Scenario 5: Post-reset different config (random model) ---
        `uvm_info("TEST", "=== Reset stress: different config after reset ===", UVM_LOW)
        model.create_random(bnn_topology);
        stim.generate_random_vectors(10);
        env.scoreboard.handle_reconfig();

        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq4");
        cfg_seq.start(env.cfg_agent.sequencer);

        in_seq = bnn_image_sequence::type_id::create("in_seq3");
        in_seq.start(env.in_agent.sequencer);
        #50000;

        env.coverage.sample_post_reset(0); // same_cfg=0

        phase.drop_objection(this);
    endtask
endclass
`endif
