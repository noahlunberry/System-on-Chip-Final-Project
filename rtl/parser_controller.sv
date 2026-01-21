// The parser Controller is an FSM that stores the header data in registers, it
// will decode this into registers to control the enable signals of the FIFO, BRAM and
// address generators. It will assert done

module parser_controller #(
    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int PARALLEL_INPUTS  = 32
) (
    input logic clk,
    input logic en,
    input logic rst,
    input logic go,
    input logic [CONFIG_BUS_WIDTH-1:0] data,
    input logic done,
    output logic header_done
);


  typedef enum logic [1:0] {
    START,
    HEADER,
    PAYLOAD,
    DONE
  } state_t;

  state_t state_r, next_state;
  logic [$bits(data)-1:0] data_r, next_data;
  bit msg_type_r, next_msg_type;
  logic [1:0] layer_id_r, next_layer_id;
  logic [15:0] num_neurons_r, next_num_neurons;
  logic [15:0] bytes_per_neuron_r, next_bytes_per_neuron;
  logic [31:0] total_bytes_r, next_total_bytes;

	

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_r            <= START;
      data_r             <= '0;
      msg_type_r         <= 1'b0;
      layer_id_r         <= '0;
      num_neurons_r      <= '0;
      bytes_per_neuron_r <= '0;
      total_bytes_r      <= '0;
    end else begin
      state_r            <= next_state;
      data_r             <= next_data;
      msg_type_r         <= next_msg_type;
      layer_id_r         <= next_layer_id;
      num_neurons_r      <= next_num_neurons;
      bytes_per_neuron_r <= next_bytes_per_neuron;
      total_bytes_r      <= next_total_bytes;
    end
  end

  always_comb begin
    next_state            = state_r;
    next_data             = data_r;
    next_msg_type         = msg_type_r;
    next_layer_id         = layer_id_r;
    next_num_neurons      = num_neurons_r;
    next_bytes_per_neuron = bytes_per_neuron_r;
    next_total_bytes      = total_bytes_r;

    case (state_r)
      START: begin
        if (en == 1) begin
          next_msg_type         = data[0];
          next_layer_id         = data[9:8];
          next_layer_inputs     = data[31:16];
          next_num_neurons      = data[47:32];
          next_bytes_per_neuron = data[63:48];
          next_state            = HEADER;
        end
      end

      HEADER: begin
        next_state = PAYLOAD;


      end

      PAYLOAD: begin
      end

      DONE: begin
      end

    endcase
  end

endmodule
