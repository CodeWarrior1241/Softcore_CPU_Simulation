# Application makefile for AD9361 no-os driver on NEORV32 + FMCOMMS2/4 AU15P.

# Override the default CPU ISA (M extension for hardware multiply, C for code density)
MARCH = rv32imc_zicsr_zifencei

# Override default optimization goal
EFFORT = -Os

# Add extended debug symbols
USER_FLAGS += -ggdb -gdwarf-3

# Adjust processor IMEM size (128KB — AD9361 driver overflows 64KB by ~17KB)
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=128k

# Adjust processor DMEM size (32KB available)
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=32k

# Heap for AD9361 driver allocations (ad9361_rf_phy, clocks, descriptors)
USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=16k

# NOTE: AXI_ADC_NOT_PRESENT used to be defined here as a footprint-saver,
# but it also stubs out ad9361_dig_tune() (the LVDS IDELAY calibration
# routine), leaving the IDELAYs at the IP's ADC_INIT_DELAY default and
# the LVDS framing un-aligned (header_s=0 across all RX channels).
# We now pull in cf_axi_adc / cf_axi_dac so dig_tune is real.

# ---------- no-os paths ----------
NOOS_HOME  ?= ../../../no-OS
AD9361_DRV  = $(NOOS_HOME)/drivers/rf-transceiver/ad9361
AXI_ADC_DRV = $(NOOS_HOME)/drivers/axi_core/axi_adc_core
AXI_DAC_DRV = $(NOOS_HOME)/drivers/axi_core/axi_dac_core

# ---------- no-os sources ----------
APP_SRC += $(wildcard ./*.c)
APP_SRC += $(AD9361_DRV)/ad9361.c
APP_SRC += $(AD9361_DRV)/ad9361_api.c
APP_SRC += $(AD9361_DRV)/ad9361_util.c
APP_SRC += $(AD9361_DRV)/ad9361_conv.c
APP_SRC += $(AXI_ADC_DRV)/axi_adc_core.c
APP_SRC += $(AXI_DAC_DRV)/axi_dac_core.c
APP_SRC += $(NOOS_HOME)/drivers/api/no_os_spi.c
APP_SRC += $(NOOS_HOME)/drivers/api/no_os_gpio.c
APP_SRC += $(NOOS_HOME)/util/no_os_util.c
APP_SRC += $(NOOS_HOME)/util/no_os_clk.c

# ---------- no-os include paths ----------
APP_INC += -I .
APP_INC += -I $(NOOS_HOME)/include
APP_INC += -I $(AD9361_DRV)
APP_INC += -I $(NOOS_HOME)/drivers/axi_core/axi_adc_core
APP_INC += -I $(NOOS_HOME)/drivers/axi_core/axi_dac_core

# Set path to NEORV32 root directory
NEORV32_HOME ?= ../..

# Include the main NEORV32 makefile
include $(NEORV32_HOME)/sw/common/common.mk

# Windows compatibility: override Unix commands not available on Windows CMD.
# Must come after the include so common.mk doesn't overwrite these.
ifeq ($(OS),Windows_NT)
SET   = echo
MKDIR = mkdir
endif
