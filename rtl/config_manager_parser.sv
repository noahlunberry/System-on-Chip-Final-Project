module config_manager_parser (
    input logic clk,
    input logic rst,

    input logic       cfg_byte_empty,
    input logic [7:0] cfg_byte_data,
    input logic       w_wr_ready,
    input logic       t_wr_ready,
    input logic       empty,

    output logic        cfg_byte_rd_en,
    output logic        payload_byte_valid,
    output logic        payload_byte_is_thresh,
    output logic [ 7:0] payload_byte_data,
    output logic        msg_type,
    output logic [ 1:0] layer_id,
    output logic [15:0] bytes_per_neuron,
    output logic        payload_start,
    output logic [31:0] payload_read_count
);

  localparam int HEADER_BYTES = 16;
  localparam int THRESH_WORD_BYTES = 4;

  typedef enum logic [1:0] {
    PARSE_HEADER,
    PARSE_PAYLOAD,
    PARSE_DONE
  } parse_state_t;

  parse_state_t parse_state_r, next_parse_state;

  // Registered message metadata for the payload currently being emitted.
  logic       next_msg_type;
  logic [1:0] next_layer_id;
  logic [31:0] total_bytes_r, next_total_bytes;
  // Cache "payload_count_r value seen on the second-to-last payload byte" so
  // payload-end detection is a simple registered compare in PARSE_PAYLOAD.
  logic [31:0] payload_second_last_idx_r, next_payload_second_last_idx;
  logic [15:0] next_bytes_per_neuron;

  // Header assembly and progress tracking.
  logic [HEADER_BYTES*8-1:0] header_buf_r, next_header_buf;
  logic [$clog2(HEADER_BYTES+1)-1:0] header_count_r, next_header_count;

  // Payload progress tracking.
  logic [31:0] payload_count_r, next_payload_count;
  logic header_last_byte_r, next_header_last_byte;
  logic payload_last_byte_r, next_payload_last_byte;

  // fifo_config_bytes uses registered read data, so cfg_byte_rd_en requests the
  // next byte and cfg_byte_data_valid_r says the staged cfg_byte_data byte is
  // available to consume in the current cycle.
  logic cfg_byte_data_valid_r, next_cfg_byte_data_valid;

  // Main parser state and message metadata registers.
  always_ff @(posedge clk) begin
    if (rst) begin
      parse_state_r             <= PARSE_HEADER;
      msg_type                  <= 1'b0;
      layer_id                  <= '0;
      total_bytes_r             <= '0;
      payload_second_last_idx_r <= '0;
      bytes_per_neuron          <= '0;
      header_buf_r              <= '0;
      header_count_r            <= '0;
      payload_count_r           <= '0;
      header_last_byte_r        <= (HEADER_BYTES == 1);
      payload_last_byte_r       <= 1'b0;
      cfg_byte_data_valid_r     <= 1'b0;
    end else begin
      parse_state_r             <= next_parse_state;
      msg_type                  <= next_msg_type;
      layer_id                  <= next_layer_id;
      total_bytes_r             <= next_total_bytes;
      payload_second_last_idx_r <= next_payload_second_last_idx;
      bytes_per_neuron          <= next_bytes_per_neuron;
      header_buf_r              <= next_header_buf;
      header_count_r            <= next_header_count;
      payload_count_r           <= next_payload_count;
      header_last_byte_r        <= next_header_last_byte;
      payload_last_byte_r       <= next_payload_last_byte;
      cfg_byte_data_valid_r     <= next_cfg_byte_data_valid;
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
    logic payload_dst_ready;
    logic cfg_byte_consume;
    logic cfg_byte_request;

    next_parse_state             = parse_state_r;
    next_msg_type                = msg_type;
    next_layer_id                = layer_id;
    next_total_bytes             = total_bytes_r;
    next_payload_second_last_idx = payload_second_last_idx_r;
    next_bytes_per_neuron        = bytes_per_neuron;
    next_header_buf              = header_buf_r;
    next_header_count            = header_count_r;
    next_payload_count           = payload_count_r;
    next_header_last_byte        = header_last_byte_r;
    next_payload_last_byte       = payload_last_byte_r;
    next_cfg_byte_data_valid     = cfg_byte_data_valid_r;

    cfg_byte_rd_en               = 1'b0;
    payload_byte_valid           = 1'b0;
    payload_byte_is_thresh       = msg_type;
    payload_byte_data            = cfg_byte_data;
    payload_dst_ready            = msg_type ? t_wr_ready : w_wr_ready;
    cfg_byte_consume             = 1'b0;
    cfg_byte_request             = 1'b0;

    case (parse_state_r)
      PARSE_HEADER: begin
        // Consume the currently staged byte, if any, and append it into the
        // packed header buffer at the current byte offset.
        if (cfg_byte_data_valid_r) begin
          cfg_byte_consume = 1'b1;
          next_header_buf[header_count_r*8+:8] = cfg_byte_data;

          if (header_last_byte_r) begin
            // The final header byte has just been written into next_header_buf,
            // so decode the complete header from that next-state image.
            next_msg_type = next_header_buf[0];
            next_layer_id = next_header_buf[9:8];
            next_total_bytes = next_header_buf[95:64];
            next_payload_second_last_idx =
                (next_header_buf[95:64] > 32'd1) ? (next_header_buf[95:64] - 32'd2) : '0;
            next_bytes_per_neuron = next_header_buf[63:48];
            next_header_count = '0;
            next_payload_count = '0;
            next_header_last_byte = (HEADER_BYTES == 1);
            next_payload_last_byte = (next_header_buf[95:64] <= 32'd1);

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
        if (cfg_byte_data_valid_r) begin
          if (payload_dst_ready) begin
            cfg_byte_consume   = 1'b1;
            payload_byte_valid = 1'b1;
            next_payload_count = payload_count_r + 1'b1;

            if (payload_last_byte_r) begin
              next_parse_state = PARSE_DONE;
            end else begin
              // payload_count_r is the index before consuming this byte. When it
              // matches payload_second_last_idx_r, the byte accepted right now is
              // the second-to-last byte, so the next accepted byte will be final.
              next_payload_last_byte = (payload_count_r == payload_second_last_idx_r);

              if (!cfg_byte_empty) begin
                cfg_byte_request = 1'b1;
              end
            end
          end
        end else if (!cfg_byte_empty && payload_dst_ready) begin
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

  // payload_start is a one-cycle pulse on the header -> payload transition.
  // payload_read_count is the pad_fsm-visible payload length; threshold payloads
  // are counted in words while weight payloads are counted in bytes.
  assign payload_start = (parse_state_r != PARSE_PAYLOAD) && (next_parse_state == PARSE_PAYLOAD);
  assign payload_read_count = next_msg_type ? (next_total_bytes / THRESH_WORD_BYTES) : next_total_bytes;

endmodule
