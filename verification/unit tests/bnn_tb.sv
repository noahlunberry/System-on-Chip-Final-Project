// MODULE: bnn_fcc_tb
//
// DESCRIPTION:
// Testbench for the binary neural net (bnn) fully connected classifier (fcc).
//
// There are two modes for the testbench. If you enable USE_CUSTOM_TOPOLOGY, the testbench
// evaluates the topology specified by CUSTOM_TOPOLOGY using a random model (weights+thresholds).
//
// For USE_CUSTOM_TOPOLOGY=0, the testbench uses the SFC topology (784->256->256->10) for MNIST from the FINN paper:
// Umuroglu, Y., Fraser, N. J., Gambardella, G., Blott, M., Leong, P., Jahre, M., & Vissers, K. (2017). FINN: A Framework for Fast, Scalable Binarized Neural Network Inference. In Proceedings of the 2017 ACM/SIGDA International Symposium on Field-Programmable Gate Arrays (pp. 65-74). DOI: 10.1145/3020078.3021744
//
// For the SFC topology, the testbench uses trained weights and thresholds from Python code.
//
// The testbench compares the actual outputs with the expected outputs provided in the BNN_MODEL
// class (see bnn_fcc_tb_pkg.sv). That class also contains a variety of functions that you might find
// useful for debugging.
//
// bnn_fcc_tb_pkg.sv also provides a BNN_FCC_Stimulus class that loads images from files (in the
// case of MNIST) or randomly generates test images (for USE_CUSTOM_TOPOLOGY=0).
//
// PARAMETERS:
// [Testbench Configuration]
// USE_CUSTOM_TOPOLOGY       - Enable user-defined NN topology specified by CUSTOM_TOPOLOGY
//                             instead of the default SFC topology for MNIST.
// CUSTOM_LAYERS             - Total layers (Includes input, hidden, and output) if using a custom topology.
// CUSTOM_TOPOLOGY           - Array defining neurons per layer, with the exception of
//                             CUSTOM_TOPOLOGY[0], which specifies the number of inputs.
// NUM_TEST_IMAGES           - Number of stimulus images for simulation
// VERIFY_MODEL              - Cross-check SV results against Python model 
//                             (only applicable to USE_CUSTOM_TOPOLOGY=1'b0)
// BASE_DIR                  - Path to Python model data and test vectors (must be set relative to
//                             your simulator's working directory)
// TOGGLE_DATA_OUT_READY     - Randomly toggles data_out_ready to simulate back-pressure. Must be enabled
//                             to fully pass tests for contest. Disable to measure throughput and latency.
// CONFIG_VALID_PROBABILITY  - Real value from 0.0 to 1.0 that specifies the probability of the
//                             configuration bus providing valid data while the DUT is ready. Used to
//                             simulate a slow upstream producer. Must be set to a value less than 1.0
//                             to full pass testing, but should be set to 1 to measure performance.
// DATA_IN_VALID_PROBABILITY - Real value from 0.0 to 1.0 that specifies the probability of the
//                             data_in bus providing valid pixels while the DUT is ready. Used to
//                             simulate a slow upstream producer. Must be set to a value less than 1.0
//                             to fully pass testing, but should be set to 1 to measure performance.
// TIMEOUT                   - Realtime value that specifies the maximum amount of time the testbench is
//                             allowed to run before being terminated. Adjust based on the expected 
//                             performance of your design.
// CLK_PERIOD                - Realtime value specifying the clock period.
// DEBUG                     - Set to print model details and an inference trace for each layer.
//
// [Bus Configuration]
// WEIGHT_WIDTH          - Bit-width for configuration bus (AXI streaming)
// INPUT_BUS_WIDTH           - Bit-width for primary input data stream (AXI streaming)
// OUTPUT_BUS_WIDTH          - Bit-width for output (AXI streaming)
//
// [App Configuration]       (Note: changes to the defaults have not been tested, may break classes in bnn_fcc_tb_pkg)
// INPUT_DATA_WIDTH          - Bit-width of individual input elements (8-bit for MNIST)
// OUTPUT_DATA_WIDTH         - Bit-width of individual output elements
//
// [DUT Configuration]       (TODO: Adapt to your own DUT if necessary. Feel free to create, ignore, and/or remove parameters)
// PARALLEL_INPUTS           - Number of inputs/weights processed in parallel in the first hidden layer.
// PARALLEL_NEURONS          - Number of neurons processed in parallel in each non-input layer.

