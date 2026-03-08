// Pawin Ruangkanit
// University of Florida

// Description: This entity implements a fully pipelined xnor-add tree that
// computes the xnor popcount of 2 input arrays and then accumulates the results.
// The inputs should be two arrays of num_inputs elements, where each element
// is in_width bits wide.

// The latency of the entity for an INPUT_WIDTH of 1 is clog2(num_inputs)+1
// For INPUT_WIDTH>1, this becomes clog2(num_inputs)+2

module xnor_add_tree #(
    parameter int NUM_INPUTS  = 64,
    parameter int INPUT_WIDTH = 1
) (
    input logic clk,
    input logic rst,
    input logic en,
    // Inputs: Packed 2D arrays [Element][Bits]
    input logic [INPUT_WIDTH-1:0] in1[NUM_INPUTS],
    input logic [INPUT_WIDTH-1:0] in2[NUM_INPUTS],
    // Output: Width grows by log2 of inputs to prevent overflow
    output logic [$clog2((INPUT_WIDTH <= 1 ? 1 : $clog2(INPUT_WIDTH + 1)) * NUM_INPUTS + 1)-1:0] sum
);

  localparam int COUNT_WIDTH = (INPUT_WIDTH <= 1) ? 1 : $clog2(INPUT_WIDTH + 1);
  localparam int SUM_WIDTH = COUNT_WIDTH + $clog2(NUM_INPUTS);

  logic [INPUT_WIDTH-1:0] xnor_out[NUM_INPUTS];
  logic [COUNT_WIDTH-1:0] popcount_out[NUM_INPUTS];

  // Calculate XNOR output
  genvar i;
  generate
    for (i = 0; i < NUM_INPUTS; i++) begin : g_xnor
      // a pipelined xnor
      always_ff @(posedge clk) begin
        if (en) begin
          xnor_out[i] <= ~(in1[i] ^ in2[i]);
        end
      end
    end
  endgenerate

  // Convert XNOR into popcount
  generate
    if (INPUT_WIDTH == 1) begin : g_no_popcount
      for (i = 0; i < NUM_INPUTS; i++) begin : g_assign_1bit
        assign popcount_out[i] = xnor_out[i];
      end
    end else begin : g_popcount
      for (i = 0; i < NUM_INPUTS; i++) begin : g_count
        always_comb begin
          popcount_out[i] = '0;
          for (int j = 0; j < INPUT_WIDTH; j++) begin
            popcount_out[i] += xnor_out[i][j];
          end
        end
      end
    end
  endgenerate

  // feed popcount output into adder tree
  add_tree #(
      .NUM_INPUTS (NUM_INPUTS),
      .INPUT_WIDTH(COUNT_WIDTH)
  ) u_add_tree (
      .clk   (clk),
      .rst   (rst),
      .en    (en),
      .inputs(popcount_out),
      .sum   (sum)
  );

endmodule
