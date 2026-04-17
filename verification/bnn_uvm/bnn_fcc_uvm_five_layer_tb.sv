`timescale 1ns / 100ps

// Dedicated wrapper that exercises a deeper custom topology while preserving
// the 10-class output layer. "Five layers" here follows the existing repo
// convention and includes the input layer:
// 784 -> 256 -> 128 -> 64 -> 10
module bnn_fcc_uvm_five_layer_tb #(
    parameter int NUM_TEST_IMAGES = 20,
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

  localparam int CUSTOM_LAYERS = 5;
  localparam int CUSTOM_TOPOLOGY[CUSTOM_LAYERS] = '{784, 256, 128, 64, 10};
  localparam int PARALLEL_NEURONS[CUSTOM_LAYERS-1] = '{64, 32, 16, 10};

  bnn_fcc_uvm_tb #(
      .USE_CUSTOM_TOPOLOGY(1'b1),
      .CUSTOM_LAYERS      (CUSTOM_LAYERS),
      .CUSTOM_TOPOLOGY    (CUSTOM_TOPOLOGY),
      .PARALLEL_INPUTS    (32),
      .PARALLEL_NEURONS   (PARALLEL_NEURONS),
      .NUM_TEST_IMAGES    (NUM_TEST_IMAGES),
      .VERIFY_MODEL       (VERIFY_MODEL),
      .BASE_DIR           (BASE_DIR),
      .TOGGLE_DATA_OUT_READY(TOGGLE_DATA_OUT_READY),
      .CONFIG_VALID_PROBABILITY(CONFIG_VALID_PROBABILITY),
      .DATA_IN_VALID_PROBABILITY(DATA_IN_VALID_PROBABILITY),
      .TIMEOUT            (TIMEOUT),
      .CLK_PERIOD         (CLK_PERIOD),
      .DEBUG              (DEBUG),
      .DEFAULT_UVM_TESTNAME(DEFAULT_UVM_TESTNAME)
  ) u_five_layer_tb ();

endmodule
