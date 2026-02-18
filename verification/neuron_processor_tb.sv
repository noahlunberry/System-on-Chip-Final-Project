module neuron_processor_tb #(
    parameter int NUM_TESTS = 1000,
    parameter int P_WIDTH = 64,
    parameter int TOTAL_INPUTS = 788,
    parameter int ACC_WIDTH = 16
);
  logic clk, rst, valid_in, last;
  logic [P_WIDTH-1:0] x, w;
  logic [ACC_WIDTH-1:0] threshold;

  logic y, y_valid;

  int passed, failed;

  // Instantiate DUT
  neuron_processor #(
      .P_WIDTH(P_WIDTH),
      .TOTAL_INPUTS(TOTAL_INPUTS)
  ) DUT (
      .*
  );

  // Transaction Item Class: Generate one full frame of x,w inputs
  class np_item;
    rand bit [TOTAL_INPUTS-1:0] x;
    rand bit [TOTAL_INPUTS-1:0] w;
    rand bit [ACC_WIDTH-1:0] threshold;
  endclass

  // Reference Model: Match the xnors/adds being computed by the tree
  function automatic int model_popcount(bit [TOTAL_INPUTS-1:0] x, bit [TOTAL_INPUTS-1:0] w);
    // signals
    int acc = 0;
    acc = 0;
    // xnor and accumulate all inputs
    for (int i = 0; i < TOTAL_INPUTS; i++) begin
      acc += (x[i] == w[i]);
    end
    return acc;
  endfunction

  // Generate Clock
  initial begin : generate_clock
    forever #5 clk <= ~clk;
  end

  // Initialize the DUT
  initial begin : initialization
    $timeformat(-9, 0, " ns ");

    // reset the design
    rst       <= 1'b1;
    valid_in  <= 1'b0;
    last      <= 1'b0;
    x         <= '0;
    w         <= '0;
    threshold <= '0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
  end

  // Stimulus generation for random tests
  initial begin : generator
    np_item test;
    for (int i = 0; i < NUM_TESTS; i++) begin
      test = new();
      assert (test.randomize())
      else $fatal(1, "Failed to randomize.");

      driver_mailbox.put(test);
    end
  end
  // Monitor to detect the start of execution

  // Monitor to detect the end of execution

  // Driver that drives the items, while also optionally toggling the inputs
  // while the DUT is active.
  initial begin : driver
    np_item test;
    int num_chunks;
    num_chunks = (TOTAL_INPUTS + P_WIDTH -1) / P_WIDTH;
    
    @(posedge clk iff !rst);
    forever begin
      driver_mailbox.get(test);


    end
  end

  // Verify the Results


endmodule
