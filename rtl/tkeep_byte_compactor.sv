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

  logic [INPUT_BUS_WIDTH-1:0] next_wr_data;
  logic [COUNT_W-1:0]         next_total_bytes;
  logic                       next_wr_en;

  always_comb begin
    next_wr_data     = '0;
    next_total_bytes = '0;
    next_wr_en       = 1'b0;

    if (data_in_valid) begin
      // Since tkeep is low-byte contiguous, the valid bytes are already packed.
      next_wr_data = data_in_data;
      next_wr_en   = |data_in_keep;

      // Count how many low bytes are valid.
      // Legal patterns are 000...000, 000...001, 000...011, 000...111, ...
      for (int i = 0; i < DATA_BYTES; i++) begin
        if (data_in_keep[i]) begin
          next_total_bytes = COUNT_W'(i + 1);
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      total_bytes <= '0;
      wr_en       <= 1'b0;
    end
    else begin
      wr_data     <= next_wr_data;
      total_bytes <= next_total_bytes;
      wr_en       <= next_wr_en;
    end
  end

endmodule