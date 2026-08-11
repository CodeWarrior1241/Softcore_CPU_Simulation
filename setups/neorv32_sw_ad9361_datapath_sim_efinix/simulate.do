# ================================================================================
# AD9361 Datapath Simulation (Efinix ti375) - Questa Prime Simulation Script
# ================================================================================
# Efinix counterpart of ../neorv32_sw_ad9361_dapath_sim_microchip/simulate.do.
# Usage: vsim [-c] -do "set SIM_TIME {20ms}; set DETAILED {no}; do simulate.do"
# ================================================================================

do compile.do

if {![info exists SIM_TIME]} { set SIM_TIME "20ms" }
if {![info exists DETAILED]} { set DETAILED "no" }

puts ""
puts "=========================================="
puts "Starting ti375 AD9361 Datapath Simulation"
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
    -L work -L neorv32 \
    work.ti375_tb \
    -o ti375_tb_opt

vsim -t 1ps -onfinish stop -lib work ti375_tb_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

if {$DETAILED eq "yes"} {
    log -r /*
    add wave -divider "Clocks and Reset"
    add wave /ti375_tb/ref_clk_25mhz
    add wave /ti375_tb/sim_clk_125mhz
    add wave /ti375_tb/sim_clk_125mhz_locked
    add wave /ti375_tb/system_resetn
    add wave /ti375_tb/dut/l_clk
    add wave -divider "SERDES controls"
    add wave {/ti375_tb/dut/u_chip/\system_top_shim~inst /u_system_top/serdes_rst_s}
    add wave -divider "GPIO"
    add wave -radix hex /ti375_tb/sim_gpio_o
    add wave -divider "LVDS pads"
    add wave /ti375_tb/rx_clk_in_p
    add wave /ti375_tb/rx_frame_in_p
    add wave -radix hex /ti375_tb/rx_data_in_p
    add wave /ti375_tb/tx_frame_out_p
    add wave -radix hex /ti375_tb/tx_data_out_p
    add wave -divider "Core words"
    add wave -radix hex {/ti375_tb/dut/u_chip/rx_frame_nb7}
    add wave -radix hex {/ti375_tb/dut/u_chip/tx_frame}
    add wave -divider "UART"
    add wave /ti375_tb/uart0_txd
}

set start_time [clock milliseconds]

run $SIM_TIME

set elapsed_sec [format "%.1f" [expr {([clock milliseconds] - $start_time) / 1000.0}]]
puts ""
puts "=========================================="
puts "Simulation stopped (wall clock: ${elapsed_sec}s)"
puts "=========================================="
