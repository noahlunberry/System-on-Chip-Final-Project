// Optimized variable-write stream builder inspired by the FPGA'24 paper
// "Low-Latency, Line-Rate Variable-Length Field Parsing for 100+ Gb/s Ethernet"
// by Stitt, Piard, and Crary.
//
// Key ideas adapted here:
//   1) Do not byte-address a circular buffer when the real problem is alignment.
//   2) Keep a small field-buffer style register bank and append packed bytes at a
//      variable byte offset.
//   3) Realize the variable byte shift as a radix-4 byte-lane shifter, which maps
//      naturally to LUT6-class FPGA mux resources.
//
// Notes:
//   * tkeep_byte_compactor_opt assumes the input keep mask is low-byte contiguous.
//     In that case, the bytes are already compacted and the only remaining work is
//     counting how many bytes are valid.
//   * vw_buffer_opt can emit an output word in the same cycle that the incoming
//     write completes it, which avoids the overflow/corruption corner case present
//     in a "read-based-only-on-old-count" circular-buffer implementation.

module byte_shift_left_radix4 #(
    parameter int BYTES     = 16,
    parameter int MAX_SHIFT = 15,
    parameter int SHAMT_W   = (MAX_SHIFT <= 0) ? 1 : $clog2(MAX_SHIFT + 1)
) (
    input  logic [BYTES*8-1:0] in,
    input  logic [SHAMT_W-1:0] shamt,
    output logic [BYTES*8-1:0] out
);
    function automatic int ceil_log4(input int value);
        int t;
        begin
            if (value <= 1) begin
                ceil_log4 = 0;
            end else begin
                t = value - 1;
                ceil_log4 = 0;
                while (t > 0) begin
                    t = t >> 2;
                    ceil_log4++;
                end
            end
        end
    endfunction

    localparam int STAGES      = ceil_log4(MAX_SHIFT + 1);
    localparam int EXT_SHAMT_W = (STAGES == 0) ? 1 : (2 * STAGES);

    function automatic logic [BYTES*8-1:0] shift_left_impl(
        input logic [BYTES*8-1:0] din,
        input logic [SHAMT_W-1:0] amt
    );
        logic [BYTES*8-1:0] stage;
        logic [BYTES*8-1:0] next_stage;
        logic [EXT_SHAMT_W-1:0] amt_ext;
        int step;
        begin
            stage   = din;
            amt_ext = amt;

            for (int s = 0; s < STAGES; s++) begin
                step       = 1 << (2 * s);
                next_stage = '0;

                for (int i = 0; i < BYTES; i++) begin
                    case (amt_ext[2*s +: 2])
                        2'd0: next_stage[i*8 +: 8] = stage[i*8 +: 8];
                        2'd1: if (i >= step)     next_stage[i*8 +: 8] = stage[(i-step)*8 +: 8];
                        2'd2: if (i >= 2*step)   next_stage[i*8 +: 8] = stage[(i-2*step)*8 +: 8];
                        2'd3: if (i >= 3*step)   next_stage[i*8 +: 8] = stage[(i-3*step)*8 +: 8];
                        default:                 next_stage[i*8 +: 8] = 8'h00;
                    endcase
                end

                stage = next_stage;
            end

            shift_left_impl = stage;
        end
    endfunction

    always_comb begin
        out = shift_left_impl(in, shamt);
    end
endmodule


