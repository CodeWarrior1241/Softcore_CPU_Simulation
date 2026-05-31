#==============================================================================
# Makefile for Verilator datapath-only simulation of the AD9361 streaming path
#
# BEHAVIORAL RTL simulation. No sim_netlists, no UNISIM primitives.
# The axi_ad9361 transceiver is bypassed — the TB drives ADC/DAC ports directly.
#
# Covers: axi_ad9361_adapter, CDC FIFOs, streaming_adapter, clk_wiz (behavioral)
# Omits:  NEORV32 CPU, smartconnect, BRAM, axi_ad9361 LVDS transceiver
#
# See tb_top.sv header for the full scope rationale.
#
# Usage:
#   make          Build and run simulation
#   make build    Build only
#   make run      Run previously built simulation
#   make clean    Remove build artifacts
#
#==============================================================================

# Vivado install (for XPM behavioral primitives only)
XILINX_VIVADO ?= /media/fpgadev/Dev_Tools/Xilinx/2025.2

# Project paths
PROJECT_DIR := ..
GEN_DIR     := $(PROJECT_DIR)/NEORV32_Simulation.gen/sources_1/bd/Top
SRC_DIR     := $(PROJECT_DIR)/../../../../src

# Testbench and datapath top
TB_FILE       := tb_top.sv
DATAPATH_TOP  := datapath_top.sv
CLK_WIZ       := clk_wiz_behavioral.sv
TOP_MODULE    := tb_top

#------------------------------------------------------------------------------
# HLS axi_ad9361_adapter — behavioral RTL from impl/verilog
#------------------------------------------------------------------------------
HLS_ADAPTER_DIR := $(SRC_DIR)/axiad9361_adapter/axiad9361_adapter/hls/impl/verilog

HLS_ADAPTER_SOURCES := \
	$(HLS_ADAPTER_DIR)/axi_ad9361_adapter_tx_process_tx_bram_RAM_1P_BRAM_1R1W.v \
	$(HLS_ADAPTER_DIR)/axi_ad9361_adapter_regslice_both.v \
	$(HLS_ADAPTER_DIR)/axi_ad9361_adapter_tx_process.v \
	$(HLS_ADAPTER_DIR)/axi_ad9361_adapter_rx_process.v \
	$(HLS_ADAPTER_DIR)/axi_ad9361_adapter.v

#------------------------------------------------------------------------------
# HLS axi_lite_to_streaming_adapter — behavioral RTL from impl/verilog
#------------------------------------------------------------------------------
HLS_STREAM_DIR := $(SRC_DIR)/axi_lite_to_streaming_adapter/axi_lite_to_streaming_adapter/hls/impl/verilog

HLS_STREAM_SOURCES := \
	$(HLS_STREAM_DIR)/axi_lite_to_streaming_adapter_ctrl_s_axi.v \
	$(HLS_STREAM_DIR)/axi_lite_to_streaming_adapter_regslice_both.v \
	$(HLS_STREAM_DIR)/axi_lite_to_streaming_adapter.v

#------------------------------------------------------------------------------
# CDC FIFOs — behavioral RTL (axis_data_fifo + XPM)
#------------------------------------------------------------------------------
XILINX_XPM_DIR := $(XILINX_VIVADO)/data/ip/xpm

CDC_SOURCES := \
	$(GEN_DIR)/ipshared/434f/hdl/axis_infrastructure_v1_1_vl_rfs.v \
	$(GEN_DIR)/ipshared/e1e3/hdl/axis_data_fifo_v2_0_vl_rfs.v

CDC_TX_WRAPPER := $(GEN_DIR)/ip/Top_ad9361_cdc_tx_streaming_fifo_0/sim/Top_ad9361_cdc_tx_streaming_fifo_0.v
CDC_RX_WRAPPER := $(GEN_DIR)/ip/Top_ad9361_cdc_rx_streaming_fifo_0/sim/Top_ad9361_cdc_rx_streaming_fifo_0.v

