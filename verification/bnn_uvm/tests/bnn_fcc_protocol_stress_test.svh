// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// TEST: bnn_fcc_protocol_stress_test
// Maps to: coverage_plan.txt CATEGORY 1 & IMPLEMENTATION_PLAN.md §"Protocol-pattern directed tests"
//
// DESCRIPTION:
// Derived test targeting AXI protocol corner cases:
//   - Bursty TVALID with large inter-beat gaps on config + input
//   - Heavy backpressure on output (long TREADY stalls)
//   - Exercises cg_cfg_handshake, cg_in_handshake, cg_out_backpressure

`ifndef _BNN_FCC_PROTOCOL_STRESS_TEST_SVH_
`define _BNN_FCC_PROTOCOL_STRESS_TEST_SVH_

class bnn_fcc_protocol_stress_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_protocol_stress_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        bnn_cfg_sequence cfg_seq;
        bnn_image_sequence in_seq;
        axi4s_ready_sequence out_seq;

        phase.raise_objection(this);

        // Large inter-beat delays to create intermittent/bursty TVALID
        env.cfg_agent.driver.set_delay(1, 10);
        env.in_agent.driver.set_delay(1, 5);

        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq");
        in_seq  = bnn_image_sequence::type_id::create("in_seq");
        out_seq = axi4s_ready_sequence::type_id::create("out_seq");

        // Heavy backpressure: long stalls on output ready
        out_seq.ready_on_min  = 1;
        out_seq.ready_on_max  = 5;
        out_seq.ready_off_min = 5;
        out_seq.ready_off_max = 20;

        fork
            out_seq.start(null);
        join_none

        // Use shuffled config ordering for additional Cat 1 coverage
        cfg_seq.reorder_msgs = 1;

        cfg_seq.start(env.cfg_agent.sequencer);
        in_seq.start(env.in_agent.sequencer);

        #500000;
        phase.drop_objection(this);
    endtask

endclass

`endif
