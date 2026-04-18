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
TOP_MODULE ?= bnn_fcc_uvm_tb
OPTIMIZED_TOP = $(TOP_MODULE)_opt
LEGACY_BNN_TB_TOP ?= bnn_fcc_tb
DEFAULT_WORK_DIR ?= work
LEGACY_WORK_DIR ?= work_legacy
WORK_DIR = $(DEFAULT_WORK_DIR)
ifeq ($(TOP_MODULE),$(LEGACY_BNN_TB_TOP))
WORK_DIR = $(LEGACY_WORK_DIR)
endif
COVERAGE_SWEEP_TOP ?= bnn_fcc_coverage_tb
FIVE_LAYER_TOP ?= bnn_fcc_uvm_five_layer_tb
FINN_SFC_TOP ?= bnn_fcc_uvm_finn_sfc_tb
FINN_LFC_TOP ?= bnn_fcc_uvm_finn_lfc_tb
TEN_HIDDEN_TOP ?= bnn_fcc_uvm_ten_hidden_tb
COVERAGE_SWEEP_TEST ?= bnn_fcc_coverage_sweep_test
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
	$(UVM_TEST_DIR)/bnn_fcc_reconfig_base_test.svh \
	$(UVM_TEST_DIR)/bnn_fcc_coverage_sweep_test.svh, \
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

# Named runtime modes for common workflows. Command-line assignments still win
# because the public knobs below use ?= with these mode-derived defaults.
RUN_MODE ?= default
MODE_DESC := repo default settings
MODE_NUM_TEST_IMAGES := 50
MODE_VERIFY_MODEL := 1
MODE_USE_CUSTOM_TOPOLOGY := 0
MODE_TOGGLE_DATA_OUT_READY := 1
MODE_CONFIG_VALID_PROBABILITY := 0.6
MODE_DATA_IN_VALID_PROBABILITY := 0.75
MODE_DEBUG := 0

ifeq ($(RUN_MODE),stats)
MODE_DESC := performance/statistics settings
MODE_NUM_TEST_IMAGES := 50
MODE_VERIFY_MODEL := 1
MODE_USE_CUSTOM_TOPOLOGY := 0
MODE_TOGGLE_DATA_OUT_READY := 0
MODE_CONFIG_VALID_PROBABILITY := 1.0
MODE_DATA_IN_VALID_PROBABILITY := 1.0
MODE_DEBUG := 0
else ifneq ($(RUN_MODE),default)
$(error "Unknown RUN_MODE '$(RUN_MODE)'. Supported values: default stats")
endif

# Architecture presets for the contest SFC topology. These feed the UVM
# package through compile-time defines so monitors, sequences, and coverage all
# agree on the active stream width.
ARCH_PROFILE ?= contest64
ARCH_PROFILE_DESC := contest baseline: 64-bit input bus, PI=32, PN='{64,32,10}
ARCH_INPUT_BUS_WIDTH := 64
ARCH_PARALLEL_INPUTS := 32
ARCH_PARALLEL_NEURONS := '{64,32,10}

ifeq ($(ARCH_PROFILE),contest64)
ARCH_PROFILE_DESC := contest baseline: 64-bit input bus, PI=32, PN='{64,32,10}
ARCH_INPUT_BUS_WIDTH := 64
ARCH_PARALLEL_INPUTS := 32
ARCH_PARALLEL_NEURONS := '{64,32,10}
else ifeq ($(ARCH_PROFILE),bus64)
ARCH_PROFILE_DESC := contest baseline: 64-bit input bus, PI=32, PN='{64,32,10}
ARCH_INPUT_BUS_WIDTH := 64
ARCH_PARALLEL_INPUTS := 32
ARCH_PARALLEL_NEURONS := '{64,32,10}
else ifeq ($(ARCH_PROFILE),bus128)
ARCH_PROFILE_DESC := 128-bit input bus, PI=64, PN='{64,32,10}
ARCH_INPUT_BUS_WIDTH := 128
ARCH_PARALLEL_INPUTS := 64
ARCH_PARALLEL_NEURONS := '{64,32,10}
else ifeq ($(ARCH_PROFILE),bus256)
ARCH_PROFILE_DESC := 256-bit input bus, PI=128, PN='{64,64,10}
ARCH_INPUT_BUS_WIDTH := 256
ARCH_PARALLEL_INPUTS := 128
ARCH_PARALLEL_NEURONS := '{64,64,10}
else ifeq ($(ARCH_PROFILE),bus512)
ARCH_PROFILE_DESC := 512-bit input bus, PI=128, PN='{128,64,10}
ARCH_INPUT_BUS_WIDTH := 512
ARCH_PARALLEL_INPUTS := 128
ARCH_PARALLEL_NEURONS := '{128,64,10}
else ifeq ($(ARCH_PROFILE),bus1024)
ARCH_PROFILE_DESC := 1024-bit input bus, PI=128, PN='{256,64,10}
ARCH_INPUT_BUS_WIDTH := 1024
ARCH_PARALLEL_INPUTS := 128
ARCH_PARALLEL_NEURONS := '{256,64,10}
else
$(error "Unknown ARCH_PROFILE '$(ARCH_PROFILE)'. Supported values: contest64 bus64 bus128 bus256 bus512 bus1024")
endif

