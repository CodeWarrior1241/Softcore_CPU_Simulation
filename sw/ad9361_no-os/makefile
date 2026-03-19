# Application makefile for AD9361 no-os skeleton.
# Use this makefile to configure all relevant CPU / compiler options.

# Override the default CPU ISA (M extension for hardware multiply, C for code density)
MARCH = rv32imc_zicsr_zifencei

# Override default optimization goal
EFFORT = -Os

# Add extended debug symbols
USER_FLAGS += -ggdb -gdwarf-3

# Adjust processor IMEM size (64KB for AD9361 driver)
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=64k

# Adjust processor DMEM size (16KB available)
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k

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
