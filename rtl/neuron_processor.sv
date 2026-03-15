module neuron_processor #(
    parameter int P_WIDTH      = 64,   // Parallel inputs per cycle
    localparam int ACC_WIDTH    = 1 + $clog2(P_WIDTH),    // Width of final accumulator
    parameter int INPUT_WIDTH = 1
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_in,  // Input stream is valid
    input  logic                 last,
    input  logic [P_WIDTH-1:0]   x,         // Input data stream
    input  logic [P_WIDTH-1:0]   w,         // Weight data stream
    input  logic [ACC_WIDTH-1:0] threshold,

    output logic                 y,       // Final neuron activation
    output logic                 y_valid  // Pulsed when y is ready
);

  localparam int TREE_OUT_W   = 1 + $clog2(P_WIDTH);  // Popcount output width
  localparam int TREE_LATENCY = 1 + $clog2(P_WIDTH);  // 1 cycle for XNOR + add tree latency

  logic [TREE_OUT_W-1:0] tree_sum;
  logic                  tree_last_out;
  logic                  tree_valid_out;


  // Convert packed vectors into 1-bit-per-element arrays for xnor_add_tree
  logic [INPUT_WIDTH-1:0] x_arr[P_WIDTH];
  logic [INPUT_WIDTH-1:0] w_arr[P_WIDTH];

  logic [ACC_WIDTH-1:0] acc;

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
      .clk (clk),
      .rst (rst),
      .en  (1'b1),
      .in1 (x_arr),
      .in2 (w_arr),
      .sum (tree_sum)
  );

  // delay the valid in and last signals for the latency of the pipeline xnor add tree
  delay #(
    .CYCLES(TREE_LATENCY),
    .WIDTH (1)
  ) u_last_delay (
    .clk(clk),
    .rst(rst),
    .en (1'b1),
    .in (last),
    .out(tree_last_out)
  );

  delay #(
    .CYCLES(TREE_LATENCY),
    .WIDTH (1)
  ) u_valid_in_delay (
    .clk(clk),
    .rst(rst),
    .en (1'b1),
    .in (valid_in),
    .out(tree_valid_out)
  );

  logic y_valid_r;
  logic y_r;

  assign y_valid = y_valid_r;
  assign y = y_r;

// accumulator control
always_ff @(posedge clk or posedge rst) begin
  if (rst) begin
    acc <= '0;
  end else begin
    if (tree_valid_out) begin
      if (tree_last_out) begin
        // last chunk: clear accumulator for next neuron
        acc <= '0;
      end else begin
        // Non-final chunk: keep accumulating
        acc <= acc + tree_sum;
      end
    end
  end
end

// output and y_valid control
always_ff @(posedge clk or posedge rst) begin
  if (rst) begin
    y_valid_r <= 1'b0;
  end else begin
    y_valid_r <= 1'b0;

    if (tree_last_out) begin
      // Compare threshold and set Y and Y_valid
      y_r       <= ((acc + tree_sum) >= threshold);
      y_valid_r <= 1'b1;
    end
  end
end

endmodule