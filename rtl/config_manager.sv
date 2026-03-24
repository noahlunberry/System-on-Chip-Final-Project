module config_manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS = 3,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int THRESHOLD_DATA_WIDTH = 32,
    parameter int BYTES_TO_PAD = 0,
    localparam int PAD_EN = BYTES_TO_PAD > 0 ? 1 : 0
) (
    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                 config_valid,
    output logic                 config_ready,
    input  logic [BUS_WIDTH-1:0] config_data_in,
    input  logic                 config_keep,
    input  logic                 config_last,

    output logic [ MAX_PARALLEL_INPUTS-1:0] weight_ram_wr_data,
    output logic [              LAYERS-1:0] weight_ram_wr_en,
    output logic [THRESHOLD_DATA_WIDTH-1:0] threshold_ram_wr_data,
    output logic [              LAYERS-1:0] threshold_ram_wr_en

);



  localparam int THRESH_RD_BYTES = (THRESHOLD_DATA_WIDTH) / 8;

  logic empty;
  logic w_empty;
  logic t_empty;

  logic fifo_wr_en_r;
  logic msg_type_r;
  logic [1:0] layer_id_r;
  logic [31:0] total_bytes_r;
  logic [15:0] bytes_per_neuron_r;

  logic [LAYERS-1:0] packer_empty;
  logic all_packers_empty;
  assign all_packers_empty = &packer_empty;

  // The config FSM waits for all underlying FIFOs to process their stream
  assign empty = w_empty && t_empty && all_packers_empty;

  // Parser controller module is responsible for writing valid data to the FIFO and communicating with the AXI stream.
  parser_controller #(
      .CONFIG_BUS_WIDTH(BUS_WIDTH)
  ) parser_controller (
      .clk             (clk),
      .valid           (config_valid),
      .rst             (rst),
      .data            (config_data_in),
      .empty           (empty),
      .ready           (config_ready),
      .wr_en           (fifo_wr_en_r),
      .msg_type        (msg_type_r),
      .layer_id        (layer_id_r),
      .total_bytes     (total_bytes_r),
      .bytes_per_neuron(bytes_per_neuron_r)
  );

  typedef enum logic [1:0] {
    READ,
    DRAIN,
    PAD
  } state_t;
  state_t state_r, next_state;

  logic [31:0] rd_count_r, next_rd_count;
  logic [31:0] count_r, next_count;
  logic [8:0] byte_idx_r, next_byte_idx;
  logic [7:0] pad_count_r, next_pad_count;
  logic buffer_wr_r, next_buffer_wr_en;
  logic fifo_rd_en_r, next_fifo_rd_en;

  logic [7:0] data;
  logic [7:0] w_byte_data;

  always_ff @(posedge clk) begin
    state_r      <= next_state;
    rd_count_r   <= next_rd_count;
    count_r      <= next_count;
    byte_idx_r   <= next_byte_idx;
    pad_count_r  <= next_pad_count;
    buffer_wr_r  <= next_buffer_wr_en;
    fifo_rd_en_r <= next_fifo_rd_en;

    if (rst) begin
      state_r      <= READ;
      rd_count_r   <= '0;
      count_r      <= '0;
      byte_idx_r   <= '0;
      pad_count_r  <= '0;
      buffer_wr_r  <= 0;
      fifo_rd_en_r <= 0;
    end
  end

  logic active_stream_empty;
  assign active_stream_empty = msg_type_r ? t_empty : w_empty;

  always_comb begin
    next_state        = state_r;
    next_rd_count     = rd_count_r;
    next_count        = count_r;
    next_byte_idx     = byte_idx_r;
    next_pad_count    = pad_count_r;
    next_buffer_wr_en = buffer_wr_r;
    next_fifo_rd_en   = fifo_rd_en_r;

    // Use live payload byte dynamically
    data              = w_byte_data;

    case (state_r)
      READ: begin
        // decode message type and layer id to find the correct amount of reads necessary.
        if (msg_type_r == 0) begin
          next_rd_count = (total_bytes_r + bytes_per_neuron_r - 1) / bytes_per_neuron_r;
        end else begin
          next_rd_count = (total_bytes_r) / 4;
        end

        // Continuously read while buffer is not empty
        if (!active_stream_empty) begin
          next_count = count_r + 1'b1;
          next_fifo_rd_en = 1;
          next_buffer_wr_en = 1;

          if (msg_type_r == 0) begin
            if (byte_idx_r == bytes_per_neuron_r - 1) begin
              next_byte_idx = '0;
              if (PAD_EN) next_state = PAD;
            end else begin
              next_byte_idx = byte_idx_r + 1;
            end
          end

          if (count_r == rd_count_r) begin
            next_state = DRAIN;
            next_count = '0;
          end
        end else begin
          next_fifo_rd_en   = 0;
          next_buffer_wr_en = 0;
        end
      end

      // For BYTES_TO_PAD cycles, inject 1's padding sequence (0xFF) to the buffer
      PAD: begin
        data = 8'hFF;
        next_fifo_rd_en = 0;
        next_buffer_wr_en = 1;
        next_pad_count = pad_count_r + 1;
        if (pad_count_r == BYTES_TO_PAD - 1) begin
          next_pad_count = '0;
          next_state = READ;
        end
      end

      DRAIN: begin
        next_fifo_rd_en   = 1;
        next_buffer_wr_en = 0;
        if (active_stream_empty) next_state = READ;
      end
    endcase
  end

  logic w_rd_en;
  logic w_wr_en;
  logic t_rd_en;
  logic t_wr_en;

  assign w_rd_en = fifo_rd_en_r && !msg_type_r && !w_empty;
  assign t_rd_en = fifo_rd_en_r && msg_type_r && !t_empty;
  assign w_wr_en = fifo_wr_en_r && !msg_type_r;
  assign t_wr_en = fifo_wr_en_r && msg_type_r;

  // Assymetric FIFO to convert bus stream into individual bytes
  fifo_vr #(
      .N(BUS_WIDTH),  // write config_data_in
      .M(8),          // read individual bytes
      .P(17)          // DEPTH
  ) fifo_weights_bytes (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (w_rd_en),
      .wr_en           (w_wr_en),
      .wr_data         (config_data_in),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (),
      .empty           (w_empty),
      .rd_data         (w_byte_data)
  );

  // Packer FIFOs: Unpack individual bytes into dynamically parameterized output interfaces
  logic [LAYERS-1:0] packer_rd_en;
  logic [MAX_PARALLEL_INPUTS-1:0] packer_rd_data[LAYERS];

  genvar i;
  generate
    for (i = 0; i < LAYERS; i++) begin : gen_packer
      localparam int LAYER_WIDTH = (i == 0) ? MAX_PARALLEL_INPUTS : PARALLEL_NEURONS[i-1];
      logic [LAYER_WIDTH-1:0] packer_layer_data;

      fifo_vr #(
          .N(8),            // convert byte back
          .M(LAYER_WIDTH),  // to properly aligned bus width per layer
          .P(10)            // DEPTH
      ) fifo_packer (
          .clk             (clk),
          .rst             (rst),
          .rd_en           (packer_rd_en[i]),
          // Write BRAM buffer when buffer is asserted, targeted to the current active layer
          .wr_en           (buffer_wr_r && !msg_type_r && layer_id_r == i),
          .wr_data         (data),
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

  fifo_vr #(
      .N(BUS_WIDTH),  // write 64-bit word
      .M(32),         // read 32-bit threshold word
      .P(12)          // DEPTH
  ) fifo_thresholds (
      .clk             (clk),
      .rst             (rst),
      .rd_en           (t_rd_en),
      .wr_en           (t_wr_en),
      .wr_data         (config_data_in),
      .alm_full_thresh ('0),
      .alm_empty_thresh('0),
      .alm_full        (),
      .alm_empty       (),
      .full            (),
      .empty           (t_empty),
      .rd_data         (threshold_ram_wr_data)  // Direct alignment for thresholds
  );

  // Layer RAM Output Alignment
  always_comb begin
    weight_ram_wr_en    = '0;
    threshold_ram_wr_en = '0;
    packer_rd_en        = '0;
    weight_ram_wr_data  = '0;

    // Thresholds output directly controlled by the main FSM
    if (buffer_wr_r && msg_type_r && (layer_id_r < LAYERS)) begin
      threshold_ram_wr_en[layer_id_r] = 1'b1;
    end

    // Weights automatically drain out of the layer specific packers when complete sequences arise
    for (int j = 0; j < LAYERS; j++) begin
      if (!packer_empty[j] && (layer_id_r == j)) begin
        packer_rd_en[j] = 1'b1;
        weight_ram_wr_en[j] = 1'b1;
        weight_ram_wr_data = packer_rd_data[j];
      end
    end
  end

endmodule
