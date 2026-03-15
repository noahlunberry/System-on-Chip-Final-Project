module fifo_basic #(
    // Configurable Parameters
    parameter DATA_W = 4,  // Data width
    parameter DEPTH  = 8,  // Depth of FIFO; must be 2^N   

    // Derived Parameters
    parameter PTR_SZ = $clog2(DEPTH)  // Write/Read pointer size
) (
    input clk,  // Clock
    input rst, // Active-low Synchronous Reset

    input               wr_en,    // Write Enable
    input  [DATA_W-1:0] wr_data,  // Write-data
    output              o_full,    // Full signal

    input               rd_en,    // Read Enable
    output [DATA_W-1:0] rd_data,  // Read-data
    output              o_empty    // Empty signal
);

  //---------------------------------------------------------------------------------------------------------------------
  // Internal Signals/Registers
  //---------------------------------------------------------------------------------------------------------------------
  logic [DATA_W-1:0] dt_arr_rg                                                 [DEPTH];  // Data array
  logic [PTR_SZ-1:0] wrptr;  // Write pointer
  logic [PTR_SZ-1:0] rdptr;  // Read pointer
  logic [PTR_SZ-0:0] wrptr_rg;  // Write pointer with wrapover bit
  logic [PTR_SZ-0:0] rdptr_rg;  // Read pointer with wrapover bit
  logic [PTR_SZ-0:0] nxt_wrptr;  // Next Write pointer
  logic [PTR_SZ-0:0] nxt_rdptr;  // Next Read pointer

  logic              wren;  // Write Enable signal conditioned with Full signal
  logic              rden;  // Read Enable signal conditioned with Empty signal
  logic              wr_wflag;  // Write wrapover bit
  logic              rd_wflag;  // Read wrapover bit
  logic              is_wrap;  // Wrapover flag
  logic              full;  // Full signal
  logic              empty;  // Empty signal

  //---------------------------------------------------------------------------------------------------------------------
  // Synchronous logic to write/read from FIFO
  //---------------------------------------------------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      dt_arr_rg <= '{default: '0};
      wrptr_rg  <= 0;
      rdptr_rg  <= 0;
    end else begin
      /* FIFO write logic */
      if (wren) begin
        dt_arr_rg[wrptr] <= wr_data;  // Data written to FIFO
        wrptr_rg         <= nxt_wrptr;
      end
      /* FIFO read logic */
      if (rden) begin
        rdptr_rg <= nxt_rdptr;
      end
    end
  end

  // Wrapover flags
  assign wr_wflag = wrptr_rg[PTR_SZ];
  assign rd_wflag = rdptr_rg[PTR_SZ];
  assign is_wrap = (wr_wflag != rd_wflag);

  // Pointers used to address FIFO
  assign wrptr = wrptr_rg[PTR_SZ-1:0];
  assign rdptr = rdptr_rg[PTR_SZ-1:0];

  // Full and Empty internal
  assign full = (wrptr == rdptr) && is_wrap;
  assign empty = (wrptr == rdptr) && !is_wrap;

  // Write and Read Enables conditioned
  assign wren = wr_en & !full;  // Do not push if FULL
  assign rden = rd_en & !empty;  // Do not pop if EMPTY

  // Next Write & Read pointers
  assign nxt_wrptr = wrptr_rg + 1;
  assign nxt_rdptr = rdptr_rg + 1;

  // Full and Empty to output
  assign o_full = full;
  assign o_empty = empty;

  // Read-data to output
  assign rd_data = dt_arr_rg[rdptr];

endmodule
