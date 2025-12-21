# ================================================================================
# NEORV32 - Aldec Active-HDL Compilation Script (VHDL-2008)
# ================================================================================
# This script compiles the NEORV32 RISC-V processor for simulation in Active-HDL
# ================================================================================

# Quit any existing simulation
endsim

# Create work library
if {[file exists work]} {
    file delete -force work
}
alib work

# Create neorv32 library
if {[file exists neorv32]} {
    file delete -force neorv32
}
alib neorv32

# Map libraries
amap work work
amap neorv32 neorv32

# Set VHDL-2008 compilation options
set VCOM_OPTS "-2008 -work neorv32"

# ================================================================================
# Compile NEORV32 Core RTL (order matters - package first)
# ================================================================================

puts "=========================================="
puts "Compiling NEORV32 Core RTL..."
puts "=========================================="

# Package (must be compiled first)
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_package.vhd

# System/Core components
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_sys.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_prim.vhd

# CPU components
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_decompressor.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_frontend.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_control.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_hwtrig.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_counters.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_regfile.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_cp_shifter.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_cp_muldiv.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_cp_bitmanip.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_cp_fpu.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_cp_cfu.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_cp_cond.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_cp_crypto.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_lsu.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_pmp.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_trace.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu.vhd

# Cache and Bus
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cache.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_bus.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_dma.vhd

# Memory
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_application_image.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_imem.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_dmem.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_xbus.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_bootloader_image.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_boot_rom.vhd

# Peripherals
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_cfs.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_sdi.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_gpio.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_wdt.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_clint.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_uart.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_spi.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_twi.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_twd.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_pwm.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_trng.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_neoled.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_gptmr.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_onewire.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_slink.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_tracer.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_sysinfo.vhd

# Debug
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_debug_dtm.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_debug_auth.vhd
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_debug_dm.vhd

# Top-level
acom {*}$VCOM_OPTS ../../rtl/core/neorv32_top.vhd

# ================================================================================
# Compile Simulation/Testbench Components
# ================================================================================

puts "=========================================="
puts "Compiling Testbench Components..."
puts "=========================================="

# Testbench support modules (compile to work library)
set VCOM_TB_OPTS "-2008 -work work"

acom {*}$VCOM_TB_OPTS ../sim_uart_rx.vhd
acom {*}$VCOM_TB_OPTS ../xbus_memory.vhd
acom {*}$VCOM_TB_OPTS ../xbus_gateway.vhd
acom {*}$VCOM_TB_OPTS ../xbus_fmem.vhd

# Main testbench
acom {*}$VCOM_TB_OPTS ../neorv32_tb.vhd

puts "=========================================="
puts "Compilation Complete!"
puts "=========================================="
