// The parser Controller is an FSM that stores the header data in registers, it
// will decode this into registers to control the enable signals of the FIFO, BRAM and
// address generators. It will assert done

module parser_controller #(
    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int PARALLEL_INPUTS = 32,
    parameter int FIFO_RD_WIDTH = 64
) (
    input logic clk,
    input logic en,
    input logic rst,
    input logic [CONFIG_BUS_WIDTH-1:0] data,
    input logic done,
    output logic ready,
    output logic header_done
);

  localparam int PARALLEL_BITS = $clog2(PARALLEL_INPUTS);  // bits needed for batch count
  //ADD ASSERTION TO BREAK IF PARALLEL_INPUTS IS NOT FACTOR OF 8
  localparam int PARALLEL_BYTES = (PARALLEL_INPUTS) / 8;


  typedef enum logic [1:0] {
    START,
    HEADER,
    PAYLOAD,
    DONE
  } state_t;

  // Control Signals
  logic ready_r, next_ready;
  logic header_done_r, next_header_done;

  state_t state_r, next_state;
  logic [$bits(data)-1:0] data_r, next_data;
  bit msg_type_r, next_msg_type;
  logic [1:0] layer_id_r, next_layer_id;
  logic [15:0] layer_inputs_r, next_layer_inputs;
  logic [15:0] num_neurons_r, next_num_neurons;
  logic [15:0] bytes_per_neuron_r, next_bytes_per_neuron;
  logic [31:0] total_bytes_r, next_total_bytes;

  // Counter Signals
  logic [15:0] batch_count_r, next_batch_count;
  logic [15:0] rd_count_r, next_rd_count;
  logic [31:0] global_count_r, next_global_count;
  logic [31:0] count_r, next_count;

  // Concurrent Assignments
  assign ready       = ready_r;
  assign header_done = header_done_r;

  always_ff @(posedge clk) begin
    // Control Signals
    ready_r            <= next_ready;
    header_done_r      <= next_header_done;

    state_r            <= next_state;
    data_r             <= next_data;
    msg_type_r         <= next_msg_type;
    layer_id_r         <= next_layer_id;
    num_neurons_r      <= next_num_neurons;
    bytes_per_neuron_r <= next_bytes_per_neuron;
    total_bytes_r      <= next_total_bytes;
    //counter signals
    batch_count_r      <= next_batch_count;
    rd_count_r         <= next_rd_count;
    global_count_r     <= next_global_count;
    count_r            <= next_count;

    if (rst) begin
      state_r            <= START;
      data_r             <= '0;
      msg_type_r         <= 1'b0;
      layer_id_r         <= '0;
      num_neurons_r      <= '0;
      bytes_per_neuron_r <= '0;
      total_bytes_r      <= '0;
    end
  end

  always_comb begin
    // Control
    next_ready            = ready_r;
    next_header_done      = header_done_r;

    next_state            = state_r;
    next_data             = data_r;
    next_msg_type         = msg_type_r;
    next_layer_id         = layer_id_r;
    next_num_neurons      = num_neurons_r;
    next_bytes_per_neuron = bytes_per_neuron_r;
    next_total_bytes      = total_bytes_r;

    // Counters
    next_batch_count      = batch_count_r;
    next_rd_count         = rd_count_r;
    next_global_count     = global_count_r;
    next_count            = count_r;


    case (state_r)
      START: begin
        next_ready = 1'b1;

        if (en == 1) begin

          next_msg_type         = data[0];
          next_layer_id         = data[9:8];
          next_layer_inputs     = data[31:16];
          next_num_neurons      = data[47:32];
          next_bytes_per_neuron = data[63:48];
          next_state            = HEADER;

          next_batch_count      = (data[31:16] + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS;
          next_rd_count         = (data[31:16] + FIFO_RD_WIDTH - 1) / FIFO_RD_WIDTH;
          next_count            = '0;
        end
      end

      HEADER: begin
        next_state        = PAYLOAD;
        next_global_count = (data[31:0] + rd_count_r - 1) / rd_count_r;
        next_header_done  = 1'b1;

      end

      PAYLOAD: begin
        if (en == 1'b1) begin
          next_count = count_r + 1'b1;

          if (count_r == global_count_r - 1) begin
            next_state = DONE;
            next_ready = 1'b0;
          end
        end

      end

      // Wait for FIFO to assert done writing the payload to memory, stall reads until then
      // Can be later optimized to improve latency
      DONE: begin
        if (done) begin
          next_state = START;
          next_ready = 1'b1;
        end
      end

    endcase
  end

endmodule
