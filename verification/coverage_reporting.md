# Coverage Reporting Guide

This guide documents the intended functional-coverage flow for the BNN FCC UVM environment and explains how to write a coverage report that is directly traceable to [coverage_plan.txt](coverage_plan.txt).

## Coverage Flow Overview

The single-run coverage flow is built from these pieces:

* Coverage testbench: [bnn_uvm/bnn_fcc_coverage_tb.sv](bnn_uvm/bnn_fcc_coverage_tb.sv)
* Composite UVM test: [bnn_uvm/tests/bnn_fcc_coverage_sweep_test.svh](bnn_uvm/tests/bnn_fcc_coverage_sweep_test.svh)
* Coverage collectors: [bnn_uvm/bnn_fcc_coverage.svh](bnn_uvm/bnn_fcc_coverage.svh)
* Build/run flow: [../Makefile](../Makefile)

The coverage testbench exists so coverage can be evaluated from one top-level module and one UCDB while still exposing `config_in_if`, `data_in_if`, and `data_out_if` directly under `bnn_fcc_coverage_tb` for external monitor attachment. It defaults to `bnn_fcc_coverage_sweep_test` as the `uvm_test`.

## How To Run The Flow

From the repo root:

```bash
make coverage-sweep
```

This compiles the sources, optimizes the `bnn_fcc_coverage_tb` top, runs `bnn_fcc_coverage_sweep_test`, and saves:

* UCDB: `coverage/bnn_fcc_coverage_sweep_test.ucdb`
* Log: `coverage/logs/bnn_fcc_coverage_sweep_test.log`

To generate a text report from that UCDB:

```bash
make coverage-sweep-report
```

This writes:

* Text report: `coverage/bnn_fcc_coverage_sweep_test_coverage.txt`

Useful follow-on commands:

```bash
make viewcov UVM_TESTNAME=bnn_fcc_coverage_sweep_test
make reportcov UVM_TESTNAME=bnn_fcc_coverage_sweep_test
```

## What The Sweep Test Actually Exercises

The composite sweep test runs a sequence of directed scenarios inside one simulation instead of relying on a merged regression. The main phases are implemented in [bnn_uvm/tests/bnn_fcc_coverage_sweep_test.svh](bnn_uvm/tests/bnn_fcc_coverage_sweep_test.svh):

* Single-beat baseline traffic
* TKEEP-focused configuration and input transfers
* Directed output-class scenarios, including backpressure
* Threshold preamble ordering
* Configuration order permutations
* Threshold absolute-value extremes
* Weight-density extremes
* Directed pixel-value stimulus
* Input workload stress
* Directed delay/gap profile for config, image spacing, and output backpressure
* Weights-only reconfiguration
* Thresholds-only reconfiguration
* Partial-layer reconfiguration
* Reset bin accumulation
* Reset followed by reconfiguration

Those scenarios feed the covergroups implemented in [bnn_uvm/bnn_fcc_coverage.svh](bnn_uvm/bnn_fcc_coverage.svh), which are organized into four buckets:

* `bnn_cfg_coverage`
* `bnn_input_coverage`
* `bnn_output_coverage`
* `bnn_system_coverage`

## How To Write The Coverage Report

When you write the achieved-coverage report for this repo, keep it tied to the generated text report instead of only describing intent.

Use this structure:

1. State the command used to generate coverage.
   Example: `make coverage-sweep-report`
2. Name the exact top and test.
   Top: `bnn_fcc_coverage_tb`
   Test: `bnn_fcc_coverage_sweep_test`
3. Cite the generated artifacts.
   Report: `coverage/bnn_fcc_coverage_sweep_test_coverage.txt`
   UCDB: `coverage/bnn_fcc_coverage_sweep_test.ucdb`
   Log: `coverage/logs/bnn_fcc_coverage_sweep_test.log`
4. Report the overall functional-coverage result from the text report.
   The summary appears under `Covergroup Coverage` and again at `TOTAL COVERGROUP COVERAGE`.
5. Break the discussion down by coverage area.
   Use the covergroup names from the report so each claim is traceable.
6. Call out remaining misses.
   Use the uncovered bins in the report to explain what was not hit and whether that is acceptable, low priority, or a candidate for future stimulus.

## Recommended Report Sections

The generated text report is easiest to summarize using these sections:

* Overall result
  Cite `TOTAL COVERGROUP COVERAGE`.
* Configuration-channel coverage
  Cite `bnn_cfg_coverage/*`.
* Input-channel coverage
  Cite `bnn_input_coverage/*`.
* Output-channel coverage
  Cite `bnn_output_coverage/*`.
* System-level sequencing and reset coverage
  Cite `bnn_system_coverage/*`.
