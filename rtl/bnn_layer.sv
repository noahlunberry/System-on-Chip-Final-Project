// This is the hidden-layer compute block for the binary neural net.
//
// The original version of this module had three structural problems:
// 1. The external interface was inconsistent about handshake direction and
//    configuration word width.
// 2. The RAM read path was not aligned to the neuron processors, so the NPs
//    would have sampled stale data.
// 3. The layer never assembled a full output vector or produced a valid/ready
//    style result.
//
// This rewrite keeps the existing high-level intent (configurable RAM banks +
// a neuron-controller-driven NP array), but makes those boundaries coherent.
module bnn_layer #(
    parameter int PARALLEL_INPUTS  = 32,
    parameter int PARALLEL_NEURONS = 32,
    // The layer-level config bus now represents one logical write word per
    // cycle from the config manager. It must be wide enough to carry the
    // widest thing the layer writes: a threshold word or one packed weight word.
    parameter int MANAGER_BUS_WIDTH = 32,
    parameter int TOTAL_INPUTS      = 256,
    // For a hidden layer, the output bus width is the number of output neurons,
    // because this module returns the entire binarized layer result at once.
    parameter int OUTPUT_BUS_WIDTH  = 256
) (
    input logic clk,
    input logic rst,

    // Upstream layer / input image side.
    input  logic [TOTAL_INPUTS-1:0] data_in,
    input  logic                    valid_in,
    output logic                    ready_in,

    // Config manager side.
    // `msg_type` is required here because the layer needs to know whether the
    // incoming word targets the weight RAMs or the threshold RAMs.
    input  logic [MANAGER_BUS_WIDTH-1:0] config_data,
    input  logic                         config_rd_en,
    input  logic                         msg_type,          // 0: weights, 1: thresholds
    input  logic [15:0]                  total_bytes,
    input  logic [7:0]                   bytes_per_neuron,
    output logic                         payload_done,

    // Downstream layer side.
    // The original module reversed these directions. This block is a producer,
    // so it must drive `valid_out` and observe `ready_out`.
    output logic                        valid_out,
    output logic [OUTPUT_BUS_WIDTH-1:0] data_out,
    input  logic                        ready_out
);

  localparam int TOTAL_NEURONS      = OUTPUT_BUS_WIDTH;
  localparam int W_RAM_DATA_W        = PARALLEL_INPUTS;
  localparam int W_RAM_ADDR_W        = 12;
  localparam int T_RAM_DATA_W        = 32;
  localparam int T_RAM_ADDR_W        = 8;
  localparam int WORDS_PER_NEURON    = (TOTAL_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS;
  localparam int PADDED_TOTAL_INPUTS = WORDS_PER_NEURON * PARALLEL_INPUTS;
  localparam int NEURON_BATCHES      = (TOTAL_NEURONS + PARALLEL_NEURONS - 1) / PARALLEL_NEURONS;
  localparam int NP_ACC_WIDTH        = $clog2(PADDED_TOTAL_INPUTS + 1);
  localparam int NP_TREE_LATENCY     = 1 + $clog2(PARALLEL_INPUTS);
  localparam int WORD_IDX_W          = (WORDS_PER_NEURON > 1) ? $clog2(WORDS_PER_NEURON) : 1;
  localparam int BATCH_IDX_W         = (NEURON_BATCHES > 1) ? $clog2(NEURON_BATCHES) : 1;

  // One RAM bank per active neuron lane.
  logic                    w_wr_en  [PARALLEL_NEURONS];
  logic [W_RAM_ADDR_W-1:0] w_wr_addr[PARALLEL_NEURONS];
  logic [W_RAM_DATA_W-1:0] w_wr_data[PARALLEL_NEURONS];

  logic                    t_wr_en  [PARALLEL_NEURONS];
  logic [T_RAM_ADDR_W-1:0] t_wr_addr[PARALLEL_NEURONS];
  logic [T_RAM_DATA_W-1:0] t_wr_data[PARALLEL_NEURONS];

  logic                    w_rd_en;
  logic [W_RAM_ADDR_W-1:0] w_rd_addr;
  logic [W_RAM_DATA_W-1:0] w_rd_data[PARALLEL_NEURONS];

  logic                    t_rd_en;
  logic [T_RAM_ADDR_W-1:0] t_rd_addr;
  logic [T_RAM_DATA_W-1:0] t_rd_data[PARALLEL_NEURONS];

  // The config writer was intentionally split into a dedicated module so this
  // layer file stays focused on compute/dataflow behavior. `config_busy`
  // remains visible here because it participates in the layer-level ready logic.
  logic config_busy;

  // Neuron controller outputs are used as read requests only.
  // We do not forward its `valid_in/last` directly, because the RAMs are
  // synchronous and the original timing was one cycle too early.
  logic ctrl_np_valid_unused;
  logic ctrl_last_req;
  logic ctrl_layer_done_unused;
  logic nc_go;

  // Input vector and output vector storage.
  logic [TOTAL_INPUTS-1:0]      data_in_r;
  logic [OUTPUT_BUS_WIDTH-1:0]  data_out_r;
  logic                         compute_busy_r;
  logic                         valid_out_r;

  // Read-aligned NP inputs.
  logic                 np_valid_aligned_r;
  logic                 np_last_aligned_r;
  logic [WORD_IDX_W-1:0] np_word_idx_r;
  logic [BATCH_IDX_W-1:0] np_batch_idx_r;
  logic [PARALLEL_INPUTS-1:0] x_chunk;
  logic [NP_ACC_WIDTH-1:0]    threshold_hold_r[PARALLEL_NEURONS];

  logic [PARALLEL_NEURONS-1:0] np_y;
  logic [PARALLEL_NEURONS-1:0] np_y_valid;

  // This pipeline tags "last word of batch" events with the batch index so the
  // output collector knows which neuron slots correspond to an arriving NP result.
  logic                     result_batch_valid_pipe[NP_TREE_LATENCY+1];
  logic [BATCH_IDX_W-1:0]   result_batch_idx_pipe  [NP_TREE_LATENCY+1];

  assign ready_in     = !rst && !config_busy && !compute_busy_r && !valid_out_r;
  assign valid_out    = valid_out_r;
  assign data_out     = data_out_r;
  assign nc_go        = valid_in && ready_in;

  initial begin
    if (MANAGER_BUS_WIDTH < W_RAM_DATA_W) begin
      $fatal(1, "bnn_layer requires MANAGER_BUS_WIDTH >= PARALLEL_INPUTS.");
    end

    if (MANAGER_BUS_WIDTH < T_RAM_DATA_W) begin
      $fatal(1, "bnn_layer requires MANAGER_BUS_WIDTH >= 32 so thresholds fit on config_data.");
    end

    if (MANAGER_BUS_WIDTH % 8 != 0) begin
      $fatal(1, "bnn_layer requires MANAGER_BUS_WIDTH to be byte aligned.");
    end

    if ((1 << W_RAM_ADDR_W) < (WORDS_PER_NEURON * NEURON_BATCHES)) begin
      $fatal(1, "bnn_layer weight RAM address width is too small for this layer.");
    end

    if ((1 << T_RAM_ADDR_W) < NEURON_BATCHES) begin
      $fatal(1, "bnn_layer threshold RAM address width is too small for this layer.");
    end
  end

  // The per-message config write sequencing now lives in a dedicated helper
  // module. That keeps the hidden-layer logic readable and makes the config
  // mapping reusable/testable in isolation.
  bnn_layer_config_controller #(
      .PARALLEL_INPUTS  (PARALLEL_INPUTS),
      .PARALLEL_NEURONS (PARALLEL_NEURONS),
      .MANAGER_BUS_WIDTH(MANAGER_BUS_WIDTH),
      .TOTAL_INPUTS     (TOTAL_INPUTS),
      .TOTAL_NEURONS    (TOTAL_NEURONS),
      .W_RAM_ADDR_W     (W_RAM_ADDR_W),
      .T_RAM_ADDR_W     (T_RAM_ADDR_W)
  ) u_cfg_ctrl (
      .clk             (clk),
      .rst             (rst),
      .config_data     (config_data),
      .config_rd_en    (config_rd_en),
      .msg_type        (msg_type),
      .total_bytes     (total_bytes),
      .bytes_per_neuron(bytes_per_neuron),
      .busy            (config_busy),
      .payload_done    (payload_done),
      .w_wr_en         (w_wr_en),
      .w_wr_addr       (w_wr_addr),
      .w_wr_data       (w_wr_data),
      .t_wr_en         (t_wr_en),
      .t_wr_addr       (t_wr_addr),
      .t_wr_data       (t_wr_data)
  );

  neuron_controller #(
      .PARALLEL_INPUTS (PARALLEL_INPUTS),
      .PARALLEL_NEURONS(PARALLEL_NEURONS),
      // The controller uses integer division internally, so we pass padded
      // sizes here. The data path itself still pads unused input bits with 0s.
      .TOTAL_INPUTS    (PADDED_TOTAL_INPUTS),
      .TOTAL_NEURONS   (NEURON_BATCHES * PARALLEL_NEURONS),
      .W_RAM_ADDR_W    (W_RAM_ADDR_W),
      .T_RAM_ADDR_W    (T_RAM_ADDR_W)
  ) u_nc (
      .clk              (clk),
      .rst              (rst),
      .go               (nc_go),
      .valid_in         (ctrl_np_valid_unused),
      .last             (ctrl_last_req),
      .layer_done       (ctrl_layer_done_unused),
      .weight_rd_en     (w_rd_en),
      .weight_rd_addr   (w_rd_addr),
      .threshold_rd_en  (t_rd_en),
      .threshold_rd_addr(t_rd_addr)
  );

  genvar gi;
  generate
    for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : gen_np_mems
      ram_sdp #(
          .DATA_WIDTH (W_RAM_DATA_W),
          .ADDR_WIDTH (W_RAM_ADDR_W),
          .REG_RD_DATA(1'b0),
          .WRITE_FIRST(1'b0),
          .STYLE      ("block")
      ) u_w_ram (
          .clk    (clk),
          .rd_en  (w_rd_en),
          .rd_addr(w_rd_addr),
          .rd_data(w_rd_data[gi]),
          .wr_en  (w_wr_en[gi]),
          .wr_addr(w_wr_addr[gi]),
          .wr_data(w_wr_data[gi])
      );

      ram_sdp #(
          .DATA_WIDTH (T_RAM_DATA_W),
          .ADDR_WIDTH (T_RAM_ADDR_W),
          .REG_RD_DATA(1'b0),
          .WRITE_FIRST(1'b0),
          .STYLE      ("block")
      ) u_t_ram (
          .clk    (clk),
          .rd_en  (t_rd_en),
          .rd_addr(t_rd_addr),
          .rd_data(t_rd_data[gi]),
          .wr_en  (t_wr_en[gi]),
          .wr_addr(t_wr_addr[gi]),
          .wr_data(t_wr_data[gi])
      );
    end
  endgenerate

  // Build the aligned input chunk from the latched full input vector.
  // `np_word_idx_r` is generated from the registered RAM read address so the
  // chunk lines up with the weight word coming back from the RAMs.
  always_comb begin
    x_chunk = '0;

    for (int i = 0; i < PARALLEL_INPUTS; i++) begin
      int input_idx;
      input_idx = (int'(np_word_idx_r) * PARALLEL_INPUTS) + i;
      if (input_idx < TOTAL_INPUTS) x_chunk[i] = data_in_r[input_idx];
    end
  end

  generate
    for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : gen_nps
      neuron_processor #(
          .P_WIDTH  (PARALLEL_INPUTS),
          .ACC_WIDTH(NP_ACC_WIDTH)
      ) u_np (
          .clk      (clk),
          .rst      (rst),
          .valid_in (np_valid_aligned_r),
          .last     (np_last_aligned_r),
          .x        (x_chunk),
          .w        (w_rd_data[gi]),
          // Thresholds are held per lane for the duration of a batch so the
          // final compare cannot accidentally observe the next batch's threshold.
          .threshold(threshold_hold_r[gi]),
          .y        (np_y[gi]),
          .y_valid  (np_y_valid[gi])
      );
    end
  endgenerate

  // Main layer control.
  // This block owns:
  // - latching a new input vector when the layer is idle
  // - delaying RAM read requests by one cycle before asserting NP valid/last
  // - tagging completed batches so outputs get written into the correct slots
  // - exposing the final layer result with a proper valid/ready handshake
  always_ff @(posedge clk) begin
    if (rst) begin
      data_in_r           <= '0;
      data_out_r          <= '0;
      compute_busy_r      <= 1'b0;
      valid_out_r         <= 1'b0;
      np_valid_aligned_r  <= 1'b0;
      np_last_aligned_r   <= 1'b0;
      np_word_idx_r       <= '0;
      np_batch_idx_r      <= '0;

      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        threshold_hold_r[i] <= '0;
      end

      for (int stage = 0; stage <= NP_TREE_LATENCY; stage++) begin
        result_batch_valid_pipe[stage] <= 1'b0;
        result_batch_idx_pipe[stage]   <= '0;
      end
    end else begin
      if (config_busy && (compute_busy_r || valid_out_r)) begin
        $fatal(1, "bnn_layer does not support overlapping configuration and inference.");
      end

      if (valid_out_r && ready_out) begin
        valid_out_r <= 1'b0;
      end

      if (valid_in && ready_in) begin
        data_in_r      <= data_in;
        data_out_r     <= '0;
        compute_busy_r <= 1'b1;
      end

      // Align RAM read requests to synchronous RAM outputs.
      // The controller issues addresses in cycle N; the RAM data is usable in
      // cycle N+1, so that is when the NP should see valid/last.
      np_valid_aligned_r <= w_rd_en;
      np_last_aligned_r  <= ctrl_last_req;

      if (w_rd_en) begin
        np_word_idx_r  <= WORD_IDX_W'(w_rd_addr % WORDS_PER_NEURON);
        np_batch_idx_r <= BATCH_IDX_W'(t_rd_addr);
      end

      // Capture each batch's threshold on the first aligned word and hold it.
      if (np_valid_aligned_r && (np_word_idx_r == '0)) begin
        for (int lane = 0; lane < PARALLEL_NEURONS; lane++) begin
          threshold_hold_r[lane] <= NP_ACC_WIDTH'(t_rd_data[lane]);
        end
      end

      // Track which batch will finish coming out of the NP pipeline.
      result_batch_valid_pipe[0] <= np_valid_aligned_r && np_last_aligned_r;
      result_batch_idx_pipe[0]   <= np_batch_idx_r;

      for (int stage = 1; stage <= NP_TREE_LATENCY; stage++) begin
        result_batch_valid_pipe[stage] <= result_batch_valid_pipe[stage-1];
        result_batch_idx_pipe[stage]   <= result_batch_idx_pipe[stage-1];
      end

      // Assemble the full output vector one batch at a time.
      if (result_batch_valid_pipe[NP_TREE_LATENCY]) begin
        assert (np_y_valid[0])
        else $fatal(1, "bnn_layer internal timing error: batch tag reached output collector before neuron results were valid.");

        for (int lane = 0; lane < PARALLEL_NEURONS; lane++) begin
          int neuron_idx;
          neuron_idx = (int'(result_batch_idx_pipe[NP_TREE_LATENCY]) * PARALLEL_NEURONS) + lane;
          if (neuron_idx < TOTAL_NEURONS) data_out_r[neuron_idx] <= np_y[lane];
        end

        if (result_batch_idx_pipe[NP_TREE_LATENCY] == (NEURON_BATCHES - 1)) begin
          compute_busy_r <= 1'b0;
          valid_out_r    <= 1'b1;
        end
      end
    end
  end
endmodule
