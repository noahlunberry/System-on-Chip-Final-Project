module config_manager_parser (
    input logic clk,
    input logic rst,

    input logic       cfg_byte_empty,
    input logic [7:0] cfg_byte_data,
    input logic       w_wr_ready,
    input logic       t_wr_ready,
    input logic       empty,

    output logic       cfg_byte_rd_en,
    output logic       payload_byte_valid,
    output logic       payload_byte_is_thresh,
    output logic [7:0] payload_byte_data,
    output logic       msg_type,
    output logic [1:0] layer_id,
    output logic [15:0] bytes_per_neuron,
    output logic       payload_start,
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

  logic         next_msg_type;
  logic [1:0]   next_layer_id;
  logic [31:0]  total_bytes_r, next_total_bytes;
  logic [15:0]  next_bytes_per_neuron;
  logic [HEADER_BYTES*8-1:0] header_buf_r, next_header_buf;
  logic [$clog2(HEADER_BYTES+1)-1:0] header_count_r, next_header_count;
  logic [31:0]  payload_count_r, next_payload_count;
  logic         header_last_byte_r, next_header_last_byte;
  logic         payload_last_byte_r, next_payload_last_byte;
  logic         cfg_byte_data_valid_r, next_cfg_byte_data_valid;

  always_ff @(posedge clk) begin
    if (rst) begin
      parse_state_r          <= PARSE_HEADER;
      msg_type               <= 1'b0;
      layer_id               <= '0;
      total_bytes_r          <= '0;
      bytes_per_neuron       <= '0;
      header_buf_r           <= '0;
      header_count_r         <= '0;
      payload_count_r        <= '0;
      header_last_byte_r     <= (HEADER_BYTES == 1);
      payload_last_byte_r    <= 1'b0;
      cfg_byte_data_valid_r  <= 1'b0;
    end else begin
      parse_state_r          <= next_parse_state;
      msg_type               <= next_msg_type;
      layer_id               <= next_layer_id;
      total_bytes_r          <= next_total_bytes;
      bytes_per_neuron       <= next_bytes_per_neuron;
      header_buf_r           <= next_header_buf;
      header_count_r         <= next_header_count;
      payload_count_r        <= next_payload_count;
      header_last_byte_r     <= next_header_last_byte;
      payload_last_byte_r    <= next_payload_last_byte;
      cfg_byte_data_valid_r  <= next_cfg_byte_data_valid;
    end
  end

  always_comb begin
    logic payload_dst_ready;
    logic next_payload_dst_ready;
    logic cfg_byte_consume;
    logic cfg_byte_request;
    logic header_msg_type;
    logic [1:0] header_layer_id;
    logic [31:0] header_total_bytes;
    logic [15:0] header_bytes_per_neuron;

    next_parse_state        = parse_state_r;
    next_msg_type           = msg_type;
    next_layer_id           = layer_id;
    next_total_bytes        = total_bytes_r;
    next_bytes_per_neuron   = bytes_per_neuron;
    next_header_buf         = header_buf_r;
    next_header_count       = header_count_r;
    next_payload_count      = payload_count_r;
    next_header_last_byte   = header_last_byte_r;
    next_payload_last_byte  = payload_last_byte_r;
    next_cfg_byte_data_valid = cfg_byte_data_valid_r;

    cfg_byte_rd_en          = 1'b0;
    payload_byte_valid      = 1'b0;
    payload_byte_is_thresh  = msg_type;
    payload_byte_data       = cfg_byte_data;
    payload_dst_ready       = msg_type ? t_wr_ready : w_wr_ready;
    next_payload_dst_ready  = next_msg_type ? t_wr_ready : w_wr_ready;
    cfg_byte_consume        = 1'b0;
    cfg_byte_request        = 1'b0;
    header_msg_type         = msg_type;
    header_layer_id         = layer_id;
    header_total_bytes      = total_bytes_r;
    header_bytes_per_neuron = bytes_per_neuron;

    case (parse_state_r)
      PARSE_HEADER: begin
        if (cfg_byte_data_valid_r) begin
          cfg_byte_consume = 1'b1;
          next_header_buf[header_count_r*8 +: 8] = cfg_byte_data;

          if (header_last_byte_r) begin
            header_msg_type         = next_header_buf[0];
            header_layer_id         = next_header_buf[9:8];
            header_total_bytes      = next_header_buf[95:64];
            header_bytes_per_neuron = next_header_buf[63:48];

            next_msg_type           = header_msg_type;
            next_layer_id           = header_layer_id;
            next_total_bytes        = header_total_bytes;
            next_bytes_per_neuron   = header_bytes_per_neuron;
            next_header_count       = '0;
            next_payload_count      = '0;
            next_header_last_byte   = (HEADER_BYTES == 1);
            next_payload_last_byte  = (header_total_bytes <= 32'd1);

            if (header_total_bytes == 32'd0) begin
              next_parse_state = PARSE_DONE;
            end else begin
              next_parse_state = PARSE_PAYLOAD;
              next_payload_dst_ready = header_msg_type ? t_wr_ready : w_wr_ready;

              if (!cfg_byte_empty && next_payload_dst_ready) begin
                cfg_byte_request = 1'b1;
              end
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
            cfg_byte_consume       = 1'b1;
            payload_byte_valid     = 1'b1;
            payload_byte_is_thresh = msg_type;
            payload_byte_data      = cfg_byte_data;
            next_payload_count     = payload_count_r + 1'b1;

            if (payload_last_byte_r) begin
              next_payload_count     = '0;
              next_header_count      = '0;
              next_header_buf        = '0;
              next_header_last_byte  = (HEADER_BYTES == 1);
              next_payload_last_byte = 1'b0;
              next_parse_state       = PARSE_DONE;
            end else begin
              next_payload_last_byte = ((next_payload_count + 32'd1) >= total_bytes_r);

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
        next_payload_count = '0;
        next_header_count  = '0;

        if (empty) begin
          next_header_buf        = '0;
          next_header_last_byte  = (HEADER_BYTES == 1);
          next_payload_last_byte = 1'b0;
          next_parse_state       = PARSE_HEADER;
        end
      end

      default: begin
        next_header_last_byte  = (HEADER_BYTES == 1);
        next_payload_last_byte = 1'b0;
        next_parse_state       = PARSE_HEADER;
      end
    endcase

    if (cfg_byte_consume) begin
      next_cfg_byte_data_valid = cfg_byte_request;
    end else if (!cfg_byte_data_valid_r) begin
      next_cfg_byte_data_valid = cfg_byte_request;
    end

    cfg_byte_rd_en = cfg_byte_request;
  end

  assign payload_start = (parse_state_r != PARSE_PAYLOAD) && (next_parse_state == PARSE_PAYLOAD);
  assign payload_read_count = next_msg_type ? (next_total_bytes / THRESH_WORD_BYTES) : next_total_bytes;

endmodule
