module np_stream_w #(
    parameter int P_WIDTH      = 8,
    parameter int TOTAL_INPUTS = 8,
    parameter int PC_WIDTH     = $clog2(P_WIDTH + 1),
    parameter int ACC_WIDTH    = PC_WIDTH
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_in,
    input  logic                 last,
    input  logic [P_WIDTH-1:0]    x,
    input  logic [P_WIDTH-1:0]    w,
    input  logic [ACC_WIDTH-1:0]  threshold,
    output logic                 y,
    output logic                 y_valid
);

  logic [P_WIDTH-1:0]   xnor_bits;
  logic [PC_WIDTH-1:0]  tree_sum;
  logic [ACC_WIDTH-1:0] acc;

  always_comb begin
    xnor_bits = ~(x ^ w);
  end

  integer i;
  always_comb begin
    tree_sum = '0;
    for (i = 0; i < P_WIDTH; i++) begin
      tree_sum = tree_sum + xnor_bits[i];
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      acc     <= '0;
      y       <= 1'b0;
      y_valid <= 1'b0;
    end else begin
      y_valid <= 1'b0;
      if (valid_in) begin
        if (last) begin
          y       <= ((acc + tree_sum) >= threshold);
          y_valid <= 1'b1;
          acc     <= '0;
        end else begin
          acc <= acc + tree_sum;
        end
      end
    end
  end

endmodule
