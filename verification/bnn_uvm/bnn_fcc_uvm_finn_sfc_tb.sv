`timescale 1ns / 100ps

// FINN SFC topology from Umuroglu et al. (2017):
// 784 -> 256 -> 256 -> 10
//
// This wrapper uses the repo's trained/default SFC flow rather than a
// randomized custom-topology model, so it exercises the exact FCC topology the
// project README already treats as the contest baseline.
module bnn_fcc_uvm_finn_sfc_tb #(
    parameter int NUM_TEST_IMAGES = 50,
    parameter bit VERIFY_MODEL = 1,
    parameter string BASE_DIR = "/ecel/UFAD/ruangkanitpawin/Projects/bnn_fcc_contest/python",
    parameter bit TOGGLE_DATA_OUT_READY = 1'b1,
    parameter real CONFIG_VALID_PROBABILITY = 0.6,
    parameter real DATA_IN_VALID_PROBABILITY = 0.75,
    parameter time TIMEOUT = 100ms,
    parameter time CLK_PERIOD = 10ns,
    parameter bit DEBUG = 1'b0,
    parameter string DEFAULT_UVM_TESTNAME = "bnn_fcc_single_beat_test"
);

  bnn_fcc_uvm_tb #(
      .USE_CUSTOM_TOPOLOGY   (1'b0),
      .NUM_TEST_IMAGES       (NUM_TEST_IMAGES),
      .VERIFY_MODEL          (VERIFY_MODEL),
      .BASE_DIR              (BASE_DIR),
      .TOGGLE_DATA_OUT_READY (TOGGLE_DATA_OUT_READY),
      .CONFIG_VALID_PROBABILITY(CONFIG_VALID_PROBABILITY),
      .DATA_IN_VALID_PROBABILITY(DATA_IN_VALID_PROBABILITY),
      .TIMEOUT               (TIMEOUT),
      .CLK_PERIOD            (CLK_PERIOD),
      .DEBUG                 (DEBUG),
      .DEFAULT_UVM_TESTNAME  (DEFAULT_UVM_TESTNAME)
  ) u_sfc_tb ();

endmodule
