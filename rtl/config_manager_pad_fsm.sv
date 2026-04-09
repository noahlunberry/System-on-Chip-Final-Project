module config_manager_pad_fsm #(
    parameter int LAYERS = 3,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS = 8
) (
    input logic clk,
    input logic rst,

    input logic       payload_start,
    input logic [31:0] payload_read_count,
    input logic       msg_type,
    input logic [1:0] layer_id,
    input logic [15:0] bytes_per_neuron,
    input logic       active_stream_empty,
    input logic [7:0] w_byte_data,

    output logic       in_read_state,
    output logic       fifo_rd_en,
    output logic       buffer_wr_en,
    output logic [7:0] data
);

  typedef enum logic [1:0] {
    READ,
    DRAIN,
    PAD
  } state_t;

  state_t state_r, next_state;

  logic [31:0] rd_count_r;
  logic [31:0] count_r;
  logic [8:0]  byte_idx_r, next_byte_idx;
  logic [7:0]  pad_count_r, next_pad_count;
  logic        read_finishes_neuron_r, next_read_finishes_neuron;
  logic        pad_last_cycle_r, next_pad_last_cycle;
  logic        pad_exit_to_drain_r, next_pad_exit_to_drain;
  logic        last_rd_r;

  logic        read_fire;
  logic        last_read_fire;
  logic [7:0]  bytes_per_word;
  logic [7:0]  pad_remainder;
  logic [7:0]  bytes_to_pad;
  logic        pad_required;

  always_ff @(posedge clk) begin
    if (rst) begin
      state_r                 <= READ;
      byte_idx_r              <= '0;
      pad_count_r             <= '0;
      read_finishes_neuron_r  <= 1'b0;
      pad_last_cycle_r        <= 1'b0;
      pad_exit_to_drain_r     <= 1'b0;
    end else begin
      state_r                 <= next_state;
      byte_idx_r              <= next_byte_idx;
      pad_count_r             <= next_pad_count;
      read_finishes_neuron_r  <= next_read_finishes_neuron;
      pad_last_cycle_r        <= next_pad_last_cycle;
      pad_exit_to_drain_r     <= next_pad_exit_to_drain;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_count_r <= '0;
      count_r    <= '0;
      last_rd_r  <= 1'b0;
    end else begin
      if (payload_start) begin
        rd_count_r <= payload_read_count;
        count_r    <= '0;
        last_rd_r  <= 1'b0;
      end else begin
        if (read_fire) begin
          count_r <= count_r + 32'd1;
        end else if (state_r == DRAIN) begin
          count_r <= '0;
        end

        if (read_fire) begin
          last_rd_r <= last_read_fire;
        end else if (state_r == DRAIN) begin
          last_rd_r <= 1'b0;
        end
      end
    end
  end

  always_comb begin
    bytes_per_word = MAX_PARALLEL_INPUTS / 8;
    for (int k = 0; k < LAYERS; k++) begin
      if (layer_id == 2'(k)) begin
        if (k == 0) bytes_per_word = MAX_PARALLEL_INPUTS / 8;
        else bytes_per_word = PARALLEL_NEURONS[k-1] / 8;
      end
    end
  end

  assign pad_remainder = bytes_per_neuron[7:0] & (bytes_per_word - 8'd1);
  assign bytes_to_pad  = (pad_remainder == 8'd0) ? 8'd0 : (bytes_per_word - pad_remainder);
  assign pad_required  = (bytes_to_pad != 8'd0);
  assign last_read_fire = read_fire && (rd_count_r != 32'd0)
                          && ((count_r + 32'd1) >= rd_count_r);
  assign in_read_state = (state_r == READ);

  always_comb begin
    next_state                = state_r;
    next_byte_idx             = byte_idx_r;
    next_pad_count            = pad_count_r;
    next_read_finishes_neuron = read_finishes_neuron_r;
    next_pad_last_cycle       = pad_last_cycle_r;
    next_pad_exit_to_drain    = pad_exit_to_drain_r;

    buffer_wr_en              = 1'b0;
    fifo_rd_en                = 1'b0;
    read_fire                 = 1'b0;
    data                      = w_byte_data;

    case (state_r)
      READ: begin
        if (last_rd_r) begin
          next_state = DRAIN;
        end else if (!active_stream_empty) begin
          fifo_rd_en = 1'b1;
          read_fire  = 1'b1;

          if (!msg_type) begin
            buffer_wr_en = 1'b1;
            if (read_finishes_neuron_r) begin
              next_byte_idx = '0;
              if (pad_required) begin
                next_state = PAD;
                next_pad_exit_to_drain = last_read_fire;
              end
            end else begin
              next_byte_idx = byte_idx_r + 1'b1;
            end
          end
        end
      end

      PAD: begin
        data           = 8'hFF;
        buffer_wr_en   = 1'b1;
        next_pad_count = pad_count_r + 1'b1;

        if (pad_last_cycle_r) begin
          next_pad_count        = '0;
          next_pad_exit_to_drain = 1'b0;
          next_state            = pad_exit_to_drain_r ? DRAIN : READ;
        end
      end

      DRAIN: begin
        fifo_rd_en = 1'b1;
        if (active_stream_empty) begin
          next_state = READ;
        end
      end

      default: next_state = READ;
    endcase

    next_read_finishes_neuron = (next_state == READ) && !msg_type
                                && (bytes_per_neuron != 16'd0)
                                && (next_byte_idx == (bytes_per_neuron - 16'd1));
    next_pad_last_cycle = (next_state == PAD) && (bytes_to_pad != 8'd0)
                          && (next_pad_count == (bytes_to_pad - 8'd1));
  end

endmodule
