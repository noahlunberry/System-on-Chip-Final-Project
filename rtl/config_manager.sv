module config_manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS = 3,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int THRESHOLD_DATA_WIDTH = 32
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
  typedef enum logic [1:0] {
    START,
    HEADER,
    PAYLOAD,
    DONE
  } state_t;

  

  fifo_vr #(
      .N(BUS_WIDTH),            // write config_data_in
      .M(MAX_PARALLEL_INPUTS),  // READ config_data_in
      .P(1024)                  // DEPTH (calculate later)
  ) fifo_weights (
      .clk            (clk),
      .rst            (rst),
      .rd_en          (w_rd_en),
      .wr_en          (w_wr_en),
      .wr_data        (config_data_in),
      .alm_full_thresh(w_alm_full_thresh),
      .alm_full       (w_alm_full),
      .full           (w_full),
      .empty          (w_empty),
      .rd_data        (weight_ram_wr_data)
  );

  fifo_vr #(
      .N(BUS_WIDTH),            // write config_data_in
      .M(MAX_PARALLEL_INPUTS),  // READ config_data_in
      .P(1024)                  // DEPTH (calculate later)
  ) fifo_thresholds (
      .clk            (clk),
      .rst            (rst),
      .rd_en          (t_rd_en),
      .wr_en          (t_wr_en),
      .wr_data        (config_data_in),
      .alm_full_thresh(t_alm_full_thresh),
      .alm_full       (t_alm_full),
      .full           (t_full),
      .empty          (t_empty),
      .rd_data        (threshold_ram_wr_data)
  );

endmodule
