module bnn #(
    parameter int LAYERS = 3,
    parameter int NUM_INPUTS = 784,
    parameter int NUM_NEURONS[LAYERS] = '{0: 256, 1: 256, 2: 10, default: 0},
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int FIRST_LAYER_PARALLEL_INPUTS = 8,
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int THRESHOLD_DATA_WIDTH = $clog2(NUM_INPUTS + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic en,
    output logic ready,

    input logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data,
    input logic [              LAYERS-1:0] weight_wr_en,
    input logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,
    input logic [              LAYERS-1:0] threshold_wr_en,

    input  logic [FIRST_LAYER_PARALLEL_INPUTS-1:0] data_in,
    input  logic                                  data_in_valid,
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0] data_out,
    output logic [      THRESHOLD_DATA_WIDTH-1:0] count_out     [PARALLEL_NEURONS[LAYERS-1]],
    output logic                                  data_out_valid
);

  // ----------------------------
  // Helpers
  // ----------------------------

  function automatic int max_array(input int arr[LAYERS]);
    int m;
    begin
      m = arr[0];
      for (int k = 1; k < LAYERS; k++) begin
        if (arr[k] > m) m = arr[k];
      end
      return m;
    end
  endfunction

  localparam int PADDED_INPUTS =
        ((NUM_INPUTS + FIRST_LAYER_PARALLEL_INPUTS - 1) / FIRST_LAYER_PARALLEL_INPUTS)
        * FIRST_LAYER_PARALLEL_INPUTS;

  localparam int MAX_LAYER_BUS_WIDTH = max_array(PARALLEL_NEURONS);

  // If LAYERS=1, we still need a legal array declaration.
  localparam int NUM_BOUNDARIES = (LAYERS > 1) ? (LAYERS - 1) : 1;

  // ----------------------------
  // Inter-layer signals
  // ----------------------------

  // valid_out from each layer
  logic [LAYERS-1:0] valid_bus;

  // ready_in from each layer
  logic [LAYERS-1:0] ready_bus;

  // shared-width buses between layers
  logic [MAX_LAYER_BUS_WIDTH-1:0] data_bus[NUM_BOUNDARIES-1:0];

  assign ready = ready_bus[0];
  assign data_out_valid = valid_bus[LAYERS-1];

  // ----------------------------
  // Generate layers
  // ----------------------------

  genvar i;
  generate
    for (i = 0; i < LAYERS; i++) begin : g_layers

      localparam int CUR_PARALLEL_INPUTS =
          (i == 0) ? FIRST_LAYER_PARALLEL_INPUTS : PARALLEL_NEURONS[i-1];

      localparam int CUR_PARALLEL_NEURONS = PARALLEL_NEURONS[i];

      localparam int CUR_TOTAL_INPUTS = (i == 0) ? PADDED_INPUTS : NUM_NEURONS[i-1];

      localparam int CUR_LAST_LAYER = (i == LAYERS - 1);

      // Per-instance local wires sized exactly for this layer
      logic [ CUR_PARALLEL_INPUTS-1:0] cur_data_in;
      logic                            cur_valid_in;
      logic [CUR_PARALLEL_NEURONS-1:0] cur_data_out;
      logic [THRESHOLD_DATA_WIDTH-1:0] cur_count_out[CUR_PARALLEL_NEURONS];

      // First layer gets top-level input.
      // Other layers get previous layer's output.
      if (i == 0) begin : g_first_input
        assign cur_data_in  = data_in;
        assign cur_valid_in = data_in_valid && ready_bus[0];
      end else begin : g_internal_input
        assign cur_data_in  = data_bus[i-1][CUR_PARALLEL_INPUTS-1:0];
        assign cur_valid_in = valid_bus[i-1];
      end

      bnn_layer #(
          .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
          .MAX_INPUTS         (NUM_INPUTS),
          .PARALLEL_INPUTS    (CUR_PARALLEL_INPUTS),
          .PARALLEL_NEURONS   (CUR_PARALLEL_NEURONS),
          .TOTAL_NEURONS      (NUM_NEURONS[i]),
          .TOTAL_INPUTS       (CUR_TOTAL_INPUTS),
          .LAST_LAYER         (CUR_LAST_LAYER)
      ) u_layer (
          .clk              (clk),
          .rst              (rst),
          .data_in          (cur_data_in),
          .valid_in         (cur_valid_in),
          .ready_in         (ready_bus[i]),
          .weight_wr_en     (weight_wr_en[i]),
          .threshold_wr_en  (threshold_wr_en[i]),
          .weight_wr_data   (weight_wr_data),
          .threshold_wr_data(threshold_wr_data),
          .valid_out        (valid_bus[i]),
          .data_out         (cur_data_out),
          .ready_out        (CUR_LAST_LAYER ? 1'b1 : ready_bus[i+1]),
          .count_out        (cur_count_out)
      );

      // Last layer drives top-level outputs.
      // Non-last layers write into the shared inter-layer bus.
      if (i == LAYERS - 1) begin : g_last_output
        assign data_out  = cur_data_out;
        assign count_out = cur_count_out;
      end else begin : g_internal_output
        always_comb begin
          data_bus[i] = '0;
          data_bus[i][CUR_PARALLEL_NEURONS-1:0] = cur_data_out;
        end
      end

    end
  endgenerate

endmodule
