# =============================================================================
# Makefile for BNN FCC UVM Testbench — Based on uvm_reference/Makefile
# =============================================================================
#
# This Makefile mirrors the Questa-oriented flow from the filter UVM example.
# It compiles the DUT + UVM TB, optimizes, and runs tests by name.
#
# USAGE:
#   make                              # compile + optimize
#   make sim                          # run default test (bnn_fcc_base_test)
#   make sim TEST=bnn_fcc_base_test   # run specific test
#   make gui TEST=bnn_fcc_base_test   # open Questa GUI
#   make regress                      # run all 5 tests sequentially
#   make clean                        # remove all generated files
#
# IMPORTANT:
#   - Run from verification/uvm/ (this directory)
#   - Your RTL source files must be added to the RTL_SOURCES variable below
#   - The working directory determines relative paths to python/model_data
# =============================================================================

# ---- Tool configuration (same as reference) ----
VLOG = vlog
VSIM = vsim
VOPT = vopt

# ---- Project configuration ----
WORK_DIR = work
TOP_MODULE = bnn_fcc_uvm_tb
OPTIMIZED_TOP = $(TOP_MODULE)_opt

# ---- UVM test selection ----
# Override on command line: make sim TEST=bnn_fcc_protocol_stress_test
TEST ?= bnn_fcc_base_test
UVM_FLAGS = +UVM_TESTNAME=$(TEST)

# ---- Seed control ----
# Override on command line: make sim SEED=12345
SEED ?= random

# ---- RTL sources ----
# >>> EDIT THIS: Add your bnn_fcc RTL files here <<<
# Example:
#   RTL_SOURCES = ../../rtl/bnn_fcc.sv ../../rtl/bnn_layer.sv ...
# If your RTL lives elsewhere, adjust paths accordingly.
RTL_SOURCES ?=

# ---- Compilation flags (from reference Makefile) ----
VLOG_FLAGS = -sv \
	-mfcu \
	-lint \
	+acc=pr \
	-suppress 2275 \
	-timescale "1ns/1ps" \
	+define+UVM_PACKER_MAX_BYTES=1500000 \
	+define+UVM_DISABLE_AUTO_ITEM_RECORDING \
	-work $(WORK_DIR)

# ---- Optimization flags ----
VOPT_FLAGS = +acc \
	-o $(OPTIMIZED_TOP)

# ---- Simulation flags (command-line mode) ----
VSIM_FLAGS = -c \
	-debugDB \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	-sv_seed $(SEED) \
	-do "run -all"

# ---- GUI simulation flags ----
VSIM_GUI_FLAGS = -gui \
	-debugDB \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	-sv_seed $(SEED)

# ===========================================================================
# Targets
# ===========================================================================

# Default: compile + optimize
all: compile optimize

# Create work library
$(WORK_DIR):
	vlib $(WORK_DIR)
	vmap work $(WORK_DIR)

# Compile RTL + TB from sources.f
compile: $(WORK_DIR)
	$(VLOG) $(VLOG_FLAGS) $(RTL_SOURCES) -f sources.f

# Optimize design
optimize: compile
	$(VOPT) $(TOP_MODULE) $(VOPT_FLAGS)

# Run simulation in command-line mode
sim: optimize
	@echo "=== Running test: $(TEST) (seed: $(SEED)) ==="
	$(VSIM) $(VSIM_FLAGS) $(OPTIMIZED_TOP)

# Open GUI for interactive debug
gui: optimize
	@echo "=== Opening GUI for test: $(TEST) ==="
	$(VSIM) $(VSIM_GUI_FLAGS) $(OPTIMIZED_TOP) &

# ===========================================================================
# Regression: run all 5 tests
# ===========================================================================
TESTS = bnn_fcc_base_test \
        bnn_fcc_protocol_stress_test \
        bnn_fcc_reconfig_test \
        bnn_fcc_reset_stress_test \
        bnn_fcc_output_class_test

regress: optimize
	@echo "=== Running full regression ($(words $(TESTS)) tests) ==="
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo "--- Running: $$t ---"; \
		$(VSIM) -c -debugDB -voptargs="+acc" \
			+UVM_NO_RELNOTES +UVM_VERBOSITY=UVM_LOW \
			+UVM_TESTNAME=$$t \
			-sv_seed random \
			-do "run -all" \
			$(OPTIMIZED_TOP) \
			> logs/$$t.log 2>&1; \
		if grep -q "TEST PASSED" logs/$$t.log; then \
			echo "  PASSED: $$t"; \
			pass=$$((pass+1)); \
		else \
			echo "  FAILED: $$t"; \
			fail=$$((fail+1)); \
		fi; \
	done; \
	echo "=== Regression complete: $$pass passed, $$fail failed ==="

# Create logs directory for regression
logs:
	mkdir -p logs

# ===========================================================================
# Coverage merge (if supported by your simulator)
# ===========================================================================
cov_merge:
	@echo "Merging coverage databases..."
	vcover merge -out merged_cov.ucdb logs/*.ucdb 2>/dev/null || \
		echo "No .ucdb files found. Run tests with -coverage flag first."
	vcover report -details merged_cov.ucdb 2>/dev/null || true

# ===========================================================================
# Clean
# ===========================================================================
clean:
	rm -rf $(WORK_DIR)
	rm -rf transcript
	rm -rf vsim.wlf
	rm -rf *.db
	rm -rf *.dbg
	rm -rf *.vstf
	rm -rf *.ucdb
	rm -rf modelsim.ini
	rm -rf logs/

.PHONY: all compile optimize sim gui regress clean cov_merge logs
