# Makefile for Questa SystemVerilog simulation with UVM

# Allow the user to point make directly at a Questa bin directory. On the EDA
# lab machines this default path avoids having to manually prepend PATH for
# every invocation, but it is only used if the directory actually exists.
DEFAULT_QUESTA_BIN_DIR := /apps/reconfig/tools/siemens/questasim/2023.3/linux_x86_64
ifeq ($(wildcard $(DEFAULT_QUESTA_BIN_DIR)/vsim),$(DEFAULT_QUESTA_BIN_DIR)/vsim)
QUESTA_BIN_DIR ?= $(DEFAULT_QUESTA_BIN_DIR)
endif

# Resolve the simulator path without assuming it is already on the shell PATH.
ifneq ($(strip $(QUESTA_BIN_DIR)),)
VSIM_PATH := $(wildcard $(QUESTA_BIN_DIR)/vsim)
endif

# Check if vsim exists in PATH
ifeq ($(strip $(VSIM_PATH)),)
VSIM_PATH := $(shell which vsim 2>/dev/null)
endif

ifeq ($(strip $(VSIM_PATH)),)
$(error "vsim not found in PATH. Please ensure Questa is properly installed and added to PATH")
endif

export PATH := $(patsubst %/,%,$(dir $(VSIM_PATH))):$(PATH)

# Tool and library configuration
VLOG = vlog
VSIM = vsim
VOPT = vopt
VCOVER = vcover

# Project configuration
WORK_DIR = work
TOP_MODULE = bnn_fcc_uvm_tb
OPTIMIZED_TOP = $(TOP_MODULE)_opt
# Unused RTL moved under rtl/unused/.
# EXTRA_RTL_SOURCES = rtl/unused/fifo_vw.sv
EXTRA_RTL_SOURCES =

# UVM configuration
UVM_TESTNAME ?= bnn_fcc_single_beat_test
UVM_FLAGS = +UVM_TESTNAME=$(UVM_TESTNAME)
UVM_TEST_DIR ?= verification/bnn_uvm/tests
# Discover concrete UVM tests from the checked-in test files so regressions
# automatically stay in sync as new tests are added.
UVM_TEST_FILES := $(sort $(wildcard $(UVM_TEST_DIR)/bnn_fcc_*_test.svh))
UVM_TESTS ?= $(basename $(notdir $(filter-out \
	$(UVM_TEST_DIR)/bnn_fcc_reconfig_base_test.svh, \
	$(UVM_TEST_FILES))))

# Questa/UVM configuration
# Default to the built-in Questa UVM that matches the server log
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
USE_CUSTOM_TOPOLOGY ?= 0
TOGGLE_DATA_OUT_READY ?= 1
CONFIG_VALID_PROBABILITY ?= 0.6
DATA_IN_VALID_PROBABILITY ?= 0.75
DEBUG ?= 0
CLK_PERIOD ?= 10ns
TIMEOUT ?= 100ms

# Functional coverage configuration
COVERAGE_DIR ?= coverage
TEST_LOG_DIR ?= $(COVERAGE_DIR)/logs
COVERAGE_FILE = $(COVERAGE_DIR)/$(UVM_TESTNAME).ucdb
TEST_LOG_FILE = $(TEST_LOG_DIR)/$(UVM_TESTNAME).log
MERGED_COVERAGE_FILE = $(COVERAGE_DIR)/regression_merged.ucdb
CURRENT_COVERAGE_REPORT = $(COVERAGE_DIR)/$(UVM_TESTNAME)_coverage.txt
MERGED_COVERAGE_REPORT = $(COVERAGE_DIR)/regression_coverage.txt
VSIM_COVERAGE_FLAGS = -coverage
VSIM_RUN_DO = coverage save -onexit $(COVERAGE_FILE); run -all
VSIM_GUI_DO = coverage save -onexit $(COVERAGE_FILE)

COMMON_TB_GFLAGS = \
	-gBASE_DIR=\"$(BASE_DIR)\" \
	-gNUM_TEST_IMAGES=$(NUM_TEST_IMAGES) \
	-gVERIFY_MODEL=$(VERIFY_MODEL) \
	-gUSE_CUSTOM_TOPOLOGY=$(USE_CUSTOM_TOPOLOGY) \
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
	+incdir+verification/bnn_uvm/tests \
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
	$(COMMON_TB_GFLAGS) \
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
	$(COMMON_TB_GFLAGS) \
	-do "$(VSIM_GUI_DO)"

