// Pawin Ruangkanit
// University of Florida
//
// This file provides the single-beat UVM test that mirrors the original
// non-UVM bnn_fcc_tb behavior using the shared base test infrastructure.

`ifndef _BNN_FCC_SINGLE_BEAT_TEST_SVH_
`define _BNN_FCC_SINGLE_BEAT_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;


// -----------------------------------------------------------------------------
// Single-Beat Test
// -----------------------------------------------------------------------------
// This test mirrors the existing non-UVM TB as closely as possible using the
// current UVM infrastructure:
// 1. optionally verify the SV reference model against Python outputs
// 2. send configuration traffic
// 3. send images as individual AXI beats
// 4. rely on the top-level TB to toggle output ready in parallel
// 5. wait until the scoreboard has checked every image
class bnn_fcc_single_beat_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_single_beat_test)

    function new(string name = "bnn_fcc_single_beat_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_beat_sequence cfg_seq;
        bnn_fcc_image_beat_sequence  img_seq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting single-beat baseline test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        cfg_seq = bnn_fcc_config_beat_sequence::type_id::create("cfg_seq");
        img_seq = bnn_fcc_image_beat_sequence::type_id::create("img_seq");

        // Use the shared helper so the raw config traffic, scoreboard model
        // commit, and reconfiguration coverage stay in sync.
        run_config_sequence(cfg_seq, model, "initial full configuration");

        if (debug)
            `uvm_info(get_type_name(), "Configuration sequence completed. Starting image sequence.", UVM_LOW)

        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_done();

        phase.drop_objection(this);
    endtask

endclass

`endif