`timescale 1ns / 100ps

module bnn_tb #(
    // Testbench configuration
    parameter int      USE_CUSTOM_TOPOLOGY                      = 1'b1,
    parameter int      CUSTOM_LAYERS                            = 4,
    parameter int      CUSTOM_TOPOLOGY          [CUSTOM_LAYERS] = '{32, 8, 8, 8},
    parameter int      NUM_TEST_IMAGES                          = 50,
    parameter bit      TOGGLE_DATA_OUT_READY                    = 1'b1,
    parameter real     CONFIG_VALID_PROBABILITY                 = 0.8,
    parameter real     DATA_IN_VALID_PROBABILITY                = 0.8,
    parameter realtime TIMEOUT                                  = 10ms,
    parameter realtime CLK_PERIOD                               = 10ns,
    parameter bit      DEBUG                                    = 1'b1,

    // Bus configuratio
    parameter int WEIGHT_WIDTH = 8,
    parameter int THRESHOLD_WIDTH = $clog2(NUM_INPUTS + 1),
    parameter int INPUT_BUS_WIDTH = 64,
    parameter int OUTPUT_BUS_WIDTH = 8,

    // BNN configuration
    parameter int LAYERS = 3,
    parameter int NUM_INPUTS = CUSTOM_TOPOLOGY[0],
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int THRESHOLD_DATA_WIDTH = THRESHOLD_WIDTH,
    //  parameter int THRESHOLD_DATA_WIDTH = $clog2(NUM_INPUTS + 1),

    // App configuration
    parameter  int INPUT_DATA_WIDTH  = 8,
    localparam int INPUTS_PER_CYCLE  = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH,
    localparam int BYTES_PER_INPUT   = INPUT_DATA_WIDTH / 8,
    parameter  int OUTPUT_DATA_WIDTH = 4,

    // Should not be changed
    localparam int TRAINED_LAYERS = 4,
    localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10},

    // DUT configuration (can be modified or extended for your own DUT)        
    localparam int NON_INPUT_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS - 1 : TRAINED_LAYERS - 1,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[NON_INPUT_LAYERS] = '{8, 8, 8}
);
  import bnn_tb_pkg::*;


  localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

  initial begin
    assert (INPUT_DATA_WIDTH == 8)
    else
      $fatal(
          1, "TB ERROR: INPUT_DATA_WIDTH must be 8. Sub-byte or multi-byte packing logic not yet implemented."
      );
  end

  // Returns 1 with probability p, 0 with probability 1-p.
  function automatic bit chance(real p);
    if (p > 1.0 || p < 0.0) $fatal(1, "Invalid probability in chance()");
    return ($urandom < (p * (2.0 ** 32)));
  endfunction

  BNN_Model #(WEIGHT_WIDTH, THRESHOLD_WIDTH) model;
  BNN_FCC_Stimulus #(INPUT_DATA_WIDTH) stim;
  // ThroughputTracker throughput;


  typedef bit [WEIGHT_WIDTH-1:0] weight_data_t;
  typedef weight_data_t weight_data_stream_t[];

  typedef bit [THRESHOLD_WIDTH-1:0] threshold_data_t;
  typedef threshold_data_t threshold_data_stream_t[];

  bit   [              WEIGHT_WIDTH-1:0] weight_data_stream   [];
  bit   [           THRESHOLD_WIDTH-1:0] threshold_data_stream[];

  int                                    num_tests;
  int                                    passed;
  int                                    failed;

  logic                                  clk = 1'b0;
  logic                                  rst;
  logic                                  data_out_ready;
  logic                                  bnn_ready;
  logic [      THRESHOLD_DATA_WIDTH-1:0] count_out            [PARALLEL_NEURONS[LAYERS-1]];

  logic [       MAX_PARALLEL_INPUTS-1:0] weight_wr_data;
  logic [                    LAYERS-1:0] weight_wr_en;
  logic [      THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data;
  logic [                    LAYERS-1:0] threshold_wr_en;

  logic [           PARALLEL_INPUTS-1:0] data_in;
  logic                                  data_in_valid;
  logic [PARALLEL_NEURONS[LAYERS-1]-1:0] data_out;
  logic                                  data_out_valid;


  bnn #(
      .LAYERS              (LAYERS  /* default 3 */),
      .NUM_INPUTS          (NUM_INPUTS  /* default 784 */),
      .NUM_NEURONS         (  CUSTOM_TOPOLOGY[1:LAYERS]),
      .PARALLEL_INPUTS     (PARALLEL_INPUTS  /* default 8 */),
      .PARALLEL_NEURONS    (PARALLEL_NEURONS  /* default '{default: 8} */),
      .MAX_PARALLEL_INPUTS (MAX_PARALLEL_INPUTS  /* default 8 */),
      .THRESHOLD_DATA_WIDTH(THRESHOLD_DATA_WIDTH  /* default $clog2(NUM_INPUTS + 1) */)
  ) bnn (
      .clk              (clk),
      .rst              (rst),
      .en               (data_out_ready),
      .ready            (bnn_ready),
      .weight_wr_data   (weight_wr_data),
      .weight_wr_en     (weight_wr_en),
      .threshold_wr_data(threshold_wr_data),
      .threshold_wr_en  (threshold_wr_en),
      .data_in          (data_in),
      .data_in_valid    (data_in_valid),
      .data_out         (data_out),
      .count_out        (count_out),
      .data_out_valid   (data_out_valid)
  );

  initial begin : generate_clock
    forever #HALF_CLK_PERIOD clk <= ~clk;
  end


  // ===========================================================================
  // Initialize model and config memory
  // ===========================================================================
  initial begin : l_init_model
    string path;
    model = new();
    stim  = new(CUSTOM_TOPOLOGY[0]);

    $display("--- Loading Randomized Model ---");
    model.create_random(CUSTOM_TOPOLOGY);
    // instead of packing the layers into a flat array, we will stream them in layer by layer in the driver

    $display("--- Generating Random Test Vectors ---");
    stim.generate_random_vectors(NUM_TEST_IMAGES);

    num_tests = stim.get_num_vectors();
    model.print_summary();

    if (DEBUG) model.print_model();

    // NOTE: You can also debug by looking at the model's weights, thresholds, and layer ouputs. 
    // For example, this prints the model for all neurons in the first hidden layer:
    // for (int i = 0; i < CUSTOM_TOPOLOGY[1]; i++) model.print_neuron(0, i);      
    //
    // where the parameters specify the layer and neuron. This loop iterates over all
    // neurons in the first hidden layer. Note that the parameters treat the first hidden layer
    // as layer 0, essentially excluding the input layer since it has no neurons.
    //
    // Weights are accessible via model.weight[][][], where the dimensions are:
    // [layer][neuron][bit]
    //
    // thresholds are accessible via model.threshold[][], where the dimensions are:
    // [layer][neuron]
  end

  logic [OUTPUT_DATA_WIDTH-1:0] expected_outputs[$];


  initial begin : l_sequencer_and_driver
    // temp variables to hold current layer's data
    weight_data_stream_t    layer_weights;
    threshold_data_stream_t layer_thresholds;

    $timeformat(-9, 0, " ns", 0);
    rst               <= 1'b1;
    data_out_ready    <= 1'b0;
    weight_wr_data    <= '0;
    weight_wr_en      <= 1'b0;
    threshold_wr_data <= '0;
    threshold_wr_en   <= 1'b0;
    data_in           <= '0;
    data_in_valid     <= 1'b0;


    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
    repeat (5) @(posedge clk);

    // Stream in weights and thresholds layer by layer.
    for (int l = 0; l < LAYERS; l++) begin

      // Stream Weights for Layer 'l'
      // Fetch just the weights (is_threshold = 0)
      model.get_layer_config(l, 0, layer_weights, layer_thresholds);

      $display("[%0t] Streaming %0d weight words for Layer %0d", $realtime, layer_weights.size(), l);

      for (int i = 0; i < layer_weights.size(); i++) begin
        // simulate gaps
        while (!chance(
            CONFIG_VALID_PROBABILITY
        )) begin
          weight_wr_en <= '0;  // De-assert all layers
          @(posedge clk);
        end

        weight_wr_en   <= (1 << l);  // Hot-encode the current layer (e.g. Layer 1 -> 2'b10)
        weight_wr_data <= layer_weights[i];
        @(posedge clk);
      end

      weight_wr_en <= '0;  // Turn off weight enable before switching to thresholds


      // Stream Thresholds for Layer 'l' (Skip final layer)
      if (l < LAYERS - 1) begin
        // Fetch just the thresholds (is_threshold = 1)
        model.get_layer_config(l, 1, layer_weights, layer_thresholds);

        $display("[%0t] Streaming %0d threshold words for Layer %0d", $realtime, layer_thresholds.size(), l);

        for (int i = 0; i < layer_thresholds.size(); i++) begin
          // Bubble generator
          while (!chance(
              CONFIG_VALID_PROBABILITY
          )) begin
            threshold_wr_en <= '0;
            @(posedge clk);
          end

          threshold_wr_en   <= (1 << l);  // Hot-encode the current layer
          threshold_wr_data <= layer_thresholds[i];
          @(posedge clk);
        end

        threshold_wr_en <= '0;  // Turn off threshold enable before moving to next layer
      end
    end



    $display("[%0t] Configuration complete. Waiting for bnn_ready...", $realtime);
    wait (bnn_ready);
    repeat (5) @(posedge clk);

    for (int i = 0; i < num_tests; i++) begin
      int expected_pred;
      bit expected_bit;
      bit [INPUT_DATA_WIDTH-1:0] current_img[];

      // Fetch stimulus image i (pre-created by either stim.load_from_file() or stim.generate_random_vectors())
      stim.get_vector(i, current_img);

      // Compute expected output for current image. This also generates references for each layer's
      // outputs, which can be accessed via model.layer_outputs[layer][neuron] for deeper verification.
      expected_pred = model.compute_reference(current_img);
      expected_outputs.push_back(expected_pred);

      // Stream image into DUT.
      $display("[%0t] Streaming image %0d.", $realtime, i);
      if (DEBUG) model.print_inference_trace();

      for (int j = 0; j < current_img.size(); j += INPUTS_PER_CYCLE) begin

        // Pack multiple pixels into a single AXI beat.
        for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
          if (j + k < current_img.size()) begin
            data_in[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= current_img[j+k];
          end else begin
            data_in[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] <= '0;
          end
        end

        // Simulate gaps on data_in bus.
        while (!chance(
            DATA_IN_VALID_PROBABILITY
        )) begin
          data_in_valid <= 1'b0;
          @(posedge clk iff bnn_ready);
        end
        data_in_valid <= 1'b1;
        @(posedge clk iff bnn_ready);

        // Start the throughput timer after the first beat of the first image has been accepted.                
        // if (i == 0 && j == 0) throughput.start_test();
      end

      data_in_valid <= 1'b0;
      @(posedge clk);
    end

    $display("[%0t] All images loaded, waiting for outputs.", $realtime);
    wait (expected_outputs.size() == 0);
    repeat (5) @(posedge clk);

    disable generate_clock;
    disable l_timeout;
    if (passed == num_tests)
      $display("[%0t] SUCCESS: all %0d tests completed successfully.", $realtime, num_tests);
    else $error("FAILED: %0d out of %0d tests failed.", failed, num_tests);

    $display("\nStats:");
  end

  initial begin : l_toggle_ready
    data_out_ready <= 1'b1;
    @(posedge clk iff !rst);
    if (TOGGLE_DATA_OUT_READY) begin
      forever begin
        data_out_ready <= $urandom();
        @(posedge clk);
      end
    end else data_out_ready <= 1'b1;
  end

  initial begin : l_output_monitor
    automatic int output_count = 0;
    forever begin
      @(posedge clk iff data_out_valid && data_out_ready);
      assert (expected_outputs.size() > 0)
      else $fatal(1, "No expected output for actual output");
      assert (data_out == expected_outputs[0]) begin
        passed++;
      end else begin
        $error("Output incorrect for image %0d: actual = %0d vs expected = %0d", output_count,
               data_out, expected_outputs[0]);
        failed++;
      end
      void'(expected_outputs.pop_front());
      // if (output_count == NUM_TEST_IMAGES - 1) throughput.sample_end();
      output_count++;
    end
  end

  initial begin : l_timeout
    #TIMEOUT;
    $fatal(1, $sformatf("Simulation failed due to timeout of %0t.", TIMEOUT));
  end

endmodule