# Testbench runtime configuration
BASE_DIR ?= $(abspath python)
NUM_TEST_IMAGES ?= $(MODE_NUM_TEST_IMAGES)
VERIFY_MODEL ?= $(MODE_VERIFY_MODEL)
USE_CUSTOM_TOPOLOGY ?= $(MODE_USE_CUSTOM_TOPOLOGY)
TOGGLE_DATA_OUT_READY ?= $(MODE_TOGGLE_DATA_OUT_READY)
CONFIG_VALID_PROBABILITY ?= $(MODE_CONFIG_VALID_PROBABILITY)
DATA_IN_VALID_PROBABILITY ?= $(MODE_DATA_IN_VALID_PROBABILITY)
DEBUG ?= $(MODE_DEBUG)
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
LEGACY_TB_LOG_FILE = $(TEST_LOG_DIR)/$(TOP_MODULE).log
LEGACY_TB_COVERAGE_FILE = $(COVERAGE_DIR)/$(TOP_MODULE).ucdb
LEGACY_TB_ARGS = \
	TOP_MODULE=$(LEGACY_BNN_TB_TOP) \
	BASE_DIR=$(BASE_DIR)
SOURCE_FILE ?= sources.txt
LEGACY_SOURCE_FILE ?= sources_legacy_tb.txt
VSIM_COVERAGE_FLAGS = -coverage
VSIM_RUN_DO = coverage save -onexit $(COVERAGE_FILE); run -all
VSIM_GUI_DO = coverage save -onexit $(COVERAGE_FILE)

COMMON_TB_GFLAGS_BASE = \
	-gBASE_DIR=\"$(BASE_DIR)\" \
	-gNUM_TEST_IMAGES=$(NUM_TEST_IMAGES) \
	-gVERIFY_MODEL=$(VERIFY_MODEL) \
	-gUSE_CUSTOM_TOPOLOGY=$(USE_CUSTOM_TOPOLOGY) \
	-gTOGGLE_DATA_OUT_READY=$(TOGGLE_DATA_OUT_READY) \
	-gCONFIG_VALID_PROBABILITY=$(CONFIG_VALID_PROBABILITY) \
	-gDATA_IN_VALID_PROBABILITY=$(DATA_IN_VALID_PROBABILITY) \
	-gDEBUG=$(DEBUG)

COMMON_TB_TIME_GFLAGS = \
	-gCLK_PERIOD=$(CLK_PERIOD) \
	-gTIMEOUT=$(TIMEOUT)

ARCH_VLOG_DEFINES = \
	"+define+BNN_FCC_UVM_INPUT_BUS_WIDTH=$(ARCH_INPUT_BUS_WIDTH)" \
	"+define+BNN_FCC_UVM_PARALLEL_INPUTS=$(ARCH_PARALLEL_INPUTS)" \
	"+define+BNN_FCC_UVM_PARALLEL_NEURONS=$(ARCH_PARALLEL_NEURONS)"

ifeq ($(TOP_MODULE),$(COVERAGE_SWEEP_TOP))
COMMON_TB_GFLAGS = $(COMMON_TB_GFLAGS_BASE)
else ifeq ($(TOP_MODULE),$(LEGACY_BNN_TB_TOP))
COMMON_TB_GFLAGS = \
	-gBASE_DIR=\"$(BASE_DIR)\"
