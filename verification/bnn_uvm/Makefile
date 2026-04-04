# =============================================================================
# Makefile for BNN FCC UVM Testbench
# =============================================================================
# Run from: verification/bnn_uvm/  (this directory)
#
# NOTE: This flow assumes GNU make on a Linux shell with Questa/ModelSim on
#       PATH. The repo uses lowercase rtl/ on case-sensitive filesystems, and
#       the default BASE_DIR below points back to ../../python so the testbench
#       can find its model data when launched from here.
#
# USAGE:
#   make                              # compile + optimize
#   make sim TEST=<name>              # run a specific test
#   make gui TEST=<name>              # open Questa GUI
#   make regress                      # run all 5 tests
#   make clean                        # remove generated files
# =============================================================================

VLIB = vlib
VMAP = vmap
VLOG = vlog
VSIM = vsim
VOPT = vopt

ROOT_DIR = ../..
RTL_DIR = $(ROOT_DIR)/rtl
BASE_DIR ?= $(ROOT_DIR)/python
USE_VOPT ?= 1
UVM_VERSION ?= 1.2
UVM_LIB ?= mtiUvm
UVM_SRC ?= $(shell dirname "$$(command -v $(VLOG) 2>/dev/null)")/../verilog_src/uvm-$(UVM_VERSION)/src
UVM_MACROS = $(UVM_SRC)/uvm_macros.svh
WORK_DIR = work
TOP_MODULE = bnn_fcc_uvm_tb
OPTIMIZED_TOP = $(TOP_MODULE)_opt
ELAB_TOP = work.$(TOP_MODULE)
SIM_TOP = work.$(OPTIMIZED_TOP)
RUN_TOP = $(if $(filter 1,$(USE_VOPT)),$(SIM_TOP),$(ELAB_TOP))
RUN_PARAM_FLAGS = $(if $(filter 1,$(USE_VOPT)),,$(PARAM_FLAGS))

TEST ?= bnn_fcc_base_test
SEED ?= random
UVM_VERBOSITY ?= UVM_MEDIUM
UVM_FLAGS = +UVM_TESTNAME=$(TEST)
PARAM_FLAGS = "-gBASE_DIR=\"$(BASE_DIR)\""

# ---- RTL sources (bottom-up compile order) ----
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
	-L $(UVM_LIB) \
	-lint \
	+acc=pr \
	-suppress 2275 \
	-timescale "1ns/1ps" \
	+define+UVM_PACKER_MAX_BYTES=1500000 \
	+define+UVM_DISABLE_AUTO_ITEM_RECORDING \
	+incdir+$(UVM_SRC) \
	-work $(WORK_DIR)

VOPT_FLAGS = -L $(UVM_LIB) +acc -o $(OPTIMIZED_TOP)

VSIM_COMMON_FLAGS = \
	-L $(UVM_LIB) \
	-debugDB \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=$(UVM_VERBOSITY) \
	$(UVM_FLAGS) \
	-sv_seed $(SEED)

VSIM_FLAGS = -c \
	$(VSIM_COMMON_FLAGS) \
	-do "run -all; quit -f"

VSIM_GUI_FLAGS = -gui \
	$(VSIM_COMMON_FLAGS)

all: compile optimize

$(WORK_DIR):
	$(VLIB) $(WORK_DIR)
	$(VMAP) work $(WORK_DIR)

compile: $(WORK_DIR) logs
	@test -f "$(UVM_MACROS)" || (echo "UVM headers not found at $(UVM_MACROS). Set UVM_SRC=/path/to/verilog_src/uvm-$(UVM_VERSION)/src"; exit 1)
	$(VLOG) $(VLOG_FLAGS) $(RTL_SOURCES) -f sources.f

optimize: compile
ifeq ($(USE_VOPT),1)
	$(VOPT) $(PARAM_FLAGS) $(ELAB_TOP) $(VOPT_FLAGS)
else
	@echo "Skipping standalone vopt (USE_VOPT=0)"
endif

sim: optimize
	@echo "=== Running test: $(TEST) (seed: $(SEED)) ==="
	$(VSIM) $(RUN_PARAM_FLAGS) $(VSIM_FLAGS) $(RUN_TOP)

gui: optimize
	$(VSIM) $(RUN_PARAM_FLAGS) $(VSIM_GUI_FLAGS) $(RUN_TOP) &

TESTS = bnn_fcc_base_test \
        bnn_fcc_protocol_stress_test \
        bnn_fcc_reconfig_test \
        bnn_fcc_reset_stress_test \
        bnn_fcc_output_class_test

regress: optimize logs
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo "--- $$t ---"; \
		$(VSIM) $(RUN_PARAM_FLAGS) -c -debugDB -voptargs="+acc" \
			+UVM_NO_RELNOTES +UVM_VERBOSITY=UVM_LOW \
			+UVM_TESTNAME=$$t -sv_seed random \
			-do "run -all; quit -f" $(RUN_TOP) > logs/$$t.log 2>&1; \
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
	rm -rf $(WORK_DIR) transcript vsim.wlf *.db *.dbg *.vstf *.ucdb logs/

.PHONY: all compile optimize sim gui regress clean logs