# XPM behavioral primitives (CDC, memory, FIFO used by axis_data_fifo)
# -DONESPIN skips glbl.GSR hierarchical references and SVA assertions.
# -DOBSOLETE skips alternative SVA assertion blocks.
XPM_SOURCES := \
	$(XILINX_XPM_DIR)/xpm_cdc/hdl/xpm_cdc.sv \
	$(XILINX_XPM_DIR)/xpm_memory/hdl/xpm_memory.sv \
	$(XILINX_XPM_DIR)/xpm_fifo/hdl/xpm_fifo.sv

# COE data for ADC stimulus
COE_HEX := ../sim/qpsk_bram_data.hex

#------------------------------------------------------------------------------
# All sources
#------------------------------------------------------------------------------
SOURCES := \
	$(XPM_SOURCES) \
	$(HLS_ADAPTER_SOURCES) \
	$(HLS_STREAM_SOURCES) \
	$(CDC_SOURCES) \
	$(CDC_TX_WRAPPER) \
	$(CDC_RX_WRAPPER) \
	$(CLK_WIZ) \
	$(DATAPATH_TOP)

VERILATOR_FLAGS := \
	--binary \
	--timing \
	--bbox-unsup \
	--threads 1 \
	--output-split 20000 \
	-j $(shell nproc) \
	-sv \
	-I$(HLS_ADAPTER_DIR) \
	-I$(HLS_STREAM_DIR) \
	-I$(GEN_DIR)/ipshared/434f/hdl \
	+libext+.v \
	-DOBSOLETE \
	-DONESPIN \
	-Wall \
	-Wno-DECLFILENAME \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNUSEDPARAM \
	-Wno-WIDTHEXPAND \
	-Wno-WIDTHTRUNC \
	-Wno-CASEINCOMPLETE \
	-Wno-PINCONNECTEMPTY \
	-Wno-GENUNNAMED \
	-Wno-PROCASSINIT \
	-Wno-UNDRIVEN \
	-Wno-MULTIDRIVEN \
	-Wno-IMPLICITSTATIC \
	-Wno-WIDTHXZEXPAND \
	-Wno-BLKANDNBLK \
	-Wno-TIMESCALEMOD \
	-Wno-INITIALDLY \
	-Wno-VARHIDDEN \
	-Wno-COMBDLY \
	-Wno-SYNCASYNCNET \
	--top-module $(TOP_MODULE) \
	--Mdir obj_dir

OBJ_DIR := obj_dir

.PHONY: all build run clean check-deps

all: build run

build: check-deps $(OBJ_DIR)/V$(TOP_MODULE)

$(OBJ_DIR)/V$(TOP_MODULE): $(TB_FILE) $(DATAPATH_TOP) $(CLK_WIZ) $(SOURCES)
	@cp -f $(COE_HEX) qpsk_bram_data.hex 2>/dev/null || true
	@cp -f $(HLS_ADAPTER_DIR)/*.dat . 2>/dev/null || true
	verilator $(VERILATOR_FLAGS) $(TB_FILE) $(SOURCES)

run: $(OBJ_DIR)/V$(TOP_MODULE)
	$(OBJ_DIR)/V$(TOP_MODULE)

clean:
	rm -rf $(OBJ_DIR) qpsk_bram_data.hex *.dat

check-deps:
	@which verilator > /dev/null 2>&1 || \
		(echo "ERROR: Verilator not found in PATH." && exit 1)
	@echo "Verilator: $$(verilator --version)"
	@test -f "$(CDC_TX_WRAPPER)" || \
		(echo "ERROR: Vivado output products not found." && \
		 echo "  Run build_all.tcl in Vivado first." && exit 1)
	@echo "Source strategy: ALL behavioral RTL, zero sim_netlists, zero UNISIM"
	@echo "  HLS ad9361_adapter:    $(words $(HLS_ADAPTER_SOURCES)) files"
	@echo "  HLS streaming_adapter: $(words $(HLS_STREAM_SOURCES)) files"
	@echo "  CDC FIFOs:             $(words $(CDC_SOURCES)) files + XPM"
	@echo "  clk_wiz:               behavioral replacement"
