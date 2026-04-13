// Greg Stitt
// University of Florida
//
// Focused UVM test that keeps the configuration stream in its normal packet
// format while exercising randomized TKEEP handling on only the image input
// stream.

`ifndef _BNN_FCC_INPUT_TKEEP_PACKET_TEST_SVH_
`define _BNN_FCC_INPUT_TKEEP_PACKET_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_input_tkeep_packet_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_input_tkeep_packet_test)

    function new(string name = "bnn_fcc_input_tkeep_packet_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence       cfg_seq;
        bnn_fcc_image_tkeep_packet_sequence  img_seq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting packet-level test with normal config and randomized data_in TKEEP.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("cfg_seq");
        img_seq = bnn_fcc_image_tkeep_packet_sequence::type_id::create("img_seq");

        run_config_sequence(cfg_seq, model, "initial full configuration");
        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_done();

        phase.drop_objection(this);
    endtask
endclass

`endif
