module neuron_tree #(
    parameter int NUM_INPUTS  = 64,
    parameter int INPUT_WIDTH = 1
) (
    input  logic                                                       clk,
    input  logic                                                       rst,
    input  logic                                                       en,
    // Inputs: Packed 2D arrays [Element][Bits]
    input  logic [                    NUM_INPUTS-1:0][INPUT_WIDTH-1:0] x,
    input  logic [                    NUM_INPUTS-1:0][INPUT_WIDTH-1:0] w,
    // Output: Width grows by log2 of inputs to prevent overflow
    output logic [INPUT_WIDTH+$clog2(NUM_INPUTS)-1:0]                  sum
);

  generate
    if (NUM_INPUTS < 1) begin : l_validation
      $fatal(1, "ERROR: NUM_INPUTS must be positive.");
    end

    if (NUM_INPUTS == 1) begin : l_leaf
      assign sum = ~(x ^ w);
    end else begin : l_recurse
      localparam int LEFT_INPUTS = int'($ceil(NUM_INPUTS / 2.0));
      localparam int RIGHT_INPUTS = NUM_INPUTS - LEFT_INPUTS;

      // Calculate Depths for Alignment
      localparam int LEFT_DEPTH = $clog2(LEFT_INPUTS);
      localparam int RIGHT_DEPTH = $clog2(RIGHT_INPUTS);

      // Wire definitions for sub-trees
      logic [INPUT_WIDTH+$clog2(LEFT_INPUTS)-1:0] left_sum;
      logic [INPUT_WIDTH+$clog2(RIGHT_INPUTS)-1:0] right_sum, right_sum_unaligned;

      // 2. Instantiate Left Tree
      // Slicing: Bottom half [LEFT-1 : 0]
      neuron_tree #(
          .NUM_INPUTS (LEFT_INPUTS),
          .INPUT_WIDTH(INPUT_WIDTH)
      ) left_tree (
          .clk,
          .rst,
          .en,
          .x  (x[LEFT_INPUTS-1:0]),
          .w  (w[LEFT_INPUTS-1:0]),
          .sum(left_sum)
      );

      // 3. Instantiate Right Tree
      // Slicing: Top half [NUM-1 : LEFT]
      neuron_tree #(
          .NUM_INPUTS (RIGHT_INPUTS),
          .INPUT_WIDTH(INPUT_WIDTH)
      ) right_tree (
          .clk,
          .rst,
          .en,
          .x  (x[NUM_INPUTS-1:LEFT_INPUTS]),
          .w  (w[NUM_INPUTS-1:LEFT_INPUTS]),
          .sum(right_sum_unaligned)
      );


      localparam int LATENCY_DIFF = LEFT_DEPTH - RIGHT_DEPTH;

      if (LATENCY_DIFF > 0) begin : l_align
        logic [$bits(right_sum_unaligned)-1:0] delay_regs[LATENCY_DIFF];

        always_ff @(posedge clk) begin
          if (rst) begin
            for (int i = 0; i < LATENCY_DIFF; i++) delay_regs[i] <= '0;
          end else if (en) begin
            delay_regs[0] <= right_sum_unaligned;
            for (int i = 1; i < LATENCY_DIFF; i++) delay_regs[i] <= delay_regs[i-1];
          end
        end
        assign right_sum = delay_regs[LATENCY_DIFF-1];
      end else begin : l_no_delay
        assign right_sum = right_sum_unaligned;
      end

      always_ff @(posedge clk) begin
        if (rst) begin
          sum <= '0;
        end else if (en) begin
          sum <= left_sum + right_sum;
        end
      end
    end
  endgenerate
endmodule
