module neuron_processor #(
    parameter int P_WIDTH      = 64,   // Parallel inputs per cycle
    parameter int TOTAL_INPUTS = 788,  // Total inputs per neuron
    parameter int ACC_WIDTH    = 16    // Width of final accumulator
) (
    input logic                 clk,
    input logic                 rst,
    input logic                 valid_in,  // Input stream is valid
    input logic                 last,
    input logic [  P_WIDTH-1:0] x,         // Input data stream
    input logic [  P_WIDTH-1:0] w,         // Weight data stream
    input logic [ACC_WIDTH-1:0] threshold,

    output logic y,       // Final neuron activation
    output logic y_valid  // Pulsed when y is ready
);


  localparam int TREE_OUT_W = 1 + $clog2(P_WIDTH);  // 7 bits
  logic [TREE_OUT_W-1:0] tree_sum;
  logic                  tree_last_out;

  neuron_tree #(
      .NUM_INPUTS(P_WIDTH)
  ) u_tree (
      .clk(clk),
      .rst(rst),
      .en(valid_in),
      .x(x),
      .w(w),
      .last_in(last),
      .last_out(tree_last_out),
      .sum(tree_sum)
  );

  logic [ACC_WIDTH-1:0] acc;

  always_ff @(posedge clk) begin
    if (rst) begin
      acc     <= '0;
      y       <= 1'b0;
      y_valid <= 1'b0;
    end else if (valid_in) begin
      y_valid <= 1'b0;
      // Wait for the 'last' signal to emerge from the pipeline
      if (tree_last_out) begin
        // Finalize: Add last chunk + Compare + Reset
        y       <= ((acc + tree_sum) >= threshold);
        y_valid <= 1'b1;
        acc     <= '0;  // Clear for next neuron instantly
      end else begin
        // Just accumulate
        acc     <= acc + tree_sum;
        y_valid <= 1'b0;
      end
    end
  end

endmodule
