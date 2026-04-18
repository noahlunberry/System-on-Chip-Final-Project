module bnn_fcc #(
    parameter int INPUT_DATA_WIDTH  = 8,
    parameter int INPUT_BUS_WIDTH   = 64,
    parameter int CONFIG_BUS_WIDTH  = 64,
    parameter int OUTPUT_DATA_WIDTH = 4,
    parameter int OUTPUT_BUS_WIDTH  = 8,

    parameter int TOTAL_LAYERS = 4,  // Includes input, hidden, and output
    parameter int TOPOLOGY[TOTAL_LAYERS] = '{
        0: 784,
        1: 256,
        2: 256,
        3: 10,
        default: 0
    },  // 0: input, TOTAL_LAYERS-1: output

    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[TOTAL_LAYERS-1] = '{default: 8},

    localparam int THRESHOLD_DATA_WIDTH = $clog2(TOPOLOGY[0] + 1)
) (

    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                          config_valid,
    output logic                          config_ready,
    input  logic [  CONFIG_BUS_WIDTH-1:0] config_data,
    input  logic [CONFIG_BUS_WIDTH/8-1:0] config_keep,
    input  logic                          config_last,

    // AXI streaming image input interface (consumer)
    input  logic                         data_in_valid,
    output logic                         data_in_ready,
    input  logic [  INPUT_BUS_WIDTH-1:0] data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0] data_in_keep,
    input  logic                         data_in_last,

    // AXI streaming classification output interface (producer)
    output logic                          data_out_valid,
    input  logic                          data_out_ready,
    output logic [  OUTPUT_BUS_WIDTH-1:0] data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0] data_out_keep,
    output logic                          data_out_last
);
  localparam int LAYERS = TOTAL_LAYERS - 1;
  localparam int THRESH_WORD_BYTES = 4;
  typedef int layer_param_arr_t[LAYERS];

  function automatic int get_max_parallel_inputs();
    int max_v = PARALLEL_INPUTS;
    for (int i = 0; i < LAYERS - 1; i++) begin
      if (PARALLEL_NEURONS[i] > max_v) max_v = PARALLEL_NEURONS[i];
    end
    return max_v;
  endfunction

  function automatic layer_param_arr_t get_weight_bytes_per_neuron();
    layer_param_arr_t result;
    for (int i = 0; i < LAYERS; i++) begin
      result[i] = (TOPOLOGY[i] + 7) / 8;
    end
    return result;
  endfunction

  function automatic layer_param_arr_t get_weight_bytes_per_word();
    layer_param_arr_t result;
    result[0] = PARALLEL_INPUTS / 8;
    for (int i = 1; i < LAYERS; i++) begin
      result[i] = PARALLEL_NEURONS[i-1] / 8;
    end
    return result;
  endfunction

  function automatic layer_param_arr_t get_weight_total_bytes();
    layer_param_arr_t result;
    for (int i = 0; i < LAYERS; i++) begin
      result[i] = TOPOLOGY[i+1] * ((TOPOLOGY[i] + 7) / 8);
    end
    return result;
  endfunction

  function automatic layer_param_arr_t get_threshold_total_bytes();
    layer_param_arr_t result;
    for (int i = 0; i < LAYERS; i++) begin
      result[i] = THRESH_WORD_BYTES * TOPOLOGY[i+1];
    end
    return result;
  endfunction

  localparam int NUM_NEURONS[LAYERS] = TOPOLOGY[1:LAYERS];
  localparam int MAX_PARALLEL_INPUTS = get_max_parallel_inputs();
  localparam layer_param_arr_t CONFIG_WEIGHT_BYTES_PER_NEURON = get_weight_bytes_per_neuron();
  localparam layer_param_arr_t CONFIG_WEIGHT_BYTES_PER_WORD   = get_weight_bytes_per_word();
  localparam layer_param_arr_t CONFIG_WEIGHT_TOTAL_BYTES      = get_weight_total_bytes();
  localparam layer_param_arr_t CONFIG_THRESHOLD_TOTAL_BYTES   = get_threshold_total_bytes();

  logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data;
  logic [              LAYERS-1:0] weight_wr_en;
  logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data;
  logic [              LAYERS-1:0] threshold_wr_en;

  logic                            bnn_ready;
  logic [   PARALLEL_INPUTS-1:0]   bnn_data_in;
  logic                            bnn_data_in_valid;
  logic [THRESHOLD_DATA_WIDTH-1:0] bnn_count_out     [PARALLEL_NEURONS[LAYERS-1]];
  logic                            bnn_count_valid;
  logic                            bnn_en;

  logic                            out_fifo_full;
  logic                            out_fifo_empty;
  logic                            out_fifo_alm_full;
  logic                            out_fifo_rd_en;
  logic                            out_fifo_data_valid_r;
  logic                            out_fifo_word_accepted;
  logic [OUTPUT_BUS_WIDTH-1:0]     out_fifo_rd_data;

  initial begin
    for (int i = 0; i < LAYERS - 1; i++) begin
      if (TOPOLOGY[i+1] % PARALLEL_NEURONS[i])
        $fatal(1, "bnn_fcc requires TOPOLOGY[%0d] to be divisible by PARALLEL_NEURONS[%0d]", i + 1, i);
    end
  end

  config_manager #(
      .BUS_WIDTH           (CONFIG_BUS_WIDTH),
      .LAYERS              (LAYERS),
      .PARALLEL_INPUTS     (PARALLEL_INPUTS),
      .MAX_PARALLEL_INPUTS (MAX_PARALLEL_INPUTS),
      .PARALLEL_NEURONS    (PARALLEL_NEURONS),
      .WEIGHT_BYTES_PER_NEURON(CONFIG_WEIGHT_BYTES_PER_NEURON),
      .WEIGHT_BYTES_PER_WORD(CONFIG_WEIGHT_BYTES_PER_WORD),
      .WEIGHT_TOTAL_BYTES  (CONFIG_WEIGHT_TOTAL_BYTES),
      .THRESHOLD_TOTAL_BYTES(CONFIG_THRESHOLD_TOTAL_BYTES),
      .THRESHOLD_DATA_WIDTH(THRESHOLD_DATA_WIDTH)
  ) config_manager (
      .clk                  (clk),
      .rst                  (rst),
      .config_data_in       (config_data),
      .config_valid         (config_valid),
      .config_keep          (config_keep),
      .config_last          (config_last),
      .config_ready         (config_ready),
      .weight_ram_wr_data   (weight_wr_data),
      .weight_ram_wr_en     (weight_wr_en),
      .threshold_ram_wr_data(threshold_wr_data),
      .threshold_ram_wr_en  (threshold_wr_en)
  );

  assign bnn_en = !out_fifo_alm_full;

  data_in_manager #(
      .INPUT_DATA_WIDTH   (INPUT_DATA_WIDTH),
      .INPUT_BUS_WIDTH    (INPUT_BUS_WIDTH),
      .TOTAL_INPUTS       (TOPOLOGY[0]),
      .PARALLEL_INPUTS    (PARALLEL_INPUTS)
  ) data_in_manager_i (
      .clk              (clk),
      .rst              (rst),
      .config_ready     (config_ready),
      .config_valid      (config_valid),
      .data_in_valid    (data_in_valid),
      .data_in_ready    (data_in_ready),
      .data_in_data     (data_in_data),
      .data_in_keep     (data_in_keep),
      .data_in_last     (data_in_last),
      .bnn_ready        (bnn_ready),
      .bnn_en           (bnn_en),
      .bnn_data_in      (bnn_data_in),
      .bnn_data_in_valid(bnn_data_in_valid)
  );



  bnn #(
      .LAYERS              (LAYERS),
      .NUM_INPUTS          (TOPOLOGY[0]),
      .NUM_NEURONS         (NUM_NEURONS),
      .PARALLEL_NEURONS    (PARALLEL_NEURONS),
      .FIRST_LAYER_PARALLEL_INPUTS(PARALLEL_INPUTS),
      .MAX_PARALLEL_INPUTS (MAX_PARALLEL_INPUTS),
      .THRESHOLD_DATA_WIDTH(THRESHOLD_DATA_WIDTH)
  ) bnn_main (
      .clk              (clk),
      .rst              (rst),
      .en               (bnn_en),
      .ready            (bnn_ready),
      .weight_wr_data   (weight_wr_data),
      .weight_wr_en     (weight_wr_en),
      .threshold_wr_data(threshold_wr_data),
      .threshold_wr_en  (threshold_wr_en),
      .data_in          (bnn_data_in),
      .data_in_valid    (bnn_data_in_valid),
      .data_out         (),
      .count_out        (bnn_count_out),
      .data_out_valid   (bnn_count_valid)
  );

  // -------------------------------------------------------------------------
  // Pipeline Backpressure Logic
  // -------------------------------------------------------------------------
  // The entire pipeline (BNN + Argmax) can advance if the AXI consumer is ready,
  // OR if the skid buffer is currently empty and can absorb a result.


  // -------------------------------------------------------------------------
  // The Argmax Tree
  // -------------------------------------------------------------------------
  localparam int NUM_CLASSES = TOPOLOGY[LAYERS];
  localparam int INDEX_WIDTH = (NUM_CLASSES > 1) ? $clog2(NUM_CLASSES) : 1;

  logic [THRESHOLD_DATA_WIDTH-1:0] tree_max_val;
  logic [         INDEX_WIDTH-1:0] tree_max_idx;

  argmax_tree #(
      .NUM_INPUTS(NUM_CLASSES),
      .DATA_WIDTH(THRESHOLD_DATA_WIDTH)
  ) argmax_inst (
      .clk    (clk),
      .rst    (rst),
      .en     (1'b1),
      .inputs (bnn_count_out),
      .max_val(tree_max_val),
      .max_idx(tree_max_idx)
  );

  // -------------------------------------------------------------------------
  // The Valid Signal Shift Register (Delay Line)
  // -------------------------------------------------------------------------
  // The depth of the argmax tree is ceil(log2(NUM_CLASSES)). 
  // For 10 classes, this is 4 clock cycles.
  localparam int ARGMAX_LATENCY = $clog2(NUM_CLASSES);
  logic tree_out_valid;

  delay #(
      .CYCLES(ARGMAX_LATENCY),
      .WIDTH (1)
  ) valid_delay_inst (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in (bnn_count_valid),
      .out(tree_out_valid)
  );

  // -------------------------------------------------------------------------
  // AXI Stream Output FIFO (Elastic Buffer)
  // -------------------------------------------------------------------------

  // Use the FIFO's registered read output and keep a local valid bit here so
  // AXI still sees a standard hold-until-ready producer interface.

  localparam int OUT_FIFO_DEPTH_LOG2 = 2;  // 4 entries
  localparam int PIPELINE_LATENCY = ARGMAX_LATENCY + 10;  // Adjust '10' to your BNN's actual latency
  // Clamp at zero so the parameter stays legal even when the desired
  // backpressure headroom exceeds this small elastic buffer's depth.
  localparam int OUT_FIFO_ALM_FULL_THRESH =
      (((1 << OUT_FIFO_DEPTH_LOG2) - PIPELINE_LATENCY - 2) > 0) ?
      ((1 << OUT_FIFO_DEPTH_LOG2) - PIPELINE_LATENCY - 2) : 0;

  fifo_vr #(
      .N(OUTPUT_BUS_WIDTH),
      .M(OUTPUT_BUS_WIDTH),
      .P(OUT_FIFO_DEPTH_LOG2),
      .FWFT(1'b0),
      .ALM_FULL_THRESH(OUT_FIFO_ALM_FULL_THRESH),
      .ALM_EMPTY_THRESH(0)
  ) out_fifo (
      .clk    (clk),
      .rst    (rst),
      // Write side: driven by the free-flowing pipeline
      .wr_en  (tree_out_valid),
      .wr_data(OUTPUT_BUS_WIDTH'(tree_max_idx)),

      // Read side: driven by the AXI consumer
      .rd_en  (out_fifo_rd_en),
      .rd_data(out_fifo_rd_data),

      .alm_full        (out_fifo_alm_full),                                  // Routed upstream to 'bnn_en'
      .alm_empty       (),
      .full            (out_fifo_full),
      .empty           (out_fifo_empty)
  );

  assign out_fifo_word_accepted = out_fifo_data_valid_r && data_out_ready;
  assign out_fifo_rd_en = !out_fifo_empty && (!out_fifo_data_valid_r || out_fifo_word_accepted);

  always_ff @(posedge clk) begin
    if (rst) begin
      out_fifo_data_valid_r <= 1'b0;
    end else begin
      if (out_fifo_rd_en) begin
        out_fifo_data_valid_r <= 1'b1;
      end else if (out_fifo_word_accepted) begin
        out_fifo_data_valid_r <= 1'b0;
      end
    end
  end

  // Final AXI Assignments
  assign data_out_valid = out_fifo_data_valid_r;
  assign data_out_data  = out_fifo_rd_data;
  assign data_out_keep  = '1;
  assign data_out_last  = 1'b1;



endmodule
