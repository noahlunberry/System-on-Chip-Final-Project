# Makefile for Questa SystemVerilog simulation with UVM

# Check if vsim exists in PATH
ifeq (,$(shell which vsim 2>/dev/null))
$(error "vsim not found in PATH. Please ensure Questa is properly installed and added to PATH")
endif

# Tool and library configuration
VLOG = vlog
VSIM = vsim
VOPT = vopt

# Project configuration
WORK_DIR = work
TOP_MODULE = bnn_fcc_uvm_tb
OPTIMIZED_TOP = $(TOP_MODULE)_opt

# UVM configuration
UVM_TESTNAME ?= bnn_fcc_single_beat_test
UVM_FLAGS = +UVM_TESTNAME=$(UVM_TESTNAME)

# Questa/UVM configuration
# Default to the built-in Questa UVM that matches the server log
VSIM_PATH := $(shell which vsim 2>/dev/null)
VSIM_BIN_DIR := $(patsubst %/,%,$(dir $(VSIM_PATH)))
QUESTA_HOME ?= $(abspath $(VSIM_BIN_DIR)/..)
UVM_VERSION ?= 1.1d
UVM_LIB ?= mtiUvm
UVM_SRC ?= $(QUESTA_HOME)/verilog_src/uvm-$(UVM_VERSION)/src

ifeq (,$(wildcard $(UVM_SRC)/uvm_macros.svh))
$(error "uvm_macros.svh not found. Override UVM_SRC=/path/to/uvm-<version>/src")
endif

# Testbench runtime configuration
BASE_DIR ?= $(abspath python)
NUM_TEST_IMAGES ?= 50
VERIFY_MODEL ?= 1
TOGGLE_DATA_OUT_READY ?= 1
CONFIG_VALID_PROBABILITY ?= 1.0
DATA_IN_VALID_PROBABILITY ?= 0.95
DEBUG ?= 0
CLK_PERIOD ?= 10ns
TIMEOUT ?= 100ms

# Functional coverage configuration
COVERAGE_DIR ?= coverage
COVERAGE_FILE = $(COVERAGE_DIR)/$(UVM_TESTNAME).ucdb
VSIM_COVERAGE_FLAGS = -coverage
VSIM_RUN_DO = coverage save -onexit $(COVERAGE_FILE); run -all
VSIM_GUI_DO = coverage save -onexit $(COVERAGE_FILE)

TB_GFLAGS = \
	-gBASE_DIR=\"$(BASE_DIR)\" \
	-gNUM_TEST_IMAGES=$(NUM_TEST_IMAGES) \
	-gVERIFY_MODEL=$(VERIFY_MODEL) \
	-gTOGGLE_DATA_OUT_READY=$(TOGGLE_DATA_OUT_READY) \
	-gCONFIG_VALID_PROBABILITY=$(CONFIG_VALID_PROBABILITY) \
	-gDATA_IN_VALID_PROBABILITY=$(DATA_IN_VALID_PROBABILITY) \
	-gDEBUG=$(DEBUG) \
	-gCLK_PERIOD=$(CLK_PERIOD) \
	-gTIMEOUT=$(TIMEOUT)

# Compilation flags
VLOG_FLAGS = -sv \
	-mfcu \
	-lint \
	+acc=pr \
	-L $(UVM_LIB) \
	-suppress 2275 \
	-timescale "1ns/100ps" \
	+define+UVM_PACKER_MAX_BYTES=1500000 \
	+define+UVM_DISABLE_AUTO_ITEM_RECORDING \
	+incdir+$(UVM_SRC) \
	+incdir+verification \
	+incdir+verification/bnn_uvm \
	-work $(WORK_DIR)

# Optimization flags (preserve full visibility with +acc)
VOPT_FLAGS = +acc \
	-L $(UVM_LIB) \
	-o $(OPTIMIZED_TOP)

# Simulation flags
VSIM_FLAGS = -c \
	$(VSIM_COVERAGE_FLAGS) \
	-debugDB \
	-L $(UVM_LIB) \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	$(TB_GFLAGS) \
	-do "$(VSIM_RUN_DO)"

# GUI simulation flags
VSIM_GUI_FLAGS = -gui \
	$(VSIM_COVERAGE_FLAGS) \
	-debugDB \
	-L $(UVM_LIB) \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	$(TB_GFLAGS) \
	-do "$(VSIM_GUI_DO)"

# Default target
all: compile optimize

# Create work library
$(WORK_DIR):
	vlib $(WORK_DIR)
	vmap work $(WORK_DIR)

$(COVERAGE_DIR):
	mkdir -p $(COVERAGE_DIR)

# Read sources from file and compile
compile: $(WORK_DIR)
	$(VLOG) $(VLOG_FLAGS) -f sources.txt

# Optimize design while maintaining full visibility
optimize: compile
	$(VOPT) $(TOP_MODULE) $(VOPT_FLAGS)

# Run simulation in command-line mode
sim: optimize $(COVERAGE_DIR)
	@if [ "$(UVM_TESTNAME)" = "" ]; then \
		echo "Error: UVM_TESTNAME is not set. Usage: make sim UVM_TESTNAME=<test_name>"; \
		exit 1; \
	fi
	$(VSIM) $(VSIM_FLAGS) $(OPTIMIZED_TOP)

# Open GUI for interactive simulation
gui: optimize $(COVERAGE_DIR)
	@if [ "$(UVM_TESTNAME)" = "" ]; then \
		echo "Error: UVM_TESTNAME is not set. Usage: make gui UVM_TESTNAME=<test_name>"; \
		exit 1; \
	fi
	$(VSIM) $(VSIM_GUI_FLAGS) $(OPTIMIZED_TOP) &

# Open a saved functional coverage database
viewcov:
	@if [ ! -f "$(COVERAGE_FILE)" ]; then \
		echo "Error: Coverage database not found at $(COVERAGE_FILE). Run 'make sim UVM_TESTNAME=$(UVM_TESTNAME)' first."; \
		exit 1; \
	fi
	$(VSIM) -viewcov $(COVERAGE_FILE)

# Clean up generated files
clean:
	rm -rf $(WORK_DIR)
	rm -rf transcript
	rm -rf vsim.wlf
	rm -rf *.db
	rm -rf *.dbg
	rm -rf *.vstf
	rm -rf *.ucdb
	rm -rf $(COVERAGE_DIR)
	rm -rf modelsim.ini

.PHONY: all compile optimize sim gui viewcov clean
