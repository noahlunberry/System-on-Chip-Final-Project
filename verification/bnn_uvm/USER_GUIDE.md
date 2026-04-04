# BNN FCC UVM Testbench — User Guide

## Table of Contents

1. [Directory Layout](#1-directory-layout)
2. [Prerequisites](#2-prerequisites)
3. [Quick Start](#3-quick-start)
4. [Test Descriptions](#4-test-descriptions)
5. [Makefile Reference](#5-makefile-reference)
6. [Customizing for Your RTL](#6-customizing-for-your-rtl)
7. [Reading Coverage Results](#7-reading-coverage-results)
8. [Debugging Failures](#8-debugging-failures)
9. [Adding New Tests](#9-adding-new-tests)
10. [Common Problems & Solutions](#10-common-problems--solutions)

---

## 1. Directory Layout

```
bnn_uvm/
├── IMPLEMENTATION_PLAN.md          # Architecture guide (normative)
├── uvm_reference/                  # Stitt's AXI4-Stream UVM agents
│   ├── Makefile                    # Reference Makefile (filter example)
│   ├── axi4_stream_pkg.sv          # AXI agent package
│   ├── axi4_stream_if.sv           # AXI interface definition
│   ├── axi4_stream_agent.svh       # Agent (driver + monitor + sequencer)
│   ├── axi4_stream_driver.svh      # AXI master driver
│   ├── axi4_stream_monitor.svh     # AXI monitor with analysis port
│   ├── axi4_stream_seq_item.svh    # Beat/packet sequence item
│   └── axi4_stream_sequencer.svh   # Standard sequencer
├── verification/
│   ├── bnn_fcc_tb.sv               # Original basic testbench (kept intact)
│   ├── bnn_fcc_tb_pkg.sv           # BNN_FCC_Model + BNN_FCC_Stimulus classes
│   ├── coverage_plan.txt           # FCC coverage requirements contract
│   └── uvm/                        # <<< YOUR UVM ENVIRONMENT >>>
│       ├── Makefile                 # Build/run/regress (this guide)
│       ├── sources.f                # Compilation file list
│       ├── bnn_fcc_pkg.sv           # Top package (include order)
│       ├── tb/
│       │   └── bnn_fcc_uvm_tb.sv    # Top module (DUT + VIFs + assertions)
│       ├── env/
│       │   ├── bnn_fcc_env.svh      # Environment (agents + SB + coverage)
│       │   ├── bnn_fcc_scoreboard.svh  # Epoch-aware scoreboard
│       │   └── bnn_fcc_coverage.svh    # 16 covergroups across 5 categories
│       ├── seq/
│       │   ├── bnn_cfg_sequence.svh    # Config sequence (ordering knobs)
│       │   ├── bnn_image_sequence.svh  # Image stimulus sequence
│       │   └── axi4s_ready_sequence.svh # Output backpressure driver
│       └── tests/
│           ├── bnn_fcc_base_test.svh           # Base test + report_phase
│           ├── bnn_fcc_protocol_stress_test.svh # AXI protocol corners
│           ├── bnn_fcc_reconfig_test.svh        # Config ordering variations
│           ├── bnn_fcc_reset_stress_test.svh    # Reset at multiple phases
│           └── bnn_fcc_output_class_test.svh    # Output class closure
```

---

## 2. Prerequisites

### Software
- **Questa** (or compatible: VCS, Xcelium, Riviera) with UVM support
- **Python** training data in `python/model_data/` and `python/test_vectors/` (for MNIST mode)

### Required Before First Run
1. Your RTL source files for `bnn_fcc` must be compiled. You need to either:
   - Add them to the `RTL_SOURCES` variable in the Makefile, **or**
   - Add them to `sources.f`

2. The `python/model_data/` directory must contain:
   - `l0_weights.txt`, `l0_thresholds.txt`
   - `l1_weights.txt`, `l1_thresholds.txt`
   - `l2_weights.txt`, `l2_thresholds.txt`
   
3. The `python/test_vectors/` directory must contain:
   - `inputs.hex`
   - `expected_outputs.txt`

> **Custom topology mode**: If you set `USE_CUSTOM_TOPOLOGY=1` in the TB parameters, model data files are not needed — the testbench generates random weights/thresholds/images internally.

---

## 3. Quick Start

All commands run from `verification/uvm/`:

```bash
cd verification/uvm/

# Step 1: Compile everything
make

# Step 2: Run the smoke test
make sim TEST=bnn_fcc_base_test

# Step 3: Check the output
# Look for:
#   "TEST PASSED" or "TEST FAILED"
#   "=== BNN FCC Coverage Summary ===" (per-category percentages)
#   "SB_REPORT" line showing match/mismatch counts
```

### Running with a Custom Topology (No MNIST Data Needed)

Edit the parameters in `tb/bnn_fcc_uvm_tb.sv`:

```systemverilog
parameter int USE_CUSTOM_TOPOLOGY = 1'b1,        // Enable custom mode
parameter int CUSTOM_LAYERS       = 4,
parameter int CUSTOM_TOPOLOGY [4] = '{8, 8, 8, 8}, // Tiny 4-layer network
parameter int NUM_TEST_IMAGES     = 20,
```

Then:
```bash
make clean
make sim TEST=bnn_fcc_base_test
```

---

## 4. Test Descriptions

| Test Name | Coverage Target | What It Does | Runtime |
|---|---|---|---|
| `bnn_fcc_base_test` | All categories (baseline) | Standard config → images → check. Light backpressure. | Fast |
| `bnn_fcc_protocol_stress_test` | Category 1: AXI protocol | Large inter-beat delays, heavy backpressure, shuffled config order. | Medium |
| `bnn_fcc_reconfig_test` | Category 4: Sequencing | Three reconfig phases: normal → thresh-first → reverse order. | Medium |
| `bnn_fcc_reset_stress_test` | Category 5: Reset | Resets during idle, config, image input. Same vs different post-reset config. | Long |
| `bnn_fcc_output_class_test` | Category 3: Outputs | 200 images (custom) or 50 (MNIST) to hit all output classes 0-9. | Medium |

### Running Individual Tests

```bash
make sim TEST=bnn_fcc_protocol_stress_test
make sim TEST=bnn_fcc_reconfig_test
make sim TEST=bnn_fcc_reset_stress_test
make sim TEST=bnn_fcc_output_class_test
```

### Running the Full Regression

```bash
mkdir -p logs
make regress
```

This runs all 5 tests with random seeds and logs each to `logs/<test_name>.log`.

---

## 5. Makefile Reference

| Command | Description |
|---|---|
| `make` | Compile + optimize (no simulation) |
| `make sim` | Run default test (`bnn_fcc_base_test`) |
| `make sim TEST=<name>` | Run a specific test |
| `make sim SEED=12345` | Run with a fixed random seed (reproducibility) |
| `make gui TEST=<name>` | Open Questa GUI for interactive debug |
| `make regress` | Run all 5 tests, report pass/fail |
| `make cov_merge` | Merge coverage databases (if `.ucdb` exists) |
| `make clean` | Remove all generated files |

### Changing Verbosity

Pass `+UVM_VERBOSITY` through VSIM_FLAGS:

```bash
# Very detailed output:
make sim TEST=bnn_fcc_base_test VSIM_FLAGS="-c +UVM_VERBOSITY=UVM_HIGH +UVM_TESTNAME=bnn_fcc_base_test -do 'run -all'"
```

Or edit the Makefile's `VSIM_FLAGS` to change the default from `UVM_MEDIUM` to `UVM_HIGH`.

---

## 6. Customizing for Your RTL

### Step 1: Point to Your RTL

Edit the Makefile:

```makefile
RTL_SOURCES = ../../rtl/bnn_fcc.sv \
              ../../rtl/bnn_layer.sv \
              ../../rtl/config_manager.sv \
              ../../rtl/bnn_core.sv
```

Or add them to `sources.f` (before the TB files):

```
+incdir+../../rtl
../../rtl/bnn_fcc.sv
../../rtl/bnn_layer.sv
...
```

### Step 2: Match DUT Port Names

The top module `tb/bnn_fcc_uvm_tb.sv` instantiates `bnn_fcc` with specific port names. If your DUT uses different names, edit the DUT instantiation block (lines ~62-92).

### Step 3: Adjust Parameters

If your DUT uses different `PARALLEL_INPUTS` or `PARALLEL_NEURONS`, edit the top module's parameters.

---

## 7. Reading Coverage Results

### End-of-Test Summary

Every test prints a coverage summary at the end (from `report_phase`):

```
=== BNN FCC Coverage Summary ===

CATEGORY 1: AXI4-Stream Protocol Patterns
  Config Handshake:      75.00%
  Config Interface:      100.00%
  Input Handshake:       62.50%
  ...

CATEGORY 2: Configuration Data Diversity
  Config Content:        85.00%
  Weight Density:        42.86%
  ...

CATEGORY 3: Computational Stimulus
  Output Classes:        70.00%
  ...
```

### What 100% Means for Each Covergroup

| Covergroup | 100% = hit all these bins |
|---|---|
| `cg_cfg_handshake` | zero, short, medium, and long gaps AND one/short/long/huge bursts |
| `cg_cfg_content` | Both msg_types × all layers × multiple ordering slots |
| `cg_weight_density` | near_zero, low, mid_low, mid, mid_high, high, near_full densities × all layers |
| `cg_thresh` | small, medium, large, huge thresholds × all layers |
| `cg_outputs` | All 10 output classes (0-9) × no/light/heavy backpressure |
| `cg_tkeep` | All partial byte counts (1-8) × last/not-last |
| `cg_reconfig` | full, weights_only, thresh_only, partial × layer counts |
| `cg_reset` | idle, during_config, during_image, during_output, at_tlast × reset counts |
| `cg_reset_post` | same config AND different config post-reset |

### Closing Holes

If specific bins are at 0%, you need to either:
1. Add a **directed test** that explicitly targets that scenario
2. Adjust **sequence knobs** (e.g., set `reorder_msgs=1` in the cfg sequence)
3. Increase **image count** or **reset count** in the test

---

## 8. Debugging Failures

### Scoreboard Mismatches (`SB_MISMATCH`)

```
UVM_ERROR: Image 5: actual=3 expected=7 (epoch cfg=0 rst=0)
```

**What it means**: DUT output doesn't match reference model for image 5.

**Debug steps**:
1. Run in GUI mode: `make gui TEST=bnn_fcc_base_test`
2. Add `model.print_inference_trace()` after `compute_reference()` in the image sequence
3. Check waveforms for the config stream — are weights loaded correctly?
4. Check if `tkeep` is handled correctly on partial last beats

### Scoreboard Empty Expected (`SB_EMPTY_EXPECTED`)

```
UVM_ERROR: Received output 5 but no expected result available
```

**What it means**: The DUT produced an output that wasn't anticipated. Usually caused by:
- Extra outputs after a reset (scoreboard flushed the queue)
- DUT producing outputs before config is complete
- Pipeline flushing artifacts

### Assertion Failures (`AXI_HOLD`)

```
UVM_ERROR: Config TVALID dropped before handshake
```

**What it means**: The AXI protocol hold rule was violated. `TVALID` went low while `TREADY` was still low. This is a DUT bug if it's on the output interface, or a testbench bug if on config/input.

### Post-Test Leftovers (`SB_LEFTOVER`)

```
UVM_ERROR: 3 expected outputs not matched
```

**What it means**: The DUT didn't produce all expected outputs in time. Either:
- Increase the `#50000` delay in the test's `run_phase`
- Check if the DUT is stalled (backpressure too aggressive)
- Check if `data_in_ready` is stuck low

---

## 9. Adding New Tests

### Step 1: Create the Test File

Create `tests/bnn_fcc_my_test.svh`:

```systemverilog
`ifndef _BNN_FCC_MY_TEST_SVH_
`define _BNN_FCC_MY_TEST_SVH_

class bnn_fcc_my_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_my_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        bnn_cfg_sequence cfg_seq;
        bnn_image_sequence in_seq;
        axi4s_ready_sequence out_seq;

        phase.raise_objection(this);

        // Your custom test logic here
        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq");
        in_seq  = bnn_image_sequence::type_id::create("in_seq");
        out_seq = axi4s_ready_sequence::type_id::create("out_seq");

        fork out_seq.start(null); join_none
        cfg_seq.start(env.cfg_agent.sequencer);
        in_seq.start(env.in_agent.sequencer);

        #50000;
        phase.drop_objection(this);
    endtask
endclass
`endif
```

### Step 2: Include in Package

Add to `bnn_fcc_pkg.sv`:

```systemverilog
`include "bnn_fcc_my_test.svh"
```

### Step 3: Run

```bash
make clean
make sim TEST=bnn_fcc_my_test
```

### Using Config Sequence Knobs

```systemverilog
// Shuffle messages randomly
cfg_seq.reorder_msgs = 1;

// Thresholds before weights
cfg_seq.thresh_before_weights = 1;

// Reverse layer order
cfg_seq.reverse_layer_order = 1;
```

### Using Backpressure Knobs

```systemverilog
// Heavy backpressure
out_seq.ready_on_min  = 1;
out_seq.ready_on_max  = 3;
out_seq.ready_off_min = 10;
out_seq.ready_off_max = 50;

// No backpressure (throughput measurement)
out_seq.ready_on_min  = 1;
out_seq.ready_on_max  = 1;
out_seq.ready_off_min = 0;
out_seq.ready_off_max = 0;
```

### Using Driver Delay Knobs

```systemverilog
// Slow config streaming (gaps between beats)
env.cfg_agent.driver.set_delay(1, 10);

// Fast image streaming (no gaps)
env.in_agent.driver.set_delay(1, 1);
```

### Sampling Coverage from Your Test

```systemverilog
// Access the coverage component
env.coverage.sample_reconfig(0, model.num_layers);  // full config
env.coverage.sample_reset_event(2, 1);               // reset during image
env.coverage.sample_post_reset(1);                    // same config post-reset
```

---

## 10. Common Problems & Solutions

| Problem | Cause | Solution |
|---|---|---|
| `Could not open .../model_data/l0_weights.txt` | Wrong `BASE_DIR` | Set `BASE_DIR` parameter relative to sim working directory |
| `Virtual interface must be set` | VIF not in config_db | Make sure `bnn_fcc_uvm_tb.sv` is the top module |
| `Failed to get BNN_FCC_Model` | Config_db key mismatch | Check that build_phase runs before sequences access config_db |
| Simulation hangs | Output never received | Increase timeout; check if DUT is stalled; check `tready` is toggling |
| All covergroups at 0% | Coverage not connected | Verify `connect_phase` wiring in `bnn_fcc_env.svh` |
| `vsim: command not found` | Questa not in PATH | Source your Questa setup script first |
| Compilation errors in `.svh` | Include order wrong | Check `bnn_fcc_pkg.sv` — sequences before env, env before tests |
| `force: unknown module bnn_fcc_uvm_tb` | Reset test hierarchical ref | Ensure top module name matches in `bnn_fcc_reset_stress_test.svh` |

### Useful Debug Commands (Questa Transcript)

```tcl
# Check coverage after sim
coverage report -detail

# List all UVM components
uvm_cmdline::display_component_list

# Change verbosity mid-sim
set_report_verbosity_level UVM_HIGH
```
