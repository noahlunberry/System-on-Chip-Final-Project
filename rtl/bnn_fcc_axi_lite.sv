// -----------------------------------------------------------------------------
// bnn_fcc_axi_lite
// -----------------------------------------------------------------------------
// AXI4-Lite MMIO wrapper for bnn_fcc.
//
// The wrapper exposes 32-bit registers to the Zynq PS. Software stages the low
// and high halves of a 64-bit stream beat, then writes the corresponding META
// register with PUSH set. Small FIFOs decouple AXI4-Lite writes from the
// bnn_fcc AXI4-Stream-style ready/valid interfaces.
//
// Register map, byte offsets:
//   0x00 CONTROL     [0] accel reset pulse, [1] clear output FIFO,
//                    [2] clear sticky errors, [3] clear cycle counter
//   0x04 STATUS      [0] cfg_full, [1] img_full, [2] out_valid, [3] busy,
//                    [4] cfg_empty, [5] img_empty, [6] cfg_overflow,
//                    [7] img_overflow, [8] out_full,
//                    [31:16] in-flight image packet count
//   0x08 CFG_DATA_LO config_data[31:0]
//   0x0c CFG_DATA_HI config_data[63:32]
//   0x10 CFG_META    [7:0] config_keep, [8] config_last, [16] push_cfg
//   0x14 IMG_DATA_LO data_in_data[31:0]
//   0x18 IMG_DATA_HI data_in_data[63:32]
//   0x1c IMG_META    [7:0] data_in_keep, [8] data_in_last, [16] push_img
//   0x20 OUT_DATA    zero-extended classification result at output FIFO head
//   0x24 OUT_CTRL    [0] pop output FIFO, [1] clear output FIFO
//   0x28 CYCLE_COUNT increments while STATUS.busy is high
// -----------------------------------------------------------------------------

