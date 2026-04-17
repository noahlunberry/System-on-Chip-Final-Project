module config_manager_pad_fsm #(
    parameter int LAYERS = 3,
    parameter int PAYLOAD_COUNT_W = 32,
    parameter int WEIGHT_TOTAL_BYTES[LAYERS] = '{default: 1},
    parameter int THRESHOLD_TOTAL_BYTES[LAYERS] = '{default: 4},
    parameter int WEIGHT_BYTES_PER_NEURON[LAYERS] = '{default: 1},
    parameter int WEIGHT_BYTES_PER_WORD  [LAYERS] = '{default: 1}
) (
    input logic clk,
    input logic rst,

    input logic        payload_start,
    input logic        msg_type,
    input logic [ 1:0] layer_id,
    input logic        active_stream_empty,
    input logic [ 7:0] w_byte_data,

    output logic       in_read_state,
    output logic       stall,
    output logic       fifo_rd_en,
    output logic       buffer_wr_en,
    output logic [7:0] data
);

  // IDLE latches per-message metadata, READ consumes payload bytes, PAD emits
  // synthetic 0xFF alignment bytes, and DRAIN flushes before the next message.
  typedef enum logic [1:0] {
    IDLE  = 2'd0,
    READ  = 2'd1,
    DRAIN = 2'd2,
    PAD   = 2'd3
  } state_t;

  (* fsm_encoding = "user" *) state_t state_r;
  state_t next_state;

  logic [PAYLOAD_COUNT_W-1:0] remaining_count_r;
  logic msg_type_r, next_msg_type;
  // Latched in IDLE when payload_start arrives so READ/PAD/DRAIN do not
  // depend on live parser metadata.
  logic [15:0] bytes_per_neuron_r, next_bytes_per_neuron;
  logic [7:0] bytes_per_word_r, next_bytes_per_word;
  logic [8:0] byte_idx_r, next_byte_idx;
  // Precompute per-message padding so READ only needs the neuron-end compare.
  logic pad_required_r, next_pad_required;
  logic [7:0] pad_count_init_r, next_pad_count_init;
  // Loaded with (pad_bytes - 1) when entering PAD.
  logic [7:0] remaining_pad_count_r, next_remaining_pad_count;
  logic pad_exit_to_drain_r, next_pad_exit_to_drain;
  // Tracks whether the prior accepted read finished the current message.
  logic last_rd_r;

  logic       read_fire;
  localparam int THRESH_WORD_BYTES = 4;

  function automatic logic [PAYLOAD_COUNT_W-1:0] decode_payload_item_count(
      input logic       cfg_msg_type,
      input logic [1:0] cfg_layer_id
  );
    decode_payload_item_count = '0;
    if (cfg_layer_id < LAYERS) begin
      decode_payload_item_count = cfg_msg_type ? (THRESHOLD_TOTAL_BYTES[cfg_layer_id] / THRESH_WORD_BYTES)
                                               : WEIGHT_TOTAL_BYTES[cfg_layer_id];
    end
  endfunction

  function automatic logic [15:0] decode_weight_bytes_per_neuron(input logic [1:0] cfg_layer_id);
    decode_weight_bytes_per_neuron = 16'd1;
    if (cfg_layer_id < LAYERS) begin
      decode_weight_bytes_per_neuron = WEIGHT_BYTES_PER_NEURON[cfg_layer_id];
    end
  endfunction

  function automatic logic [7:0] decode_weight_bytes_per_word(input logic [1:0] cfg_layer_id);
    decode_weight_bytes_per_word = 8'd1;
    if (cfg_layer_id < LAYERS) begin
      decode_weight_bytes_per_word = WEIGHT_BYTES_PER_WORD[cfg_layer_id];
    end
  endfunction

  always_ff @(posedge clk) begin
    if (rst) begin
      state_r               <= IDLE;
      msg_type_r            <= 1'b0;
      bytes_per_neuron_r    <= WEIGHT_BYTES_PER_NEURON[0];
      bytes_per_word_r      <= WEIGHT_BYTES_PER_WORD[0];
      byte_idx_r            <= '0;
      pad_required_r        <= 1'b0;
      pad_count_init_r      <= '0;
      remaining_pad_count_r <= '0;
      pad_exit_to_drain_r   <= 1'b0;
    end else begin
      state_r               <= next_state;
      msg_type_r            <= next_msg_type;
      bytes_per_neuron_r    <= next_bytes_per_neuron;
      bytes_per_word_r      <= next_bytes_per_word;
      byte_idx_r            <= next_byte_idx;
      pad_required_r        <= next_pad_required;
      pad_count_init_r      <= next_pad_count_init;
      remaining_pad_count_r <= next_remaining_pad_count;
      pad_exit_to_drain_r   <= next_pad_exit_to_drain;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      remaining_count_r <= '0;
      last_rd_r         <= 1'b0;
    end else begin
      if (payload_start) begin
        remaining_count_r <= decode_payload_item_count(msg_type, layer_id);
        last_rd_r         <= 1'b0;
      end else begin
        if (read_fire && (remaining_count_r != '0)) begin
          remaining_count_r <= remaining_count_r - 1'b1;
        end else if (state_r == DRAIN) begin
          remaining_count_r <= '0;
        end

        if (read_fire) begin
          last_rd_r <= (remaining_count_r == 'd1);
        end else if (state_r == DRAIN) begin
          last_rd_r <= 1'b0;
        end
      end
    end
  end

  assign in_read_state = (state_r == IDLE) || (state_r == READ);
  assign stall         = (state_r == PAD);

  always_comb begin
    logic [15:0] decoded_bytes_per_neuron;
    logic [7:0] decoded_bytes_per_word;
    logic [7:0] neuron_tail_bytes;
    logic [7:0] pad_bytes_needed;

    next_state               = state_r;
    next_msg_type            = msg_type_r;
    next_bytes_per_neuron    = bytes_per_neuron_r;
    next_bytes_per_word      = bytes_per_word_r;
    next_byte_idx            = byte_idx_r;
    next_pad_required        = pad_required_r;
    next_pad_count_init      = pad_count_init_r;
    next_remaining_pad_count = remaining_pad_count_r;
    next_pad_exit_to_drain   = pad_exit_to_drain_r;

    fifo_rd_en               = 1'b0;
    buffer_wr_en             = 1'b0;
    read_fire                = 1'b0;
    data                     = w_byte_data;
    decoded_bytes_per_neuron = '0;
    decoded_bytes_per_word   = '0;
    neuron_tail_bytes        = '0;
    pad_bytes_needed         = '0;

    case (state_r)
      IDLE: begin
        if (payload_start) begin
          decoded_bytes_per_neuron = decode_weight_bytes_per_neuron(layer_id);
          decoded_bytes_per_word   = decode_weight_bytes_per_word(layer_id);
          neuron_tail_bytes        = decoded_bytes_per_neuron[7:0] & (decoded_bytes_per_word - 1'b1);
          pad_bytes_needed         = decoded_bytes_per_word - neuron_tail_bytes;
          next_state               = READ;
          next_msg_type            = msg_type;
          next_bytes_per_neuron    = decoded_bytes_per_neuron;
          next_bytes_per_word      = decoded_bytes_per_word;
          next_byte_idx            = '0;
          next_pad_required        = !msg_type && (neuron_tail_bytes != '0);
          next_pad_count_init      = (!msg_type && (neuron_tail_bytes != '0)) ? (pad_bytes_needed - 1'b1) : '0;
          next_remaining_pad_count = '0;
          next_pad_exit_to_drain   = 1'b0;
        end
      end

      READ: begin
        if (last_rd_r) begin
          next_state = DRAIN;
        end else if (!active_stream_empty) begin
          fifo_rd_en = 1'b1;
          buffer_wr_en = 1'b1;
          read_fire = 1'b1;

          if (!msg_type_r) begin
            // Use the current registered byte index to detect neuron end.
            if (byte_idx_r == (bytes_per_neuron_r - 1'b1)) begin
              next_byte_idx = '0;

              if (pad_required_r) begin
                next_state               = PAD;
                next_remaining_pad_count = pad_count_init_r;
                next_pad_exit_to_drain   = (remaining_count_r == 'd1);
              end
            end else begin
              next_byte_idx = byte_idx_r + 1'b1;
            end
          end
        end
      end

      PAD: begin
        data         = '1;
        buffer_wr_en = 1'b1;

        if (remaining_pad_count_r == '0) begin
          next_remaining_pad_count = '0;
          next_pad_exit_to_drain   = 1'b0;
          next_state               = pad_exit_to_drain_r ? DRAIN : READ;
        end else begin
          next_remaining_pad_count = remaining_pad_count_r - 1'b1;
        end
      end

      DRAIN: begin
        fifo_rd_en = 1'b1;

        if (active_stream_empty) begin
          next_state = IDLE;
        end
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

endmodule
