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
#   axis_async_fifo x2            mpf300 CDC FIFO (Bedrock-RTL
#                                 br_cdc_fifo_ctrl_1r1w inside; real RTL)
#   sys_ctrl, lclk_reset_sync     mpf300 reset blocks (real RTL; Bedrock +
#                                 mpf300_reset_gen since the migration)
#   dac_hold                      mpf300 DAC holding registers
#   PF_CCC                        behavioral replacement (pf_ccc_behavioral.sv)
# Omits: NEORV32 CPU, axi_1to3_decoder/BRAM, axi_ad9361 LVDS transceiver
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
# CDC FIFOs + reset blocks — the REAL mpf300 RTL, no stand-ins: since the
# Bedrock-RTL migration (doc/MPF300-Splash-Kit/bedrock_migration_design.md)
# axis_async_fifo, sys_ctrl and lclk_reset_sync are pure SystemVerilog
# (Bedrock br_cdc_fifo_ctrl_1r1w / br_cdc_bit_toggle / br_cdc_rst_sync +
# project mpf300_reset_gen), so Verilator compiles the synthesis sources
# directly. Bedrock file list in dependency order — same list as
# build_all.tcl and the Questa compile.do. BR_ASSERT_ON and SIMULATION are
# deliberately NOT defined (the SIMULATION-gated CDC delay randomization
# uses process::self(), unsupported by Verilator; without the defines the
# deterministic path is used).
#------------------------------------------------------------------------------
MPF300_HDL_DIR   := $(REPO_ROOT)/deps/hdl/projects/fmcomms2/mpf300/hdl
BEDROCK_DIR      := $(REPO_ROOT)/deps/bedrock-rtl

BEDROCK_SOURCES := \
	$(BEDROCK_DIR)/pkg/br_math_pkg.sv \
	$(BEDROCK_DIR)/gate/rtl/br_gate_mock.sv \
	$(BEDROCK_DIR)/misc/rtl/br_misc_unused.sv \
	$(BEDROCK_DIR)/misc/rtl/br_misc_tieoff_zero.sv \
	$(BEDROCK_DIR)/misc/rtl/br_misc_tieoff_one.sv \
	$(BEDROCK_DIR)/cdc/rtl/br_cdc_pkg.sv \
	$(BEDROCK_DIR)/cdc/rtl/br_cdc_bit_toggle.sv \
	$(BEDROCK_DIR)/counter/rtl/br_counter_incr.sv \
	$(BEDROCK_DIR)/flow/rtl/internal/br_flow_checks_valid_data_intg.sv \
	$(BEDROCK_DIR)/fifo/rtl/internal/br_fifo_push_ctrl_core.sv \
	$(BEDROCK_DIR)/enc/rtl/br_enc_bin2gray.sv \
	$(BEDROCK_DIR)/delay/rtl/br_delay_nr.sv \
	$(BEDROCK_DIR)/cdc/rtl/internal/br_cdc_fifo_reset_overlap_checks.sv \
	$(BEDROCK_DIR)/enc/rtl/br_enc_gray2bin.sv \
	$(BEDROCK_DIR)/cdc/rtl/internal/br_cdc_fifo_push_flag_mgr.sv \
	$(BEDROCK_DIR)/cdc/rtl/internal/br_cdc_fifo_push_ctrl.sv \
	$(BEDROCK_DIR)/cdc/rtl/internal/br_cdc_fifo_gray_count_sync.sv \
	$(BEDROCK_DIR)/cdc/rtl/br_cdc_fifo_ctrl_push_1r1w.sv \
	$(BEDROCK_DIR)/cdc/rtl/internal/br_cdc_fifo_pop_flag_mgr.sv \
	$(BEDROCK_DIR)/delay/rtl/br_delay_valid.sv \
	$(BEDROCK_DIR)/delay/rtl/br_delay_shift_reg.sv \
	$(BEDROCK_DIR)/counter/rtl/br_counter.sv \
	$(BEDROCK_DIR)/flow/rtl/internal/br_flow_checks_valid_data_impl.sv \
	$(BEDROCK_DIR)/flow/rtl/br_flow_reg_fwd.sv \
	$(BEDROCK_DIR)/mux/rtl/br_mux_onehot.sv \
	$(BEDROCK_DIR)/fifo/rtl/internal/br_fifo_staging_buffer.sv \
	$(BEDROCK_DIR)/fifo/rtl/internal/br_fifo_pop_ctrl_core.sv \
	$(BEDROCK_DIR)/cdc/rtl/internal/br_cdc_fifo_pop_ctrl.sv \
	$(BEDROCK_DIR)/cdc/rtl/br_cdc_fifo_ctrl_pop_1r1w.sv \
	$(BEDROCK_DIR)/cdc/rtl/br_cdc_fifo_ctrl_1r1w.sv \
	$(BEDROCK_DIR)/cdc/rtl/br_cdc_rst_sync.sv

CDC_SOURCES := \
	$(BEDROCK_SOURCES) \
	$(MPF300_HDL_DIR)/axis_async_fifo.v

MPF300_SOURCES := \
	$(MPF300_HDL_DIR)/mpf300_reset_gen.sv \
	$(MPF300_HDL_DIR)/sys_ctrl.v \
	$(MPF300_HDL_DIR)/lclk_reset_sync.v \
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
	-I$(BEDROCK_DIR)/macros \
	+define+BR_VERILATOR \
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
	@echo "  CDC FIFOs (Bedrock + wrapper): $(words $(CDC_SOURCES)) files"
	@echo "  PF_CCC:                     behavioral replacement"
