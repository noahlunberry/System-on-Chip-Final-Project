// Pawin Ruangkanit
//
// Description:
//   This module is a byte-addressed circular buffer that supports:
//
//     1) Variable-sized writes:
//        - Up to MAX_WR_BYTES can be written in one cycle.
//        - The exact number of valid input bytes is given by total_bytes.
//
//     2) Fixed-sized reads:
//        - Each successful read removes exactly RD_BYTES from the buffer.
//
//     3) Byte packing:
//        - Written bytes are stored sequentially in byte order.
//        - Reads return the oldest RD_BYTES currently stored.
//
//   The buffer depth is specified in "read words":
//        RD_DEPTH = 2^N
//   so total byte storage is:
//        DEPTH_BYTES = RD_DEPTH * RD_BYTES
//
// Important behavior / timing notes:
//   - rd_data is SHOW-AHEAD / COMBINATIONAL.
//     If at least one full RD_BYTES word is available, rd_valid is asserted and
//     rd_data immediately reflects the next readable word.
//
//   - A read is accepted when:
//         rd_en && rd_valid
//
//   - A write is accepted when:
//         wr_en && (total_bytes != 0) && wr_ready
//
//   - wr_ready is computed allowing a same-cycle read to free space first.
//     So a read and write may happen in the same cycle even if the buffer would
//     otherwise appear too full before the read.
//
//   - empty does NOT mean "zero bytes stored".
//     empty means "fewer than RD_BYTES bytes are stored", i.e. there is not
//     enough data to produce one full read word.
//
//   - full means all byte locations are occupied.
//
//   - alm_full is measured in occupied READ ADDRESSES, not raw bytes.
//     Example: if RD_DEPTH = 8 and threshold is 3/4, alm_full asserts when
//     6 read-word slots are occupied.
//
//   - alm_empty is measured in readable READ ADDRESSES remaining.
//     Example: if RD_DEPTH = 8 and threshold is 1/4, alm_empty asserts when
//     2 or fewer full read words remain.
//
// Handshake summary:
//   Write side:
//     wr_en      : producer requests a write this cycle
//     total_bytes: number of valid bytes in wr_data
//     wr_ready   : buffer can accept total_bytes this cycle
//
//     Write occurs only if wr_en && wr_ready && (total_bytes != 0)
//
//   Read side:
//     rd_valid   : a full RD_BYTES output word is available
//     rd_en      : consumer accepts the current output word
//
//     Read occurs only if rd_en && rd_valid
//

