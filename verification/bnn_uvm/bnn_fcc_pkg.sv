// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// PACKAGE: bnn_fcc_pkg
// Maps to: IMPLEMENTATION_PLAN.md §"UVM scaffold integration"
//
// DESCRIPTION:
// Compilation-ordered package including all BNN UVM components.
// Include order matters: sequences before env components, env before tests.

package bnn_fcc_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import axi4_stream_pkg::*;
    import bnn_fcc_tb_pkg::*;

    // Sequences (no dependencies on env)
    `include "bnn_cfg_sequence.svh"
    `include "bnn_image_sequence.svh"
    `include "axi4s_ready_sequence.svh"

    // Environment components (scoreboard defines bnn_expected_queue used by sequences)
    `include "bnn_fcc_scoreboard.svh"
    `include "bnn_fcc_coverage.svh"
    `include "bnn_fcc_env.svh"

    // Tests (depend on env + sequences)
    `include "bnn_fcc_base_test.svh"
    `include "bnn_fcc_protocol_stress_test.svh"
    `include "bnn_fcc_reconfig_test.svh"
    `include "bnn_fcc_reset_stress_test.svh"
    `include "bnn_fcc_output_class_test.svh"

endpackage
