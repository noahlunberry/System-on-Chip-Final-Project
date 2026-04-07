// This module compacts data in bytes according to tkeep to support partial byte packing
// It rearranges the data into sequential order of total_bytes in order to feed the variable
// write buffer that configures these partial bytes into a full read
module tkeep_byte_compactor #(
    parameter int INPUT_BUS_WIDTH = 64
) (
    input  logic                             clk,
    input  logic                             rst,

    input  logic                             data_in_valid,
    input  logic [INPUT_BUS_WIDTH-1:0]       data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0]     data_in_keep,

    output logic                             wr_en,
    output logic [INPUT_BUS_WIDTH-1:0]       wr_data,
    output logic [$clog2(INPUT_BUS_WIDTH/8+1)-1:0] total_bytes
);

  localparam int DATA_BYTES = INPUT_BUS_WIDTH / 8;
  localparam int COUNT_W    = $clog2(DATA_BYTES + 1);

  // Next-state versions of the registered outputs.
  logic [INPUT_BUS_WIDTH-1:0] wr_data_next;
  logic [COUNT_W-1:0]         total_bytes_next;
  logic                       wr_en_next;

  // Byte-array views to make packing logic easier to read.
  logic [DATA_BYTES-1:0][7:0] data_in_bytes;
  logic [DATA_BYTES-1:0][7:0] wr_data_bytes_next;

  assign data_in_bytes = data_in_data;
  assign wr_data_next  = wr_data_bytes_next;

  always_comb begin
    int wr_idx;

    // Defaults
    wr_data_bytes_next = '0;
    total_bytes_next   = '0;
    wr_en_next         = 1'b0;
    wr_idx             = 0;

    // Only pack bytes when the input beat is valid.
    if (data_in_valid) begin
      // Walk through each byte lane in order.
      // If the corresponding keep bit is 1, copy that byte into the next
      // consecutive low byte position of wr_data.
      for (int i = 0; i < DATA_BYTES; i++) begin
        if (data_in_keep[i]) begin
          wr_data_bytes_next[wr_idx] = data_in_bytes[i];
          wr_idx++;
        end
      end

      total_bytes_next = COUNT_W'(wr_idx);
      wr_en_next       = (wr_idx != 0);
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_data     <= '0;
      total_bytes <= '0;
      wr_en       <= 1'b0;
    end
    else begin
      wr_data     <= wr_data_next;
      total_bytes <= total_bytes_next;
      wr_en       <= wr_en_next;
    end
  end

endmodule