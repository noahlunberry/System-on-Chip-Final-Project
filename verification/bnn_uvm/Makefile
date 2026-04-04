# =============================================================================
# Makefile for BNN FCC UVM Testbench
# =============================================================================
# Run from: verification/uvm/  (this directory)
#
# NOTE: The recommended simulation directory is sim/ at the project root.
#       This Makefile works if you prefer to run from here instead.
#       BASE_DIR in bnn_fcc_uvm_tb.sv defaults to "../python", which resolves
#       to bnn_uvm/verification/python from here — you may need to override it.
#       If using the sim/ directory, this is not an issue.
#
# USAGE:
#   make                              # compile + optimize
#   make sim TEST=<name>              # run a specific test
#   make gui TEST=<name>              # open Questa GUI
#   make regress                      # run all 5 tests
#   make clean                        # remove generated files
# =============================================================================

VLOG = vlog
VSIM = vsim
VOPT = vopt

WORK_DIR = work
TOP_MODULE = bnn_fcc_uvm_tb
OPTIMIZED_TOP = $(TOP_MODULE)_opt

TEST ?= bnn_fcc_base_test
SEED ?= random
UVM_FLAGS = +UVM_TESTNAME=$(TEST)

# ---- RTL sources (bottom-up compile order) ----
RTL_DIR = ../../RTL

RTL_SOURCES = \
	$(RTL_DIR)/ram_sdp.sv \
	$(RTL_DIR)/sync_fifo.sv \
	$(RTL_DIR)/fifo_vr.sv \
	$(RTL_DIR)/delay.sv \
	$(RTL_DIR)/replay_buffer.sv \
	$(RTL_DIR)/add_tree.sv \
	$(RTL_DIR)/xnor_add_tree.sv \
	$(RTL_DIR)/argmax_tree.sv \
	$(RTL_DIR)/parser_controller.sv \
	$(RTL_DIR)/config_controller.sv \
	$(RTL_DIR)/config_manager.sv \
	$(RTL_DIR)/neuron_processor.sv \
	$(RTL_DIR)/neuron_controller.sv \
	$(RTL_DIR)/bnn_layer.sv \
	$(RTL_DIR)/bnn.sv \
	$(RTL_DIR)/bnn_fcc.sv

VLOG_FLAGS = -sv \
	-mfcu \
	-lint \
	+acc=pr \
	-suppress 2275 \
	-timescale "1ns/1ps" \
	+define+UVM_PACKER_MAX_BYTES=1500000 \
	+define+UVM_DISABLE_AUTO_ITEM_RECORDING \
	-work $(WORK_DIR)

VOPT_FLAGS = +acc -o $(OPTIMIZED_TOP)

VSIM_FLAGS = -c \
	-debugDB \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	-sv_seed $(SEED) \
	-do "run -all"

VSIM_GUI_FLAGS = -gui \
	-debugDB \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	-sv_seed $(SEED)

all: compile optimize

$(WORK_DIR):
	vlib $(WORK_DIR)
	vmap work $(WORK_DIR)

compile: $(WORK_DIR) logs
	$(VLOG) $(VLOG_FLAGS) $(RTL_SOURCES) -f sources.f

optimize: compile
	$(VOPT) $(TOP_MODULE) $(VOPT_FLAGS)

sim: optimize
	@echo "=== Running test: $(TEST) (seed: $(SEED)) ==="
	$(VSIM) $(VSIM_FLAGS) $(OPTIMIZED_TOP)

gui: optimize
	$(VSIM) $(VSIM_GUI_FLAGS) $(OPTIMIZED_TOP) &

TESTS = bnn_fcc_base_test \
        bnn_fcc_protocol_stress_test \
        bnn_fcc_reconfig_test \
        bnn_fcc_reset_stress_test \
        bnn_fcc_output_class_test

regress: optimize
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo "--- $$t ---"; \
		$(VSIM) -c -debugDB -voptargs="+acc" \
			+UVM_NO_RELNOTES +UVM_VERBOSITY=UVM_LOW \
			+UVM_TESTNAME=$$t -sv_seed random \
			-do "run -all" $(OPTIMIZED_TOP) > logs/$$t.log 2>&1; \
		if grep -q "TEST PASSED" logs/$$t.log; then \
			echo "  PASSED"; pass=$$((pass+1)); \
		else \
			echo "  FAILED (see logs/$$t.log)"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo "=== $$pass passed, $$fail failed ==="

logs:
	mkdir -p logs

clean:
	rm -rf $(WORK_DIR) transcript vsim.wlf *.db *.dbg *.vstf *.ucdb modelsim.ini logs/

.PHONY: all compile optimize sim gui regress clean logs
