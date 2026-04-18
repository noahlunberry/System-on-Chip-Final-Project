module neuron_processor #(
    parameter  int P_WIDTH         = 64,                   // Parallel inputs per cycle
    parameter  int THRESHOLD_WIDTH = $clog2(P_WIDTH + 1),
    localparam int ACC_WIDTH       = THRESHOLD_WIDTH,      // Width of final accumulator
    parameter  int INPUT_WIDTH     = 1
) (
    input logic                       clk,
    input logic                       rst,
    input logic                       valid_in,  // Input stream is valid
    input logic                       last,
    input logic [        P_WIDTH-1:0] x,         // Input data stream
    input logic [        P_WIDTH-1:0] w,         // Weight data stream
    input logic [THRESHOLD_WIDTH-1:0] threshold,

    output logic [THRESHOLD_WIDTH-1:0] count_out,
    output logic                       y,          // Final neuron activation
    output logic                       y_valid     // Pulsed when y is ready
);

  localparam int TREE_OUT_W = 1 + $clog2(P_WIDTH);  // Popcount output width
  localparam int TREE_LATENCY = 1 + $clog2(P_WIDTH);  // 1 cycle for XNOR + add tree latency

  logic [ TREE_OUT_W-1:0] tree_sum;
  logic                   tree_last_out;
  logic                   tree_valid_out;


  // Convert packed vectors into 1-bit-per-element arrays for xnor_add_tree
  logic [INPUT_WIDTH-1:0] x_arr          [P_WIDTH];
  logic [INPUT_WIDTH-1:0] w_arr          [P_WIDTH];

  logic [  ACC_WIDTH-1:0] acc_r;

  genvar i;
  generate
    for (i = 0; i < P_WIDTH; i++) begin : g_pack_inputs
      assign x_arr[i] = x[i];
      assign w_arr[i] = w[i];
    end
  endgenerate

  // instantiate the xnor add tree
  xnor_add_tree #(
      .NUM_INPUTS (P_WIDTH),
      .INPUT_WIDTH(1)
  ) u_tree (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in1(x_arr),
      .in2(w_arr),
      .sum(tree_sum)
  );

  // delay the valid in and last signals for the latency of the pipeline xnor add tree
  delay #(
      .CYCLES       (TREE_LATENCY),
      .WIDTH        (1),
      .PRESERVE_REGS(1'b1)
  ) u_last_delay (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in (last),
      .out(tree_last_out)
  );

  delay #(
      .CYCLES       (TREE_LATENCY),
      .WIDTH        (1),
      .PRESERVE_REGS(1'b1)
  ) u_valid_in_delay (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in (valid_in),
      .out(tree_valid_out)
  );


  logic [THRESHOLD_WIDTH-1:0] threshold_out_r;

  delay #(
      .CYCLES(TREE_LATENCY),
      .WIDTH (THRESHOLD_WIDTH),
      .PRESERVE_REGS(1'b1)
  ) u_threshold_delay (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in (threshold),
      .out(threshold_out_r)
  );

  logic y_valid_r;
  logic y_r;
  logic [THRESHOLD_WIDTH-1:0] final_sum_r;
  logic [THRESHOLD_WIDTH-1:0] threshold_final_r;
  logic compare_valid_r;
  logic [ACC_WIDTH-1:0] next_acc_r;
  logic [THRESHOLD_WIDTH-1:0] final_sum_next;

  assign y_valid = y_valid_r;
  assign y = y_r;
  assign final_sum_next = acc_r + THRESHOLD_WIDTH'(tree_sum);

  always_comb begin
    next_acc_r = acc_r;

    if (tree_valid_out) begin
      if (tree_last_out) begin
        // last chunk: clear accumulator for next neuron
        next_acc_r = '0;
      end else begin
        // Non-final chunk: keep accumulating
        next_acc_r = acc_r + ACC_WIDTH'(tree_sum);
      end
    end
  end

  // accumulator control
  always_ff @(posedge clk) begin
    if (rst) begin
      acc_r <= '0;
    end else begin
      acc_r <= next_acc_r;
    end
  end

  // final-sum capture
  always_ff @(posedge clk) begin
    if (rst) begin
      // final_sum_r      <= '0;
      // threshold_final_r <= '0;
      compare_valid_r  <= 1'b0;
    end else begin
      compare_valid_r <= tree_last_out;

      if (tree_last_out) begin
        // Register the final accumulated sum locally so the threshold compare
        // happens in its own cycle instead of on the add-tree output path.
        final_sum_r       <= final_sum_next;
        threshold_final_r <= threshold_out_r;
      end
    end
  end

  // output and y_valid control
  always_ff @(posedge clk) begin
    if (rst) begin
      // y_r              <= 1'b0;
      // count_out        <= '0;
      y_valid_r <= 1'b0;
    end else begin
      y_valid_r       <= 1'b0;

      if (compare_valid_r) begin
        y_r       <= (final_sum_r >= threshold_final_r);
        count_out <= final_sum_r;
        y_valid_r <= 1'b1;
      end
    end
  end

endmodule
