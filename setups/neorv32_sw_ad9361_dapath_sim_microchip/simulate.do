# ================================================================================
# AD9361 Datapath Simulation (Microchip mpf300) - Questa Prime Simulation Script
# ================================================================================
# Microchip counterpart of ../neorv32_sw_ad9361_datapath_sim/sim/simulate.do.
# Usage: vsim [-c] -do "set SIM_TIME {20ms}; set DETAILED {no}; do simulate.do"
# ================================================================================

do compile.do

if {![info exists SIM_TIME]} { set SIM_TIME "20ms" }
if {![info exists DETAILED]} { set DETAILED "no" }

puts ""
puts "=========================================="
puts "Starting mpf300 AD9361 Datapath Simulation"
puts "Simulation time: $SIM_TIME  (detailed: $DETAILED)"
puts "=========================================="

# +acc=rn is enough for the TB's hierarchical monitors and the
# dac_sync_enable force; npr adds full net visibility for waveform debug
if {$DETAILED eq "yes"} {
    set ACC "+acc=npr"
} else {
    set ACC "+acc=rn"
}

vopt -quiet $ACC -suppress 10016 \
    -L work -L polarfire -L neorv32 \
    work.mpf300_tb \
    -o mpf300_tb_opt

vsim -t 1ps -onfinish stop -lib work mpf300_tb_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

if {$DETAILED eq "yes"} {
    log -r /*
    add wave -divider "Clocks and Reset"
    add wave /mpf300_tb/ref_clk_50mhz
    add wave /mpf300_tb/sim_clk_125mhz
    add wave /mpf300_tb/sim_clk_125mhz_locked
    add wave /mpf300_tb/system_resetn
    add wave /mpf300_tb/dut/axi_ad9361_0/l_clk
    add wave -divider "GPIO"
    add wave -radix hex /mpf300_tb/sim_gpio_o
    add wave -divider "LVDS"
    add wave /mpf300_tb/rx_clk_in_p
    add wave /mpf300_tb/rx_frame_in_p
    add wave -radix hex /mpf300_tb/rx_data_in_p
    add wave /mpf300_tb/tx_frame_out_p
    add wave -radix hex /mpf300_tb/tx_data_out_p
    add wave -divider "UART"
    add wave /mpf300_tb/uart0_txd
}

set start_time [clock milliseconds]

run $SIM_TIME

set elapsed_sec [format "%.1f" [expr {([clock milliseconds] - $start_time) / 1000.0}]]
puts ""
puts "=========================================="
puts "Simulation stopped (wall clock: ${elapsed_sec}s)"
puts "=========================================="