else ifeq ($(TOP_MODULE),$(FIVE_LAYER_TOP))
COMMON_TB_GFLAGS = \
	-gBASE_DIR=\"$(BASE_DIR)\" \
	-gNUM_TEST_IMAGES=$(NUM_TEST_IMAGES) \
	-gVERIFY_MODEL=$(VERIFY_MODEL) \
	-gTOGGLE_DATA_OUT_READY=$(TOGGLE_DATA_OUT_READY) \
	-gCONFIG_VALID_PROBABILITY=$(CONFIG_VALID_PROBABILITY) \
	-gDATA_IN_VALID_PROBABILITY=$(DATA_IN_VALID_PROBABILITY) \
	-gDEBUG=$(DEBUG) \
	$(COMMON_TB_TIME_GFLAGS)
else ifeq ($(TOP_MODULE),$(FINN_SFC_TOP))
COMMON_TB_GFLAGS = \
	-gBASE_DIR=\"$(BASE_DIR)\" \
	-gNUM_TEST_IMAGES=$(NUM_TEST_IMAGES) \
	-gVERIFY_MODEL=$(VERIFY_MODEL) \
	-gTOGGLE_DATA_OUT_READY=$(TOGGLE_DATA_OUT_READY) \
	-gCONFIG_VALID_PROBABILITY=$(CONFIG_VALID_PROBABILITY) \
	-gDATA_IN_VALID_PROBABILITY=$(DATA_IN_VALID_PROBABILITY) \
	-gDEBUG=$(DEBUG) \
	$(COMMON_TB_TIME_GFLAGS)
else ifeq ($(TOP_MODULE),$(FINN_LFC_TOP))
COMMON_TB_GFLAGS = \
	-gBASE_DIR=\"$(BASE_DIR)\" \
	-gNUM_TEST_IMAGES=$(NUM_TEST_IMAGES) \
	-gVERIFY_MODEL=$(VERIFY_MODEL) \
	-gTOGGLE_DATA_OUT_READY=$(TOGGLE_DATA_OUT_READY) \
	-gCONFIG_VALID_PROBABILITY=$(CONFIG_VALID_PROBABILITY) \
	-gDATA_IN_VALID_PROBABILITY=$(DATA_IN_VALID_PROBABILITY) \
	-gDEBUG=$(DEBUG) \
	$(COMMON_TB_TIME_GFLAGS)
else ifeq ($(TOP_MODULE),$(TEN_HIDDEN_TOP))
COMMON_TB_GFLAGS = \
	-gBASE_DIR=\"$(BASE_DIR)\" \
	-gNUM_TEST_IMAGES=$(NUM_TEST_IMAGES) \
	-gVERIFY_MODEL=$(VERIFY_MODEL) \
	-gTOGGLE_DATA_OUT_READY=$(TOGGLE_DATA_OUT_READY) \
	-gCONFIG_VALID_PROBABILITY=$(CONFIG_VALID_PROBABILITY) \
	-gDATA_IN_VALID_PROBABILITY=$(DATA_IN_VALID_PROBABILITY) \
	-gDEBUG=$(DEBUG) \
	$(COMMON_TB_TIME_GFLAGS)
else
COMMON_TB_GFLAGS = $(COMMON_TB_GFLAGS_BASE) $(COMMON_TB_TIME_GFLAGS)
endif

ifeq ($(TOP_MODULE),$(LEGACY_BNN_TB_TOP))
SOURCE_FILE := $(LEGACY_SOURCE_FILE)
endif

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
	$(ARCH_VLOG_DEFINES) \
	+incdir+$(UVM_SRC) \
	+incdir+verification \
	+incdir+verification/bnn_uvm \
	+incdir+verification/bnn_uvm/tests \
	-work $(WORK_DIR)

# Optimization flags (preserve full visibility with +acc)
VOPT_FLAGS = +acc \
	-L $(UVM_LIB) \
	$(COMMON_TB_GFLAGS) \
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
	-do "coverage save -onexit $(COVERAGE_DIR)/$(1).ucdb" \
	$(OPTIMIZED_TOP)
endef

define RUN_LEGACY_TB
$(VSIM) -c \
	$(VSIM_COVERAGE_FLAGS) \
	-debugDB \
	-l $(LEGACY_TB_LOG_FILE) \
	-L $(UVM_LIB) \
	-voptargs="+acc" \
	-do "coverage save -onexit $(LEGACY_TB_COVERAGE_FILE); run -all" \
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
	$(VLOG) $(VLOG_FLAGS) -f $(SOURCE_FILE) $(EXTRA_RTL_SOURCES)

