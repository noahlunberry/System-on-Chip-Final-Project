module config_manager_parser #(
    parameter int LAYERS = 3,
    parameter int WEIGHT_TOTAL_BYTES[LAYERS] = '{default: 1},
    parameter int THRESHOLD_TOTAL_BYTES[LAYERS] = '{default: 4}
) (
    input logic clk,
    input logic rst,

    input logic       cfg_byte_empty,
    input logic [7:0] cfg_byte_data,
    input logic       empty,
    input logic       stall,

    output logic        cfg_byte_rd_en,
    output logic        payload_byte_valid,
    output logic        payload_byte_is_thresh,
    output logic [ 7:0] payload_byte_data,
    output logic        msg_type,
    output logic [ 1:0] layer_id,
    output logic        payload_start,
    output logic [31:0] payload_read_count
);

  localparam int HEADER_BYTES = 16;
  localparam int THRESH_WORD_BYTES = 4;

  typedef enum logic [1:0] {
    PARSE_HEADER  = 2'd0,
    PARSE_PAYLOAD = 2'd1,
    PARSE_DONE    = 2'd2
  } parse_state_t;

  // Keep the parser in its explicit binary encoding so reset stays a plain
  // synchronous clear instead of becoming a preset-driven one-hot state bit.
  (* fsm_encoding = "user" *) parse_state_t parse_state_r;
  parse_state_t next_parse_state;

  // Registered message metadata for the payload currently being emitted.
  logic       next_msg_type;
  logic [1:0] next_layer_id;
  // Cache "payload_count_r value seen on the second-to-last payload byte" so
  // payload-end detection is a simple registered compare in PARSE_PAYLOAD.
  logic [31:0] payload_second_last_idx_r, next_payload_second_last_idx;

  // Header assembly and progress tracking.
  logic [HEADER_BYTES*8-1:0] header_buf_r, next_header_buf;
  logic [$clog2(HEADER_BYTES+1)-1:0] header_count_r, next_header_count;

  // Payload progress tracking.
  logic [31:0] payload_count_r, next_payload_count;
  logic header_last_byte_r, next_header_last_byte;
  logic payload_last_byte_r, next_payload_last_byte;
  logic next_payload_start;
  logic [31:0] next_payload_read_count;

  // fifo_config_bytes uses registered read data, so cfg_byte_rd_en requests the
  // next byte and cfg_byte_data_valid_r says the staged cfg_byte_data byte is
  // available to consume in the current cycle.
  logic cfg_byte_data_valid_r, next_cfg_byte_data_valid;

  function automatic logic [31:0] calc_payload_bytes(
      input logic       cfg_msg_type,
      input logic [1:0] cfg_layer_id
  );
    calc_payload_bytes = '0;
    if (cfg_layer_id < LAYERS) begin
      calc_payload_bytes = cfg_msg_type ? THRESHOLD_TOTAL_BYTES[cfg_layer_id] :
                                          WEIGHT_TOTAL_BYTES[cfg_layer_id];
    end
  endfunction

  function automatic logic [31:0] calc_payload_read_count(
      input logic       cfg_msg_type,
      input logic [1:0] cfg_layer_id
  );
    logic [31:0] payload_bytes;
    begin
      payload_bytes = calc_payload_bytes(cfg_msg_type, cfg_layer_id);
      calc_payload_read_count = cfg_msg_type ? (payload_bytes / THRESH_WORD_BYTES) : payload_bytes;
    end
  endfunction

  // Main parser state and message metadata registers.
  always_ff @(posedge clk) begin
    if (rst) begin
      parse_state_r             <= PARSE_HEADER;
      msg_type                  <= 1'b0;
      layer_id                  <= '0;
      payload_second_last_idx_r <= '0;
      header_buf_r              <= '0;
      header_count_r            <= '0;
      payload_count_r           <= '0;
      header_last_byte_r        <= (HEADER_BYTES == 1);
      payload_last_byte_r       <= 1'b0;
      cfg_byte_data_valid_r     <= 1'b0;
      payload_start             <= 1'b0;
      payload_read_count        <= '0;
    end else begin
      parse_state_r             <= next_parse_state;
      msg_type                  <= next_msg_type;
      layer_id                  <= next_layer_id;
      payload_second_last_idx_r <= next_payload_second_last_idx;
      header_buf_r              <= next_header_buf;
      header_count_r            <= next_header_count;
      payload_count_r           <= next_payload_count;
      header_last_byte_r        <= next_header_last_byte;
      payload_last_byte_r       <= next_payload_last_byte;
      cfg_byte_data_valid_r     <= next_cfg_byte_data_valid;
      payload_start             <= next_payload_start;
      payload_read_count        <= next_payload_read_count;
    end
  end

  // Next-state and control logic.
  //
  // High-level flow:
  // 1. PARSE_HEADER pulls HEADER_BYTES bytes into header_buf_r.
  // 2. On the final header byte, decode metadata and switch to PARSE_PAYLOAD.
  // 3. PARSE_PAYLOAD streams bytes into either the weight or threshold path.
  // 4. PARSE_DONE waits for the rest of config_manager to finish draining the
  //    current message before accepting the next header.
  always_comb begin
    logic cfg_byte_consume;
    logic cfg_byte_request;
    logic [31:0] decoded_payload_bytes;

    next_parse_state             = parse_state_r;
    next_msg_type                = msg_type;
    next_layer_id                = layer_id;
    next_payload_second_last_idx = payload_second_last_idx_r;
    next_header_buf              = header_buf_r;
    next_header_count            = header_count_r;
    next_payload_count           = payload_count_r;
    next_header_last_byte        = header_last_byte_r;
    next_payload_last_byte       = payload_last_byte_r;
    next_cfg_byte_data_valid     = cfg_byte_data_valid_r;
    next_payload_start           = 1'b0;
    next_payload_read_count      = payload_read_count;

    cfg_byte_rd_en               = 1'b0;
    payload_byte_valid           = 1'b0;
    payload_byte_is_thresh       = msg_type;
    payload_byte_data            = cfg_byte_data;
    cfg_byte_consume             = 1'b0;
    cfg_byte_request             = 1'b0;
    decoded_payload_bytes        = '0;

    case (parse_state_r)
      PARSE_HEADER: begin
        // Consume the currently staged byte, if any, and append it into the
        // packed header buffer at the current byte offset. Per-layer payload
        // sizing is compile-time, so only msg_type/layer_id remain live
        // metadata from the header itself.
        next_msg_type = header_buf_r[0];
        next_layer_id = header_buf_r[9:8];
        decoded_payload_bytes = calc_payload_bytes(next_msg_type, next_layer_id);
        next_payload_second_last_idx =
            (decoded_payload_bytes > 32'd1) ? (decoded_payload_bytes - 32'd2) : '0;
        next_header_count = '0;
        next_payload_count = '0;
        next_header_last_byte = (HEADER_BYTES == 1);
        next_payload_last_byte = (decoded_payload_bytes <= 32'd1);

        if (cfg_byte_data_valid_r) begin
          cfg_byte_consume = 1'b1;
          next_header_buf[header_count_r*8+:8] = cfg_byte_data;

          if (header_last_byte_r) begin
            next_payload_start = 1'b1;
            next_payload_read_count = calc_payload_read_count(next_msg_type, next_layer_id);

            // Start payload hot by requesting the first payload byte as soon
            // as one is available after the header completes.
            next_parse_state = PARSE_PAYLOAD;

            if (!cfg_byte_empty) begin
              cfg_byte_request = 1'b1;
            end
          end else begin
            next_header_count = header_count_r + 1'b1;
            next_header_last_byte = ((header_count_r + 1'b1) == (HEADER_BYTES - 1));

            if (!cfg_byte_empty) begin
              cfg_byte_request = 1'b1;
            end
          end
        end else if (!cfg_byte_empty) begin
          cfg_byte_request = 1'b1;
        end
      end

      PARSE_PAYLOAD: begin
        // Hold the staged payload byte whenever pad_fsm is emitting synthetic
        // padding so weight parsing does not outrun the downstream consumer.
        if (cfg_byte_data_valid_r && !stall) begin
          cfg_byte_consume   = 1'b1;
          payload_byte_valid = 1'b1;
          next_payload_count = payload_count_r + 1'b1;

          if (payload_last_byte_r) begin
            next_parse_state = PARSE_DONE;
          end
          // payload_count_r is the index before consuming this byte. When it
          // matches payload_second_last_idx_r, the byte accepted right now is
          // the second-to-last byte, so the next accepted byte will be final.
          next_payload_last_byte = (payload_count_r == payload_second_last_idx_r);

          if (!cfg_byte_empty) begin
            cfg_byte_request = 1'b1;
          end

        end else if (!cfg_byte_empty && !stall) begin
          cfg_byte_request = 1'b1;
        end
      end

      PARSE_DONE: begin
        next_payload_count           = '0;
        next_header_count            = '0;
        next_header_buf              = '0;
        next_header_last_byte        = (HEADER_BYTES == 1);
        next_payload_last_byte       = 1'b0;
        next_payload_second_last_idx = '0;

        if (empty) begin
          next_header_buf              = '0;
          next_header_last_byte        = (HEADER_BYTES == 1);
          next_payload_last_byte       = 1'b0;
          next_payload_second_last_idx = '0;
          next_parse_state             = PARSE_HEADER;
        end
      end

      default: begin
        next_header_last_byte        = (HEADER_BYTES == 1);
        next_payload_last_byte       = 1'b0;
        next_payload_second_last_idx = '0;
        next_parse_state             = PARSE_HEADER;
      end
    endcase

    // Update the staged-byte valid bit. If we consumed the current staged byte,
    // the next valid value depends on whether we also requested a replacement.
    // If no byte was staged, a new request will make one valid next cycle.
    if (cfg_byte_consume) begin
      next_cfg_byte_data_valid = cfg_byte_request;
    end else if (!cfg_byte_data_valid_r) begin
      next_cfg_byte_data_valid = cfg_byte_request;
    end

    cfg_byte_rd_en = cfg_byte_request;
  end

endmodule
