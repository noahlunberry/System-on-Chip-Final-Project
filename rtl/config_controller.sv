module config_controller #(
    parameter int MANAGER_BUS_WIDTH = 8,
    parameter int PARALLEL_NEURONS  = 32,
    parameter int W_RAM_DATA_W      = 32,
    parameter int W_RAM_ADDR_W      = 10,
    parameter int T_RAM_ADDR_W      = 10
) (
    input logic clk,
    input logic rst,

    // Config stream interface
    input  logic [MANAGER_BUS_WIDTH-1:0] config_data,
    input  logic                         config_rd_en,
    input  logic [                 15:0] total_bytes,
    input  logic [                  7:0] bytes_per_neuron,
    output logic                         payload_done,

    // Weight RAM write interface (fanout lanes)
    output logic [PARALLEL_NEURONS-1:0]                   weight_wr_en,
    output logic [PARALLEL_NEURONS-1:0][W_RAM_ADDR_W-1:0] weight_wr_addr,

    // Threshold RAM write interface
    output logic [PARALLEL_NEURONS-1:0]                   threshold_wr_en,
    output logic [PARALLEL_NEURONS-1:0][T_RAM_ADDR_W-1:0] threshold_wr_addr
);

  // ============================================================
  // Internal signals (add as needed)
  // ============================================================



  // ============================================================
  // FSM / control logic goes here
  // ============================================================



endmodule