module vw_buffer #(
    parameter int MAX_WR_BYTES = 8,
    parameter int RD_BYTES     = 8
) (
    input  logic                              clk,
    input  logic                              rst,

    input  logic                              wr_en,
    input  logic [MAX_WR_BYTES*8-1:0]         wr_data,
    input  logic [$clog2(MAX_WR_BYTES+1)-1:0] total_bytes,

    output logic                              rd_en,
    output logic [RD_BYTES*8-1:0]             rd_data
);
    initial begin
        if (MAX_WR_BYTES < 1) begin
            $fatal(1, "vw_buffer_opt parameter error: MAX_WR_BYTES must be positive.");
        end
        if (RD_BYTES < MAX_WR_BYTES) begin
            $fatal(1, "vw_buffer_opt parameter error: RD_BYTES (%0d) must be >= MAX_WR_BYTES (%0d).",
                   RD_BYTES, MAX_WR_BYTES);
        end
    end

    // Enough space to hold the previous partial word plus one maximum write.
    localparam int BUF_BYTES = RD_BYTES + MAX_WR_BYTES;
    localparam int CNT_W     = $clog2(BUF_BYTES + 1);
    localparam int APPEND_W  = (RD_BYTES <= 1) ? 1 : $clog2(RD_BYTES);

    logic [BUF_BYTES*8-1:0] buf_r, next_buf;
    logic [CNT_W-1:0]       count_r, next_count;

    logic [BUF_BYTES*8-1:0] wr_data_ext;
    logic [BUF_BYTES*8-1:0] wr_mask_ext;
    logic [BUF_BYTES*8-1:0] wr_data_shifted;
    logic [BUF_BYTES*8-1:0] wr_mask_shifted;
    logic [BUF_BYTES*8-1:0] buf_after_write;

    logic [APPEND_W-1:0]    append_bytes;
    logic [CNT_W:0]         wr_bytes_wide;
    logic [CNT_W:0]         count_after_write;
    logic                   do_read;

    function automatic logic [BUF_BYTES*8-1:0] low_byte_mask(
        input logic [$clog2(MAX_WR_BYTES+1)-1:0] nbytes
    );
        logic [BUF_BYTES*8-1:0] m;
        begin
            m = '0;
            for (int i = 0; i < MAX_WR_BYTES; i++) begin
                if (i < nbytes) begin
                    m[i*8 +: 8] = 8'hFF;
                end
            end
            low_byte_mask = m;
        end
    endfunction

    function automatic logic [BUF_BYTES*8-1:0] drop_low_rd_bytes(
        input logic [BUF_BYTES*8-1:0] din
    );
        logic [BUF_BYTES*8-1:0] dout;
        begin
            dout = '0;
            for (int i = RD_BYTES; i < BUF_BYTES; i++) begin
                dout[(i-RD_BYTES)*8 +: 8] = din[i*8 +: 8];
            end
            drop_low_rd_bytes = dout;
        end
    endfunction

    byte_shift_left_radix4 #(
        .BYTES    (BUF_BYTES),
        .MAX_SHIFT((RD_BYTES <= 1) ? 0 : (RD_BYTES - 1))
    ) u_shift_data (
        .in   (wr_data_ext),
        .shamt(append_bytes),
        .out  (wr_data_shifted)
    );

    byte_shift_left_radix4 #(
        .BYTES    (BUF_BYTES),
        .MAX_SHIFT((RD_BYTES <= 1) ? 0 : (RD_BYTES - 1))
    ) u_shift_mask (
        .in   (wr_mask_ext),
        .shamt(append_bytes),
        .out  (wr_mask_shifted)
    );

    always_comb begin
        wr_data_ext = '0;
        wr_data_ext[MAX_WR_BYTES*8-1:0] = wr_data;

        wr_mask_ext = low_byte_mask(wr_en ? total_bytes : '0);

        // count_r is always < RD_BYTES after a cycle completes because the design
        // emits an output word as soon as enough bytes are present.
        append_bytes = APPEND_W'(count_r);
        wr_bytes_wide = wr_en ? total_bytes : '0;

        // Append the new packed bytes at byte offset count_r.
        buf_after_write = (buf_r & ~wr_mask_shifted) | (wr_data_shifted & wr_mask_shifted);

        // A current write is allowed to complete an output word immediately.
        count_after_write = count_r + wr_bytes_wide;
        do_read           = (count_after_write >= RD_BYTES);

        rd_en   = do_read;
        rd_data = do_read ? buf_after_write[RD_BYTES*8-1:0] : '0;

        if (do_read) begin
            next_buf   = drop_low_rd_bytes(buf_after_write);
            next_count = CNT_W'(count_after_write - RD_BYTES);
        end else begin
            next_buf   = buf_after_write;
            next_count = count_after_write[CNT_W-1:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            buf_r   <= '0;
            count_r <= '0;
        end else begin
            buf_r   <= next_buf;
            count_r <= next_count;
        end
    end
endmodule
