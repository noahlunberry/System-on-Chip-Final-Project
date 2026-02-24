// np_xnor_neuron.sv
// Single “selectable architecture” wrapper, like your count_ones example.
// Choose between streamed weights vs hardcoded weights using a string parameter ARCH.
//
// ARCH options:
//  - "stream_w"  : uses input w
//  - "const_w"   : ignores input w and uses W_CONST

module np_xnor_neuron #(
    parameter int    P_WIDTH      = 8,
    parameter int    TOTAL_INPUTS = 8,
    parameter int    PC_WIDTH     = $clog2(P_WIDTH + 1),
    parameter int    ACC_WIDTH    = PC_WIDTH,
    parameter string ARCH         = "const_w",           // "stream_w" or "const_w"
    parameter logic [P_WIDTH-1:0] W_CONST      = 8'b01100011      // used when ARCH=="const_w"
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_in,
    input  logic                 last,

    input  logic [P_WIDTH-1:0]   x,
    input  logic [P_WIDTH-1:0]   w,
    input  logic [ACC_WIDTH-1:0] threshold,

    output logic                 y,
    output logic                 y_valid
);

  if (ARCH == "stream_w") begin : g_stream_w
    np_stream_w #(
        .P_WIDTH(P_WIDTH),
        .TOTAL_INPUTS(TOTAL_INPUTS),
        .PC_WIDTH(PC_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) i_np (.*);

  end else if (ARCH == "const_w") begin : g_const_w
    np_const_w #(
        .P_WIDTH(P_WIDTH),
        .TOTAL_INPUTS(TOTAL_INPUTS),
        .PC_WIDTH(PC_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .W_CONST(W_CONST)
    ) i_np (.*);

  end else begin : g_error
    initial $error("np_xnor_neuron: Invalid ARCH '%s'. Use 'stream_w' or 'const_w'.", ARCH);
  end

endmodule
