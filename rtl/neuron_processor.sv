// ============================================================
// neuron_processor.sv (skeleton)
// Matches your generate instantiation u_np
// IMPORTANT: valid_in/last are PER-NEURON signals, so in the generate
// you likely want: .valid_in(np_valid[gi]) and .last(np_last[gi])
// ============================================================
module neuron_processor #(
    parameter int PARALLEL_INPUTS = 32
) (
    input logic clk,
    input logic rst,

    input logic                       valid_in,
    input logic                       last,
    input logic [PARALLEL_INPUTS-1:0] x,

    // Keep these as "logic [*]" so you can drive them from BRAM outputs
    // (often W_RAM_DATA_W == PARALLEL_INPUTS for BNN bit-weights)
    input logic [PARALLEL_INPUTS-1:0] w,
    input logic [PARALLEL_INPUTS-1:0] thresh,

    output logic y
);

  // ============================================================
  // Datapath / accumulation / compare logic goes here
  // ============================================================



endmodule