# Optimize design while maintaining full visibility
optimize: compile
	$(VOPT) $(TOP_MODULE) $(VOPT_FLAGS)

# Print the discovered test list used by the regression target.
list-tests:
	@for test in $(UVM_TESTS); do echo $$test; done

# Print the resolved runtime/architecture settings after Makefile mode/profile
# selection so runs are easy to reproduce in reports.
print-config:
	@echo "RUN_MODE=$(RUN_MODE) ($(MODE_DESC))"
	@echo "ARCH_PROFILE=$(ARCH_PROFILE) ($(ARCH_PROFILE_DESC))"
	@echo "INPUT_BUS_WIDTH=$(ARCH_INPUT_BUS_WIDTH)"
	@echo "PARALLEL_INPUTS=$(ARCH_PARALLEL_INPUTS)"
	@echo "PARALLEL_NEURONS=$(ARCH_PARALLEL_NEURONS)"
	@echo "NUM_TEST_IMAGES=$(NUM_TEST_IMAGES)"
	@echo "TOGGLE_DATA_OUT_READY=$(TOGGLE_DATA_OUT_READY)"
	@echo "CONFIG_VALID_PROBABILITY=$(CONFIG_VALID_PROBABILITY)"
	@echo "DATA_IN_VALID_PROBABILITY=$(DATA_IN_VALID_PROBABILITY)"
	@echo "VERIFY_MODEL=$(VERIFY_MODEL)"
	@echo "USE_CUSTOM_TOPOLOGY=$(USE_CUSTOM_TOPOLOGY)"

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

run-legacy-tb: $(COVERAGE_DIR) $(TEST_LOG_DIR)
	@set -e; \
	rm -f "$(LEGACY_TB_LOG_FILE)"; \
	test_status=0; \
	$(call RUN_LEGACY_TB) || test_status=$$?; \
	if [ $$test_status -ne 0 ]; then \
		echo "[FAIL] $(TOP_MODULE) (simulator exit $$test_status, log: $(LEGACY_TB_LOG_FILE))"; \
		exit $$test_status; \
	fi; \
	if [ ! -f "$(LEGACY_TB_LOG_FILE)" ]; then \
		echo "[FAIL] $(TOP_MODULE) (missing log: $(LEGACY_TB_LOG_FILE))"; \
		exit 1; \
	fi; \
	if grep -qiE "FAILED:|\\*\\* Error:|\\*\\* Fatal:" "$(LEGACY_TB_LOG_FILE)"; then \
		echo "[FAIL] $(TOP_MODULE) (see $(LEGACY_TB_LOG_FILE))"; \
		exit 1; \
	fi; \
	if grep -q "SUCCESS:" "$(LEGACY_TB_LOG_FILE)"; then \
		echo "[PASS] $(TOP_MODULE)"; \
	else \
		echo "[FAIL] $(TOP_MODULE) (no SUCCESS banner found in $(LEGACY_TB_LOG_FILE))"; \
		exit 1; \
	fi

# Run simulation in command-line mode
sim: optimize $(COVERAGE_DIR)
	@$(MAKE) --no-print-directory run-test UVM_TESTNAME=$(UVM_TESTNAME)

# Convenience target for the single-run coverage sweep top/testbench.
coverage-sweep:
	@$(MAKE) --no-print-directory sim TOP_MODULE=$(COVERAGE_SWEEP_TOP) UVM_TESTNAME=$(COVERAGE_SWEEP_TEST)

# Simple alias for the one-shot coverage sweep flow.
sim-coverage:
	@$(MAKE) --no-print-directory coverage-sweep RUN_MODE=$(RUN_MODE) ARCH_PROFILE=$(ARCH_PROFILE)

# Convenience target for the deeper 5-total-layer custom-topology smoke test.
sim-five-layer:
	@$(MAKE) --no-print-directory sim TOP_MODULE=bnn_fcc_uvm_five_layer_tb UVM_TESTNAME=bnn_fcc_single_beat_test

