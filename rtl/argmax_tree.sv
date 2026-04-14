// This is a pipelined implementation of the argmax function
// It largely follows the pipelined recursive adder tree from Dr. Stitt's tutorial

module argmax_tree #(
    parameter int NUM_INPUTS  = 10,
    parameter int DATA_WIDTH  = 16,
    // Ensures width is at least 1 bit even for 1 input to avoid synthesis errors (-1:0)
    parameter int INDEX_WIDTH = (NUM_INPUTS > 1) ? $clog2(NUM_INPUTS) : 1
) (
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   en,
    input  logic [ DATA_WIDTH-1:0] inputs [NUM_INPUTS],
    output logic [ DATA_WIDTH-1:0] max_val,
    output logic [INDEX_WIDTH-1:0] max_idx
);

  generate
    if (DATA_WIDTH < 1) begin : l_width_validation
      $fatal(1, "ERROR: DATA_WIDTH must be positive.");
    end

    if (NUM_INPUTS < 1) begin : l_num_inputs_validation
      $fatal(1, "ERROR: Number of inputs must be positive.");
    end else if (NUM_INPUTS == 1) begin : l_base_1_input
      // Base case: Pass the single value and a relative index of 0
      assign max_val = inputs[0];
      assign max_idx = '0;
    end else begin : l_recurse

      //--------------------------------------------------------------------
      // Create the left subtree (Largest power of 2 <= NUM_INPUTS)
      //--------------------------------------------------------------------            
      localparam int LEFT_TREE_INPUTS = int'(2 ** ($clog2(NUM_INPUTS) - 1));
      localparam int LEFT_TREE_DEPTH = $clog2(LEFT_TREE_INPUTS);
      localparam int LEFT_INDEX_WIDTH = (LEFT_TREE_INPUTS > 1) ? $clog2(LEFT_TREE_INPUTS) : 1;

      logic [      DATA_WIDTH-1:0] left_val;
      logic [LEFT_INDEX_WIDTH-1:0] left_idx;

      argmax_tree #(
          .NUM_INPUTS(LEFT_TREE_INPUTS),
          .DATA_WIDTH(DATA_WIDTH)
      ) left_tree (
          .clk    (clk),
          .rst    (rst),
          .en     (en),
          .inputs (inputs[0+:LEFT_TREE_INPUTS]),
          .max_val(left_val),
          .max_idx(left_idx)
      );

      //--------------------------------------------------------------------
      // Create the right subtree
      //--------------------------------------------------------------------
      localparam int RIGHT_TREE_INPUTS = NUM_INPUTS - LEFT_TREE_INPUTS;
      localparam int RIGHT_TREE_DEPTH = (RIGHT_TREE_INPUTS > 1) ? $clog2(RIGHT_TREE_INPUTS) : 0;
      localparam int RIGHT_INDEX_WIDTH = (RIGHT_TREE_INPUTS > 1) ? $clog2(RIGHT_TREE_INPUTS) : 1;

      logic [       DATA_WIDTH-1:0] right_val_unaligned;
      logic [RIGHT_INDEX_WIDTH-1:0] right_idx_unaligned;
      logic [       DATA_WIDTH-1:0] right_val;
      logic [RIGHT_INDEX_WIDTH-1:0] right_idx;

      argmax_tree #(
          .NUM_INPUTS(RIGHT_TREE_INPUTS),
          .DATA_WIDTH(DATA_WIDTH)
      ) right_tree (
          .clk    (clk),
          .rst    (rst),
          .en     (en),
          .inputs (inputs[LEFT_TREE_INPUTS+:RIGHT_TREE_INPUTS]),
          .max_val(right_val_unaligned),
          .max_idx(right_idx_unaligned)
      );

      //--------------------------------------------------------------------
      // Delay the right max so it is aligned with the left max.            
      //--------------------------------------------------------------------
      localparam int LATENCY_DIFFERENCE = LEFT_TREE_DEPTH - RIGHT_TREE_DEPTH;

      if (LATENCY_DIFFERENCE > 0) begin : l_delay
        logic [       DATA_WIDTH-1:0] delay_val_r[LATENCY_DIFFERENCE];
        logic [RIGHT_INDEX_WIDTH-1:0] delay_idx_r[LATENCY_DIFFERENCE];

        always_ff @(posedge clk) begin
          if (rst) begin
            delay_val_r <= '{default: '0};
            delay_idx_r <= '{default: '0};
          end else if (en) begin
            delay_val_r[0] <= right_val_unaligned;
            delay_idx_r[0] <= right_idx_unaligned;
            for (int i = 1; i < LATENCY_DIFFERENCE; i++) begin
              delay_val_r[i] <= delay_val_r[i-1];
              delay_idx_r[i] <= delay_idx_r[i-1];
            end
          end
        end

        assign right_val = delay_val_r[LATENCY_DIFFERENCE-1];
        assign right_idx = delay_idx_r[LATENCY_DIFFERENCE-1];
      end else begin : l_no_delay
        assign right_val = right_val_unaligned;
        assign right_idx = right_idx_unaligned;
      end

      //--------------------------------------------------------------------
      // Compare the branches and register the winner
      //--------------------------------------------------------------------
      always_ff @(posedge clk) begin
        if (rst) begin
          max_val <= '0;
          max_idx <= '0;
        end else if (en) begin
          // >= ensures lower index is prioritized if values are identical
          if (left_val >= right_val) begin
            max_val <= left_val;
            max_idx <= INDEX_WIDTH'(left_idx);
          end else begin
            max_val <= right_val;
            // Adjust the right index to account for the left split
            max_idx <= INDEX_WIDTH'(right_idx + LEFT_TREE_INPUTS);
          end
        end
      end
    end
  endgenerate
endmodule
