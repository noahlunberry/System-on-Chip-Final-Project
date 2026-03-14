// This helper owns the layer-local configuration write mapping.
//
// The config manager is expected to provide one logical RAM word per
// `config_rd_en` cycle. This module translates that serialized stream into
// per-lane weight/threshold RAM writes and validates the layer-specific header
// fields while the message is being consumed.
module bnn_layer_config_controller #(
    parameter int PARALLEL_INPUTS   = 32,
    parameter int PARALLEL_NEURONS  = 32,
    parameter int MANAGER_BUS_WIDTH = 32,
    parameter int TOTAL_INPUTS      = 256,
    parameter int TOTAL_NEURONS     = 256,
    parameter int W_RAM_ADDR_W      = 12,
    parameter int T_RAM_ADDR_W      = 8
) (
    input logic clk,
    input logic rst,

    input  logic [MANAGER_BUS_WIDTH-1:0] config_data,
    input  logic                         config_rd_en,
    input  logic                         msg_type,          // 0: weights, 1: thresholds
    input  logic [15:0]                  total_bytes,
    input  logic [7:0]                   bytes_per_neuron,

    output logic busy,
    output logic payload_done,

    output logic                    w_wr_en  [PARALLEL_NEURONS],
    output logic [W_RAM_ADDR_W-1:0] w_wr_addr[PARALLEL_NEURONS],
    output logic [PARALLEL_INPUTS-1:0] w_wr_data[PARALLEL_NEURONS],

    output logic                    t_wr_en  [PARALLEL_NEURONS],
    output logic [T_RAM_ADDR_W-1:0] t_wr_addr[PARALLEL_NEURONS],
    output logic [31:0]             t_wr_data[PARALLEL_NEURONS]
);
  localparam int W_RAM_DATA_W     = PARALLEL_INPUTS;
  localparam int T_RAM_DATA_W     = 32;
  localparam int WORDS_PER_NEURON = (TOTAL_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS;
  localparam int CFG_WEIGHT_BYTES = (TOTAL_INPUTS + 7) / 8;
  localparam int CFG_THRESH_BYTES = 4;
  localparam int WORD_IDX_W       = (WORDS_PER_NEURON > 1) ? $clog2(WORDS_PER_NEURON) : 1;
  localparam int NEURON_IDX_W     = (TOTAL_NEURONS > 1) ? $clog2(TOTAL_NEURONS) : 1;

  logic                    cfg_msg_type_r;
  logic [WORD_IDX_W-1:0]   cfg_word_idx_r;
  logic [NEURON_IDX_W-1:0] cfg_neuron_idx_r;
  logic                    cfg_busy_r;
  logic                    payload_done_r;

  logic        cfg_msg_type_active;
  int unsigned cfg_words_per_neuron_active;
  int unsigned cfg_lane_idx;
  int unsigned cfg_batch_idx;

  assign busy         = cfg_busy_r;
  assign payload_done = payload_done_r;

  always_comb begin
    cfg_msg_type_active         = cfg_busy_r ? cfg_msg_type_r : msg_type;
    cfg_words_per_neuron_active = cfg_msg_type_active ? 1 : WORDS_PER_NEURON;
    cfg_lane_idx                = cfg_neuron_idx_r % PARALLEL_NEURONS;
    cfg_batch_idx               = cfg_neuron_idx_r / PARALLEL_NEURONS;

    for (int i = 0; i < PARALLEL_NEURONS; i++) begin
      w_wr_en[i]   = 1'b0;
      w_wr_addr[i] = '0;
      w_wr_data[i] = W_RAM_DATA_W'(config_data);
      t_wr_en[i]   = 1'b0;
      t_wr_addr[i] = '0;
      t_wr_data[i] = T_RAM_DATA_W'(config_data);
    end

    if (config_rd_en) begin
      if (cfg_msg_type_active == 1'b0) begin
        w_wr_en[cfg_lane_idx]   = 1'b1;
        w_wr_addr[cfg_lane_idx] = W_RAM_ADDR_W'((cfg_batch_idx * WORDS_PER_NEURON) + cfg_word_idx_r);
      end else begin
        t_wr_en[cfg_lane_idx]   = 1'b1;
        t_wr_addr[cfg_lane_idx] = T_RAM_ADDR_W'(cfg_batch_idx);
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      cfg_busy_r       <= 1'b0;
      cfg_msg_type_r   <= 1'b0;
      cfg_word_idx_r   <= '0;
      cfg_neuron_idx_r <= '0;
      payload_done_r   <= 1'b0;
    end else begin
      payload_done_r <= 1'b0;

      if (config_rd_en) begin
        if (!cfg_busy_r) begin
          cfg_busy_r       <= 1'b1;
          cfg_msg_type_r   <= msg_type;
          cfg_word_idx_r   <= '0;
          cfg_neuron_idx_r <= '0;

          if (msg_type == 1'b0) begin
            assert (bytes_per_neuron == CFG_WEIGHT_BYTES)
            else $fatal(1, "bnn_layer_config_controller weight header mismatch: bytes_per_neuron=%0d expected=%0d",
                        bytes_per_neuron, CFG_WEIGHT_BYTES);
            assert (total_bytes == (CFG_WEIGHT_BYTES * TOTAL_NEURONS))
            else $fatal(1, "bnn_layer_config_controller weight header mismatch: total_bytes=%0d expected=%0d",
                        total_bytes, CFG_WEIGHT_BYTES * TOTAL_NEURONS);
          end else begin
            assert (bytes_per_neuron == CFG_THRESH_BYTES)
            else $fatal(1, "bnn_layer_config_controller threshold header mismatch: bytes_per_neuron=%0d expected=%0d",
                        bytes_per_neuron, CFG_THRESH_BYTES);
            assert (total_bytes == (CFG_THRESH_BYTES * TOTAL_NEURONS))
            else $fatal(1, "bnn_layer_config_controller threshold header mismatch: total_bytes=%0d expected=%0d",
                        total_bytes, CFG_THRESH_BYTES * TOTAL_NEURONS);
          end
        end

        if (cfg_word_idx_r == (cfg_words_per_neuron_active - 1)) begin
          cfg_word_idx_r <= '0;

          if (cfg_neuron_idx_r == (TOTAL_NEURONS - 1)) begin
            cfg_busy_r       <= 1'b0;
            cfg_neuron_idx_r <= '0;
            payload_done_r   <= 1'b1;
          end else begin
            cfg_neuron_idx_r <= cfg_neuron_idx_r + 1'b1;
          end
        end else begin
          cfg_word_idx_r <= cfg_word_idx_r + 1'b1;
        end
      end
    end
  end
endmodule