# Convenience targets for the fully connected FINN topologies this RTL can represent.
sim-finn-sfc:
	@$(MAKE) --no-print-directory sim TOP_MODULE=$(FINN_SFC_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test

sim-finn-lfc:
	@$(MAKE) --no-print-directory sim TOP_MODULE=$(FINN_LFC_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test

# Convenience target for a very deep FCC stress topology.
sim-ten-hidden:
	@$(MAKE) --no-print-directory sim TOP_MODULE=$(TEN_HIDDEN_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test

sim-finn-topologies:
	@set -e; \
	echo "=== Running FINN SFC topology ==="; \
	$(MAKE) --no-print-directory sim TOP_MODULE=$(FINN_SFC_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test; \
	echo "=== Running FINN LFC topology ==="; \
	$(MAKE) --no-print-directory sim TOP_MODULE=$(FINN_LFC_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test

sim-topology-sweep:
	@set -e; \
	echo "=== Running FINN SFC topology ==="; \
	$(MAKE) --no-print-directory sim TOP_MODULE=$(FINN_SFC_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test; \
	echo "=== Running FINN LFC topology ==="; \
	$(MAKE) --no-print-directory sim TOP_MODULE=$(FINN_LFC_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test; \
	echo "=== Running custom 5-total-layer topology ==="; \
	$(MAKE) --no-print-directory sim TOP_MODULE=$(FIVE_LAYER_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test; \
	echo "=== Running custom 10-hidden-layer topology ==="; \
	$(MAKE) --no-print-directory sim TOP_MODULE=$(TEN_HIDDEN_TOP) UVM_TESTNAME=bnn_fcc_single_beat_test

# Run the one-shot coverage sweep and emit a single text coverage report.
coverage-sweep-report:
	@$(MAKE) --no-print-directory coverage-sweep
	@$(MAKE) --no-print-directory reportcov UVM_TESTNAME=$(COVERAGE_SWEEP_TEST)

# Convenience target for the user-requested "statistics" mode: fixed 50-image
# run, no output backpressure, and 100% input/config valid probability.
stats:
	@$(MAKE) --no-print-directory print-config RUN_MODE=stats ARCH_PROFILE=$(ARCH_PROFILE) UVM_TESTNAME=$(UVM_TESTNAME)
	@$(MAKE) --no-print-directory sim RUN_MODE=stats ARCH_PROFILE=$(ARCH_PROFILE) UVM_TESTNAME=$(UVM_TESTNAME)

# Same statistics mode, but for the single-run coverage top.
coverage-sweep-stats:
	@$(MAKE) --no-print-directory print-config RUN_MODE=stats ARCH_PROFILE=$(ARCH_PROFILE)
	@$(MAKE) --no-print-directory coverage-sweep RUN_MODE=stats ARCH_PROFILE=$(ARCH_PROFILE)

# Common contest/performance architecture presets.
stats-bus64:
	@$(MAKE) --no-print-directory print-config RUN_MODE=stats ARCH_PROFILE=contest64 UVM_TESTNAME=$(UVM_TESTNAME)
	@$(MAKE) --no-print-directory sim RUN_MODE=stats ARCH_PROFILE=contest64 UVM_TESTNAME=$(UVM_TESTNAME)

stats-bus128:
	@$(MAKE) --no-print-directory print-config RUN_MODE=stats ARCH_PROFILE=bus128 UVM_TESTNAME=$(UVM_TESTNAME)
	@$(MAKE) --no-print-directory sim RUN_MODE=stats ARCH_PROFILE=bus128 UVM_TESTNAME=$(UVM_TESTNAME)

stats-bus256:
	@$(MAKE) --no-print-directory print-config RUN_MODE=stats ARCH_PROFILE=bus256 UVM_TESTNAME=$(UVM_TESTNAME)
	@$(MAKE) --no-print-directory sim RUN_MODE=stats ARCH_PROFILE=bus256 UVM_TESTNAME=$(UVM_TESTNAME)

stats-bus512:
	@$(MAKE) --no-print-directory print-config RUN_MODE=stats ARCH_PROFILE=bus512 UVM_TESTNAME=$(UVM_TESTNAME)
	@$(MAKE) --no-print-directory sim RUN_MODE=stats ARCH_PROFILE=bus512 UVM_TESTNAME=$(UVM_TESTNAME)

stats-bus1024:
	@$(MAKE) --no-print-directory print-config RUN_MODE=stats ARCH_PROFILE=bus1024 UVM_TESTNAME=$(UVM_TESTNAME)
	@$(MAKE) --no-print-directory sim RUN_MODE=stats ARCH_PROFILE=bus1024 UVM_TESTNAME=$(UVM_TESTNAME)

# Convenience target for the original non-UVM contest testbench using the
# parameter values checked into verification/bnn_fcc_tb.sv.
sim-original-tb:
	@$(MAKE) --no-print-directory optimize $(LEGACY_TB_ARGS)
	@$(MAKE) --no-print-directory run-legacy-tb $(LEGACY_TB_ARGS)

# Backward-compatible alias for the earlier target name.
sim-original-tb-stats:
	@$(MAKE) --no-print-directory sim-original-tb $(LEGACY_TB_ARGS)

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
	@echo "                                      Optional: RUN_MODE=default|stats ARCH_PROFILE=contest64|bus128|bus256|bus512|bus1024"
	@echo "make sim-<test_name>                  Run one test in batch mode"
	@echo "make gui UVM_TESTNAME=<test_name>     Open one test in the GUI"
	@echo "make gui-<test_name>                  Open one test in the GUI"
	@echo "make list-tests                       Show discovered regression tests"
	@echo "make print-config                     Show the resolved mode/profile settings"
	@echo "make stats UVM_TESTNAME=<test_name>   Run one test in statistics mode"
	@echo "make stats-bus64                      Run statistics mode for the 64-bit contest baseline"
	@echo "make stats-bus128                     Run statistics mode for the 128-bit profile"
	@echo "make stats-bus256                     Run statistics mode for the 256-bit profile"
	@echo "make stats-bus512                     Run statistics mode for the 512-bit profile"
	@echo "make stats-bus1024                    Run statistics mode for the 1024-bit profile"
	@echo "make sim-original-tb                 Run the original bnn_fcc_tb with its checked-in parameter values"
	@echo "make sim-original-tb-stats           Alias for make sim-original-tb"
	@echo "make regress                          Run all discovered tests and merge coverage"
	@echo "                                      Per-test logs are written under $(TEST_LOG_DIR)"
	@echo "make sim-coverage                     Run the one-shot coverage sweep top/testbench"
	@echo "make coverage-sweep                   Run the one-shot coverage sweep top/testbench"
	@echo "make coverage-sweep-stats             Run the one-shot coverage sweep in statistics mode"
	@echo "make sim-finn-sfc                    Run the FINN SFC fully connected topology"
	@echo "make sim-finn-lfc                    Run the FINN LFC fully connected topology"
	@echo "make sim-finn-topologies             Run the supported FINN fully connected topology sweep"
	@echo "make sim-five-layer                  Run the 5-total-layer custom-topology smoke test"
	@echo "make sim-ten-hidden                  Run the custom 10-hidden-layer stress topology"
	@echo "make sim-topology-sweep              Run FINN FC topologies plus the custom deep topologies"
	@echo "make coverage-sweep-report            Run the one-shot coverage sweep and write one report"
	@echo "make viewcov UVM_TESTNAME=<test_name> Open one test's UCDB"
	@echo "make viewcov-merged                   Open merged regression coverage"
	@echo "make reportcov UVM_TESTNAME=<test_name> Generate a text report for one UCDB"
	@echo "make reportcov-merged                 Generate a text report for merged regression coverage"

# Clean up generated files
clean:
	rm -rf $(WORK_DIR)
	rm -rf $(DEFAULT_WORK_DIR)
	rm -rf $(LEGACY_WORK_DIR)
	rm -rf transcript
	rm -rf vsim.wlf
	rm -rf *.db
	rm -rf *.dbg
	rm -rf *.vstf
	rm -rf *.ucdb
	rm -rf $(COVERAGE_DIR)
	rm -rf modelsim.ini

.PHONY: all compile optimize list-tests print-config run-test run-legacy-tb sim sim-% sim-coverage stats stats-bus64 stats-bus128 stats-bus256 stats-bus512 stats-bus1024 sim-original-tb sim-original-tb-stats sim-five-layer sim-ten-hidden sim-finn-sfc sim-finn-lfc sim-finn-topologies sim-topology-sweep coverage-sweep coverage-sweep-stats coverage-sweep-report gui gui-% regress mergecov reportcov reportcov-merged viewcov viewcov-merged help clean