define RUN_BATCH_TEST
$(VSIM) -c \
	$(VSIM_COVERAGE_FLAGS) \
	-debugDB \
	-l $(TEST_LOG_DIR)/$(1).log \
	-L $(UVM_LIB) \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	+UVM_TESTNAME=$(1) \
	$(COMMON_TB_GFLAGS) \
	-do "coverage save -onexit $(COVERAGE_DIR)/$(1).ucdb; run -all" \
	$(OPTIMIZED_TOP)
endef

define RUN_GUI_TEST
$(VSIM) -gui \
	$(VSIM_COVERAGE_FLAGS) \
	-debugDB \
	-L $(UVM_LIB) \
	-voptargs="+acc" \
	+UVM_NO_RELNOTES \
	+UVM_VERBOSITY=UVM_MEDIUM \
	+UVM_TESTNAME=$(1) \
	$(COMMON_TB_GFLAGS) \
	-do "coverage save -onexit $(COVERAGE_DIR)/$(1).ucdb" \
	$(OPTIMIZED_TOP)
endef

# Default target
all: compile optimize

# Create work library
$(WORK_DIR):
	vlib $(WORK_DIR)
	vmap work $(WORK_DIR)

$(COVERAGE_DIR):
	mkdir -p $(COVERAGE_DIR)

$(TEST_LOG_DIR):
	mkdir -p $(TEST_LOG_DIR)

# Read sources from file and compile
compile: $(WORK_DIR)
	$(VLOG) $(VLOG_FLAGS) -f sources.txt $(EXTRA_RTL_SOURCES)

# Optimize design while maintaining full visibility
optimize: compile
	$(VOPT) $(TOP_MODULE) $(VOPT_FLAGS)

# Print the discovered test list used by the regression target.
list-tests:
	@for test in $(UVM_TESTS); do echo $$test; done

# Internal helper that runs exactly one test using the already optimized image.
run-test: $(COVERAGE_DIR) $(TEST_LOG_DIR)
	@if [ "$(UVM_TESTNAME)" = "" ]; then \
		echo "Error: UVM_TESTNAME is not set. Usage: make sim UVM_TESTNAME=<test_name>"; \
		exit 1; \
	fi
	@set -e; \
	rm -f "$(TEST_LOG_FILE)"; \
	test_status=0; \
	$(call RUN_BATCH_TEST,$(UVM_TESTNAME)) || test_status=$$?; \
	if [ $$test_status -ne 0 ]; then \
		echo "[FAIL] $(UVM_TESTNAME) (simulator exit $$test_status, log: $(TEST_LOG_FILE))"; \
		exit $$test_status; \
	fi; \
	if [ ! -f "$(TEST_LOG_FILE)" ]; then \
		echo "[FAIL] $(UVM_TESTNAME) (missing log: $(TEST_LOG_FILE))"; \
		exit 1; \
	fi; \
	if grep -q "TEST FAILED" "$(TEST_LOG_FILE)"; then \
		echo "[FAIL] $(UVM_TESTNAME) (see $(TEST_LOG_FILE))"; \
		exit 1; \
	fi; \
	if grep -q "TEST PASSED" "$(TEST_LOG_FILE)"; then \
		echo "[PASS] $(UVM_TESTNAME)"; \
	else \
		echo "[FAIL] $(UVM_TESTNAME) (no TEST PASSED banner found in $(TEST_LOG_FILE))"; \
		exit 1; \
	fi

# Run simulation in command-line mode
sim: optimize $(COVERAGE_DIR)
	@$(MAKE) --no-print-directory run-test UVM_TESTNAME=$(UVM_TESTNAME)

# Convenience target: make sim-bnn_fcc_single_beat_test
sim-%: optimize $(COVERAGE_DIR)
	@$(MAKE) --no-print-directory run-test UVM_TESTNAME=$*

# Open GUI for interactive simulation
gui: optimize $(COVERAGE_DIR)
	@if [ "$(UVM_TESTNAME)" = "" ]; then \
		echo "Error: UVM_TESTNAME is not set. Usage: make gui UVM_TESTNAME=<test_name>"; \
		exit 1; \
	fi
	$(call RUN_GUI_TEST,$(UVM_TESTNAME)) &

