module config_manager_parser #(
    parameter int LAYERS = 3,
    parameter int PAYLOAD_COUNT_W = 32,
    parameter int WEIGHT_TOTAL_BYTES[LAYERS] = '{default: 1},
    parameter int THRESHOLD_TOTAL_BYTES[LAYERS] = '{default: 4}
) (
    input logic clk,
    input logic rst,

    input logic       cfg_byte_valid,
    input logic [7:0] cfg_byte_data,
    input logic       empty,
    input logic       stall,

    output logic       cfg_byte_rd_en,
    output logic       payload_byte_valid,
    output logic [7:0] payload_byte_data,
    output logic       msg_type,
    output logic [7:0] layer_id,
    output logic       payload_start
);

  localparam int HEADER_BYTES = 16;

  typedef enum logic [1:0] {
    PARSE_HEADER  = 2'd0,
    PARSE_PAYLOAD = 2'd1,
    PARSE_DONE    = 2'd2
  } parse_state_t;

  // Keep the parser in its explicit binary encoding so reset stays a plain
  // synchronous clear instead of becoming a preset-driven one-hot state bit.
  (* fsm_encoding = "user" *)parse_state_t       parse_state_r;
  parse_state_t       next_parse_state;

  // Registered message metadata for the payload currently being emitted.
  logic               next_msg_type;
  logic         [7:0] next_layer_id;

  // Header progress tracking.
  logic [$clog2(HEADER_BYTES+1)-1:0] header_count_r, next_header_count;

  // Payload progress tracking.
  logic [PAYLOAD_COUNT_W-1:0] payload_bytes_r, next_payload_bytes;
  logic [PAYLOAD_COUNT_W-1:0] payload_count_r, next_payload_count;
  logic next_payload_start;

  // fifo_config_bytes uses registered read data, so cfg_byte_rd_en requests the
  // next byte and cfg_byte_data_valid_r says the staged cfg_byte_data byte is
  // available to consume in the current cycle.
  logic cfg_byte_data_valid_r, next_cfg_byte_data_valid;

  function automatic logic [PAYLOAD_COUNT_W-1:0] calc_payload_bytes(input logic cfg_msg_type,
                                                                    input logic [7:0] cfg_layer_id);
    calc_payload_bytes = '0;
    if (cfg_layer_id < LAYERS) begin
      calc_payload_bytes = cfg_msg_type ? THRESHOLD_TOTAL_BYTES[cfg_layer_id] :
                                          WEIGHT_TOTAL_BYTES[cfg_layer_id];
    end
  endfunction

  // Main parser state and message metadata registers.
  always_ff @(posedge clk) begin
    if (rst) begin
      parse_state_r         <= PARSE_HEADER;
      msg_type              <= 1'b0;
      layer_id              <= '0;
      header_count_r        <= '0;
      payload_bytes_r       <= '0;
      payload_count_r       <= '0;
      cfg_byte_data_valid_r <= 1'b0;
      payload_start         <= 1'b0;
    end else begin
      parse_state_r         <= next_parse_state;
      msg_type              <= next_msg_type;
      layer_id              <= next_layer_id;
      header_count_r        <= next_header_count;
      payload_bytes_r       <= next_payload_bytes;
      payload_count_r       <= next_payload_count;
      cfg_byte_data_valid_r <= next_cfg_byte_data_valid;
      payload_start         <= next_payload_start;
    end
  end

  // Next-state and control logic.
  //
  // High-level flow:
  // 1. PARSE_HEADER consumes HEADER_BYTES bytes and latches only the metadata
  //    still used after the compile-time config-table refactor.
  // 2. On the final header byte, switch to PARSE_PAYLOAD.
  // 3. PARSE_PAYLOAD streams bytes into either the weight or threshold path.
  // 4. PARSE_DONE waits for the rest of config_manager to finish draining the
  //    current message before accepting the next header.
  always_comb begin
    logic cfg_byte_consume;
    logic header_last_byte;
    logic payload_last_byte;

    next_parse_state         = parse_state_r;
    next_msg_type            = msg_type;
    next_layer_id            = layer_id;
    next_header_count        = header_count_r;
    next_payload_bytes       = payload_bytes_r;
    next_payload_count       = payload_count_r;
    next_cfg_byte_data_valid = cfg_byte_data_valid_r;
    next_payload_start       = 1'b0;

    cfg_byte_rd_en           = cfg_byte_valid
                               && ((parse_state_r == PARSE_HEADER)
                                   || ((parse_state_r == PARSE_PAYLOAD) && !stall));
    payload_byte_valid       = 1'b0;
    payload_byte_data        = cfg_byte_data;
    cfg_byte_consume         = 1'b0;
    header_last_byte         = (header_count_r == (HEADER_BYTES - 1));
    payload_last_byte        = 1'b0;

    case (parse_state_r)
      PARSE_HEADER: begin
        next_payload_count = '0;
        next_payload_bytes = calc_payload_bytes(msg_type, layer_id);

        if (cfg_byte_data_valid_r) begin
          cfg_byte_consume = 1'b1;

          if (header_count_r == '0) begin
            next_msg_type = cfg_byte_data[0];
          end else if (header_count_r == 'd1) begin
            next_layer_id = cfg_byte_data;
          end

          if (header_last_byte) begin
            next_payload_start = 1'b1;
            next_header_count  = '0;

            // The shared read-enable rule above keeps the byte stream hot
            // across the header -> payload transition whenever data is ready.
            next_parse_state   = PARSE_PAYLOAD;
          end else begin
            next_header_count = header_count_r + 1'b1;
          end
        end
      end

      PARSE_PAYLOAD: begin
        payload_last_byte = (payload_bytes_r != '0) && (payload_count_r == (payload_bytes_r - 1'b1));

        // Hold the staged payload byte whenever pad_fsm is emitting synthetic
        // padding so weight parsing does not outrun the downstream consumer.
        if (cfg_byte_data_valid_r && !stall) begin
          cfg_byte_consume   = 1'b1;
          payload_byte_valid = 1'b1;
          next_payload_count = payload_count_r + 1'b1;

          if (payload_last_byte) begin
            next_parse_state = PARSE_DONE;
          end

        end
      end

      PARSE_DONE: begin
        next_payload_bytes = '0;
        next_payload_count = '0;
        next_header_count  = '0;

        if (empty) begin
          next_parse_state = PARSE_HEADER;
        end
      end

      default: begin
        next_payload_bytes = '0;
        next_header_count  = '0;
        next_payload_count = '0;
        next_parse_state   = PARSE_HEADER;
      end
    endcase

    // Update the staged-byte valid bit. If we consumed the current staged byte,
    // the next valid value depends on whether we also requested a replacement.
    // If no byte was staged, a new request will make one valid next cycle.
    if (cfg_byte_consume) begin
      next_cfg_byte_data_valid = cfg_byte_rd_en;
    end else if (!cfg_byte_data_valid_r) begin
      next_cfg_byte_data_valid = cfg_byte_rd_en;
    end
  end

endmodule
