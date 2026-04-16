// Greg Stitt, Christopher Crary
// StittHub (stitt-hub.com)

module add_tree #(
    parameter int NUM_INPUTS  = 8,
    parameter int INPUT_WIDTH = 16
) (
    input  logic                                      clk,
    input  logic                                      rst,
    input  logic                                      en,
    input  logic [                   INPUT_WIDTH-1:0] inputs[NUM_INPUTS],
    output logic [INPUT_WIDTH+$clog2(NUM_INPUTS)-1:0] sum
);
    generate
        if (INPUT_WIDTH < 1) begin : l_width_validation
            $fatal(1, "ERROR: INPUT_WIDTH must be positive.");
        end

        if (NUM_INPUTS < 1) begin : l_num_inputs_validation
            $fatal(1, "ERROR: Number of inputs must be positive.");
        end else if (NUM_INPUTS == 1) begin : l_base_1_input
            assign sum = inputs[0];
        end else begin : l_recurse

            //--------------------------------------------------------------------
            // Create the left subtree
            //--------------------------------------------------------------------            
            localparam int LEFT_TREE_INPUTS = int'(2 ** ($clog2(NUM_INPUTS) - 1));
            localparam int LEFT_TREE_DEPTH = $clog2(LEFT_TREE_INPUTS);
            logic [INPUT_WIDTH + $clog2(LEFT_TREE_INPUTS)-1:0] left_sum;

            add_tree #(
                .NUM_INPUTS (LEFT_TREE_INPUTS),
                .INPUT_WIDTH(INPUT_WIDTH)
            ) left_tree (
                .clk   (clk),
                .rst   (rst),
                .en    (en),
                .inputs(inputs[0+:LEFT_TREE_INPUTS]),
                .sum   (left_sum)
            );

            //--------------------------------------------------------------------
            // Create the right subtree.            
            //--------------------------------------------------------------------
            localparam int RIGHT_TREE_INPUTS = NUM_INPUTS - LEFT_TREE_INPUTS;
            localparam int RIGHT_TREE_DEPTH = $clog2(RIGHT_TREE_INPUTS);
            logic [INPUT_WIDTH + $clog2(RIGHT_TREE_INPUTS)-1:0] right_sum, right_sum_unaligned;

            add_tree #(
                .NUM_INPUTS (RIGHT_TREE_INPUTS),
                .INPUT_WIDTH(INPUT_WIDTH)
            ) right_tree (
                .clk   (clk),
                .rst   (rst),
                .en    (en),
                .inputs(inputs[LEFT_TREE_INPUTS+:RIGHT_TREE_INPUTS]),
                .sum   (right_sum_unaligned)
            );

            //--------------------------------------------------------------------
            // Delay the right sum so it is aligned with the left sum.            
            //--------------------------------------------------------------------
            localparam int LATENCY_DIFFERENCE = LEFT_TREE_DEPTH - RIGHT_TREE_DEPTH;

            if (LATENCY_DIFFERENCE > 0) begin : l_delay
                logic [$bits(right_sum)-1:0] delay_r[LATENCY_DIFFERENCE];

                always_ff @(posedge clk) begin
                    // if (rst) delay_r <= '{default: '0};
                    // else if (en) begin
                    if (en) begin
                        delay_r[0] <= right_sum_unaligned;
                        for (int i = 1; i < LATENCY_DIFFERENCE; i++) begin
                            delay_r[i] <= delay_r[i-1];
                        end
                    end
                end

                assign right_sum = delay_r[LATENCY_DIFFERENCE-1];
            end else begin : l_no_delay
                assign right_sum = right_sum_unaligned;
            end

            // Add the two trees together.
            always_ff @(posedge clk) begin
                // if (rst) sum <= '0;
                // else if (en) sum <= left_sum + right_sum;
                if (en) sum <= left_sum + right_sum;
            end
        end
    endgenerate
endmodule