# Convenience target: make gui-bnn_fcc_single_beat_test
gui-%: optimize $(COVERAGE_DIR)
	$(call RUN_GUI_TEST,$*) &

# Run the discovered regression list and immediately merge/report coverage.
regress: optimize $(COVERAGE_DIR) $(TEST_LOG_DIR)
	@set -u; \
	passed=0; failed=0; total=0; \
	for test in $(UVM_TESTS); do \
		total=$$((total + 1)); \
		echo "=== Running $$test ==="; \
		if $(MAKE) --no-print-directory run-test UVM_TESTNAME=$$test; then \
			passed=$$((passed + 1)); \
		else \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	echo "=== Regression summary: $$passed/$$total tests passed, $$failed failed ==="; \
	if [ $$failed -ne 0 ]; then \
		echo "Per-test logs are in $(TEST_LOG_DIR)"; \
		exit 1; \
	fi; \
	$(MAKE) --no-print-directory mergecov; \
	$(MAKE) --no-print-directory reportcov-merged

# Merge all per-test UCDBs from the discovered regression list.
mergecov: $(COVERAGE_DIR)
	@set -e; \
	for test in $(UVM_TESTS); do \
		if [ ! -f "$(COVERAGE_DIR)/$$test.ucdb" ]; then \
			echo "Error: Missing coverage file $(COVERAGE_DIR)/$$test.ucdb"; \
			echo "Run 'make regress' or 'make sim-<test>' first."; \
			exit 1; \
		fi; \
	done
	$(VCOVER) merge $(MERGED_COVERAGE_FILE) $(foreach test,$(UVM_TESTS),$(COVERAGE_DIR)/$(test).ucdb)

# Generate a text report for one test's UCDB.
reportcov:
	@if [ ! -f "$(COVERAGE_FILE)" ]; then \
		echo "Error: Coverage database not found at $(COVERAGE_FILE). Run 'make sim UVM_TESTNAME=$(UVM_TESTNAME)' first."; \
		exit 1; \
	fi
	$(VCOVER) report -details -output $(CURRENT_COVERAGE_REPORT) $(COVERAGE_FILE)
	@echo "Wrote $(CURRENT_COVERAGE_REPORT)"

# Generate a merged regression coverage report.
reportcov-merged: mergecov
	$(VCOVER) report -details -output $(MERGED_COVERAGE_REPORT) $(MERGED_COVERAGE_FILE)
	@echo "Wrote $(MERGED_COVERAGE_REPORT)"

# Open a saved functional coverage database
viewcov:
	@if [ ! -f "$(COVERAGE_FILE)" ]; then \
		echo "Error: Coverage database not found at $(COVERAGE_FILE). Run 'make sim UVM_TESTNAME=$(UVM_TESTNAME)' first."; \
		exit 1; \
	fi
	$(VSIM) -viewcov $(COVERAGE_FILE)

# Open the merged regression coverage database in the GUI coverage viewer.
viewcov-merged: mergecov
	$(VSIM) -viewcov $(MERGED_COVERAGE_FILE)

# Quick usage summary for the main workflows.
help:
	@echo "make sim UVM_TESTNAME=<test_name>     Run one test in batch mode"
	@echo "make sim-<test_name>                  Run one test in batch mode"
	@echo "make gui UVM_TESTNAME=<test_name>     Open one test in the GUI"
	@echo "make gui-<test_name>                  Open one test in the GUI"
	@echo "make list-tests                       Show discovered regression tests"
	@echo "make regress                          Run all discovered tests and merge coverage"
	@echo "                                      Per-test logs are written under $(TEST_LOG_DIR)"
	@echo "make viewcov UVM_TESTNAME=<test_name> Open one test's UCDB"
	@echo "make viewcov-merged                   Open merged regression coverage"
	@echo "make reportcov UVM_TESTNAME=<test_name> Generate a text report for one UCDB"
	@echo "make reportcov-merged                 Generate a text report for merged regression coverage"

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

.PHONY: all compile optimize list-tests run-test sim sim-% gui gui-% regress mergecov reportcov reportcov-merged viewcov viewcov-merged help clean
