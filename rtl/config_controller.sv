module config_controller #(
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS    = 8,
    parameter int TOTAL_NEURONS       = 256,
    parameter int TOTAL_INPUTS        = 256,
    parameter int W_RAM_ADDR_W        = 10,
    parameter int T_RAM_DATA_W        = 32,
    parameter int T_RAM_ADDR_W        = 10
) (
    input logic clk,
    input logic rst,
    input logic weight_wr_en,
    input logic threshold_wr_en,

    // RAM write interfaces
    output logic [PARALLEL_NEURONS-1:0] ram_weight_wr_en,
    output logic [PARALLEL_NEURONS-1:0] ram_threshold_wr_en,
    output logic [    W_RAM_ADDR_W-1:0] weight_addr_out,
    output logic [    T_RAM_ADDR_W-1:0] threshold_addr_out,
    output logic                        done
);

  // add assertion to make sure this is true
  localparam int TOTAL_CYCLES = TOTAL_NEURONS / PARALLEL_NEURONS;
  localparam int W_ADDR_PER_CYCLE = (TOTAL_INPUTS / MAX_PARALLEL_INPUTS);
  localparam int T_ADDR_PER_CYCLE = (TOTAL_NEURONS / T_RAM_DATA_W);


  // Registers
  logic [W_RAM_ADDR_W-1:0] w_addr_r, next_w_addr;
  logic [W_RAM_ADDR_W-1:0] w_addr_out_r, next_w_addr_out;
  logic [PARALLEL_NEURONS-1:0] w_neuron_r, next_w_neuron;  // one hot bram wr_en
  logic [W_RAM_ADDR_W-1:0] w_total_cycles_r, next_w_total_cycles;

  logic [T_RAM_ADDR_W-1:0] t_addr_r, next_t_addr;
  logic [T_RAM_ADDR_W-1:0] t_addr_out_r, next_t_addr_out;
  logic [PARALLEL_NEURONS-1:0] t_neuron_r, next_t_neuron;
  logic [T_RAM_ADDR_W-1:0] t_total_cycles_r, next_t_total_cycles;


  // Assignments
  assign weight_addr_out     = w_addr_out_r;
  assign ram_weight_wr_en    = w_neuron_r;
  assign threshold_addr_out  = t_addr_out_r;
  assign ram_threshold_wr_en = t_neuron_r;

  always_ff @(posedge clk) begin
    w_addr_r         <= next_w_addr;
    w_addr_out_r     <= next_w_addr_out;
    w_neuron_r       <= next_w_neuron;
    w_total_cycles_r <= next_w_total_cycles;
    t_addr_r         <= next_t_addr;
    t_addr_out_r     <= next_t_addr_out;
    t_neuron_r       <= next_t_neuron;
    t_total_cycles_r <= next_t_total_cycles;

    if (rst) begin
      w_addr_r         <= '0;
      w_addr_out_r     <= '0;
      w_neuron_r       <= {{(PARALLEL_NEURONS - 1) {1'b0}}, 1'b1};  // start at 1 to get rid of init state
      w_total_cycles_r <= '0;
      t_addr_r         <= '0;
      t_addr_out_r     <= '0;
      t_neuron_r       <= {{(PARALLEL_NEURONS - 1) {1'b0}}, 1'b1};
      t_total_cycles_r <= '0;
    end
  end

  always_comb begin
    // Default Assignments
    next_w_addr         = w_addr_r;
    next_w_addr_out     = w_addr_out_r;
    next_w_neuron       = w_neuron_r;
    next_w_total_cycles = w_total_cycles_r;

    next_t_addr         = t_addr_r;
    next_t_addr_out     = t_addr_out_r;
    next_t_neuron       = t_neuron_r;
    next_t_total_cycles = t_total_cycles_r;

    done                = 0;

    if (weight_wr_en) begin

      // if last address for neuron, move to address 0 for next neuron
      if (w_addr_r == W_ADDR_PER_CYCLE - 1) begin
        next_w_addr = 0;
        // if last neuron, move to neuron 0
        if (w_neuron_r[PARALLEL_NEURONS-1] == 1) begin
          next_w_neuron = '0;
          next_w_neuron[0] = 1'b1;
          next_w_total_cycles = next_w_total_cycles + 1;
        end else begin
          next_w_neuron = next_w_neuron << 1;  // shift left bc represents one hot enable
        end
      end else next_w_addr = next_w_addr + 1;

      // multiplex true address out using total cycles
      next_w_addr_out = next_w_addr + (next_w_total_cycles * W_ADDR_PER_CYCLE);
    end

    if (threshold_wr_en) begin
      // if last address for neuron, move to address 0 for next neuron
      if (t_addr_r == T_ADDR_PER_CYCLE - 1) begin
        next_t_addr = 0;
        // if last neuron, move to neuron 0
        if (t_neuron_r[PARALLEL_NEURONS-1] == 1) begin
          next_t_neuron = '0;
          next_t_neuron[0] = 1'b1;
          next_t_total_cycles = next_t_total_cycles + 1;
        end else begin
          next_t_neuron = next_t_neuron << 1;  // shift left bc represents one hot enable
        end
      end else next_t_addr = next_t_addr + 1;
    end
    // multiplex true address out using total cycles
    next_t_addr_out = next_t_addr + (next_t_total_cycles * T_ADDR_PER_CYCLE);

    // assert done and enable data in stream
    if ((t_total_cycles_r == TOTAL_CYCLES - 1) && (w_total_cycles_r == TOTAL_CYCLES - 1)) done = 1;
  end
endmodule
