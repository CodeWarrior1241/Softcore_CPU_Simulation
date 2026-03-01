# ================================================================================
# NEORV32 - Questa Prime Compilation Script (VHDL-2008)
# ================================================================================
# This script compiles the NEORV32 RISC-V processor for simulation in Questa Prime
# ================================================================================

# Quit any existing simulation
quit -sim

# Create work library
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Create neorv32 library
if {[file exists neorv32]} {
    vdel -lib neorv32 -all
}
vlib neorv32

# Map libraries
vmap work work
vmap neorv32 neorv32

# Set VHDL-2008 compilation options
set VCOM_OPTS "-2008 -explicit -work neorv32"

# ================================================================================
# Compile NEORV32 Core RTL (order matters - package first)
# ================================================================================

puts "=========================================="
puts "Compiling NEORV32 Core RTL..."
puts "=========================================="

# Package (must be compiled first)
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_package.vhd

# System/Core components
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_sys.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_prim.vhd

# CPU components
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_decompressor.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_frontend.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_control.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_hwtrig.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_counters.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_regfile.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu_shifter.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu_muldiv.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu_bitmanip.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu_fpu.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu_cfu.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu_cond.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu_crypto.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_alu.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_lsu.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_pmp.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu_trace.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cpu.vhd

# Cache and Bus
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cache.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cache_ram.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_bus.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_dma.vhd

# Memory
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_imem_image.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_imem.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_imem_ram.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_imem_rom.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_dmem.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_dmem_ram.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_xbus.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_bootrom_image.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_bootrom.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_bootrom_rom.vhd

# Peripherals
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_cfs.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_sdi.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_gpio.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_wdt.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_clint.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_uart.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_spi.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_twi.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_twd.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_pwm.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_trng.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_neoled.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_gptmr.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_onewire.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_slink.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_tracer.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_sysinfo.vhd

# Debug
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_debug_dtm.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_debug_auth.vhd
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_debug_dm.vhd

# Top-level
vcom {*}$VCOM_OPTS ../../rtl/core/neorv32_top.vhd

# ================================================================================
# Compile Simulation/Testbench Components
# ================================================================================

puts "=========================================="
puts "Compiling Testbench Components..."
puts "=========================================="

# Testbench support modules (compile to work library)
set VCOM_TB_OPTS "-2008 -explicit -work work"

vcom {*}$VCOM_TB_OPTS ../sim_uart_rx.vhd
vcom {*}$VCOM_TB_OPTS ../sim_uart_tx.vhd
vcom {*}$VCOM_TB_OPTS ../xbus_memory.vhd
vcom {*}$VCOM_TB_OPTS ../xbus_gateway.vhd
vcom {*}$VCOM_TB_OPTS ../xbus_fmem.vhd
vcom {*}$VCOM_TB_OPTS ../iq_bram.vhd

# Main testbench
vcom {*}$VCOM_TB_OPTS ../neorv32_tb.vhd

puts "=========================================="
puts "Compilation Complete!"
puts "=========================================="
