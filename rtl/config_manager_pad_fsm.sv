module config_manager_pad_fsm #(
    parameter int LAYERS = 3,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8}
) (
    input logic clk,
    input logic rst,

    input logic        payload_start,
    input logic [31:0] payload_read_count,
    input logic        msg_type,
    input logic [ 1:0] layer_id,
    input logic [15:0] bytes_per_neuron,
    input logic        active_stream_empty,
    input logic [ 7:0] w_byte_data,

    output logic       in_read_state,
    output logic       stall,
    output logic       fifo_rd_en,
    output logic       buffer_wr_en,
    output logic [7:0] data
);

  //--------------------------------------------------------------------------
  // Overview
  //--------------------------------------------------------------------------
  // This FSM sits between the parsed config payload stream and the downstream
  // byte packer / buffer path.
  //
  // msg_type == 0 : weight payload
  //   - Real bytes are read from the active FIFO.
  //   - If a neuron ends before a downstream word boundary, synthetic 0xFF
  //     padding bytes are emitted locally in PAD.
  //
  // msg_type == 1 : threshold payload
  //   - The FSM mainly manages message read / drain flow.
  //   - No weight-byte padding is inserted.
  //
  // The important timing change in this rewrite is that the "this read finishes
  // a neuron" decision is made from:
  //
  //   read_fire && (byte_idx_r == bytes_per_neuron - 1)
  //
  // using the CURRENT registered byte index, instead of first computing
  // next_byte_idx and then comparing that. This shortens the control cone.

  typedef enum logic [1:0] {
    READ  = 2'd0,  // Read real payload bytes from the FIFO
    DRAIN = 2'd1,  // Flush any leftover FIFO contents before next message
    PAD   = 2'd2   // Emit synthetic all-ones bytes for weight alignment
  } state_t;

  // Keep the pad FSM in its explicit binary encoding so reset does not infer
  // a preset-style one-hot state register.
  (* fsm_encoding = "user" *) state_t state_r;
  state_t next_state;

  //--------------------------------------------------------------------------
  // Registered bookkeeping
  //--------------------------------------------------------------------------

  // Remaining unread payload bytes for the current message.
  logic [31:0] remaining_count_r;

  // Byte index within the current neuron for weight payloads.
  logic [8:0] byte_idx_r, next_byte_idx;

  // PAD countdown.
  //
  // Convention:
  // When entering PAD, this register is loaded with (bytes_to_pad - 1).
  // Therefore:
  //   remaining_pad_count_r == 0  -> current PAD cycle is the final pad byte
  //   remaining_pad_count_r >  0  -> more PAD cycles remain after this one
  logic [7:0] remaining_pad_count_r, next_remaining_pad_count;

  // Remembers whether PAD should fall through to DRAIN when it finishes.
  logic pad_exit_to_drain_r, next_pad_exit_to_drain;

  // Registered "the previous accepted payload read was the final payload read".
  // This delays READ -> DRAIN by one cycle and keeps the count-end decision
  // out of the direct next-state path.
  logic       last_rd_r;

  //--------------------------------------------------------------------------
  // Combinational control / status signals
  //--------------------------------------------------------------------------

  logic       read_fire;
  logic       last_read_fire;

  logic [7:0] bytes_per_word;
  logic [7:0] pad_remainder;
  logic [7:0] bytes_to_pad;
  logic       pad_required;

  logic       current_byte_is_last;
  logic       read_finishes_neuron;
  logic       pad_last_cycle;

  //--------------------------------------------------------------------------
  // State / per-neuron registers
  //--------------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rst) begin
      state_r               <= READ;
      byte_idx_r            <= '0;
      remaining_pad_count_r <= '0;
      pad_exit_to_drain_r   <= 1'b0;
    end else begin
      state_r               <= next_state;
      byte_idx_r            <= next_byte_idx;
      remaining_pad_count_r <= next_remaining_pad_count;
      pad_exit_to_drain_r   <= next_pad_exit_to_drain;
    end
  end

  //--------------------------------------------------------------------------
  // Message-level bookkeeping
  //--------------------------------------------------------------------------
  // remaining_count_r:
  //   Loaded from payload_read_count at payload_start, then decremented on each
  //   accepted FIFO read.
  //
  // last_rd_r:
  //   Registers whether the payload read that happened in the PREVIOUS cycle
  //   was the last byte of the message.
  //--------------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rst) begin
      remaining_count_r <= '0;
      last_rd_r         <= 1'b0;
    end else begin
      if (payload_start) begin
        remaining_count_r <= payload_read_count;
        last_rd_r         <= 1'b0;
      end else begin
        if (read_fire && (remaining_count_r != '0)) begin
          remaining_count_r <= remaining_count_r - 1'b1;
        end else if (state_r == DRAIN) begin
          remaining_count_r <= '0;
        end

        if (read_fire) begin
          last_rd_r <= last_read_fire;
        end else if (state_r == DRAIN) begin
          last_rd_r <= 1'b0;
        end
      end
    end
  end

  //--------------------------------------------------------------------------
  // Determine downstream packing width for this layer
  //--------------------------------------------------------------------------
  // Layer 0 consumes raw input bytes.
  // Later layers consume bytes sized to the previous layer's parallel neuron
  // count.
  //--------------------------------------------------------------------------

  always_comb begin
    bytes_per_word = PARALLEL_INPUTS / 8;

    for (int k = 0; k < LAYERS; k++) begin
      if (layer_id == 2'(k)) begin
        if (k == 0) begin
          bytes_per_word = PARALLEL_INPUTS / 8;
        end else begin
          bytes_per_word = PARALLEL_NEURONS[k-1] / 8;
        end
      end
    end
  end

  //--------------------------------------------------------------------------
  // Padding math
  //--------------------------------------------------------------------------
  // pad_remainder : bytes_per_neuron modulo bytes_per_word
  // bytes_to_pad  : number of synthetic bytes needed to align the neuron
  // pad_required  : true if the neuron does not already end on a word boundary
  //--------------------------------------------------------------------------

  assign pad_remainder = bytes_per_neuron[7:0] & (bytes_per_word - 1'b1);
  assign bytes_to_pad = (pad_remainder == '0) ? '0 : (bytes_per_word - pad_remainder);
  assign pad_required = (bytes_to_pad != '0);

  //--------------------------------------------------------------------------
  // Traditional "last byte of neuron" detection
  //--------------------------------------------------------------------------
  // IMPORTANT:
  // This is the key rewrite. We do NOT derive neuron completion from
  // next_byte_idx anymore.
  //
  // Instead:
  //   current_byte_is_last  -> current registered byte index is the last index
  //   read_finishes_neuron  -> the read happening THIS cycle consumes that byte
  //
  // This keeps the neuron-end decision tied to:
  //   - current registered state
  //   - read handshake
  // rather than to the whole next-index mux cone.
  //--------------------------------------------------------------------------


  //--------------------------------------------------------------------------
  // Final payload-byte detection
  //--------------------------------------------------------------------------
  // The last payload byte is the one read while remaining_count_r == 1.
  //--------------------------------------------------------------------------

  assign last_read_fire = remaining_count_r == 1'b1;

  //--------------------------------------------------------------------------
  // PAD exit detection
  //--------------------------------------------------------------------------
  // Because remaining_pad_count_r is loaded with (bytes_to_pad - 1) on PAD
  // entry, a value of 0 means "the current PAD cycle is the last one."
  //--------------------------------------------------------------------------

  assign pad_last_cycle = remaining_pad_count_r == '0;

  assign in_read_state = (state_r == READ);
  assign stall = (state_r == PAD);

  //--------------------------------------------------------------------------
  // Next-state / output logic
  //--------------------------------------------------------------------------

  always_comb begin
    // Defaults: hold state / registers unless explicitly changed
    next_state               = state_r;
    next_byte_idx            = byte_idx_r;
    next_remaining_pad_count = remaining_pad_count_r;
    next_pad_exit_to_drain   = pad_exit_to_drain_r;

    fifo_rd_en               = 1'b0;
    buffer_wr_en             = 1'b0;
    read_fire                = 1'b0;
    data                     = w_byte_data;

    case (state_r)

      //----------------------------------------------------------------------
      // READ
      //----------------------------------------------------------------------
      // Consume real payload bytes from the FIFO.
      //
      // If the previous cycle's accepted read was the final payload byte,
      // transition into DRAIN here.
      //----------------------------------------------------------------------
      READ: begin
        if (last_rd_r) begin
          next_state = DRAIN;
        end else if (!active_stream_empty) begin
          fifo_rd_en = 1'b1;
          read_fire  = 1'b1;

          // Only weight payloads are forwarded into the downstream byte buffer.
          if (!msg_type) begin
            buffer_wr_en = 1'b1;

            // The current accepted read completes a neuron.
            if (byte_idx_r == (bytes_per_neuron - 1'b1)) begin
              next_byte_idx = '0;

              // If this neuron needs alignment padding, switch to PAD.
              if (pad_required) begin
                next_state               = PAD;
                next_remaining_pad_count = bytes_to_pad - 1'b1;

                // Remember whether the payload read that just ended the neuron
                // also ended the entire message. If so, PAD should fall through
                // to DRAIN after the final synthetic byte.
                next_pad_exit_to_drain   = last_read_fire;
              end
            end else begin
              // Normal in-neuron advance
              next_byte_idx = byte_idx_r + 1'b1;
            end
          end
        end
      end

      //----------------------------------------------------------------------
      // PAD
      //----------------------------------------------------------------------
      // Emit synthetic 0xFF bytes locally. No FIFO read occurs here.
      //----------------------------------------------------------------------
      PAD: begin
        data         = '1;
        buffer_wr_en = 1'b1;

        if (pad_last_cycle) begin
          next_remaining_pad_count = '0;
          next_pad_exit_to_drain   = 1'b0;
          next_state               = pad_exit_to_drain_r ? DRAIN : READ;
        end else begin
          next_remaining_pad_count = remaining_pad_count_r - 1'b1;
        end
      end

      //----------------------------------------------------------------------
      // DRAIN
      //----------------------------------------------------------------------
      // Continue popping until the active FIFO reports empty, then return to
      // READ and wait for the next message.
      //----------------------------------------------------------------------
      DRAIN: begin
        fifo_rd_en = 1'b1;

        if (active_stream_empty) begin
          next_state = READ;
        end
      end

      default: begin
        next_state = READ;
      end
    endcase
  end

endmodule
