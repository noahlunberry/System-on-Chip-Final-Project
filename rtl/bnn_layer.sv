// This is the top level compute block for the binary neural net.
module bnn_layer #(
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int MAX_INPUTS = 784,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_NEURONS = 256,
    parameter int TOTAL_INPUTS = 256,
    parameter int LAST_LAYER = 0,
    localparam int W_RAM_ADDR_W = $clog2(
        (TOTAL_NEURONS / PARALLEL_NEURONS) * (TOTAL_INPUTS / PARALLEL_INPUTS) + 1
    ),
    localparam int T_RAM_ADDR_W = $clog2((TOTAL_NEURONS / PARALLEL_NEURONS) + 1),
    localparam int THRESHOLD_DATA_WIDTH = $clog2(MAX_INPUTS + 1),
    localparam int ACC_WIDTH = 1 + $clog2(PARALLEL_INPUTS)

) (
    input logic clk,
    input logic rst,

    // Communicate with input side layer
    input  logic [PARALLEL_INPUTS-1:0] data_in,
    input  logic                       valid_in,
    output logic                       ready_in,

    // Config Manager Interface
    input logic                            weight_wr_en,
    input logic                            threshold_wr_en,
    input logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data,
    input logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,

    // Communication with output side layer
    output logic                            valid_out,                   // write enable to the output buffer
    output logic [    PARALLEL_NEURONS-1:0] data_out,
    output logic [THRESHOLD_DATA_WIDTH-1:0] count_out[PARALLEL_NEURONS],

    input logic ready_out  // comes from the output buffers not full signal


);

  initial begin
    if (TOTAL_INPUTS % PARALLEL_INPUTS)
      $fatal(1, "layer requires TOTAL_INPUTS to be a multiple of PARRALEL_INPUTS");
  end


  // Each BRAM has its own write enable and write address.
  logic [PARALLEL_NEURONS-1:0] w_wr_en;
  logic [W_RAM_ADDR_W-1:0]     w_wr_addr[PARALLEL_NEURONS];

  logic [PARALLEL_NEURONS-1:0] t_wr_en;
  logic [T_RAM_ADDR_W-1:0]     t_wr_addr[PARALLEL_NEURONS];

  // The rd address and enable can be combined into one array, since data is read in parallel
  // They each have their own rd data and rd addresses, since data will be read in parallel
  logic                            w_rd_en;
  logic [        W_RAM_ADDR_W-1:0] w_rd_addr;
  logic [     PARALLEL_INPUTS-1:0] w_rd_data       [PARALLEL_NEURONS];

  logic                            t_rd_en;
  logic [        T_RAM_ADDR_W-1:0] t_rd_addr;
  logic [THRESHOLD_DATA_WIDTH-1:0] t_rd_data       [PARALLEL_NEURONS];

  // Input buffer signals
  logic [     PARALLEL_INPUTS-1:0] buffer_rd_data;
  logic [     PARALLEL_INPUTS-1:0] buffer_rd_data_aligned;
  logic                            buffer_empty;
  logic                            buffer_rd_ready;
  logic                            buffer_not_full;

  logic                            config_done;

  // Stage config writes locally so the long config_manager -> RAM write path
  // is cut at this layer boundary. The controller and RAMs then see aligned
  // enable/data one cycle later.
  logic                            cfg_weight_wr_en_r;
  logic [ MAX_PARALLEL_INPUTS-1:0] cfg_weight_wr_data_r;
  logic                            cfg_threshold_wr_en_r;
  logic [THRESHOLD_DATA_WIDTH-1:0] cfg_threshold_wr_data_r;
  logic [PARALLEL_NEURONS-1:0]     w_wr_en_pipe_r;
  logic [W_RAM_ADDR_W-1:0]         w_wr_addr_pipe_r[PARALLEL_NEURONS];
  logic [PARALLEL_NEURONS-1:0]     t_wr_en_pipe_r;
  logic [T_RAM_ADDR_W-1:0]         t_wr_addr_pipe_r[PARALLEL_NEURONS];
  logic [ MAX_PARALLEL_INPUTS-1:0] cfg_weight_wr_data_pipe_r;
  logic [THRESHOLD_DATA_WIDTH-1:0] cfg_threshold_wr_data_pipe_r;

  assign ready_in = config_done && buffer_not_full;


  localparam int REUSE_CYCLES = TOTAL_NEURONS / PARALLEL_NEURONS;
  localparam int REPLAY_WIDTH = TOTAL_INPUTS / PARALLEL_INPUTS;

  replay_buffer #(
      .ELEMENT_WIDTH(PARALLEL_INPUTS),
      .NUM_ELEMENTS (REPLAY_WIDTH),
      .REUSE_CYCLES (REUSE_CYCLES)
  ) u_input_buffer (
      .clk     (clk),
      .rst     (rst),
      .wr_en   (valid_in),
      .rd_en   (w_rd_en),
      .wr_data (data_in),
      .rd_data (buffer_rd_data),
      .empty   (buffer_empty),
      .not_full(buffer_not_full),
      .rd_ready(buffer_rd_ready)
  );

  // The replay buffer returns data one cycle earlier than the now-registered
  // RAM outputs, so stage it once here before it enters the neuron processors.
  always_ff @(posedge clk) begin
    if (rst) begin
      buffer_rd_data_aligned <= '0;
    end else begin
      buffer_rd_data_aligned <= buffer_rd_data;
    end
  end

  // Local pipelining for config writes.
  // This breaks the long path from config_manager/packer logic into the RAM
  // write-data pins. The layer still accepts one config word per cycle.
  always_ff @(posedge clk) begin
    if (rst) begin
      cfg_weight_wr_en_r      <= 1'b0;
      cfg_weight_wr_data_r    <= '0;
      cfg_threshold_wr_en_r   <= 1'b0;
      cfg_threshold_wr_data_r <= '0;
    end else begin
      cfg_weight_wr_en_r    <= weight_wr_en;
      cfg_threshold_wr_en_r <= threshold_wr_en;

      if (weight_wr_en) begin
        cfg_weight_wr_data_r <= weight_wr_data;
      end

      if (threshold_wr_en) begin
        cfg_threshold_wr_data_r <= threshold_wr_data;
      end
    end
  end


  // config controller : communicates with config manager and streams data into the rams
  // send valid in to the neuron processor
  // outputs the enables to write into the BRAMS
  config_controller #(
    .PARALLEL_INPUTS (PARALLEL_INPUTS),
    .PARALLEL_NEURONS(PARALLEL_NEURONS),
    .TOTAL_NEURONS   (TOTAL_NEURONS),
    .TOTAL_INPUTS    (TOTAL_INPUTS),
    .LAST_LAYER      (LAST_LAYER)
  ) u_cfc (
      .clk(clk),
      .rst(rst),

      .weight_wr_en   (cfg_weight_wr_en_r),
      .threshold_wr_en(cfg_threshold_wr_en_r),

      .ram_weight_wr_en   (w_wr_en),
      .ram_threshold_wr_en(t_wr_en),
      .weight_addr_out    (w_wr_addr),
      .threshold_addr_out (t_wr_addr),
      .done               (config_done)
  );

  // Register the config-controller outputs before they drive the per-NP RAMs.
  // This cuts the long controller-to-BRAM address/enable routes at the layer
  // boundary while keeping one config write per cycle after pipeline fill.
  always_ff @(posedge clk) begin
    if (rst) begin
      w_wr_en_pipe_r             <= '0;
      t_wr_en_pipe_r             <= '0;
      cfg_weight_wr_data_pipe_r  <= '0;
      cfg_threshold_wr_data_pipe_r <= '0;

      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        w_wr_addr_pipe_r[i] <= '0;
        t_wr_addr_pipe_r[i] <= '0;
      end
    end else begin
      w_wr_en_pipe_r             <= w_wr_en;
      t_wr_en_pipe_r             <= t_wr_en;
      cfg_weight_wr_data_pipe_r  <= cfg_weight_wr_data_r;
      cfg_threshold_wr_data_pipe_r <= cfg_threshold_wr_data_r;

      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        w_wr_addr_pipe_r[i] <= w_wr_addr[i];
        t_wr_addr_pipe_r[i] <= t_wr_addr[i];
      end
    end
  end

  logic np_valid;
  logic np_last;
  logic valid_data;
  // Only begin producing new data if downstream interface is ready
  assign valid_data = buffer_rd_ready && ready_out;

  neuron_controller #(
      .PARALLEL_INPUTS (PARALLEL_INPUTS),
      .PARALLEL_NEURONS(PARALLEL_NEURONS),
      .TOTAL_INPUTS    (TOTAL_INPUTS),
      .TOTAL_NEURONS   (TOTAL_NEURONS),
      .W_RAM_ADDR_W    (W_RAM_ADDR_W),
      .T_RAM_ADDR_W    (T_RAM_ADDR_W)
  ) u_nc (
      .clk       (clk),
      .rst       (rst),
      .go        (config_done),
      .valid_data(valid_data),

      // from the brams delayed rd_en, signifies when valid data is ready to enter the NPs
      .valid_in  (np_valid),
      .last      (np_last),
      .layer_done(),          // to the buffer

      // fanout read lanes
      .weight_rd_en  (w_rd_en),
      .weight_rd_addr(w_rd_addr),

      .threshold_rd_en  (t_rd_en),
      .threshold_rd_addr(t_rd_addr)
  );


  genvar gi;
  generate
    for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : gen_np_mems

      // Weights RAM (one per NP)
      ram_sdp #(
          .DATA_WIDTH (MAX_PARALLEL_INPUTS),
          .ADDR_WIDTH (W_RAM_ADDR_W),
          .REG_RD_DATA(1'b1),
          .WRITE_FIRST(1'b0),
          .STYLE      ("distributed")
      ) u_w_ram (
          .clk    (clk),
          .rd_en  (1'b1), // was a super huge fanout signal
          .rd_addr(w_rd_addr),
          .rd_data(w_rd_data[gi]),
          .wr_en  (w_wr_en_pipe_r[gi]),
          .wr_addr(w_wr_addr_pipe_r[gi]),
          .wr_data(cfg_weight_wr_data_pipe_r)
      );

      // Threshold RAM (one per NP)
      ram_sdp #(
          .DATA_WIDTH (THRESHOLD_DATA_WIDTH),
          .ADDR_WIDTH (T_RAM_ADDR_W),
          .REG_RD_DATA(1'b1),
          .WRITE_FIRST(1'b0),
          .STYLE      ("distributed")
      ) u_t_ram (
          .clk    (clk),
          .rd_en  (1'b1),
          .rd_addr(t_rd_addr),
          .rd_data(t_rd_data[gi]),
          .wr_en  (t_wr_en_pipe_r[gi]),
          .wr_addr(t_wr_addr_pipe_r[gi]),
          .wr_data(cfg_threshold_wr_data_pipe_r)
      );

    end
  endgenerate

  // neuron processors : instantiates and streams data into the neuron processors

  logic [PARALLEL_NEURONS-1:0] np_y;
  logic [THRESHOLD_DATA_WIDTH-1:0] np_count_out[PARALLEL_NEURONS];
  logic [PARALLEL_NEURONS-1:0] y_valid;

  generate
    for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : gen_nps
      neuron_processor #(
          .P_WIDTH        (PARALLEL_INPUTS),
          .THRESHOLD_WIDTH(THRESHOLD_DATA_WIDTH)
      ) u_np (
          .clk      (clk),
          .rst      (rst),
          .valid_in (np_valid),
          .last     (np_last),
          .x        (buffer_rd_data_aligned),
          .w        (w_rd_data[gi]),
          .threshold(t_rd_data[gi]),
          .y        (np_y[gi]),
          .count_out(np_count_out[gi]),
          .y_valid  (y_valid[gi])
      );
    end

  endgenerate

  // Register the layer outputs so the wide NP result bus does not cross the
  // module boundary combinationally.
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      data_out  <= '0;
      valid_out <= 1'b0;
      count_out <= '{default: '0};
    end else begin
      valid_out <= y_valid[0];

      if (y_valid[0]) begin
        data_out  <= np_y;
        count_out <= np_count_out;
      end
    end
  end
endmodule
