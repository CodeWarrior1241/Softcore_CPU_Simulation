# ================================================================================
# NEORV32 - Aldec Active-HDL Simulation Script (VHDL-2008)
# ================================================================================
# This script runs the NEORV32 simulation in Active-HDL
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

# Load the testbench
asim -t 1ns \
    +access +r \
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

# ================================================================================
# Run Simulation
# ================================================================================

# Run simulation
run $SIM_TIME

puts "=========================================="
puts "Simulation Complete!"
puts "=========================================="
