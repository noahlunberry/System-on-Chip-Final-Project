module config_manager #(
    parameter int BUS_WIDTH                    = 64,
    parameter int LAYERS                       = 3,
    parameter int PARALLEL_INPUTS              = 8,
    parameter int PARALLEL_NEURONS    [LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS          = 8,
    parameter int THRESHOLD_DATA_WIDTH         = 32
) (
    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                    config_valid,
    output logic                    config_ready,
    input  logic [    BUS_WIDTH-1:0] config_data_in,
    input  logic [BUS_WIDTH/8-1:0]   config_keep,
    input  logic                    config_last,

    // RAM Write Interfaces
    output logic [ MAX_PARALLEL_INPUTS-1:0] weight_ram_wr_data,
    output logic [              LAYERS-1:0] weight_ram_wr_en,
    output logic [THRESHOLD_DATA_WIDTH-1:0] threshold_ram_wr_data,
    output logic [              LAYERS-1:0] threshold_ram_wr_en
);

  // =========================================================================
  // Local Parameters
  // =========================================================================
  localparam int BUS_BYTES              = BUS_WIDTH / 8;
  localparam int THRESH_WORD_BYTES      = 4;
  localparam int HEADER_BYTES           = 16;
  localparam int CONFIG_BYTE_FIFO_DEPTH_LOG2 = 6;
  localparam int CONFIG_BYTE_FIFO_DEPTH = 1 << CONFIG_BYTE_FIFO_DEPTH_LOG2;
  localparam int CONFIG_BYTE_FIFO_WRITE_CAPACITY = CONFIG_BYTE_FIFO_DEPTH / BUS_BYTES;
  localparam int CONFIG_BYTE_FIFO_RESERVED_WRITE_WORDS = 3;
  // `fifo_vr` measures alm_full in terms of whole write words when N > M. Pick
  // a threshold that leaves enough room for:
  // 1. all full words already buffered inside `vw_buffer`, and
  // 2. one more word still in flight from the registered TKEEP compactor.
  localparam logic [CONFIG_BYTE_FIFO_DEPTH_LOG2-1:0] CONFIG_BYTE_FIFO_ALM_FULL_THRESH =
      CONFIG_BYTE_FIFO_DEPTH_LOG2'(
          CONFIG_BYTE_FIFO_DEPTH - CONFIG_BYTE_FIFO_WRITE_CAPACITY + CONFIG_BYTE_FIFO_RESERVED_WRITE_WORDS
      );

  // FIFO sizing
  localparam int WEIGHT_FIFO_DEPTH = 64;
  localparam int THRESH_FIFO_DEPTH = 64;

  // =========================================================================
  // Signal Declarations
  // =========================================================================
  // Parser & Config
  logic              empty;
  typedef enum logic [1:0] {
    PARSE_HEADER,
    PARSE_PAYLOAD,
    PARSE_DONE
  } parse_state_t;

  parse_state_t       parse_state_r, next_parse_state;
  logic              msg_type_r;
  logic [       1:0] layer_id_r;
  logic [      31:0] total_bytes_r;
  logic [      15:0] bytes_per_neuron_r;
  logic              next_msg_type;
  logic [       1:0] next_layer_id;
  logic [      31:0] next_total_bytes;
  logic [      15:0] next_bytes_per_neuron;
  logic              compact_wr_en;
  logic [BUS_WIDTH-1:0] compact_wr_data;
  logic [$clog2(BUS_BYTES+1)-1:0] compact_total_bytes;
  logic [HEADER_BYTES*8-1:0] header_buf_r, next_header_buf;
  logic [$clog2(HEADER_BYTES+1)-1:0] header_count_r, next_header_count;
  logic [31:0]       payload_count_r, next_payload_count;
  logic              cfg_byte_rd_en;
  logic              cfg_byte_empty;
  logic              cfg_byte_alm_full;
  logic              cfg_vw_rd_en;
  logic              cfg_byte_full;
  logic [BUS_WIDTH-1:0] cfg_vw_rd_data;
  logic [7:0]        cfg_byte_data;
  logic              cfg_byte_data_valid_r, next_cfg_byte_data_valid;
  logic              payload_byte_valid;
  logic              payload_byte_is_thresh;
  logic [7:0]        payload_byte_data;

  // FIFO Status
  logic              w_empty;
  logic              t_empty;
  logic              w_full;
  logic              t_full;
  logic              w_wr_ready;
  logic              t_wr_ready;
  logic              w_rd_en;
  logic              w_wr_en;
  logic              t_rd_en;
  logic              t_wr_en;

  logic [LAYERS-1:0] packer_empty;
  logic              all_packers_empty;
  logic              active_stream_empty;

  // FSM Control Signals
  typedef enum logic [1:0] {
    READ,
    DRAIN,
    PAD
  } state_t;

  state_t state_r, next_state;

  logic [31:0] rd_count_r;
  logic [31:0] count_r;
  logic [8:0] byte_idx_r, next_byte_idx;
  logic [7:0] pad_count_r, next_pad_count;
  logic last_rd_r;

  logic       buffer_wr_en;
  logic       fifo_rd_en;
  logic       read_fire;
  logic       last_read_fire;
  logic       load_rd_count;
  logic [31:0] rd_count_load_value;

  // Data Routing & Padding
  logic [7:0] data;
  logic [7:0] w_byte_data;
  logic [31:0] threshold_fifo_rd_data;
  logic [7:0] bytes_per_word;
  logic [7:0] pad_remainder;
  logic [7:0] bytes_to_pad;
  logic       pad_en;

  // Register one cycle of weight-byte traffic before writing into the packers.
  // This breaks the long combinational path from fifo_weights_bytes show-ahead
  // data into the downstream packer memories.
  logic       packer_wr_valid_r;
  logic [7:0] packer_wr_data_r;
  logic [1:0] packer_wr_layer_r;

  // =========================================================================
  // Combinational Assignments & Top-Level Logic
  // =========================================================================
  assign all_packers_empty   = &packer_empty;
  assign active_stream_empty = msg_type_r ? t_empty : w_empty;

  // The config FSM waits for all downstream FIFOs and packers to finish the
  // current message before starting the next one.
  assign empty = w_empty && t_empty && all_packers_empty && !packer_wr_valid_r
                 && (state_r == READ);
  assign config_ready        = !cfg_byte_alm_full;

  assign w_rd_en             = fifo_rd_en && !msg_type_r && !w_empty;
  assign t_rd_en             = fifo_rd_en && msg_type_r && !t_empty;
  assign w_wr_en             = payload_byte_valid && !payload_byte_is_thresh;
  assign t_wr_en             = payload_byte_valid && payload_byte_is_thresh;
  assign w_wr_ready          = !w_full;
  assign t_wr_ready          = !t_full;
  assign load_rd_count       = (parse_state_r != PARSE_PAYLOAD) && (next_parse_state == PARSE_PAYLOAD);
  assign rd_count_load_value = next_msg_type ? (next_total_bytes / THRESH_WORD_BYTES) : next_total_bytes;
  assign last_read_fire = read_fire && (rd_count_r != 32'd0)
                          && ((count_r + 32'd1) >= rd_count_r);

  // =========================================================================
  // Padding Calculation (Dynamic per-layer)
  // =========================================================================
  always_comb begin
    bytes_per_word = MAX_PARALLEL_INPUTS / 8;  // layer 0 default
    for (int k = 0; k < LAYERS; k++) begin
      if (layer_id_r == 2'(k)) begin
        if (k == 0) bytes_per_word = MAX_PARALLEL_INPUTS / 8;
        else bytes_per_word = PARALLEL_NEURONS[k-1] / 8;
      end
    end
  end

  assign pad_remainder = bytes_per_neuron_r[7:0] & (bytes_per_word - 8'd1);
  assign bytes_to_pad  = (pad_remainder == 0) ? 8'd0 : (bytes_per_word - pad_remainder);
  assign pad_en        = (bytes_to_pad != 0);

  // Compact every accepted config beat first so fragmented headers and payload
  // bytes are converted into one contiguous byte stream.
  tkeep_byte_compactor #(
      .INPUT_BUS_WIDTH(BUS_WIDTH)
  ) config_tkeep_byte_compactor_i (
      .clk          (clk),
      .rst          (rst),
      .data_in_valid(config_valid && config_ready),
      .data_in_data (config_data_in),
      .data_in_keep (config_keep),
      .wr_en        (compact_wr_en),
      .wr_data      (compact_wr_data),
      .total_bytes  (compact_total_bytes)
  );

  initial begin
    if ((CONFIG_BYTE_FIFO_DEPTH % BUS_BYTES) != 0) begin
      $fatal(1,
             "config_manager requires CONFIG_BYTE_FIFO_DEPTH (%0d) to be divisible by BUS_BYTES (%0d).",
             CONFIG_BYTE_FIFO_DEPTH, BUS_BYTES);
    end

    if (CONFIG_BYTE_FIFO_WRITE_CAPACITY <= CONFIG_BYTE_FIFO_RESERVED_WRITE_WORDS) begin
      $fatal(1,
             "config_manager requires config byte FIFO write capacity (%0d words) to exceed reserved inflight words (%0d).",
             CONFIG_BYTE_FIFO_WRITE_CAPACITY, CONFIG_BYTE_FIFO_RESERVED_WRITE_WORDS);
    end
  end

  // First repack the compacted stream into full BUS_BYTES chunks. This keeps
  // the variable-size AXI/TKEEP handling localized to the vw_buffer.
  vw_buffer #(
      .MAX_WR_BYTES(BUS_BYTES),
      .RD_BYTES    (BUS_BYTES)
  ) config_vw_buffer_i (
      .clk       (clk),
      .rst       (rst),
      .wr_en     (compact_wr_en),
      .wr_data   (compact_wr_data),
      .total_bytes(compact_total_bytes),
      .rd_en     (cfg_vw_rd_en),
      .rd_data   (cfg_vw_rd_data)
  );

  // Then serialize those full words into bytes for the header/payload parser.
  // Use the non-FWFT mode here so the parser sees a registered byte output
  // instead of the FIFO's internal show-ahead decode cone.
  fifo_vr #(
      .N(BUS_WIDTH),
      .M(8),
      .P(CONFIG_BYTE_FIFO_DEPTH_LOG2),
      .FWFT(1'b0)
  ) fifo_config_bytes (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (cfg_byte_rd_en),
      .wr_en           (cfg_vw_rd_en && !cfg_byte_full),
      .wr_data         (cfg_vw_rd_data),
      .alm_full_thresh (CONFIG_BYTE_FIFO_ALM_FULL_THRESH),
      .alm_empty_thresh('0),
      .alm_full        (cfg_byte_alm_full),
      .alm_empty       (),
      .full            (cfg_byte_full),
      .empty           (cfg_byte_empty),
      .rd_data         (cfg_byte_data)
  );

  // Parse the staged byte stream one byte at a time. This keeps header
  // handling simple while still allowing randomized TKEEP to split headers
  // across arbitrary beat boundaries.
  always_ff @(posedge clk) begin
    if (rst) begin
      parse_state_r      <= PARSE_HEADER;
      msg_type_r         <= 1'b0;
      layer_id_r         <= '0;
      total_bytes_r      <= '0;
      bytes_per_neuron_r <= '0;
      header_buf_r       <= '0;
      header_count_r     <= '0;
      payload_count_r    <= '0;
      cfg_byte_data_valid_r <= 1'b0;
    end else begin
      parse_state_r      <= next_parse_state;
      msg_type_r         <= next_msg_type;
      layer_id_r         <= next_layer_id;
      total_bytes_r      <= next_total_bytes;
      bytes_per_neuron_r <= next_bytes_per_neuron;
      header_buf_r       <= next_header_buf;
      header_count_r     <= next_header_count;
      payload_count_r    <= next_payload_count;
      cfg_byte_data_valid_r <= next_cfg_byte_data_valid;
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

    next_parse_state  = parse_state_r;
    next_msg_type     = msg_type_r;
    next_layer_id     = layer_id_r;
    next_total_bytes  = total_bytes_r;
    next_bytes_per_neuron = bytes_per_neuron_r;
    next_header_buf   = header_buf_r;
    next_header_count = header_count_r;
    next_payload_count = payload_count_r;
    next_cfg_byte_data_valid = cfg_byte_data_valid_r;

    cfg_byte_rd_en         = 1'b0;
    payload_byte_valid     = 1'b0;
    payload_byte_is_thresh = msg_type_r;
    payload_byte_data      = cfg_byte_data;
    payload_dst_ready      = msg_type_r ? t_wr_ready : w_wr_ready;
    next_payload_dst_ready = next_msg_type ? t_wr_ready : w_wr_ready;
    cfg_byte_consume       = 1'b0;
    cfg_byte_request       = 1'b0;
    header_msg_type        = msg_type_r;
    header_layer_id        = layer_id_r;
    header_total_bytes     = total_bytes_r;
    header_bytes_per_neuron = bytes_per_neuron_r;

    case (parse_state_r)
      PARSE_HEADER: begin
        if (cfg_byte_data_valid_r) begin
          cfg_byte_consume = 1'b1;
          next_header_buf[header_count_r*8 +: 8] = cfg_byte_data;

          if (header_count_r == HEADER_BYTES - 1) begin
            header_msg_type         = next_header_buf[0];
            header_layer_id         = next_header_buf[9:8];
            header_total_bytes      = next_header_buf[95:64];
            header_bytes_per_neuron = next_header_buf[63:48];

            next_msg_type         = header_msg_type;
            next_layer_id         = header_layer_id;
            next_total_bytes      = header_total_bytes;
            next_bytes_per_neuron = header_bytes_per_neuron;
            next_header_count = '0;
            next_payload_count = '0;

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
            payload_byte_is_thresh = msg_type_r;
            payload_byte_data      = cfg_byte_data;
            next_payload_count     = payload_count_r + 1'b1;

            if ((payload_count_r + 1'b1) >= total_bytes_r) begin
              next_payload_count = '0;
              next_header_count  = '0;
              next_header_buf    = '0;
              next_parse_state   = PARSE_DONE;
            end else if (!cfg_byte_empty) begin
              cfg_byte_request = 1'b1;
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
          next_header_buf  = '0;
          next_parse_state = PARSE_HEADER;
        end
      end

      default: begin
        next_parse_state = PARSE_HEADER;
      end
    endcase

    if (cfg_byte_consume) begin
      next_cfg_byte_data_valid = cfg_byte_request;
    end else if (!cfg_byte_data_valid_r) begin
      next_cfg_byte_data_valid = cfg_byte_request;
    end

    cfg_byte_rd_en = cfg_byte_request;
  end

  // =========================================================================
  // Fifo Write Control/Padding FSM
  // =========================================================================
  always_ff @(posedge clk) begin
    if (rst) begin
      state_r     <= READ;
      byte_idx_r  <= '0;
      pad_count_r <= '0;
    end else begin
      state_r     <= next_state;
      byte_idx_r  <= next_byte_idx;
      pad_count_r <= next_pad_count;
    end
  end

  // Keep the message read count and terminal-read decision in a small sequential
  // block so the state machine no longer feeds back through the same count cone.
  always_ff @(posedge clk) begin
    if (rst) begin
      rd_count_r <= '0;
      count_r    <= '0;
      last_rd_r  <= 1'b0;
    end else begin
      if (load_rd_count) begin
        rd_count_r <= rd_count_load_value;
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

  always_ff @(posedge clk) begin
    if (rst) begin
      packer_wr_valid_r <= 1'b0;
      packer_wr_data_r  <= '0;
      packer_wr_layer_r <= '0;
    end else begin
      packer_wr_valid_r <= buffer_wr_en && !msg_type_r;

      if (buffer_wr_en && !msg_type_r) begin
        packer_wr_data_r  <= data;
        packer_wr_layer_r <= layer_id_r;
      end
    end
  end

  always_comb begin
    // Default Assignments
    next_state     = state_r;
    next_byte_idx  = byte_idx_r;
    next_pad_count = pad_count_r;

    buffer_wr_en   = 1'b0;
    fifo_rd_en     = 1'b0;
    read_fire      = 1'b0;
    data           = w_byte_data;  // Use live payload byte dynamically

    case (state_r)
      READ: begin
        if (last_rd_r) begin
          next_state = DRAIN;
        end else if (!active_stream_empty) begin
          fifo_rd_en = 1'b1;
          read_fire  = 1'b1;

          if (!msg_type_r) begin
            buffer_wr_en = 1'b1;
            if (byte_idx_r == (bytes_per_neuron_r - 1)) begin
              next_byte_idx = '0;
              if (pad_en) begin
                next_state = PAD;
              end
            end else begin
              next_byte_idx = byte_idx_r + 1'b1;
            end
          end

        end
      end

      PAD: begin
        // Inject 1's padding sequence (0xFF) to the buffer
        data           = 8'hFF;
        fifo_rd_en     = 1'b0;
        buffer_wr_en   = 1'b1;
        next_pad_count = pad_count_r + 1'b1;

        if (pad_count_r == (bytes_to_pad - 1)) begin
          next_pad_count = '0;
          // After padding the last neuron, drain remaining FIFO data
          if (last_rd_r) begin
            next_state = DRAIN;
          end else begin
            next_state = READ;
          end
        end
      end

      DRAIN: begin
        fifo_rd_en   = 1'b1;
        buffer_wr_en = 1'b0;
        if (active_stream_empty) begin
          next_state = READ;
        end
      end

      default: next_state = READ;
    endcase
  end

  // =========================================================================
  // Datapath & FIFOs
  // =========================================================================

  // Weight bytes already arrive one at a time from the parser, so a regular
  // byte-wide FIFO is enough to decouple parsing from the padding/packer path.
  fifo_vr #(
      .N(8),
      .M(8),
      .P($clog2(WEIGHT_FIFO_DEPTH))
  ) fifo_weights_bytes (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (w_rd_en),
      .wr_en           (w_wr_en),
      .wr_data         (payload_byte_data),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (w_full),
      .empty           (w_empty),
      .rd_data         (w_byte_data)
  );

  // Packer FIFOs: Unpack bytes into dynamically parameterized output interfaces
  logic [             LAYERS-1:0] packer_rd_en;
  logic [MAX_PARALLEL_INPUTS-1:0] packer_rd_data[LAYERS];

  genvar i;
  generate
    for (i = 0; i < LAYERS; i++) begin : gen_packer
      localparam int LAYER_WIDTH = (i == 0) ? MAX_PARALLEL_INPUTS : PARALLEL_NEURONS[i-1];
      logic [LAYER_WIDTH-1:0] packer_layer_data;

      fifo_vr #(
          .N(8),                               // Write byte
          .M(LAYER_WIDTH),                     // Read aligned bus width
          .P(3)  // Depth
      ) fifo_packer (
          .clk             (clk),
          .rst             (rst),
          .rd_en           (packer_rd_en[i]),
          .wr_en           (packer_wr_valid_r && (packer_wr_layer_r == i)),
          .wr_data         (packer_wr_data_r),
          .alm_full_thresh ('0),
          .alm_empty_thresh('0),
          .alm_full        (),
          .alm_empty       (),
          .full            (),
          .empty           (packer_empty[i]),
          .rd_data         (packer_layer_data)
      );

      // Pad remainder up to MAX_PARALLEL_INPUTS
      assign packer_rd_data[i] = {{(MAX_PARALLEL_INPUTS - LAYER_WIDTH) {1'b0}}, packer_layer_data};
    end
  endgenerate

  // Threshold bytes also arrive one at a time, so use a fixed-width FIFO that
  // repacks four incoming bytes into one threshold word on the read side.
  fifo_vr #(
      .N(8),
      .M(THRESH_WORD_BYTES * 8),
      .P($clog2(THRESH_FIFO_DEPTH))
  ) fifo_thresholds (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (t_rd_en),
      .wr_en           (t_wr_en),
      .wr_data         (payload_byte_data),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (t_full),
      .empty           (t_empty),
      .rd_data         (threshold_fifo_rd_data)
  );

  assign threshold_ram_wr_data = threshold_fifo_rd_data[THRESHOLD_DATA_WIDTH-1:0];

  // =========================================================================
  // Layer RAM Output Alignment
  // =========================================================================
  always_comb begin
    weight_ram_wr_en    = '0;
    threshold_ram_wr_en = '0;
    packer_rd_en        = '0;
    weight_ram_wr_data  = '0;

    // Thresholds output directly controlled by the main FSM
    if (t_rd_en && msg_type_r && (layer_id_r < LAYERS)) begin
      threshold_ram_wr_en[layer_id_r] = 1'b1;
    end

    // Weights automatically drain out of the specific packers when sequences arise
    for (int j = 0; j < LAYERS; j++) begin
      if (!packer_empty[j] && (layer_id_r == 2'(j))) begin
        packer_rd_en[j]     = 1'b1;
        weight_ram_wr_en[j] = 1'b1;
        weight_ram_wr_data  = packer_rd_data[j];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst && cfg_vw_rd_en) begin
      assert (!cfg_byte_full)
        else $fatal(1,
                    "config_manager overflow: config byte serializer fifo rejected a vw_buffer word.");
    end

    if (!rst && w_wr_en) begin
      assert (w_wr_ready)
        else $fatal(1,
                    "config_manager overflow: weight fifo_vr rejected a payload byte.");
    end

    if (!rst && t_wr_en) begin
      assert (t_wr_ready)
        else $fatal(1,
                    "config_manager overflow: threshold fifo_vr rejected a payload byte.");
    end
  end

endmodule
