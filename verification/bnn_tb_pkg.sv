// This package includes the BNN model class. This is implemented closely from the complete bnn_fcc
// package, modified to test a binary neural net without AXI.

package bnn_tb_pkg;

  // Provides a reference model and testing/debugging methods for a BNN
  class BNN_FCC_Model #(
      int WEIGHT_WIDTH = 32,
      int THRESHOLD_WIDTH = 32
  );
    typedef bit weight_row_t[];
    typedef weight_row_t layer_t[];
    typedef int thresh_row_t[];

    typedef bit [WEIGHT_WIDTH-1:0] weight_word_t;
    typedef weight_word_t weight_stream_t[];

    typedef bit [THRESHOLD_WIDTH-1:0] threshold_word_t;
    typedef threshold_word_t threshold_stream_t[];

    // Dimensions: [ LAYER ][ NEURON ][ INPUT_BIT ]
    layer_t            weight       [];

    // Dimensions: [ LAYER ][ NEURON ]
    thresh_row_t       threshold    [];

    // Dimensions: [ LAYER ][ NEURON ]
    int                layer_outputs[] [];

    int                num_layers;

    //  [Inputs, L0_Neurons, L1_Neurons, ...]
    int                topology     [];

    bit                is_loaded           = 0;
    bit                outputs_valid       = 0;
    bit          [7:0] last_input   [];

    function new();
      is_loaded     = 0;
      outputs_valid = '0;
    endfunction

    // Compute the prediction, and the output of each layer, for the provided image.
    // The layer outputs can be used for deeper debugging/testing.
    // Returns the prediction.
    function int compute_reference(input bit [7:0] img_data[]);
      if (!is_loaded) begin
        $fatal(
            1,
            "BNN_FCC_Model Error: Attempted to use model before loading weights! Call load_from_file() or create_random() first.");
      end

      this.last_input = img_data;
      this.layer_outputs = new[num_layers];

      for (int l = 0; l < num_layers; l++) begin
        int fan_in = this.topology[l];
        int n_neurons = this.topology[l+1];

        this.layer_outputs[l] = new[n_neurons];

        for (int n = 0; n < n_neurons; n++) begin
          int popcount = 0;

          for (int i = 0; i < fan_in; i++) begin
            bit in_bit;
            bit w_bit;

            if (l == 0) in_bit = (img_data[i] >= 8'd128) ? 1'b1 : 1'b0;
            else in_bit = (this.layer_outputs[l-1][i] == 1) ? 1'b1 : 1'b0;

            w_bit = this.weight[l][n][i];
            if (in_bit == w_bit) popcount++;
          end

          if (l == num_layers - 1) this.layer_outputs[l][n] = popcount;
          else this.layer_outputs[l][n] = (popcount >= this.threshold[l][n]) ? 1 : 0;
        end
      end

      this.outputs_valid = 1;
      return get_prediction();
    endfunction

    function int get_prediction();
      int last = num_layers - 1;
      int max_val = -1;
      int winner = 0;

      if (!outputs_valid) begin
        $fatal(
            1,
            "BNN_FCC_Model Error: Requested prediction but no inputs processed. Call compute_reference() first.");
      end

      for (int n = 0; n < this.layer_outputs[last].size(); n++) begin
        if (this.layer_outputs[last][n] > max_val) begin
          max_val = this.layer_outputs[last][n];
          winner  = n;
        end
      end
      return winner;
    endfunction

    // Returns the output value of a specific neuron in a specific layer.
    function int get_layer_output(int layer_idx, int neuron_idx);
      if (!outputs_valid) begin
        $fatal(1, "BNN_FCC_Model: Read attempted before compute_reference().");
      end

      if (layer_idx < 0 || layer_idx >= num_layers) begin
        $fatal(1, "BNN_FCC_Model: Layer index %0d out of bounds (0 to %0d).", layer_idx, num_layers - 1);
      end

      if (neuron_idx < 0 || neuron_idx >= layer_outputs[layer_idx].size()) begin
        $fatal(1, "BNN_FCC_Model: Neuron index %0d out of bounds for Layer %0d.", neuron_idx, layer_idx);
      end

      return layer_outputs[layer_idx][neuron_idx];
    endfunction

    // Generates the configuration stream for a given layer, a given mode (weight/threshold), and 
    // outputs the data stream and respective weight/threshold enables
    function void get_layer_config(input int layer_idx, input bit is_threshold, output bus_stream_t stream,
                                   output keep_stream_t keep);

      // [$] sets up these variables as queues
      bit [7:0] byte_q[$];
      weight_word_t weight_q[$];
      threshold_word_t threshold_q[$];



      int fan_in, n_neurons;
      int bytes_per_neuron;
      int layer_inputs;
      longint total_payload_bytes;

      weight_word_t current_word;
      threshold_word_t current_keep;
      int bytes_per_beat;
      int byte_count;

      int w_idx;
      bit [7:0] byte_val;
      bit [31:0] t_val;

      fan_in = this.topology[layer_idx];
      n_neurons = this.topology[layer_idx+1];

      // calculate the weight/threshold dimensions
      if (is_threshold) begin
        bytes_per_neuron = 4;
        layer_inputs     = 32;
      end else begin
        bytes_per_neuron = (fan_in + 7) / 8;
        layer_inputs     = fan_in;
      end

      total_payload_bytes = bytes_per_neuron * n_neurons;

      // Since this module does not test parsing, pass data directly to the weight/threshold rams and assert enable
      for (int n = 0; n < n_neurons; n++) begin
        if (is_threshold) begin
          // Thresholds: Push entire word
          t_val = this.threshold[layer_idx][n];
          threshold_q.push_back(t_val);
        end else begin
          // Weights: Pack bits into full word
          w_idx = 0;
          for (int b = 0; b < bytes_per_neuron; b++) begin
            for (int k = 0; k < 8; k++) begin
              if (w_idx < fan_in) byte_val[k] = this.weight[layer_idx][n][w_idx];
              else byte_val[k] = 1'b1;  // Pad unused bits in the byte
              w_idx++;
            end
            weight_q.push_back(byte_val);
          end
        end
      end


      // Output data and keep arrays
      weight = new[weight_q.size()];
      threshold   = new[threshold_q.size()];
      foreach (weight_q[i]) begin
        weight[i] = weight_q[i];
        threshold[i]   = keep_q[i];
      end
    endfunction

    // Generates the configuration stream (weights and thresholds) for all layers (i.e. the full model). 
    // Outputs both data (stream) and keep (keep_stream) for AXI streaming.
    // The keep is needed because the length of the stream might not be a multiple of BUS_WIDTH.
    function void encode_configuration(output bus_stream_t full_stream, output keep_stream_t full_keep);
      bus_stream_t  layer_stream;
      keep_stream_t layer_keep;

      full_stream = new[0];
      full_keep   = new[0];

      for (int l = 0; l < num_layers; l++) begin
        // Generate weights
        get_layer_config(l, 0, layer_stream, layer_keep);
        full_stream = {full_stream, layer_stream};
        full_keep   = {full_keep, layer_keep};

        // Generate thresholds, but skip output layer
        if (l < num_layers - 1) begin
          get_layer_config(l, 1, layer_stream, layer_keep);
          full_stream = {full_stream, layer_stream};
          full_keep   = {full_keep, layer_keep};
        end
      end
    endfunction
  endclass
endpackage
