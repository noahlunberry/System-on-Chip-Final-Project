module config_manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS = 3,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8},
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int THRESHOLD_DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                    config_valid,
    output logic                    config_ready,
    input  logic [    BUS_WIDTH-1:0] config_data_in,
    input  logic [BUS_WIDTH/8-1:0] config_keep,
    input  logic                    config_last,

    output logic [        MAX_PARALLEL_INPUTS-1:0] weight_ram_wr_data,
    output logic [                     LAYERS-1:0] weight_ram_wr_en,
    output logic [      THRESHOLD_DATA_WIDTH-1:0] threshold_ram_wr_data,
    output logic [                     LAYERS-1:0] threshold_ram_wr_en

);
  logic        msg_type;
  logic [7:0]  layer_id;
  logic [15:0] layer_inputs;
  logic [15:0] num_neurons;
  logic [15:0] bytes_per_neuron;
  logic [31:0] total_bytes;
  logic        header_done;
  logic [LAYERS-1:0] layer_payload_done;
  logic [LAYERS-1:0] layer_config_done;

  assign weight_ram_wr_data = config_data_in[MAX_PARALLEL_INPUTS-1:0];
  assign threshold_ram_wr_data = config_data_in[THRESHOLD_DATA_WIDTH-1:0];

  // Parser Controler Module
  parser_controller #(
      .CONFIG_BUS_WIDTH(BUS_WIDTH),
      .PARALLEL_INPUTS (PARALLEL_INPUTS),
      .FIFO_RD_WIDTH(64)
  ) parser_controller (
      .clk            (clk),
      .en             (config_valid),
      .rst            (rst),
      .data           (config_data_in),
      .done           (|layer_payload_done),
      .ready          (config_ready),
      .header_done    (header_done),
      .msg_type       (msg_type),
      .layer_id       (layer_id),
      .layer_inputs   (layer_inputs),
      .num_neurons    (num_neurons),
      .bytes_per_neuron(bytes_per_neuron),
      .total_bytes    (total_bytes)
  );

  genvar gi;
  generate
    for (gi = 0; gi < LAYERS; gi++) begin : gen_config_controllers
      logic weight_wr_en_local[PARALLEL_NEURONS[gi]];
      logic threshold_wr_en_local[PARALLEL_NEURONS[gi]];
      logic [9:0] addr_out_local;

      config_controller #(
          .MANAGER_BUS_WIDTH(BUS_WIDTH),
          .PARALLEL_NEURONS (PARALLEL_NEURONS[gi]),
          .PARALLEL_INPUTS  (PARALLEL_INPUTS)
      ) u_cfc (
          .clk             (clk),
          .rst             (rst),
          .config_rd_en    (config_valid && header_done && (layer_id == gi)),
          .msg_type        (msg_type),
          .total_bytes     (total_bytes[15:0]),
          .bytes_per_neuron(bytes_per_neuron[7:0]),
          .payload_done    (layer_payload_done[gi]),
          .config_done     (layer_config_done[gi]),
          .weight_wr_en    (weight_wr_en_local),
          .threshold_wr_en (threshold_wr_en_local),
          .addr_out        (addr_out_local)
      );

      always_comb begin
        weight_ram_wr_en[gi] = 1'b0;
        threshold_ram_wr_en[gi] = 1'b0;

        for (int j = 0; j < PARALLEL_NEURONS[gi]; j++) begin
          weight_ram_wr_en[gi] = weight_ram_wr_en[gi] | weight_wr_en_local[j];
          threshold_ram_wr_en[gi] = threshold_ram_wr_en[gi] | threshold_wr_en_local[j];
        end
      end
    end
  endgenerate


endmodule
