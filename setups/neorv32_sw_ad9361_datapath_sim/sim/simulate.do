# ================================================================================
# AD9361 Datapath Simulation - Questa Prime Simulation Script
# ================================================================================
# This script runs the AD9361 datapath loopback simulation
# Usage: vsim -do simulate.do
# ================================================================================

# Source the compilation script first
do compile.do

# ================================================================================
# Simulation Parameters
# ================================================================================

# Default simulation time (can be overridden from command line)
if {![info exists SIM_TIME]} {
    set SIM_TIME "10ms"
}

puts "=========================================="
puts "Starting AD9361 Datapath Simulation..."
puts "Simulation time: $SIM_TIME"
puts "=========================================="

# ================================================================================
# Map locally-compiled libraries from Vivado's questa directory
# ================================================================================

# The compile.do already set sim_dir and vivado_questa_dir
# Map only the libraries that we compile locally (others come from pre-compiled modelsim.ini)
vmap xilinx_vip $vivado_questa_dir/questa_lib/msim/xilinx_vip
vmap xpm $vivado_questa_dir/questa_lib/msim/xpm
vmap xil_defaultlib $vivado_questa_dir/questa_lib/msim/xil_defaultlib
vmap proc_sys_reset_v5_0_17 $vivado_questa_dir/questa_lib/msim/proc_sys_reset_v5_0_17
vmap axi_bram_ctrl_v4_1_13 $vivado_questa_dir/questa_lib/msim/axi_bram_ctrl_v4_1_13
vmap neorv32 $vivado_questa_dir/questa_lib/msim/neorv32
vmap util_vector_logic_v2_0_5 $vivado_questa_dir/questa_lib/msim/util_vector_logic_v2_0_5
vmap smartconnect_v1_0 $vivado_questa_dir/questa_lib/msim/smartconnect_v1_0
vmap axi_infrastructure_v1_1_0 $vivado_questa_dir/questa_lib/msim/axi_infrastructure_v1_1_0
vmap axi_register_slice_v2_1_36 $vivado_questa_dir/questa_lib/msim/axi_register_slice_v2_1_36
vmap axi_vip_v1_1_22 $vivado_questa_dir/questa_lib/msim/axi_vip_v1_1_22
vmap blk_mem_gen_v8_4_12 $vivado_questa_dir/questa_lib/msim/blk_mem_gen_v8_4_12
vmap xlslice_v1_0_5 $vivado_questa_dir/questa_lib/msim/xlslice_v1_0_5
vmap xlconcat_v2_1_7 $vivado_questa_dir/questa_lib/msim/xlconcat_v2_1_7
vmap util_reduced_logic_v2_0_7 $vivado_questa_dir/questa_lib/msim/util_reduced_logic_v2_0_7

# ================================================================================
# Elaborate and Load Design
# ================================================================================

# Change to Vivado's questa directory where the MIF files and hex files are located
cd $vivado_questa_dir

# Copy the hex file to the questa directory so $readmemh can find it
file copy -force $sim_dir/qpsk_bram_data.hex qpsk_bram_data.hex

# Elaborate with optimization for the testbench
# Include all required Xilinx libraries
# Use -Lf neorv32 to force component binding to search the neorv32 library
vopt -l elaborate.log +acc=npr -suppress 10016 \
    -L xil_defaultlib \
    -L xilinx_vip \
    -L xpm \
    -Lf neorv32 \
    -L proc_sys_reset_v5_0_17 \
    -L util_vector_logic_v2_0_5 \
    -L smartconnect_v1_0 \
    -L axi_infrastructure_v1_1_0 \
    -L axi_register_slice_v2_1_36 \
    -L axi_vip_v1_1_22 \
    -L axi_bram_ctrl_v4_1_13 \
    -L blk_mem_gen_v8_4_12 \
    -L xlslice_v1_0_5 \
    -L xlconcat_v2_1_7 \
    -L util_reduced_logic_v2_0_7 \
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
add wave -hex /vivado_tb/ecs_clk_in_p
add wave -hex /vivado_tb/ecs_clk_in_n
add wave -hex /vivado_tb/system_resetn
add wave -hex /vivado_tb/sim_clock_100MHz_locked

add wave -divider "UART Signals"
add wave -hex /vivado_tb/uart0_txd
add wave -hex /vivado_tb/uart0_rxd

add wave -divider "AD9361 Control"
add wave -hex /vivado_tb/enable
add wave -hex /vivado_tb/txnrx

add wave -divider "AD9361 LVDS RX"
add wave -hex /vivado_tb/rx_clk_in_p
add wave -hex /vivado_tb/rx_frame_in_p
add wave -hex /vivado_tb/rx_data_in_p

add wave -divider "AD9361 LVDS TX"
add wave -hex /vivado_tb/tx_clk_out_p
add wave -hex /vivado_tb/tx_frame_out_p
add wave -hex /vivado_tb/tx_data_out_p

add wave -divider "Stimulus Control"
add wave -hex /vivado_tb/loopback_mode
add wave -radix unsigned /vivado_tb/samples_sent
add wave -radix unsigned /vivado_tb/coe_index

add wave -divider "COE Data"
add wave -hex /vivado_tb/current_i
add wave -hex /vivado_tb/current_q

add wave -divider "UUT Internal - Clock Wizard"
catch {
    add wave -hex /vivado_tb/dut/Top_i/ECS_Clock_300MHz/clk_out1
    add wave -hex /vivado_tb/dut/Top_i/ECS_Clock_300MHz/locked
}

add wave -divider "UUT Internal - NEORV32 CPU"
catch {
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/clk
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/resetn
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/uart0_txd_o
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/gpio_o
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
