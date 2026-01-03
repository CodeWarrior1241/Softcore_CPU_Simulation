# ================================================================================
# Vivado Block Design Testbench - Questa Prime Simulation Script
# ================================================================================
# This script runs the Vivado block design simulation with our custom testbench
# Usage: vsim -do simulate.do
# ================================================================================

# Source the compilation script first
do compile.do

# ================================================================================
# Simulation Parameters
# ================================================================================

# Default simulation time (can be overridden from command line)
if {![info exists SIM_TIME]} {
    set SIM_TIME "500ms"
}

puts "=========================================="
puts "Starting Vivado Block Design Simulation..."
puts "Simulation time: $SIM_TIME"
puts "=========================================="

# ================================================================================
# Map all libraries from Vivado's questa directory
# ================================================================================

# The compile.do already set sim_dir and vivado_questa_dir
# Map all the required libraries
vmap xilinx_vip $vivado_questa_dir/questa_lib/msim/xilinx_vip
vmap xpm $vivado_questa_dir/questa_lib/msim/xpm
vmap proc_sys_reset_v5_0_17 $vivado_questa_dir/questa_lib/msim/proc_sys_reset_v5_0_17
vmap util_vector_logic_v2_0_5 $vivado_questa_dir/questa_lib/msim/util_vector_logic_v2_0_5
vmap smartconnect_v1_0 $vivado_questa_dir/questa_lib/msim/smartconnect_v1_0
vmap axi_infrastructure_v1_1_0 $vivado_questa_dir/questa_lib/msim/axi_infrastructure_v1_1_0
vmap axi_register_slice_v2_1_36 $vivado_questa_dir/questa_lib/msim/axi_register_slice_v2_1_36
vmap axi_vip_v1_1_22 $vivado_questa_dir/questa_lib/msim/axi_vip_v1_1_22
vmap axi_bram_ctrl_v4_1_13 $vivado_questa_dir/questa_lib/msim/axi_bram_ctrl_v4_1_13
vmap blk_mem_gen_v8_4_12 $vivado_questa_dir/questa_lib/msim/blk_mem_gen_v8_4_12

# ================================================================================
# Elaborate and Load Design
# ================================================================================

# Change to Vivado's questa directory where the MIF files are located
# This is required for BRAM initialization files to be found
cd $vivado_questa_dir

# Elaborate with optimization for the testbench
# Include all required Xilinx libraries
vopt -l elaborate.log +acc=npr -suppress 10016 \
    -L xil_defaultlib \
    -L xilinx_vip \
    -L xpm \
    -L neorv32 \
    -L proc_sys_reset_v5_0_17 \
    -L util_vector_logic_v2_0_5 \
    -L smartconnect_v1_0 \
    -L axi_infrastructure_v1_1_0 \
    -L axi_register_slice_v2_1_36 \
    -L axi_vip_v1_1_22 \
    -L axi_bram_ctrl_v4_1_13 \
    -L blk_mem_gen_v8_4_12 \
    -L unisims_ver \
    -L unimacro_ver \
    -L secureip \
    -work xil_defaultlib \
    xil_defaultlib.vivado_tb xil_defaultlib.glbl \
    -o vivado_tb_opt

# Load the optimized design
# Use -t 1ps for time resolution (required by Verilog sources)
vsim -t 1ps -lib xil_defaultlib vivado_tb_opt

# Suppress numeric std warnings
set NumericStdNoWarnings 1
set StdArithNoWarnings 1

# ================================================================================
# Add Waveforms
# ================================================================================

add wave -divider "Clock & Reset"
add wave -hex /vivado_tb/clk_p
add wave -hex /vivado_tb/clk_n
add wave -hex /vivado_tb/rst_n
add wave -hex /vivado_tb/cpu_clk
add wave -hex /vivado_tb/cpu_clk_locked

add wave -divider "UART Signals"
add wave -hex /vivado_tb/uart_txd
add wave -hex /vivado_tb/uart_txd_gated
add wave -hex /vivado_tb/uart_rxd

add wave -divider "UART TX Control (Testbench -> CPU)"
add wave -hex /vivado_tb/tx_data
add wave -hex /vivado_tb/tx_valid
add wave -hex /vivado_tb/tx_ready
add wave      /vivado_tb/cmd_state
add wave -radix unsigned -noshowbase /vivado_tb/qpsk_count

add wave -divider "UUT Internal - Clock Wizard"
catch {
    add wave -hex /vivado_tb/uut/Top_i/ECS_Clock_300MHz/clk_out1
    add wave -hex /vivado_tb/uut/Top_i/ECS_Clock_300MHz/locked
}

add wave -divider "UUT Internal - NEORV32 CPU"
catch {
    add wave -hex /vivado_tb/uut/Top_i/NEORV32_RISC_V/clk
    add wave -hex /vivado_tb/uut/Top_i/NEORV32_RISC_V/resetn
    add wave -hex /vivado_tb/uut/Top_i/NEORV32_RISC_V/uart0_txd_o
    add wave -hex /vivado_tb/uut/Top_i/NEORV32_RISC_V/uart0_rxd_i
}

add wave -divider "UUT Internal - AXI Bus"
catch {
    add wave -hex /vivado_tb/uut/Top_i/NEORV32_RISC_V/m_axi_*
}

# ================================================================================
# Configure Waveform Display
# ================================================================================

configure wave -namecolwidth 350
configure wave -valuecolwidth 120
configure wave -signalnamewidth 1

view wave
view structure
view signals

# ================================================================================
# Run Simulation
# ================================================================================

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
