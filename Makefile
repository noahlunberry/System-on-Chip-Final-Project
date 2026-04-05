# Makefile for Questa SystemVerilog/UVM simulation of the bnn_fcc UVM testbench

# Check if Questa tools exist in PATH
ifeq (,$(shell which vsim 2>/dev/null))
$(error "vsim not found in PATH. Please ensure Questa is properly installed and added to PATH")
endif

ifeq (,$(shell which vlog 2>/dev/null))
$(error "vlog not found in PATH. Please ensure Questa is properly installed and added to PATH")
endif

ifeq (,$(shell which vopt 2>/dev/null))
$(error "vopt not found in PATH. Please ensure Questa is properly installed and added to PATH")
endif

# Tool and library configuration
VLOG = vlog
VSIM = vsim
VOPT = vopt

# Project configuration
WORK_DIR = work
SOURCES_FILE = sources.txt
TOP_MODULE = work.bnn_fcc_uvm_tb
OPTIMIZED_TOP = bnn_fcc_uvm_tb_opt

# UVM configuration
UVM_TESTNAME ?= bnn_fcc_single_beat_test
UVM_FLAGS = +UVM_TESTNAME=$(UVM_TESTNAME)

# Common testbench knobs
BASE_DIR ?= $(abspath python)
NUM_TEST_IMAGES ?= 50
VERIFY_MODEL ?= 1
TOGGLE_DATA_OUT_READY ?= 1
CONFIG_VALID_PROBABILITY ?= 1.0
DATA_IN_VALID_PROBABILITY ?= 0.95
DEBUG ?= 0
CLK_PERIOD ?= 10ns
TIMEOUT ?= 100ms

# Questa/UVM source location
VSIM_PATH := $(shell which vsim 2>/dev/null)
VSIM_BIN_DIR := $(patsubst %/,%,$(dir $(VSIM_PATH)))
UVM_SRC ?= $(if $(UVM_HOME),$(UVM_HOME)/src,$(if $(QUESTA_HOME),$(QUESTA_HOME)/verilog_src/uvm-1.2/src,$(if $(MTI_HOME),$(MTI_HOME)/verilog_src/uvm-1.2/src,$(abspath $(VSIM_BIN_DIR)/../verilog_src/uvm-1.2/src))))

ifeq (,$(wildcard $(UVM_SRC)/uvm_macros.svh))
$(error "Could not locate uvm_macros.svh. Set UVM_SRC=/path/to/uvm-1.2/src or UVM_HOME=/path/to/uvm-1.2")
endif

INCDIRS = \
	+incdir+$(UVM_SRC) \
	+incdir+verification \
	+incdir+verification/bnn_uvm

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
	-L uvm \
	-suppress 2275 \
	-timescale "1ns/100ps" \
	+define+UVM_PACKER_MAX_BYTES=1500000 \
	+define+UVM_DISABLE_AUTO_ITEM_RECORDING \
	$(INCDIRS) \
	-work $(WORK_DIR)

# Optimization flags
VOPT_FLAGS = +acc \
	-L uvm \
	-o $(OPTIMIZED_TOP)

# Simulation flags
VSIM_FLAGS = -c \
	-debugDB \
	-L uvm \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	$(TB_GFLAGS) \
	-do "run -all; quit -f"

# GUI simulation flags
VSIM_GUI_FLAGS = -gui \
	-debugDB \
	-L uvm \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	$(UVM_FLAGS) \
	$(TB_GFLAGS)

# Default target
all: compile optimize

# Create work library
$(WORK_DIR):
	vlib $(WORK_DIR)
	vmap work $(WORK_DIR)

# Compile all sources in a single compilation unit
compile: $(WORK_DIR)
	$(VLOG) $(VLOG_FLAGS) -f $(SOURCES_FILE)

# Optimize design
optimize: compile
	$(VOPT) $(TOP_MODULE) $(VOPT_FLAGS)

# Run simulation in command-line mode
sim: optimize
	@if [ "$(UVM_TESTNAME)" = "" ]; then \
		echo "Error: UVM_TESTNAME is not set. Usage: make sim UVM_TESTNAME=<test_name>"; \
		exit 1; \
	fi
	$(VSIM) $(VSIM_FLAGS) $(OPTIMIZED_TOP)

# Open GUI for interactive simulation
gui: optimize
	@if [ "$(UVM_TESTNAME)" = "" ]; then \
		echo "Error: UVM_TESTNAME is not set. Usage: make gui UVM_TESTNAME=<test_name>"; \
		exit 1; \
	fi
	$(VSIM) $(VSIM_GUI_FLAGS) $(OPTIMIZED_TOP) &

# Clean up generated files
clean:
	rm -rf $(WORK_DIR)
	rm -rf transcript
	rm -rf vsim.wlf
	rm -rf *.db
	rm -rf *.dbg
	rm -rf *.vstf
	rm -rf *.ucdb
	rm -rf modelsim.ini

# Print common usage examples
help:
	@echo "Targets: compile optimize sim gui clean"
	@echo "Example CLI run:"
	@echo "  make sim UVM_TESTNAME=bnn_fcc_single_beat_test NUM_TEST_IMAGES=10"
	@echo "Example with explicit UVM source path:"
	@echo "  make sim UVM_SRC=/path/to/uvm-1.2/src"

.PHONY: all compile optimize sim gui clean help
