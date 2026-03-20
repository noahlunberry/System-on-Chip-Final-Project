// This package includes the BNN model class. This is implemented closely from the complete bnn_fcc
// package, modified to test a binary neural net without AXI.

package bnn_tb_pkg;

  // Provides a reference model and testing/debugging methods for a BNN
  class BNN_Model #(
      int WEIGHT_WIDTH = 8,
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
    function void get_layer_config(input int layer_idx, input bit is_threshold, output weight_stream_t weight,
                                   output threshold_stream_t threshold);

      // [$] sets up these variables as queues
      bit [7:0] byte_q[$];
      weight_word_t weight_q[$];
      threshold_word_t threshold_q[$];



      int fan_in, n_neurons;
      int words_per_neuron;
      int layer_inputs;
      longint total_payload_bytes;

      weight_word_t current_weight;
      int bytes_per_beat;
      int byte_count;

      int w_idx;
      bit [7:0] byte_val;
      bit [31:0] t_val;

      fan_in = this.topology[layer_idx];
      n_neurons = this.topology[layer_idx+1];

      // Calculate dimensions for weights
      if (!is_threshold) begin
        // Round up to the nearest full word based on the WEIGHT_WIDTH parameter
        words_per_neuron = (fan_in + WEIGHT_WIDTH - 1) / WEIGHT_WIDTH;
      end

      // Since this module does not test parsing, pass data directly to the weight/threshold rams and assert enable
      for (int n = 0; n < n_neurons; n++) begin
        if (is_threshold) begin
          // Thresholds: Push directly to threshold queue
          threshold_q.push_back(this.threshold[layer_idx][n]);
        end else begin
          // Weights: Densely pack bits into full WEIGHT_WIDTH words
          w_idx = 0;
          for (int w = 0; w < words_per_neuron; w++) begin
            for (int k = 0; k < WEIGHT_WIDTH; k++) begin
              if (w_idx < fan_in) begin
                current_weight[k] = this.weight[layer_idx][n][w_idx];
              end else begin
                current_weight[k] = 1'b1;  // Pad unused bits at the end of the word
              end
              w_idx++;
            end
            weight_q.push_back(current_weight);
          end
        end
      end

      // Populate output arrays independently
      weight = new[weight_q.size()];
      foreach (weight_q[i]) begin
        weight[i] = weight_q[i];
      end

      threshold = new[threshold_q.size()];
      foreach (threshold_q[i]) begin
        threshold[i] = threshold_q[i];
      end
    endfunction

    // Generates the configuration stream (weights and thresholds) for all layers (i.e. the full model). 
    // Outputs both weight and threshold stream for direct configuration.
    function void encode_configuration(output weight_stream_t full_weights,
                                       output threshold_stream_t full_threshold);
      weight_stream_t layer_weight;
      threshold_stream_t layer_threshold;

      full_weights   = new[0];
      full_threshold = new[0];

      for (int l = 0; l < num_layers; l++) begin
        // Generate weights
        get_layer_config(l, 0, layer_weight, layer_threshold);
        full_weights   = {full_weights, layer_weight};
        full_threshold = {full_threshold, layer_threshold};

        // Generate thresholds, but skip output layer
        if (l < num_layers - 1) begin
          get_layer_config(l, 1, layer_weight, layer_threshold);
          full_weights   = {full_weights, layer_weight};
          full_threshold = {full_threshold, layer_threshold};
        end
      end
    endfunction

    // Everything else can be directly copied from the original tb
    /////////////////////////////////////////////////////////////

    // Creates a randomized model (weights/thresholds) for the specified topology)
    function void create_random(int user_topology[]);
      this.topology = user_topology;
      this.num_layers = user_topology.size() - 1;
      this.weight    = new[num_layers];
      this.threshold = new[num_layers];

      for (int l = 0; l < num_layers; l++) begin
        int n_inputs = topology[l];
        int n_neurons = topology[l+1];

        $display("Randomizing Layer %0d: %0d inputs -> %0d neurons", l, n_inputs, n_neurons);
        this.weight[l]    = new[n_neurons];
        this.threshold[l] = new[n_neurons];

        for (int n = 0; n < n_neurons; n++) begin
          weight_row_t temp_w;
          int temp_t;

          temp_w = new[n_inputs];
          if (!std::randomize(temp_w)) $fatal(1, "Randomizing weights failed.");
          this.weight[l][n] = temp_w;

          if (!std::randomize(
                  temp_t
              ) with {
                temp_t >= 0;
                temp_t <= n_inputs;
                temp_t dist {
                  [n_inputs / 3 : 2 * n_inputs / 3] := 80,
                  [0 : n_inputs] := 20
                };
              })
            $fatal(1, "Randomizing thresholds failed.");
          this.threshold[l][n] = temp_t;
        end

        if (l == num_layers - 1) begin
          for (int n = 0; n < n_neurons; n++) this.threshold[l][n] = 0;
        end
      end

      is_loaded = 1;
      outputs_valid = 0;
    endfunction

    function void print_summary();
      $display("BNN Model: %0d Layers, %0d Inputs", num_layers, this.topology[0]);
      for (int i = 0; i < num_layers; i++) begin
        $display("  Layer %0d (%s): %0d Neurons", i, i == num_layers - 1 ? "output" : "hidden",
                 weight[i].size());
      end
    endfunction

    function void print_neuron(int layer_idx, int neuron_idx, bit msb_first = 1);
      int fan_in;
      int w;
      int bits_printed;

      if (layer_idx < 0 || layer_idx >= num_layers) begin
        $display("Error: Layer Index %0d out of bounds.", layer_idx);
        return;
      end
      if (neuron_idx < 0 || neuron_idx >= this.weight[layer_idx].size()) begin
        $display("Error: Neuron Index %0d out of bounds for Layer %0d.", neuron_idx, layer_idx);
        return;
      end

      fan_in = this.weight[layer_idx][neuron_idx].size();

      $display("\n--- [DEBUG] Model Inspection: Layer %0d, Neuron %0d ---", layer_idx, neuron_idx);
      $display("  Fan-In:    %0d", fan_in);
      $display("  Threshold: %0d", this.threshold[layer_idx][neuron_idx]);

      if (msb_first) $display("  Weights:   (MSB [Idx %0d] ... LSB [Idx 0])", fan_in - 1);
      else $display("  Weights:   (LSB [Idx 0] ... MSB [Idx %0d])", fan_in - 1);

      $write("    ");
      bits_printed = 0;

      if (msb_first) begin
        for (w = fan_in - 1; w >= 0; w--) begin
          $write("%b", this.weight[layer_idx][neuron_idx][w]);
          bits_printed++;

          if (w > 0) begin
            if (bits_printed % 64 == 0) $write("\n    ");
            else if (bits_printed % 8 == 0) $write("_");
          end
        end
      end else begin
        for (w = 0; w < fan_in; w++) begin
          $write("%b", this.weight[layer_idx][neuron_idx][w]);
          bits_printed++;

          if (w < fan_in - 1) begin
            if (bits_printed % 64 == 0) $write("\n    ");
            else if (bits_printed % 8 == 0) $write("_");
          end
        end
      end

      $write("\n");
      $display("-------------------------------------------------------");
    endfunction

    function void print_model(bit msb_first = 1);
      $display("\n====================================================");
      $display("FULL MODEL CONFIGURATION DUMP (Order: %s First)", msb_first ? "MSB" : "LSB");
      $display("====================================================");
      for (int l = 0; l < num_layers; l++) begin
        $display("\n>>> LAYER %0d <<<", l);
        for (int n = 0; n < topology[l+1]; n++) begin
          this.print_neuron(l, n, msb_first);
        end
      end
      $display("\n====================================================\n");
    endfunction

    // Prints inputs, per-neuron popcounts/thresholds, and layer outputs.                
    function void print_inference_trace(bit msb_first = 1);
      int l, n, i;
      int fan_in, n_neurons;
      int popcount;
      bit in_bit, w_bit;
      int out_val;
      int bits_printed;

      if (this.layer_outputs.size() == 0) begin
        $display("Error: No inference results. Run compute_reference() first.");
        return;
      end

      $display("\n=== BNN INFERENCE DEBUG TRACE ===");

      // Print image input in hex.
      $display("Input Vector (%0d bytes, shown as 0 to %0d):", this.last_input.size(),
               this.last_input.size() - 1);
      $write("  0x");
      foreach (this.last_input[x]) begin
        $write("%02h", this.last_input[x]);
        if ((x + 1) % 32 == 0 && x != this.last_input.size() - 1) $write("\n    ");
      end
      $write("\n");

      // Print binarized input
      fan_in = this.last_input.size();
      if (!msb_first) $write("Input Bits (Idx 0 -> N): ");
      else $write("Input Bits (Idx N -> 0): ");

      bits_printed = 0;
      if (!msb_first) begin
        for (i = 0; i < fan_in; i++) begin
          in_bit = (this.last_input[i] >= 8'd128);
          $write("%b", in_bit);
          bits_printed++;
          if (i < fan_in - 1 && bits_printed % 8 == 0) $write("_");
        end
      end else begin
        for (i = fan_in - 1; i >= 0; i--) begin
          in_bit = (this.last_input[i] >= 8'd128);
          $write("%b", in_bit);
          bits_printed++;
          if (i > 0 && bits_printed % 8 == 0) $write("_");
        end
      end
      $write("\n");

      // Print each layer.
      for (l = 0; l < num_layers; l++) begin
        int max_pop = -1;
        int argmax;

        fan_in = this.topology[l];
        n_neurons = this.topology[l+1];

        $display("\nLAYER %0d (%0d Inputs -> %0d Neurons):", l, fan_in, n_neurons);

        for (n = 0; n < n_neurons; n++) begin
          popcount = 0;

          // Recalculate popcount (this could potentially be saved from compute_reference())
          for (i = 0; i < fan_in; i++) begin
            if (l == 0) in_bit = (this.last_input[i] >= 8'd128) ? 1'b1 : 1'b0;
            else in_bit = (this.layer_outputs[l-1][i] == 1) ? 1'b1 : 1'b0;

            w_bit = this.weight[l][n][i];
            if (in_bit == w_bit) popcount++;
          end

          out_val = this.layer_outputs[l][n];

          // Print neuron info
          if (l == num_layers - 1) $write("  Neuron %3d: Pop=%3d (Argmax) -> Out=%0d", n, popcount, out_val);
          else
            $write(
                "  Neuron %3d: Pop=%3d (Thresh=%3d) -> Out=%b", n, popcount, this.threshold[l][n], 1'(out_val)
            );

          // Track argmax for the output layer.
          if (popcount > max_pop) begin
            argmax  = n;
            max_pop = popcount;
          end

          // Print weights used by current neuron
          $write(" | W: ");
          bits_printed = 0;

          if (!msb_first) begin
            for (i = 0; i < fan_in; i++) begin
              $write("%b", this.weight[l][n][i]);
              bits_printed++;
              if (i < fan_in - 1 && bits_printed % 8 == 0) $write("_");
            end
          end else begin
            for (i = fan_in - 1; i >= 0; i--) begin
              $write("%b", this.weight[l][n][i]);
              bits_printed++;
              if (i > 0 && bits_printed % 8 == 0) $write("_");
            end
          end
          $display("");
        end

        // Print layer outputs
        if (l < num_layers - 1) begin
          if (!msb_first) $write("  Layer %0d Output Bits (Idx 0 -> N): ", l);
          else $write("  Layer %0d Output Bits (Idx N -> 0): ", l);

          bits_printed = 0;
          if (!msb_first) begin
            for (n = 0; n < n_neurons; n++) begin
              $write("%b", 1'(this.layer_outputs[l][n]));
              bits_printed++;

              if (n < n_neurons - 1) begin
                if (bits_printed % 64 == 0) $write("\n                                           ");
                else if (bits_printed % 8 == 0) $write("_");
              end
            end
          end else begin
            for (n = n_neurons - 1; n >= 0; n--) begin
              $write("%b", 1'(this.layer_outputs[l][n]));
              bits_printed++;

              if (n > 0) begin
                if (bits_printed % 64 == 0) $write("\n                                           ");
                else if (bits_printed % 8 == 0) $write("_");
              end
            end
          end
          $display("");
        end else begin
          $display("  Layer %0d Argmax: %0d, (Popcount: %0d)", l, argmax, max_pop);
        end
      end

      $display("=================================\n");
    endfunction

  endclass

  // Provides methods for loading stimulus images and/or randomly generating them.
  class BNN_FCC_Stimulus #(
      int PIXEL_WIDTH = 8
  );

    typedef bit [PIXEL_WIDTH-1:0] pixel_t;
    typedef pixel_t input_vector_t[];

    local input_vector_t input_db[$];
    local int input_size;

    function new(int size);
      this.input_size = size;
    endfunction

    function int get_num_vectors();
      return this.input_db.size();
    endfunction

    // Loads up to "num_images" images from sepcified hex File
    // num_images=-1 loads entire file. Stores vectors in input_db to be
    // retrieved via get_vector().
    function void load_from_file(string filename, int num_images = -1);
      int fd;
      bit [8191:0] buffer;
      int code;
      input_vector_t vec;
      int i, high, low;

      fd = $fopen(filename, "r");
      if (fd == 0) $fatal(1, "BNN_FCC_Stimulus: Could not open %s", filename);

      this.input_db.delete();

      while (!$feof(
          fd
      )) begin
        if (num_images != -1 && this.input_db.size() >= num_images) break;

        code = $fscanf(fd, "%h\n", buffer);
        if (code == 1) begin
          vec = new[input_size];

          for (i = 0; i < input_size; i++) begin
            high = (input_size * PIXEL_WIDTH) - 1 - (i * PIXEL_WIDTH);
            low = high - PIXEL_WIDTH + 1;
            vec[i] = buffer[high-:PIXEL_WIDTH];
          end
          this.input_db.push_back(vec);
        end
      end
      $fclose(fd);
      if (this.input_db.size() < num_images)
        $warning(
            "BNN_FCC_Stimulus: Unable to load %0d vectors from %s. Using %0d instead.",
            num_images,
            filename,
            input_db.size()
        );
      $display("BNN_FCC_Stimulus: Loaded %0d vectors from %s", this.input_db.size(), filename);
    endfunction

    // Provides a single test vector for image index. Assumes images have already been loaded or created.
    function void get_vector(int index, output input_vector_t result);
      if (index >= 0 && index < this.input_db.size()) begin
        result = this.input_db[index];
      end else begin
        $warning("BNN_FCC_Stimulus: Index %0d out of bounds.", index);
        result = new[input_size];
      end
    endfunction

    // Generates num_vectors random input images, and stores them in input_db to be
    // retrieved via get_vector().
    function void generate_random_vectors(int num_vectors);
      input_vector_t vec;
      this.input_db.delete();

      $display("BNN_FCC_Stimulus: Generating %0d random vectors...", num_vectors);

      for (int i = 0; i < num_vectors; i++) begin
        // Get a random vector
        vec = new[input_size];
        if (!std::randomize(vec)) begin
          $fatal(1, "BNN_FCC_Stimulus: Failed to randomize input vector.");
        end
        // Add to database
        this.input_db.push_back(vec);
      end
      //$display("BNN_FCC_Stimulus: Generated %0d random vectors.", this.input_db.size());
    endfunction

    // Generate one random input image and returns it without changing input_db.
    function void get_random_vector(output input_vector_t result);
      result = new[input_size];
      if (!std::randomize(result)) $fatal(1, "BNN_FCC_Stimulus: Randomization failed");
    endfunction

  endclass
endpackage
