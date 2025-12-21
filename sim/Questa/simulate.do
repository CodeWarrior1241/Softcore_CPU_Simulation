# ================================================================================
# NEORV32 - Questa Prime Simulation Script (VHDL-2008)
# ================================================================================
# This script runs the NEORV32 simulation in Questa Prime
# Usage: vsim -do simulate.do
# ================================================================================

# Source the compilation script first
do compile.do

# ================================================================================
# Simulation Parameters
# ================================================================================

# Default simulation time (can be overridden)
if {![info exists SIM_TIME]} {
    set SIM_TIME "150ms"
}

puts "=========================================="
puts "Starting NEORV32 Simulation..."
puts "Simulation time: $SIM_TIME"
puts "=========================================="

# ================================================================================
# Load Design and Configure Simulation
# ================================================================================

# Load the testbench with optimization disabled for debugging
vsim -t 1ns -voptargs="+acc" \
    -L neorv32 \
    -L work \
    work.neorv32_tb

# ================================================================================
# Add Waveforms
# ================================================================================

# Add all top-level signals
add wave -divider "Clock & Reset"
add wave -hex /neorv32_tb/clk_gen
add wave -hex /neorv32_tb/rst_gen

add wave -divider "UART0"
add wave -hex /neorv32_tb/uart0_txd

add wave -divider "UART1"
add wave -hex /neorv32_tb/uart1_txd

add wave -divider "GPIO"
add wave -hex /neorv32_tb/gpio

add wave -divider "XBUS Interface"
add wave -hex /neorv32_tb/xbus_core_req
add wave -hex /neorv32_tb/xbus_core_rsp

# Add CPU internal signals (optional - may not exist in all configurations)
catch {
    add wave -divider "CPU Core"
    add wave -hex /neorv32_tb/neorv32_top_inst/core_complex_gen/neorv32_core_inst/cpu_core0/neorv32_cpu_inst/*
}

# ================================================================================
# Run Simulation
# ================================================================================

# Configure waveform display
configure wave -namecolwidth 250
configure wave -valuecolwidth 120
configure wave -signalnamewidth 1

# Record start time
set start_time [clock milliseconds]

# Run simulation
run $SIM_TIME

# Calculate and display wall clock time
set end_time [clock milliseconds]
set elapsed_ms [expr {$end_time - $start_time}]
set elapsed_sec [format "%.2f" [expr {$elapsed_ms / 1000.0}]]
puts "=========================================="
puts "Simulation Complete!"
puts "Wall clock time: $elapsed_sec seconds"
puts "=========================================="
catch {wave zoom full}
