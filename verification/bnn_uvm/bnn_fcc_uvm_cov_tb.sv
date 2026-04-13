`timescale 1ns / 100ps

// Thin wrapper used only for one-shot coverage evaluation. It intentionally
// does not redeclare the runtime/configuration parameters from
// bnn_fcc_uvm_tb, so Questa's global -g overrides continue to apply directly
// to the instantiated UVM top without conflicting duplicate parameters. The
// sweep-specific time parameters are baked in here because Questa rejects the
// global -g override when those `time` parameters live under a nested instance.
module bnn_fcc_uvm_cov_tb;

    bnn_fcc_uvm_tb #(
        .TIMEOUT(1s),
        .CLK_PERIOD(10ns),
        .DEFAULT_UVM_TESTNAME("bnn_fcc_coverage_sweep_test")
    ) u_cov_tb ();

endmodule
