# ================================================================================
# AD9361 Datapath Simulation - Questa Prime Simulation Script
# ================================================================================
# This script runs the AD9361 datapath loopback simulation
#
# Usage (via run_sim.sh / run_sim.bat):
#   ./run_sim.sh                    Fast mode (+acc=rn, no waveforms)
#   ./run_sim.sh --detailed         Detailed mode (+acc=npr, full waveforms)
#
# Direct usage:
#   vsim -do simulate.do
#   vsim -do "set DETAILED yes; do simulate.do"
#
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

# Detailed mode: "yes" = full signal visibility (+acc=npr) with waveforms
# Default (fast): +acc=rn, no waveforms — significantly faster simulation
if {![info exists DETAILED]} {
    set DETAILED "no"
}

if {$DETAILED eq "yes"} {
    set acc_flag "+acc"
    set mode_str "DETAILED (+acc, full signal visibility)"
} else {
    set acc_flag "+acc=rn"
    set mode_str "FAST (+acc=rn, no waveforms)"
}

puts "=========================================="
puts "Starting AD9361 Datapath Simulation..."
puts "Mode:            $mode_str"
puts "Simulation time: $SIM_TIME"
puts "=========================================="

# ================================================================================
# Map locally-compiled libraries from Vivado's questa directory
# ================================================================================

# The compile.do already set sim_dir and vivado_questa_dir.
# Enumerate the libraries the generated compile.do actually built instead of
# hardcoding them: the versioned IP library names carry an _NN revision suffix
# that changes with nearly every Vivado release (e.g. axi_bram_ctrl_v4_1_13 in
# 2025.2 -> axi_bram_ctrl_v4_1_14 in 2026.1). Pre-compiled libraries (unisims
# etc.) still come from the modelsim.ini copied by compile.do.
set local_libs {}
foreach libdir [lsort [glob -nocomplain -types d -directory $vivado_questa_dir/questa_lib/msim *]] {
    set lib [file tail $libdir]
    vmap $lib $libdir
    lappend local_libs $lib
}
if {[llength $local_libs] == 0} {
    error "simulate.do: no compiled libraries found under $vivado_questa_dir/questa_lib/msim - did compile.do run?"
}
puts "INFO: Mapped [llength $local_libs] locally-compiled libraries: $local_libs"

# ================================================================================
# Elaborate and Load Design
# ================================================================================

# Change to Vivado's questa directory where the MIF files and hex files are located
cd $vivado_questa_dir

# Copy the hex file to the questa directory so $readmemh can find it
file copy -force $sim_dir/qpsk_bram_data.hex qpsk_bram_data.hex

# Elaborate with optimization for the testbench
# The -L switches are generated from the enumerated local libraries (so IP
# revision bumps between Vivado releases need no edits here); xil_defaultlib
# stays first and neorv32 keeps its -Lf forced component binding.
set L_args {}
foreach lib $local_libs {
    if {$lib eq "xil_defaultlib" || $lib eq "neorv32"} { continue }
    lappend L_args -L $lib
}
vopt -l elaborate.log $acc_flag -suppress 10016 \
    -L xil_defaultlib \
    {*}$L_args \
    -Lf neorv32 \
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
# Add Waveforms (detailed mode only)
# ================================================================================

if {$DETAILED eq "yes"} {

add wave -divider "Clock & Reset"
add wave -hex /vivado_tb/ecs_clk_in_p
add wave -hex /vivado_tb/ecs_clk_in_n
add wave -hex /vivado_tb/system_resetn
add wave -hex /vivado_tb/sim_clock_150MHz_locked

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

add wave -divider "UUT Internal - AD9361 Control Path"
catch {
    add wave -hex /vivado_tb/dut/Top_i/gpio_up_enable_slice_Dout
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361/up_enable
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361/up_txnrx
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adc_valid_i0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adc_valid_q0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361/l_clk
}

add wave -divider "UUT Internal - Clock Wizard"
catch {
    add wave -hex /vivado_tb/dut/Top_i/SiTime_300MHz/clk_out1
    add wave -hex /vivado_tb/dut/Top_i/SiTime_300MHz/locked
}

add wave -divider "UUT Internal - NEORV32 CPU"
catch {
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/clk
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/resetn
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/uart0_txd_o
    add wave -hex /vivado_tb/dut/Top_i/NEORV32_RISC_V/gpio_o
}

add wave -divider "UUT Internal - AD9361 Adapter (125 MHz l_clk)"
catch {
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/ap_clk
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/ap_rst_n
}

add wave -divider "UUT Internal - AD9361 Adapter ADC"
catch {
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/adc_data_i0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/adc_data_q0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/adc_valid_i0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/adc_enable_i0
}

add wave -divider "UUT Internal - AD9361 Adapter DAC"
catch {
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/dac_data_i0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/dac_data_q0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/dac_valid_i0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/dac_enable_i0
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/dac_dunf
}

add wave -divider "UUT Internal - AD9361 Adapter AXI-Stream"
catch {
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/tx_stream_TDATA
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/tx_stream_TVALID
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/tx_stream_TREADY
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/tx_stream_TLAST
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/rx_stream_TDATA
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/rx_stream_TVALID
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/rx_stream_TREADY
    add wave -hex /vivado_tb/dut/Top_i/axi_ad9361_adapter/rx_stream_TLAST
}

add wave -divider "UUT Internal - TX CDC FIFO"
catch {
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/s_axis_aclk
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/m_axis_aclk
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/s_axis_tvalid
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/s_axis_tready
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/s_axis_tlast
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/m_axis_tvalid
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/m_axis_tready
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_tx_streaming_fifo/m_axis_tlast
}

add wave -divider "UUT Internal - RX CDC FIFO"
catch {
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/s_axis_aclk
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/m_axis_aclk
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/s_axis_tvalid
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/s_axis_tready
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/s_axis_tlast
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/m_axis_tvalid
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/m_axis_tready
    add wave -hex /vivado_tb/dut/Top_i/ad9361_cdc_rx_streaming_fifo/m_axis_tlast
}

add wave -divider "UUT Internal - Streaming Adapter (150 MHz)"
catch {
    add wave -hex /vivado_tb/dut/Top_i/axi_streaming_adapter/ap_clk
    add wave -hex /vivado_tb/dut/Top_i/axi_streaming_adapter/ap_rst_n
    add wave -hex /vivado_tb/dut/Top_i/axi_streaming_adapter/state
    add wave -hex /vivado_tb/dut/Top_i/axi_streaming_adapter/tx_ptr
    add wave -hex /vivado_tb/dut/Top_i/axi_streaming_adapter/rx_ptr
    add wave -hex /vivado_tb/dut/Top_i/axi_streaming_adapter/rx_buffer_ready
}

configure wave -namecolwidth 400
configure wave -valuecolwidth 120
configure wave -signalnamewidth 1

view wave
view structure
view signals

}
# end if DETAILED

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

if {$DETAILED eq "yes"} {
    catch {wave zoom full}
}
