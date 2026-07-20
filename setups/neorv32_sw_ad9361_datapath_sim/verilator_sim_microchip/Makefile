#==============================================================================
# Makefile for Verilator datapath-only simulation of the AD9361 streaming path
# — Microchip PolarFire (mpf300) variant of ../verilator_sim/Makefile.
#
# BEHAVIORAL RTL simulation. No vendor primitives, no encrypted IP.
# The axi_ad9361 transceiver is bypassed — the TB drives ADC/DAC ports
# directly (its PolarFire port is covered by the QuestaSim flow in
# deps/hdl/library/axi_ad9361/sim/microchip).
#
# Covers the components of the mpf300 FMCOMMS2 design
# (deps/hdl/projects/fmcomms2/mpf300):
#   axi_ad9361_adapter            SmartHLS RTL (src/axi_ad9361_adapter_microchip)
#   axi_lite_to_streaming_adapter SmartHLS RTL (src/axi_lite_to_streaming_adapter_microchip)
#   axis_async_fifo x2            mpf300 CDC FIFO (open-logic olo_base_fifo_async;
#                                 behavioral SV model of the VHDL entity here)
#   dac_hold                      mpf300 DAC holding registers
#   PF_CCC                        behavioral replacement (pf_ccc_behavioral.sv)
# Omits: NEORV32 CPU, axi_1to3_decoder/BRAM, axi_ad9361 LVDS transceiver,
#        open-logic reset blocks (VHDL; modeled behaviorally in datapath_top)
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

# Project paths
PROJECT_DIR := ..
REPO_ROOT   := $(PROJECT_DIR)/../../../..
SRC_DIR     := $(REPO_ROOT)/src

# Testbench and datapath top
TB_FILE       := tb_top.sv
DATAPATH_TOP  := datapath_top.sv
PF_CCC        := pf_ccc_behavioral.sv
TOP_MODULE    := tb_top

#------------------------------------------------------------------------------
# SmartHLS axi_ad9361_adapter — generated RTL
#------------------------------------------------------------------------------
HLS_ADAPTER_DIR := $(SRC_DIR)/axi_ad9361_adapter_microchip/hls_output/rtl

HLS_ADAPTER_SOURCES := \
	$(HLS_ADAPTER_DIR)/axi_ad9361_adapter_axi_ad9361_adapter.v

#------------------------------------------------------------------------------
# SmartHLS axi_lite_to_streaming_adapter — generated RTL
#------------------------------------------------------------------------------
HLS_STREAM_DIR := $(SRC_DIR)/axi_lite_to_streaming_adapter_microchip/hls_output/rtl

HLS_STREAM_SOURCES := \
	$(HLS_STREAM_DIR)/axi_lite_to_streaming_adapter_axi_lite_to_streaming_adapter.v

#------------------------------------------------------------------------------
# CDC FIFOs — mpf300 axis_async_fifo wrapper + open-logic olo_base_fifo_async
# engine. The real engine is VHDL (deps/open-logic), which Verilator cannot
# compile; olo_base_fifo_async.sv here is a port-compatible behavioral model
# (same pattern as pf_ccc_behavioral.sv and the reset blocks in datapath_top).
#------------------------------------------------------------------------------
MPF300_HDL_DIR   := $(REPO_ROOT)/deps/hdl/projects/fmcomms2/mpf300/hdl

CDC_SOURCES := \
	olo_base_fifo_async.sv \
	$(MPF300_HDL_DIR)/axis_async_fifo.v

MPF300_SOURCES := \
	$(MPF300_HDL_DIR)/dac_hold.v

# The SmartHLS RAM models load init files via {`MEM_INIT_DIR, "<name>.mem"};
# the .mem files are copied into the run directory at build time
MEM_INIT := +define+MEM_INIT_DIR=\"./\"

# COE data for ADC stimulus
COE_HEX := ../sim/qpsk_bram_data.hex

#------------------------------------------------------------------------------
# All sources
#------------------------------------------------------------------------------
SOURCES := \
	$(HLS_ADAPTER_SOURCES) \
	$(HLS_STREAM_SOURCES) \
	$(CDC_SOURCES) \
	$(MPF300_SOURCES) \
	$(PF_CCC) \
	$(DATAPATH_TOP)

VERILATOR_FLAGS := \
	--binary \
	--timing \
	--threads 1 \
	-j $(shell nproc) \
	-sv \
	-I$(HLS_ADAPTER_DIR) \
	-I$(HLS_STREAM_DIR) \
	$(MEM_INIT) \
	+libext+.v \
	-Wall \
	-Wno-fatal \
	-Wno-DECLFILENAME \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNUSEDPARAM \
	-Wno-WIDTHEXPAND \
	-Wno-WIDTHTRUNC \
	-Wno-CASEINCOMPLETE \
	-Wno-PINCONNECTEMPTY \
	-Wno-GENUNNAMED \
	-Wno-UNDRIVEN \
	-Wno-IMPLICITSTATIC \
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

$(OBJ_DIR)/V$(TOP_MODULE): $(TB_FILE) $(DATAPATH_TOP) $(PF_CCC) $(SOURCES)
	@cp -f $(COE_HEX) qpsk_bram_data.hex 2>/dev/null || true
	@cp -f $(HLS_ADAPTER_DIR)/mem_init/*.mem . 2>/dev/null || true
	@cp -f $(HLS_STREAM_DIR)/mem_init/*.mem . 2>/dev/null || true
	verilator $(VERILATOR_FLAGS) $(TB_FILE) $(SOURCES)

run: $(OBJ_DIR)/V$(TOP_MODULE)
	$(OBJ_DIR)/V$(TOP_MODULE)

clean:
	rm -rf $(OBJ_DIR) qpsk_bram_data.hex *.mem

check-deps:
	@which verilator > /dev/null 2>&1 || \
		(echo "ERROR: Verilator not found in PATH." && exit 1)
	@echo "Verilator: $$(verilator --version)"
	@test -f "$(HLS_STREAM_DIR)/axi_lite_to_streaming_adapter_axi_lite_to_streaming_adapter.v" || \
		(echo "ERROR: SmartHLS RTL not found." && \
		 echo "  Run 'shls -a hw' in src/*_microchip first." && exit 1)
	@echo "Source strategy: ALL behavioral RTL, zero vendor primitives"
	@echo "  SmartHLS ad9361_adapter:    $(words $(HLS_ADAPTER_SOURCES)) file(s)"
	@echo "  SmartHLS streaming_adapter: $(words $(HLS_STREAM_SOURCES)) file(s)"
	@echo "  CDC FIFOs (olo model + wrapper): $(words $(CDC_SOURCES)) files"
	@echo "  PF_CCC:                     behavioral replacement"
