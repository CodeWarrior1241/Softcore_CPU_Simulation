# Application makefile for AD9361 Loopback Test.
# Use this makefile to configure all relevant CPU / compiler options.

# Use standard VHDL application image filename (so it's included in IP packaging)
# APP_VHD = neorv32_application_image.vhd (default)

# Override the default CPU ISA
MARCH = rv32i_zicsr_zifencei

# Override the default RISC-V GCC prefix
#RISCV_PREFIX ?= riscv-none-elf-

# Override default optimization goal
EFFORT = -Os

# Add extended debug symbols
USER_FLAGS += -ggdb -gdwarf-3

# Adjust processor IMEM size (32KB available)
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k

# Adjust processor DMEM size (16KB available)
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k

# Adjust maximum heap size
#USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=1k

# Additional sources
#APP_SRC += $(wildcard ./*.c)
#APP_INC += -I .

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
