module sliding_window #(
    parameter int ELEMENT_WIDTH = 16,
    parameter int NUM_ELEMENTS  = 128
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     wr_en,
    input  logic                     rd_en,
    input  logic [ELEMENT_WIDTH-1:0] wr_data,
    output logic [ELEMENT_WIDTH-1:0] rd_data,
    output logic                     empty,
    output logic                     not_full,
    output logic                     full
);

    localparam int COUNT_W = (NUM_ELEMENTS <= 1) ? 1 : $clog2(NUM_ELEMENTS + 1);

    logic [NUM_ELEMENTS-1:0][ELEMENT_WIDTH-1:0] d_r, d_n;
    logic [COUNT_W-1:0]                         count_r, count_n;
    logic [ELEMENT_WIDTH-1:0]                   rd_data_r, rd_data_n;

    logic rd_fire, wr_fire;

    assign rd_data  = rd_data_r;
    assign empty    = (count_r == 0);
    assign not_full = (count_r < NUM_ELEMENTS);
    assign full     = (count_r == NUM_ELEMENTS);

    assign rd_fire = rd_en && !empty;
    assign wr_fire = wr_en && !full;

    always_comb begin
        d_n       = d_r;
        count_n   = count_r;
        rd_data_n = rd_data_r;

        // pop oldest word
        if (rd_fire) begin
            rd_data_n = d_r[0];

            for (int i = 0; i < NUM_ELEMENTS-1; i++) begin
                d_n[i] = d_r[i+1];
            end
            d_n[NUM_ELEMENTS-1] = '0;

            count_n = count_r - 1'b1;
        end

        // push newest word
        if (wr_fire) begin
            if (rd_fire) begin
                // one word was removed, so append at the new tail
                d_n[count_r-1] = wr_data;
                count_n        = count_r;
            end
            else begin
                d_n[count_r] = wr_data;
                count_n      = count_r + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            d_r       <= '0;
            count_r   <= '0;
            rd_data_r <= '0;
        end
        else begin
            d_r       <= d_n;
            count_r   <= count_n;
            rd_data_r <= rd_data_n;
        end
    end

endmodule