* Coverage gaps and next steps
  Cite any uncovered bins that remain in the report.

## Traceability To coverage_plan.txt

The table below maps each coverage-plan category to the sweep scenarios and the report sections that provide evidence.

| Coverage plan category | How the sweep test stimulates it | What to cite in the generated report |
| :--- | :--- | :--- |
| Category 1: AXI4-Stream protocol patterns | `run_single_beat_scenario`, `run_tkeep_scenarios`, `run_output_directed_scenarios`, `run_input_stress_scenario`, and `run_delay_gap_profile_scenario` vary packet sizing, TKEEP usage, burst/gap behavior, inter-image spacing, and output backpressure. | `bnn_cfg_coverage.packet_coverage`, `bnn_cfg_coverage.cfg_handshake_coverage`, `bnn_cfg_coverage.cfg_interface_coverage`, `bnn_input_coverage.image_coverage`, `bnn_input_coverage.input_handshake_coverage`, `bnn_input_coverage.input_image_spacing_coverage`, `bnn_input_coverage.input_interface_coverage`, `bnn_output_coverage.output_coverage`, `bnn_output_coverage.output_backpressure_coverage`, `bnn_output_coverage.output_interface_coverage` |
| Category 2: Configuration data diversity | `run_density_extremes_scenario` varies weight densities from empty to full. `run_threshold_abs_scenario` drives large negative, near-zero, and large positive thresholds. Full-configuration phases also exercise header fields and payload sizes. | `bnn_cfg_coverage.header_coverage`, `bnn_cfg_coverage.weight_density_coverage`, `bnn_cfg_coverage.threshold_coverage`, `bnn_cfg_coverage.config_toggle_cov` |
| Category 3: Computational stimulus | `run_output_directed_scenarios` targets specific output classes and repeats. `run_pixel_value_scenario` uses all-zero, all-255, and mixed-extreme images. `run_input_stress_scenario` expands the image count. | `bnn_input_coverage.pixel_coverage`, `bnn_input_coverage.pixel_toggle_cov`, `bnn_input_coverage.workload_coverage`, `bnn_output_coverage.output_coverage`, `bnn_output_coverage.output_pattern_coverage`, `bnn_output_coverage.output_toggle_cov` |
| Category 4: Configuration-image sequencing | `run_threshold_preamble_scenario`, `run_config_order_scenario`, `run_weights_only_reconfig_scenario`, `run_thresh_only_reconfig_scenario`, and `run_partial_reconfig_scenario` intentionally vary full versus partial programming and the order of weights versus thresholds before image traffic. | `bnn_cfg_coverage.order_coverage`, `bnn_system_coverage.reconfig_coverage` |
| Category 5: Reset scenarios | `run_reset_bins_scenario` varies reset workload buckets. `run_reset_reconfig_scenario` covers reset followed by a different full configuration. Resets are sampled against live stream state. | `bnn_system_coverage.reset_coverage`, `bnn_system_coverage.reset_post_coverage` |

## Why This Mapping Is Defensible

The coverage plan is written as high-level stimulus guidance, while the report is generated from concrete covergroups. The alignment is defensible because the sweep test explicitly drives the scenario classes named in the plan, and the coverage model records those scenarios at the protocol, payload, output-pattern, reconfiguration, and reset levels.

In other words:

* The plan says what kinds of behavior should be exercised.
* `bnn_fcc_coverage_sweep_test` injects those behaviors in one run.
* `bnn_fcc_coverage.svh` records whether those behaviors were observed.
* `coverage/bnn_fcc_coverage_sweep_test_coverage.txt` is the artifact you cite in the final write-up.

## Suggested Short Report Template

You can use wording like this:

> Functional coverage was collected by running `make coverage-sweep-report`, which simulates the coverage testbench `bnn_fcc_coverage_tb` and executes the composite UVM test `bnn_fcc_coverage_sweep_test`. The resulting UCDB was saved to `coverage/bnn_fcc_coverage_sweep_test.ucdb`, and the detailed text report was written to `coverage/bnn_fcc_coverage_sweep_test_coverage.txt`.
>
> The report should then summarize overall covergroup coverage and break the result down across configuration, input, output, and system-level covergroups. Evidence for `coverage_plan.txt` Category 1 comes from the handshake, packet-shape, image-spacing, and output-backpressure covergroups. Category 2 is covered by weight-density and threshold-extremes covergroups. Category 3 is covered by pixel-value, workload, output-class, and output-pattern covergroups. Category 4 is covered by configuration-order and reconfiguration covergroups. Category 5 is covered by reset-phase, reset-workload, and post-reset configuration covergroups.

Replace the summary sentences with the actual percentages and any uncovered-bin discussion from your generated report.
