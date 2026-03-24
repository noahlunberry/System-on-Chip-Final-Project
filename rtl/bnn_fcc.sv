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

  function automatic int get_max_parallel_inputs();
    int max_v = PARALLEL_INPUTS;
    for (int i = 0; i < LAYERS - 1; i++) begin
      if (PARALLEL_NEURONS[i] > max_v) max_v = PARALLEL_NEURONS[i];
    end
    return max_v;
  endfunction

  localparam int NUM_NEURONS[LAYERS] = TOPOLOGY[1:LAYERS];
  localparam int INPUT_BUS_ELEMENTS = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH;
  localparam int INPUT_BINARIZATION_THRESHOLD = 1 << (INPUT_DATA_WIDTH - 1);
  localparam int MAX_PARALLEL_INPUTS = get_max_parallel_inputs();

  // Round up TOPOLOGY[0] to nearest multiple of MAX_PARALLEL_INPUTS
  // Matches PADDED_INPUTS in bnn.sv so layer 1 gets the right number of input chunks
  localparam int PADDED_INPUTS = ((TOPOLOGY[0] + MAX_PARALLEL_INPUTS - 1)
                                / MAX_PARALLEL_INPUTS) * MAX_PARALLEL_INPUTS;
  // After all real pixels, how many extra zero beats to push
  localparam int AXI_TOTAL_BITS = ((TOPOLOGY[0] + INPUT_BUS_ELEMENTS - 1)
                                 / INPUT_BUS_ELEMENTS) * INPUT_BUS_ELEMENTS;
  localparam int BITS_TO_PAD = PADDED_INPUTS - AXI_TOTAL_BITS;
  localparam int PAD_BEATS = BITS_TO_PAD / INPUT_BUS_ELEMENTS;

  logic [    INPUT_DATA_WIDTH-1:0] pixels            [        INPUT_BUS_ELEMENTS];

  logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data;
  logic [              LAYERS-1:0] weight_wr_en;
  logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data;
  logic [              LAYERS-1:0] threshold_wr_en;

  logic                            bnn_ready;
  logic [ MAX_PARALLEL_INPUTS-1:0] bnn_data_in;
  logic                            bnn_data_in_valid;
  logic [THRESHOLD_DATA_WIDTH-1:0] bnn_count_out     [PARALLEL_NEURONS[LAYERS-1]];
  logic                            bnn_count_valid;

  initial begin
    for (int i = 0; i < LAYERS - 1; i++) begin
      if (TOPOLOGY[i+1] % PARALLEL_NEURONS[i])
        $fatal(1, "bnn_fcc requires TOPOLOGY[%0d] to be divisible by PARALLEL_NEURONS[%0d]", i+1, i);
    end
  end

  config_manager #(
      .BUS_WIDTH           (CONFIG_BUS_WIDTH),
      .LAYERS              (LAYERS),
      .PARALLEL_INPUTS     (PARALLEL_INPUTS),
      .MAX_PARALLEL_INPUTS (MAX_PARALLEL_INPUTS),
      .PARALLEL_NEURONS    (PARALLEL_NEURONS),
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

  // ── Binarization + Serial-to-Parallel FIFO ──────────────────────────────
  // The AXI bus delivers INPUT_BUS_ELEMENTS pixels per beat. Each pixel is
  // binarized (>= threshold → 1) and the resulting bits are written into a
  // fifo_vr that accumulates narrow writes and produces MAX_PARALLEL_INPUTS-wide
  // reads. This decouples the bus width from the BNN's parallelism.
  //
  // When TOPOLOGY[0] is not a multiple of MAX_PARALLEL_INPUTS, the input stream
  // needs zero-padding to fill PADDED_INPUTS total bits — analogous to how
  // config_manager pads weights with 0xFF in its PAD state.

  // Unpack pixels from AXI beat
  always_comb begin
    for (int i = 0; i < INPUT_BUS_ELEMENTS; i++) begin
      pixels[i] = data_in_data[i*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH];
    end
  end

  // Binarize pixels (registered)
  logic [INPUT_BUS_ELEMENTS-1:0] bin_data_r;
  logic                          bin_valid_r;
  logic                          bin_last_r;

  always_ff @(posedge clk) begin
    if (rst) begin
      bin_valid_r <= 1'b0;
      bin_last_r  <= 1'b0;
    end else begin
      bin_valid_r <= data_in_valid && data_in_ready;
      bin_last_r  <= data_in_valid && data_in_ready && data_in_last;
      if (data_in_valid && data_in_ready) begin
        for (int i = 0; i < INPUT_BUS_ELEMENTS; i++)
          bin_data_r[i] <= pixels[i] >= INPUT_BINARIZATION_THRESHOLD;
      end
    end
  end

  // ── Input Padding FSM ───────────────────────────────────────────────────
  // After the last real AXI beat, inject PAD_BEATS zero-valued writes into
  // the bin_fifo so the total bit count reaches PADDED_INPUTS.
  logic [INPUT_BUS_ELEMENTS-1:0] fifo_wr_data;
  logic                          fifo_wr_en;

  generate
    if (PAD_BEATS > 0) begin : gen_input_pad
      localparam int PAD_CTR_W = $clog2(PAD_BEATS + 1);
      logic [PAD_CTR_W-1:0] pad_ctr_r;
      logic                 padding_r;

      always_ff @(posedge clk) begin
        if (rst) begin
          pad_ctr_r <= '0;
          padding_r <= 1'b0;
        end else begin
          if (bin_last_r && !padding_r) begin
            padding_r <= 1'b1;
            pad_ctr_r <= '0;
          end else if (padding_r) begin
            if (pad_ctr_r == PAD_BEATS - 1) begin
              padding_r <= 1'b0;
              pad_ctr_r <= '0;
            end else begin
              pad_ctr_r <= pad_ctr_r + 1;
            end
          end
        end
      end

      assign fifo_wr_data = padding_r ? {INPUT_BUS_ELEMENTS{1'b0}} : bin_data_r;
      assign fifo_wr_en   = bin_valid_r || padding_r;
    end else begin : gen_no_input_pad
      assign fifo_wr_data = bin_data_r;
      assign fifo_wr_en   = bin_valid_r;
    end
  endgenerate

  // Serial-to-parallel FIFO: writes INPUT_BUS_ELEMENTS bits, reads MAX_PARALLEL_INPUTS bits
  logic bin_fifo_full;
  logic bin_fifo_empty;
  logic bin_fifo_alm_full;

  fifo_vr #(
      .N(INPUT_BUS_ELEMENTS),    // write width (e.g. 8 binary bits per AXI beat)
      .M(MAX_PARALLEL_INPUTS),   // read width  (e.g. 32 bits for layer 1)
      .P(5)                      // depth: 2^5 = 32 entries in M-units
  ) bin_fifo (
      .clk             (clk),
      .rst             (rst),
      .wr_en           (fifo_wr_en),
      .wr_data         (fifo_wr_data),
      .rd_en           (!bin_fifo_empty && bnn_ready),
      .rd_data         (bnn_data_in),
      .alm_full_thresh (5'd1),    // assert 1 entry before full
      .alm_empty_thresh('0),
      .alm_full        (bin_fifo_alm_full),
      .alm_empty       (),
      .full            (bin_fifo_full),
      .empty           (bin_fifo_empty)
  );

  assign bnn_data_in_valid = !bin_fifo_empty && bnn_ready;
  assign data_in_ready     = config_ready && !bin_fifo_alm_full;

  bnn #(
      .LAYERS              (LAYERS),
      .NUM_INPUTS          (TOPOLOGY[0]),
      .NUM_NEURONS         (NUM_NEURONS),
      .PARALLEL_INPUTS     (PARALLEL_INPUTS),
      .PARALLEL_NEURONS    (PARALLEL_NEURONS),
      .MAX_PARALLEL_INPUTS (MAX_PARALLEL_INPUTS),
      .THRESHOLD_DATA_WIDTH(THRESHOLD_DATA_WIDTH)
  ) bnn_main (
      .clk              (clk),
      .rst              (rst),
      .en               (data_out_ready),
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

  logic [THRESHOLD_DATA_WIDTH-1:0] max_count;

  always_comb begin : argmax
    if (PARALLEL_NEURONS[LAYERS-1] != TOPOLOGY[LAYERS])
      $fatal(1, "bnn_fcc currently requires output layer neurons to match PARALLEL_NEURONS for that layer");

    data_out_valid = bnn_count_valid;

    // This is beyond horrible for synthesis and is solely intended to test the testbench framework.
    max_count = bnn_count_out[0];
    data_out_data = '0;
    for (int i = 1; i < TOPOLOGY[LAYERS]; i++) begin
      if (bnn_count_out[i] > max_count) begin
        data_out_data = i;
        max_count = bnn_count_out[i];
      end
    end
  end

  // Configuration Manager

  // Instantiate the 3 layers



endmodule
