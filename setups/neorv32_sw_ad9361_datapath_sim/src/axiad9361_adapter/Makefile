#==============================================================================
# Makefile
#
# Build automation for AXI AD9361 Adapter HLS IP
# Compatible with Vitis HLS 2025.2
#
# Prerequisites:
#   - Vitis 2025.2 installed and in PATH
#   - On Linux: source settings64.sh
#   - On Windows: use from Vitis command prompt
#
# Usage:
#   make csim      - Run C simulation
#   make csynth    - Run C synthesis
#   make cosim     - Run co-simulation
#   make package   - Export IP to Vivado IP catalog format
#   make all       - Run csim, csynth, and package
#   make clean     - Remove build artifacts
#
# Reference: UG1399 - Vitis HLS User Guide (2025.2)
#==============================================================================

# Project settings
PROJECT_NAME := axi_ad9361_adapter
TOP_FUNCTION := axi_ad9361_adapter
PART := xcau15p-ffvb676-2-e
CLOCK_PERIOD := 10ns

# Directories
WORK_DIR := work
IP_OUTPUT_DIR := ../../../hls_ip
CONFIG_FILE := axi_ad9361_adapter.cfg

# Source files
SRC_FILES := axi_ad9361_adapter.cpp axi_ad9361_adapter.hpp
TB_FILES := axi_ad9361_adapter_tb.cpp

# Vitis HLS tools
VITIS_RUN := vitis-run
VPP := v++

# Tool options
COMMON_OPTS := --mode hls --config $(CONFIG_FILE) --work_dir $(WORK_DIR)

#==============================================================================
# Targets
#==============================================================================

.PHONY: all csim csynth cosim package clean help

# Default target
all: csim csynth package

# C Simulation
csim: $(SRC_FILES) $(TB_FILES) $(CONFIG_FILE)
	@echo "=============================================="
	@echo "[CSIM] Running C Simulation..."
	@echo "=============================================="
	$(VITIS_RUN) --csim $(COMMON_OPTS)
	@echo "C Simulation complete."

# C Synthesis
csynth: $(SRC_FILES) $(CONFIG_FILE)
	@echo "=============================================="
	@echo "[CSYNTH] Running C Synthesis..."
	@echo "=============================================="
	$(VPP) --compile $(COMMON_OPTS)
	@echo "C Synthesis complete."

# Co-Simulation (RTL simulation)
cosim: csynth $(TB_FILES)
	@echo "=============================================="
	@echo "[COSIM] Running Co-Simulation..."
	@echo "=============================================="
	$(VITIS_RUN) --cosim $(COMMON_OPTS)
	@echo "Co-Simulation complete."

# Package/Export IP
package: csynth
	@echo "=============================================="
	@echo "[PACKAGE] Exporting IP..."
	@echo "=============================================="
	$(VPP) --package $(COMMON_OPTS)
	@echo ""
	@echo "Copying IP to output directory..."
	@mkdir -p $(IP_OUTPUT_DIR)
	@find $(WORK_DIR) -name "*.zip" -exec cp -v {} $(IP_OUTPUT_DIR)/ \;
	@echo ""
	@echo "IP Export complete."
	@echo "IP available at: $(IP_OUTPUT_DIR)"

# Clean build artifacts
clean:
	@echo "=============================================="
	@echo "[CLEAN] Removing build artifacts..."
	@echo "=============================================="
	rm -rf $(WORK_DIR)
	rm -rf *.log
	rm -rf vitis_hls.log
	@echo "Clean complete."

# Help
help:
	@echo "=============================================="
	@echo "AXI AD9361 Adapter HLS Build System"
	@echo "=============================================="
	@echo ""
	@echo "Available targets:"
	@echo "  make csim      - Run C simulation"
	@echo "  make csynth    - Run C synthesis"
	@echo "  make cosim     - Run co-simulation (RTL)"
	@echo "  make package   - Export IP for Vivado"
	@echo "  make all       - Run csim, csynth, package"
	@echo "  make clean     - Remove build artifacts"
	@echo "  make help      - Show this help message"
	@echo ""
	@echo "Configuration:"
	@echo "  Part:          $(PART)"
	@echo "  Clock:         $(CLOCK_PERIOD)"
	@echo "  Top Function:  $(TOP_FUNCTION)"
	@echo "  Work Dir:      $(WORK_DIR)"
	@echo "  IP Output:     $(IP_OUTPUT_DIR)"
	@echo ""