module fifo_vw #(
    parameter int MAX_WR_BYTES = 8,
    parameter int RD_BYTES     = 8,
    parameter int N            = 3   // depth in read-address bits => 2^N read words
) (
    input  logic                              clk,
    input  logic                              rst,

    // ------------------------------------------------------------------------
    // Write-side interface
    // ------------------------------------------------------------------------
    // wr_en       : request to write this cycle
    // wr_data     : write payload; only the lowest total_bytes bytes are used
    // total_bytes : number of valid bytes in wr_data
    // wr_ready    : buffer can accept this write this cycle
    input  logic                              wr_en,
    input  logic [MAX_WR_BYTES*8-1:0]         wr_data,
    input  logic [$clog2(MAX_WR_BYTES+1)-1:0] total_bytes,
    output logic                              wr_ready,

    // ------------------------------------------------------------------------
    // Read-side interface
    // ------------------------------------------------------------------------
    // rd_en    : consumer accepts the current output word
    // rd_valid : at least one full RD_BYTES word is available
    // rd_data  : next output word (combinational show-ahead)
    input  logic                              rd_en,
    output logic                              rd_valid,
    output logic [RD_BYTES*8-1:0]             rd_data,

    // ------------------------------------------------------------------------
    // Status
    // ------------------------------------------------------------------------
    output logic                              alm_full,
    output logic                              full,
    output logic                              alm_empty,
    output logic                              empty
);

    // Number of readable output words the buffer can hold.
    localparam int RD_DEPTH    = 1 << N;

    // Total number of bytes stored in the circular buffer.
    localparam int DEPTH_BYTES = RD_DEPTH * RD_BYTES;

    // Width of byte pointers into the circular buffer.
    localparam int PTR_W = (DEPTH_BYTES <= 1) ? 1 : $clog2(DEPTH_BYTES);

    // Width of byte occupancy counter: count_r ranges from 0 to DEPTH_BYTES.
    localparam int CNT_W = $clog2(DEPTH_BYTES + 1);

    // Width for counters expressed in read-word units.
    localparam int WORD_CNT_W = N + 1;

    // ------------------------------------------------------------------------
    // Threshold definitions
    // ------------------------------------------------------------------------
    // Almost-full threshold in units of occupied read-word slots.
    // Default = 3/4 full.
    localparam int ALM_FULL_NUM      = 3;
    localparam int ALM_FULL_DEN      = 4;
    localparam int ALM_FULL_RD_ADDRS =
        ((RD_DEPTH * ALM_FULL_NUM) + ALM_FULL_DEN - 1) / ALM_FULL_DEN;

    // Almost-empty threshold in units of readable full output words.
    // Default = 1/4 full words remaining.
    localparam int ALM_EMPTY_NUM      = 1;
    localparam int ALM_EMPTY_DEN      = 4;
    localparam int ALM_EMPTY_RD_ADDRS =
        ((RD_DEPTH * ALM_EMPTY_NUM) + ALM_EMPTY_DEN - 1) / ALM_EMPTY_DEN;

    // ------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------
    // Byte-addressed memory.
    //
    // mem[0] ... mem[DEPTH_BYTES-1]
    //
    // Writes store bytes sequentially starting at wr_ptr_r.
    // Reads return RD_BYTES sequential bytes starting at rd_ptr_r.
    logic [7:0] mem [0:DEPTH_BYTES-1];

    // Byte write pointer: points to the next byte location to be written.
    logic [PTR_W-1:0] wr_ptr_r;

    // Byte read pointer: points to the oldest unread byte in the buffer.
    logic [PTR_W-1:0] rd_ptr_r;

    // Total number of bytes currently stored in the buffer.
    logic [CNT_W-1:0] count_r;

    // ------------------------------------------------------------------------
    // Derived quantities
    // ------------------------------------------------------------------------
    // Number of bytes requested for the current write.
    logic [CNT_W-1:0] wr_bytes;

    // Free bytes available after considering a same-cycle read.
    logic [CNT_W-1:0] free_bytes_after_read;

    // Number of full RD_BYTES words currently readable.
    logic [WORD_CNT_W-1:0] readable_words;

    // Number of read-word slots occupied by stored data.
    // This is ceil(count_r / RD_BYTES), except it stays 0 when count_r == 0.
    logic [WORD_CNT_W-1:0] occupied_slots;

    // Internal accepted-operation signals.
    logic valid_wr, valid_rd;

    // ------------------------------------------------------------------------
    // Helper function: increment a byte pointer with wrap-around
    // ------------------------------------------------------------------------
    function automatic logic [PTR_W-1:0] bump_ptr (
        input logic [PTR_W-1:0] ptr
    );
        if (ptr == DEPTH_BYTES-1)
            bump_ptr = '0;
        else
            bump_ptr = ptr + 1'b1;
    endfunction

    // ------------------------------------------------------------------------
    // Helper function: add an amount to a byte pointer with circular wrap
    // ------------------------------------------------------------------------
    // This is used for:
    //   - indexing bytes relative to rd_ptr_r and wr_ptr_r
    //   - advancing pointers after reads/writes
    //
    // Since amount is small and bounded, a simple iterative implementation is
    // clear and synthesizable.
    function automatic logic [PTR_W-1:0] ptr_add (
        input logic [PTR_W-1:0] ptr,
        input logic [CNT_W-1:0] amount
    );
        logic [PTR_W-1:0] tmp;
        begin
            tmp = ptr;
            for (int i = 0; i < DEPTH_BYTES; i++) begin
                if (i < amount)
                    tmp = bump_ptr(tmp);
            end
            ptr_add = tmp;
        end
    endfunction

    // Number of requested write bytes, cast to the counter width used internally.
    assign wr_bytes = total_bytes;

    // Number of full RD_BYTES output words currently available.
    assign readable_words = count_r / RD_BYTES;

    // Number of read-word slots occupied.
    //
    // Example:
    //   count_r = 0  -> 0 slots occupied
    //   count_r = 1  -> 1 slot occupied
    //   count_r = 8  -> 1 slot occupied
    //   count_r = 9  -> 2 slots occupied
    assign occupied_slots =
        (count_r == 0) ? '0 : (((count_r - 1'b1) / RD_BYTES) + 1'b1);

    // ------------------------------------------------------------------------
    // Status outputs
    // ------------------------------------------------------------------------
    // full means every byte location is occupied.
    assign full = (count_r == CNT_W'(DEPTH_BYTES));

    // empty means fewer than RD_BYTES bytes are available, so no full output
    // word can be produced.
    assign empty = (readable_words == '0);

    // rd_valid means a full RD_BYTES output word is available now.
    assign rd_valid = !empty;

    // Almost-full based on occupied read-word slots.
    assign alm_full = (occupied_slots >= WORD_CNT_W'(ALM_FULL_RD_ADDRS));

    // Almost-empty based on readable full words remaining.
    assign alm_empty = (readable_words <= WORD_CNT_W'(ALM_EMPTY_RD_ADDRS));

    // ------------------------------------------------------------------------
    // Read / write acceptance
    // ------------------------------------------------------------------------
    // A read is accepted only when the consumer requests it and a full word is
    // currently available.
    assign valid_rd = rd_en && rd_valid;

    // Compute available space after allowing a same-cycle read to happen first.
    //
    // This lets a write use the space freed by a simultaneous accepted read.
    assign free_bytes_after_read =
        CNT_W'(DEPTH_BYTES) - count_r + (valid_rd ? CNT_W'(RD_BYTES) : '0);

    // Buffer is ready if it can accept all requested bytes this cycle.
    assign wr_ready = (wr_bytes <= free_bytes_after_read);

    // A write is accepted only if:
    //   - producer is requesting a write
    //   - at least one byte is being written
    //   - the buffer can accept all requested bytes
    assign valid_wr = wr_en && (wr_bytes != '0) && wr_ready;

    // ------------------------------------------------------------------------
    // Show-ahead read data
    // ------------------------------------------------------------------------
    // rd_data always reflects the next readable RD_BYTES bytes whenever rd_valid
    // is high. This is combinational and does not require rd_en.
    always_comb begin
        rd_data = '0;

        if (rd_valid) begin
            for (int i = 0; i < RD_BYTES; i++) begin
                rd_data[i*8 +: 8] = mem[ptr_add(rd_ptr_r, CNT_W'(i))];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Sequential state updates
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            // On reset, pointers and occupancy clear to empty state.
            wr_ptr_r <= '0;
            rd_ptr_r <= '0;
            count_r  <= '0;
        end else begin
            // --------------------------------------------------------------
            // Accepted write
            // --------------------------------------------------------------
            // Store total_bytes bytes sequentially starting at wr_ptr_r.
            if (valid_wr) begin
                for (int i = 0; i < MAX_WR_BYTES; i++) begin
                    if (i < total_bytes)
                        mem[ptr_add(wr_ptr_r, CNT_W'(i))] <= wr_data[i*8 +: 8];
                end

                // Advance write pointer by the exact number of bytes written.
                wr_ptr_r <= ptr_add(wr_ptr_r, wr_bytes);
            end

            // --------------------------------------------------------------
            // Accepted read
            // --------------------------------------------------------------
            // Advance read pointer by one full read word.
            if (valid_rd)
                rd_ptr_r <= ptr_add(rd_ptr_r, CNT_W'(RD_BYTES));

            // --------------------------------------------------------------
            // Occupancy count update
            // --------------------------------------------------------------
            // count_r tracks total bytes stored.
            //
            // valid_wr only: add number of written bytes
            // valid_rd only: subtract RD_BYTES
            // both        : do both in same cycle
            case ({valid_wr, valid_rd})
                2'b10: count_r <= count_r + wr_bytes;
                2'b01: count_r <= count_r - CNT_W'(RD_BYTES);
                2'b11: count_r <= count_r + wr_bytes - CNT_W'(RD_BYTES);
                default: count_r <= count_r;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    // If an operation is accepted, the corresponding handshake condition must
    // have been valid.
    assert property (@(posedge clk) valid_wr |-> wr_ready);
    assert property (@(posedge clk) valid_rd |-> rd_valid);

endmodule