module bnn_fcc_axi_lite #(
    parameter int C_S_AXI_ADDR_WIDTH = 6,

    parameter int INPUT_DATA_WIDTH  = 8,
    parameter int INPUT_BUS_WIDTH   = 64,
    parameter int CONFIG_BUS_WIDTH  = 64,
    parameter int OUTPUT_DATA_WIDTH = 4,
    parameter int OUTPUT_BUS_WIDTH  = 8,

    parameter int TOTAL_LAYERS = 4,
    parameter int TOPOLOGY[TOTAL_LAYERS] = '{
        0: 784,
        1: 256,
        2: 256,
        3: 10,
        default: 0
    },

    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[TOTAL_LAYERS-1] = '{8, 8, 10},

    parameter int CFG_FIFO_DEPTH_LOG2 = 3,
    parameter int IMG_FIFO_DEPTH_LOG2 = 3,
    parameter int OUT_FIFO_DEPTH_LOG2 = 3
) (
    input  logic                             s_axi_aclk,
    input  logic                             s_axi_aresetn,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  logic [2:0]                       s_axi_awprot,
    input  logic                             s_axi_awvalid,
    output logic                             s_axi_awready,

    input  logic [31:0]                      s_axi_wdata,
    input  logic [3:0]                       s_axi_wstrb,
    input  logic                             s_axi_wvalid,
    output logic                             s_axi_wready,

    output logic [1:0]                       s_axi_bresp,
    output logic                             s_axi_bvalid,
    input  logic                             s_axi_bready,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  logic [2:0]                       s_axi_arprot,
    input  logic                             s_axi_arvalid,
    output logic                             s_axi_arready,

    output logic [31:0]                      s_axi_rdata,
    output logic [1:0]                       s_axi_rresp,
    output logic                             s_axi_rvalid,
    input  logic                             s_axi_rready
);

  localparam int REG_ADDR_WIDTH = 6;

  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CONTROL     = 6'h00;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_STATUS      = 6'h04;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CFG_DATA_LO = 6'h08;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CFG_DATA_HI = 6'h0c;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CFG_META    = 6'h10;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_IMG_DATA_LO = 6'h14;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_IMG_DATA_HI = 6'h18;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_IMG_META    = 6'h1c;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_OUT_DATA    = 6'h20;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_OUT_CTRL    = 6'h24;
  localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CYCLE_COUNT = 6'h28;

  localparam int META_KEEP_LSB = 0;
  localparam int META_KEEP_MSB = 7;
  localparam int META_LAST_BIT = 8;
  localparam int META_PUSH_BIT = 16;
  localparam logic [31:0] META_PUSH_MASK = 32'h0000_0001 << META_PUSH_BIT;

  localparam int CONFIG_KEEP_WIDTH = CONFIG_BUS_WIDTH / 8;
  localparam int INPUT_KEEP_WIDTH  = INPUT_BUS_WIDTH / 8;
  localparam int OUTPUT_KEEP_WIDTH = OUTPUT_BUS_WIDTH / 8;

  localparam int CFG_FIFO_WORD_WIDTH = CONFIG_BUS_WIDTH + CONFIG_KEEP_WIDTH + 1;
  localparam int IMG_FIFO_WORD_WIDTH = INPUT_BUS_WIDTH + INPUT_KEEP_WIDTH + 1;
  localparam int OUT_FIFO_WORD_WIDTH = OUTPUT_BUS_WIDTH + OUTPUT_KEEP_WIDTH + 1;

  localparam int CFG_KEEP_LSB  = CONFIG_BUS_WIDTH;
  localparam int CFG_LAST_BIT  = CONFIG_BUS_WIDTH + CONFIG_KEEP_WIDTH;
  localparam int IMG_KEEP_LSB  = INPUT_BUS_WIDTH;
  localparam int IMG_LAST_BIT  = INPUT_BUS_WIDTH + INPUT_KEEP_WIDTH;
  localparam int OUT_KEEP_LSB  = OUTPUT_BUS_WIDTH;
  localparam int OUT_LAST_BIT  = OUTPUT_BUS_WIDTH + OUTPUT_KEEP_WIDTH;

  localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

  initial begin
    if (C_S_AXI_ADDR_WIDTH < REG_ADDR_WIDTH) begin
      $fatal(1, "bnn_fcc_axi_lite requires at least %0d AXI address bits.", REG_ADDR_WIDTH);
    end
    if (CONFIG_BUS_WIDTH != 64) begin
      $fatal(1, "bnn_fcc_axi_lite register map requires CONFIG_BUS_WIDTH == 64.");
    end
    if (INPUT_BUS_WIDTH != 64) begin
      $fatal(1, "bnn_fcc_axi_lite register map requires INPUT_BUS_WIDTH == 64.");
    end
    if (OUTPUT_BUS_WIDTH > 32) begin
      $fatal(1, "bnn_fcc_axi_lite OUT_DATA supports OUTPUT_BUS_WIDTH <= 32.");
    end
  end

  function automatic logic [31:0] apply_wstrb32(
      input logic [31:0] old_data,
      input logic [31:0] new_data,
      input logic [ 3:0] strb
  );
    logic [31:0] result;
    begin
      result = old_data;
      for (int i = 0; i < 4; i++) begin
        if (strb[i]) result[i*8+:8] = new_data[i*8+:8];
      end
      return result;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // AXI4-Lite write channel
  // ---------------------------------------------------------------------------
  logic                              aw_holding;
  logic [C_S_AXI_ADDR_WIDTH-1:0]     awaddr_r;
  logic                              w_holding;
  logic [31:0]                       wdata_r;
  logic [3:0]                        wstrb_r;

  logic                              aw_accept;
  logic                              w_accept;
  logic                              write_fire;
  logic [C_S_AXI_ADDR_WIDTH-1:0]     write_addr_full;
  logic [REG_ADDR_WIDTH-1:0]         write_addr;
  logic [REG_ADDR_WIDTH-1:0]         write_addr_aligned;
  logic [31:0]                       write_data;
  logic [3:0]                        write_strb;

  assign s_axi_awready = !aw_holding && !(s_axi_bvalid && !s_axi_bready);
  assign s_axi_wready  = !w_holding  && !(s_axi_bvalid && !s_axi_bready);
  assign aw_accept     = s_axi_awvalid && s_axi_awready;
  assign w_accept      = s_axi_wvalid && s_axi_wready;

  assign write_addr_full = aw_holding ? awaddr_r : s_axi_awaddr;
  assign write_addr      = write_addr_full[REG_ADDR_WIDTH-1:0];
  assign write_addr_aligned = {write_addr[REG_ADDR_WIDTH-1:2], 2'b00};
  assign write_data      = w_holding ? wdata_r : s_axi_wdata;
  assign write_strb      = w_holding ? wstrb_r : s_axi_wstrb;
  assign write_fire      = (aw_holding || aw_accept) &&
                           (w_holding || w_accept) &&
                           (!s_axi_bvalid || s_axi_bready);

  // ---------------------------------------------------------------------------
  // MMIO staging registers and push decode
  // ---------------------------------------------------------------------------
  logic [31:0] cfg_data_lo_r;
  logic [31:0] cfg_data_hi_r;
  logic [31:0] cfg_meta_r;
  logic [31:0] img_data_lo_r;
  logic [31:0] img_data_hi_r;
  logic [31:0] img_meta_r;

  logic [31:0] cfg_meta_next;
  logic [31:0] img_meta_next;

  logic cfg_push_req;
  logic img_push_req;
  logic cfg_push_blocked;
  logic img_push_blocked;
  logic cfg_fifo_wr_en;
  logic img_fifo_wr_en;
  logic [CFG_FIFO_WORD_WIDTH-1:0] cfg_fifo_wr_data;
  logic [IMG_FIFO_WORD_WIDTH-1:0] img_fifo_wr_data;

  logic cfg_overflow_r;
  logic img_overflow_r;
  logic sw_reset_pulse_r;
  logic out_clear_pulse_r;
  logic out_pop_pulse_r;
  logic clear_errors_pulse_r;
  logic clear_cycles_pulse_r;

  assign cfg_meta_next = apply_wstrb32(cfg_meta_r, write_data, write_strb);
  assign img_meta_next = apply_wstrb32(img_meta_r, write_data, write_strb);

  // FIFO status signals are declared with the FIFO instances below.
  logic cfg_fifo_full;
  logic img_fifo_full;
  logic out_fifo_full;

  assign cfg_push_req = write_fire &&
                        (write_addr_aligned == ADDR_CFG_META) &&
                        cfg_meta_next[META_PUSH_BIT];
  assign img_push_req = write_fire &&
                        (write_addr_aligned == ADDR_IMG_META) &&
                        img_meta_next[META_PUSH_BIT];

  assign cfg_push_blocked = cfg_push_req && cfg_fifo_full;
  assign img_push_blocked = img_push_req && img_fifo_full;

  assign cfg_fifo_wr_en = cfg_push_req && !cfg_fifo_full;
  assign img_fifo_wr_en = img_push_req && !img_fifo_full;

  assign cfg_fifo_wr_data = {
    cfg_meta_next[META_LAST_BIT],
    cfg_meta_next[META_KEEP_MSB:META_KEEP_LSB],
    cfg_data_hi_r,
    cfg_data_lo_r
  };

  assign img_fifo_wr_data = {
    img_meta_next[META_LAST_BIT],
    img_meta_next[META_KEEP_MSB:META_KEEP_LSB],
    img_data_hi_r,
    img_data_lo_r
  };

  logic [1:0] write_resp;
  assign write_resp = (cfg_push_blocked || img_push_blocked) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      aw_holding           <= 1'b0;
      awaddr_r             <= '0;
      w_holding            <= 1'b0;
      wdata_r              <= '0;
      wstrb_r              <= '0;
      s_axi_bvalid         <= 1'b0;
      s_axi_bresp          <= AXI_RESP_OKAY;

      cfg_data_lo_r        <= '0;
      cfg_data_hi_r        <= '0;
      cfg_meta_r           <= '0;
      img_data_lo_r        <= '0;
      img_data_hi_r        <= '0;
      img_meta_r           <= '0;
      cfg_overflow_r       <= 1'b0;
      img_overflow_r       <= 1'b0;
      sw_reset_pulse_r     <= 1'b0;
      out_clear_pulse_r    <= 1'b0;
      out_pop_pulse_r      <= 1'b0;
      clear_errors_pulse_r <= 1'b0;
      clear_cycles_pulse_r <= 1'b0;
    end else begin
      sw_reset_pulse_r     <= 1'b0;
      out_clear_pulse_r    <= 1'b0;
      out_pop_pulse_r      <= 1'b0;
      clear_errors_pulse_r <= 1'b0;
      clear_cycles_pulse_r <= 1'b0;

      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (aw_accept && !write_fire) begin
        aw_holding <= 1'b1;
        awaddr_r   <= s_axi_awaddr;
      end else if (write_fire) begin
        aw_holding <= 1'b0;
      end

      if (w_accept && !write_fire) begin
        w_holding <= 1'b1;
        wdata_r   <= s_axi_wdata;
        wstrb_r   <= s_axi_wstrb;
      end else if (write_fire) begin
        w_holding <= 1'b0;
      end

      if (sw_reset_pulse_r || clear_errors_pulse_r) begin
        cfg_overflow_r <= 1'b0;
        img_overflow_r <= 1'b0;
      end

      if (write_fire) begin
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= write_resp;

        unique case (write_addr_aligned)
          ADDR_CONTROL: begin
            if (write_data[0]) sw_reset_pulse_r <= 1'b1;
            if (write_data[1]) out_clear_pulse_r <= 1'b1;
            if (write_data[2]) clear_errors_pulse_r <= 1'b1;
            if (write_data[3]) clear_cycles_pulse_r <= 1'b1;
          end

          ADDR_CFG_DATA_LO: cfg_data_lo_r <= apply_wstrb32(cfg_data_lo_r, write_data, write_strb);
          ADDR_CFG_DATA_HI: cfg_data_hi_r <= apply_wstrb32(cfg_data_hi_r, write_data, write_strb);
          ADDR_CFG_META: begin
            cfg_meta_r <= cfg_meta_next & ~META_PUSH_MASK;
            if (cfg_push_blocked) cfg_overflow_r <= 1'b1;
          end

          ADDR_IMG_DATA_LO: img_data_lo_r <= apply_wstrb32(img_data_lo_r, write_data, write_strb);
          ADDR_IMG_DATA_HI: img_data_hi_r <= apply_wstrb32(img_data_hi_r, write_data, write_strb);
          ADDR_IMG_META: begin
            img_meta_r <= img_meta_next & ~META_PUSH_MASK;
            if (img_push_blocked) img_overflow_r <= 1'b1;
          end

          ADDR_OUT_CTRL: begin
            if (write_data[0]) out_pop_pulse_r <= 1'b1;
            if (write_data[1]) out_clear_pulse_r <= 1'b1;
          end

          default: begin
          end
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // AXI4-Lite read channel
  // ---------------------------------------------------------------------------
  logic [REG_ADDR_WIDTH-1:0] read_addr;
  logic [REG_ADDR_WIDTH-1:0] read_addr_aligned;
  logic [31:0] read_data_comb;
  logic [1:0] read_resp_comb;

  logic cfg_fifo_empty;
  logic img_fifo_empty;
  logic out_fifo_empty;
  logic cfg_axis_valid_r;
  logic img_axis_valid_r;
  logic busy;
  logic [15:0] inflight_count_r;
  logic [31:0] cycle_count_r;
  logic [31:0] status_word;
  logic [OUT_FIFO_WORD_WIDTH-1:0] out_fifo_rd_data;
  logic [31:0] out_data_word;

  assign s_axi_arready = !s_axi_rvalid || s_axi_rready;
  assign read_addr = s_axi_araddr[REG_ADDR_WIDTH-1:0];
  assign read_addr_aligned = {read_addr[REG_ADDR_WIDTH-1:2], 2'b00};

  always_comb begin
    out_data_word = '0;
    out_data_word[OUTPUT_BUS_WIDTH-1:0] = out_fifo_rd_data[OUTPUT_BUS_WIDTH-1:0];
  end

  assign status_word = {
    inflight_count_r,
    7'd0,
    out_fifo_full,
    img_overflow_r,
    cfg_overflow_r,
    img_fifo_empty && !img_axis_valid_r,
    cfg_fifo_empty && !cfg_axis_valid_r,
    busy,
    !out_fifo_empty,
    img_fifo_full,
    cfg_fifo_full
  };

  always_comb begin
    read_data_comb = '0;
    read_resp_comb = AXI_RESP_OKAY;

    unique case (read_addr_aligned)
      ADDR_CONTROL:     read_data_comb = 32'd0;
      ADDR_STATUS:      read_data_comb = status_word;
      ADDR_CFG_DATA_LO: read_data_comb = cfg_data_lo_r;
      ADDR_CFG_DATA_HI: read_data_comb = cfg_data_hi_r;
      ADDR_CFG_META:    read_data_comb = cfg_meta_r & ~META_PUSH_MASK;
      ADDR_IMG_DATA_LO: read_data_comb = img_data_lo_r;
      ADDR_IMG_DATA_HI: read_data_comb = img_data_hi_r;
      ADDR_IMG_META:    read_data_comb = img_meta_r & ~META_PUSH_MASK;
      ADDR_OUT_DATA:    read_data_comb = out_fifo_empty ? 32'd0 : out_data_word;
      ADDR_OUT_CTRL:    read_data_comb = 32'd0;
      ADDR_CYCLE_COUNT: read_data_comb = cycle_count_r;
      default: begin
        read_resp_comb = AXI_RESP_SLVERR;
      end
    endcase
  end

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_rvalid <= 1'b0;
      s_axi_rresp  <= AXI_RESP_OKAY;
      s_axi_rdata  <= '0;
    end else begin
      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      if (s_axi_arvalid && s_axi_arready) begin
        s_axi_rvalid <= 1'b1;
        s_axi_rresp  <= read_resp_comb;
        s_axi_rdata  <= read_data_comb;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Stream FIFOs and hold-until-ready skid stages
  // ---------------------------------------------------------------------------
  logic acc_rst;
  assign acc_rst = !s_axi_aresetn || sw_reset_pulse_r;

  logic [CFG_FIFO_WORD_WIDTH-1:0] cfg_fifo_rd_data;
  logic cfg_fifo_rd_en;
  logic cfg_axis_accepted;
  logic config_ready;
  logic config_valid;
  logic [CONFIG_BUS_WIDTH-1:0] config_data;
  logic [CONFIG_KEEP_WIDTH-1:0] config_keep;
  logic config_last;

  fifo_vr #(
      .N(CFG_FIFO_WORD_WIDTH),
      .M(CFG_FIFO_WORD_WIDTH),
      .P(CFG_FIFO_DEPTH_LOG2),
      .FWFT(1'b0),
      .ALM_FULL_THRESH(0),
      .ALM_EMPTY_THRESH(0)
  ) cfg_fifo (
      .clk(s_axi_aclk),
      .rst(acc_rst),
      .rd_en(cfg_fifo_rd_en),
      .wr_en(cfg_fifo_wr_en),
      .wr_data(cfg_fifo_wr_data),
      .alm_full(),
      .full(cfg_fifo_full),
      .alm_empty(),
      .empty(cfg_fifo_empty),
      .rd_data(cfg_fifo_rd_data)
  );

  assign cfg_axis_accepted = cfg_axis_valid_r && config_ready;
  assign cfg_fifo_rd_en = !cfg_fifo_empty && (!cfg_axis_valid_r || cfg_axis_accepted);

  always_ff @(posedge s_axi_aclk) begin
    if (acc_rst) begin
      cfg_axis_valid_r <= 1'b0;
    end else begin
      if (cfg_fifo_rd_en) begin
        cfg_axis_valid_r <= 1'b1;
      end else if (cfg_axis_accepted) begin
        cfg_axis_valid_r <= 1'b0;
      end
    end
  end

  assign config_valid = cfg_axis_valid_r;
  assign config_data  = cfg_fifo_rd_data[CONFIG_BUS_WIDTH-1:0];
  assign config_keep  = cfg_fifo_rd_data[CFG_KEEP_LSB+:CONFIG_KEEP_WIDTH];
  assign config_last  = cfg_fifo_rd_data[CFG_LAST_BIT];

  logic [IMG_FIFO_WORD_WIDTH-1:0] img_fifo_rd_data;
  logic img_fifo_rd_en;
  logic img_axis_accepted;
  logic data_in_ready;
  logic data_in_valid;
  logic [INPUT_BUS_WIDTH-1:0] data_in_data;
  logic [INPUT_KEEP_WIDTH-1:0] data_in_keep;
  logic data_in_last;

  fifo_vr #(
      .N(IMG_FIFO_WORD_WIDTH),
      .M(IMG_FIFO_WORD_WIDTH),
      .P(IMG_FIFO_DEPTH_LOG2),
      .FWFT(1'b0),
      .ALM_FULL_THRESH(0),
      .ALM_EMPTY_THRESH(0)
  ) img_fifo (
      .clk(s_axi_aclk),
      .rst(acc_rst),
      .rd_en(img_fifo_rd_en),
      .wr_en(img_fifo_wr_en),
      .wr_data(img_fifo_wr_data),
      .alm_full(),
      .full(img_fifo_full),
      .alm_empty(),
      .empty(img_fifo_empty),
      .rd_data(img_fifo_rd_data)
  );

  assign img_axis_accepted = img_axis_valid_r && data_in_ready;
  assign img_fifo_rd_en = !img_fifo_empty && (!img_axis_valid_r || img_axis_accepted);

  always_ff @(posedge s_axi_aclk) begin
    if (acc_rst) begin
      img_axis_valid_r <= 1'b0;
    end else begin
      if (img_fifo_rd_en) begin
        img_axis_valid_r <= 1'b1;
      end else if (img_axis_accepted) begin
        img_axis_valid_r <= 1'b0;
      end
    end
  end

  assign data_in_valid = img_axis_valid_r;
  assign data_in_data  = img_fifo_rd_data[INPUT_BUS_WIDTH-1:0];
  assign data_in_keep  = img_fifo_rd_data[IMG_KEEP_LSB+:INPUT_KEEP_WIDTH];
  assign data_in_last  = img_fifo_rd_data[IMG_LAST_BIT];

  logic data_out_valid;
  logic data_out_ready;
  logic [OUTPUT_BUS_WIDTH-1:0] data_out_data;
  logic [OUTPUT_KEEP_WIDTH-1:0] data_out_keep;
  logic data_out_last;

  logic out_fifo_rst;
  logic out_fifo_rd_en;
  logic out_fifo_wr_en;
  logic [OUT_FIFO_WORD_WIDTH-1:0] out_fifo_wr_data;

  assign out_fifo_rst = acc_rst || out_clear_pulse_r;
  assign data_out_ready = !out_fifo_full;
  assign out_fifo_wr_en = data_out_valid && data_out_ready;
  assign out_fifo_wr_data = {data_out_last, data_out_keep, data_out_data};
  assign out_fifo_rd_en = out_pop_pulse_r && !out_fifo_empty;

  fifo_vr #(
      .N(OUT_FIFO_WORD_WIDTH),
      .M(OUT_FIFO_WORD_WIDTH),
      .P(OUT_FIFO_DEPTH_LOG2),
      .FWFT(1'b1),
      .ALM_FULL_THRESH(0),
      .ALM_EMPTY_THRESH(0)
  ) out_fifo (
      .clk(s_axi_aclk),
      .rst(out_fifo_rst),
      .rd_en(out_fifo_rd_en),
      .wr_en(out_fifo_wr_en),
      .wr_data(out_fifo_wr_data),
      .alm_full(),
      .full(out_fifo_full),
      .alm_empty(),
      .empty(out_fifo_empty),
      .rd_data(out_fifo_rd_data)
  );

  // ---------------------------------------------------------------------------
  // Accelerator instance
  // ---------------------------------------------------------------------------
  bnn_fcc #(
      .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
      .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
      .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
      .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH),
      .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
      .TOTAL_LAYERS     (TOTAL_LAYERS),
      .TOPOLOGY         (TOPOLOGY),
      .PARALLEL_INPUTS  (PARALLEL_INPUTS),
      .PARALLEL_NEURONS (PARALLEL_NEURONS)
  ) bnn_fcc_i (
      .clk(s_axi_aclk),
      .rst(acc_rst),

      .config_valid(config_valid),
      .config_ready(config_ready),
      .config_data(config_data),
      .config_keep(config_keep),
      .config_last(config_last),

      .data_in_valid(data_in_valid),
      .data_in_ready(data_in_ready),
      .data_in_data(data_in_data),
      .data_in_keep(data_in_keep),
      .data_in_last(data_in_last),

      .data_out_valid(data_out_valid),
      .data_out_ready(data_out_ready),
      .data_out_data(data_out_data),
      .data_out_keep(data_out_keep),
      .data_out_last(data_out_last)
  );

  // ---------------------------------------------------------------------------
  // Busy/counter bookkeeping
  // ---------------------------------------------------------------------------
  logic img_packet_queued;
  logic out_packet_captured;

  assign img_packet_queued   = img_fifo_wr_en && img_fifo_wr_data[IMG_LAST_BIT];
  assign out_packet_captured = out_fifo_wr_en;
  assign busy = !cfg_fifo_empty || cfg_axis_valid_r ||
                !img_fifo_empty || img_axis_valid_r ||
                (inflight_count_r != 16'd0);

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn || sw_reset_pulse_r) begin
      inflight_count_r <= '0;
      cycle_count_r    <= '0;
    end else begin
      unique case ({img_packet_queued, out_packet_captured})
        2'b10: begin
          if (inflight_count_r != 16'hffff) inflight_count_r <= inflight_count_r + 16'd1;
        end
        2'b01: begin
          if (inflight_count_r != 16'd0) inflight_count_r <= inflight_count_r - 16'd1;
        end
        default: begin
        end
      endcase

      if (clear_cycles_pulse_r) begin
        cycle_count_r <= '0;
      end else if (busy) begin
        cycle_count_r <= cycle_count_r + 32'd1;
      end
    end
  end

  // Mark unused AXI protection bits as consumed.
  logic unused_axi_prot;
  assign unused_axi_prot = ^{s_axi_awprot, s_axi_arprot, out_fifo_rd_data[OUT_LAST_BIT]};

endmodule
