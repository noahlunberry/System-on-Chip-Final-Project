// Parser controller module is responsible for writing vlaid datato the FIFO and communicating with the AXI stream.
// The FSM parses valid header/payload data from the config stream. Once the entire payload is written, it
// deasserts valid pausing data until the buffers are empty(all read from the config manager FSM)

module parser_controller #(
    parameter int CONFIG_BUS_WIDTH = 64
) (
    input  logic                        clk,
    input  logic                        valid,
    input  logic                        rst,
    input  logic [CONFIG_BUS_WIDTH-1:0] data,
    input  logic                        empty,
    output logic                        ready,
    output logic                        wr_en,
    output logic                        msg_type,
    output logic [                 1:0] layer_id,
    output logic [                31:0] total_bytes,
    output logic [                15:0] bytes_per_neuron
);

  localparam int FIFO_RD_BYTES = (CONFIG_BUS_WIDTH) / 8;


  typedef enum logic [1:0] {
    HDR0,
    HDR1,
    PAYLOAD,
    DONE
  } state_t;

  // Control Signals
  logic ready_r, next_ready;

  state_t state_r, next_state;
  bit msg_type_r, next_msg_type;
  logic [1:0] layer_id_r, next_layer_id;
  logic [31:0] total_bytes_r, next_total_bytes;
  logic [15:0] bytes_per_neuron_r, next_bytes_per_neuron;

  // Counter Signals
  logic [31:0] wr_count_r, next_wr_count;
  logic [31:0] count_r, next_count;

  assign ready = ready_r;
  assign msg_type = msg_type_r;
  assign total_bytes = total_bytes_r;
  assign layer_id = layer_id_r;
  assign bytes_per_neuron = bytes_per_neuron_r;

  always_ff @(posedge clk) begin
    // Control Signals
    state_r            <= next_state;
    ready_r            <= next_ready;

    msg_type_r         <= next_msg_type;
    layer_id_r         <= next_layer_id;
    total_bytes_r      <= next_total_bytes;
    bytes_per_neuron_r <= next_bytes_per_neuron;
    count_r            <= next_count;
    wr_count_r         <= next_wr_count;

    if (rst) begin
      state_r       <= HDR0;
      msg_type_r    <= 1'b0;
      layer_id_r    <= '0;
      total_bytes_r <= '0;
      count_r       <= '0;
      wr_count_r    <= '0;
    end
  end

  always_comb begin
    // Control
    next_ready            = ready_r;

    next_state            = state_r;
    next_msg_type         = msg_type_r;
    next_layer_id         = layer_id_r;
    next_total_bytes      = total_bytes_r;
    next_bytes_per_neuron = bytes_per_neuron_r;

    // Counters
    next_wr_count         = wr_count_r;
    next_count            = count_r;

    wr_en                 = 0;



    case (state_r)
      HDR0: begin
        next_ready = 1'b1;

        if (valid == 1) begin

          next_msg_type = data[0];
          next_layer_id = data[9:8];
          next_bytes_per_neuron = data[63:48];
          next_state    = HDR1;

          next_count    = '0;
        end
      end

      HDR1: begin
        if (valid == 1) begin
          next_state       = PAYLOAD;
          next_total_bytes = data[31:0];
          next_wr_count    = (data[31:0] + FIFO_RD_BYTES - 1) / 8;
        end
      end

      PAYLOAD: begin
        if (valid == 1'b1) begin
          next_count = count_r + 1'b1;
          wr_en = 1;

          if (count_r == wr_count_r - 1) begin
            next_state = DONE;
            next_ready = 1'b0;
          end
        end

      end

      // Wait for FIFO to assert done writing the payload to memory, stall reads until then
      // Can be later optimized to improve latency
      DONE: begin
        if (empty) begin
          next_state = HDR0;
          next_ready = 1'b1;
        end
      end
    endcase
  end

endmodule
