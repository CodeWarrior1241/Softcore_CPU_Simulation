###############################################################################
#
# Top-level build script for simulation-only project
#
# Usage: vivado -mode batch -source build_all.tcl
#    or: vivado -mode tcl -source build_all.tcl
#
###############################################################################

# Project configuration
set project_name "NEORV32_Simulation"
set part "xcau15p-ffvb676-2-e"
set project_dir [file dirname [info script]]
set top_level_bd_name "Top"

# Block design component names
set neorv32_cpu "NEORV32_RISC_V"
set ecs_clock_300_mhz "ECS_Clock_300MHz"
set cpu_sys_reset "CPU_Reset"
set neorv32_cpu_input_reset "NEORV32_CPU_Input_Reset_Inv"
set axi_cpu_interconnect "AXI_CPU_Interconnect"
set axi_bram_controller "AXI_BRAM_Controller"
set qpsk_snapshot_bram "QPSK_Snapshot_BRAM"

###############################################################################
# Board file check and installation instructions
###############################################################################

proc check_board_files {} {
    # Try to get the AU15P board - if it fails, board files are not installed
    set boards [get_board_parts -quiet "*auboard_15p*"]

    if {[llength $boards] == 0} {
        puts ""
        puts "==============================================================================="
        puts "  ERROR: Avnet AU15P board definition files not found in Vivado"
        puts "==============================================================================="
        puts ""
        puts "  The AU15P board files must be installed before building this project."
        puts ""
        puts "  Installation Instructions:"
        puts "  ---------------------------"
        puts ""
        puts "  1. Download the AU15P board files from Avnet:"
        puts "       https://avnet.github.io/bdf/"
        puts ""
        puts "  2. Copy the 'aub15p' folder to the Vivado board_files directory:"
        puts ""
        puts "     WINDOWS (requires admin privileges):"
        puts "       Copy to: <Vivado_Install>/data/boards/board_files/"
        puts "       Example: C:\\Xilinx\\Vivado\\2025.2\\data\\boards\\board_files\\aub15p"
        puts ""
        puts "     WINDOWS (user-specific, no admin required):"
        puts "       Copy to: %APPDATA%\\Xilinx\\Vivado\\board_files\\"
        puts "       Example: C:\\Users\\<username>\\AppData\\Roaming\\Xilinx\\Vivado\\board_files\\aub15p"
        puts ""
        puts "     LINUX (system-wide):"
        puts "       Copy to: <Vivado_Install>/data/boards/board_files/"
        puts "       Example: /opt/Xilinx/Vivado/2025.2/data/boards/board_files/aub15p"
        puts ""
        puts "     LINUX (user-specific, no admin required):"
        puts "       Copy to: ~/.Xilinx/Vivado/board_files/"
        puts "       Example: /home/<username>/.Xilinx/Vivado/board_files/aub15p"
        puts ""
        puts "  3. Restart Vivado and re-run this script."
        puts ""
        puts "==============================================================================="
        puts ""
        return 0
    }

    puts "INFO: AU15P board definition found: $boards"
    return 1
}

###############################################################################
# Main build flow
###############################################################################

puts ""
puts "==============================================================================="
puts "  Simulation project for NEORV32 RISC-V CPU - Build Script"
puts "==============================================================================="
puts ""
puts "  Project: $project_name"
puts "  Part:    $part"
puts "  Dir:     $project_dir"
puts ""

# Create the project targeting the AU15P part
# This will fail gracefully if board files are missing - we just use the part
puts "INFO: Creating project..."

if {[catch {create_project $project_name . -part $part -force} result]} {
    puts "ERROR: Failed to create project: $result"
    exit 1
}

# Check if board files are installed (optional but recommended)
if {[check_board_files]} {
    # Set the board part if available
    set board_part [lindex [get_board_parts -quiet "*auboard_15p*"] 0]
    if {$board_part ne ""} {
        set_property board_part $board_part [current_project]
        puts "INFO: Board part set to: $board_part"
    }
} else {
    puts "WARNING: Continuing without board files (using part only)"
    puts "         Some IP presets may not be available."
}

puts ""
puts "INFO: Project created successfully."
puts ""
puts "==============================================================================="
puts "  Next steps will be added here..."
puts "==============================================================================="
puts ""

# Save off the critical sources names
set synth_sources_name [get_filesets -filter {FILESET_TYPE == "DesignSrcs"}]
set sim_sources_name [get_filesets -filter {FILESET_TYPE == "SimulationSrcs"}]
set impl_sources_name [get_filesets -filter {FILESET_TYPE == "Constrs"}]

# Create the top level block design
create_bd_design $top_level_bd_name
update_compile_order -fileset $synth_sources_name

###############################################################################
# NEORV32 RISC-V Processor
###############################################################################

# Path to NEORV32 sources (repository root, two levels up from setups/vivado/)
set neorv32_home [file normalize "$project_dir/../.."]

# Package NEORV32 as Vivado IP (using existing script)
# Note: neorv32_vivado_ip.tcl creates its own project, packages the IP, then closes it
puts "INFO: Packaging NEORV32 as Vivado IP..."
set neorv32_ip_output_dir "$neorv32_home/rtl/system_integration/neorv32_vivado_ip_work"
source $neorv32_home/rtl/system_integration/neorv32_vivado_ip.tcl

# The neorv32_vivado_ip.tcl script creates/closes its own project for packaging.
# Our project should still be current, but the block design may need reopening.

# Add NEORV32 IP to our project's repository paths
puts "INFO: Adding NEORV32 IP to repository..."
set current_ip_paths [get_property ip_repo_paths [current_project]]
lappend current_ip_paths "$neorv32_ip_output_dir/packaged_ip"
set_property ip_repo_paths $current_ip_paths [current_project]
update_ip_catalog -rebuild

# Reopen the block design
open_bd_design ./$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd

# Instantiate NEORV32 in block design
puts "INFO: Instantiating NEORV32 in block design..."
create_bd_cell -type ip -vlnv NEORV32:user:neorv32_vivado_ip:1.0 $neorv32_cpu

# Configure NEORV32 for AU15P / FMCOMMS4 application
set_property -dict [list \
    CONFIG.CLOCK_FREQUENCY {100000000} \
    CONFIG.BOOT_MODE_SELECT {0} \
    CONFIG.IMEM_EN {true} \
    CONFIG.IMEM_SIZE {32768} \
    CONFIG.DMEM_EN {true} \
    CONFIG.DMEM_SIZE {16384} \
    CONFIG.RISCV_ISA_C {true} \
    CONFIG.RISCV_ISA_M {true} \
    CONFIG.RISCV_ISA_Zicntr {true} \
    CONFIG.CPU_FAST_MUL_EN {true} \
    CONFIG.CPU_FAST_SHIFT_EN {true} \
    CONFIG.IO_UART0_EN {true} \
    CONFIG.IO_UART0_RX_FIFO {32} \
    CONFIG.IO_UART0_TX_FIFO {32} \
    CONFIG.IO_GPIO_EN {true} \
    CONFIG.IO_GPIO_IN_NUM {8} \
    CONFIG.IO_GPIO_OUT_NUM {8} \
    CONFIG.IO_SPI_EN {true} \
    CONFIG.IO_SPI_FIFO {4} \
    CONFIG.XBUS_EN {true} \
    CONFIG.XBUS_TIMEOUT {255} \
    CONFIG.IO_CLINT_EN {true} \
] [get_bd_cells $neorv32_cpu]

puts "INFO: NEORV32 configured (RV32IMC, 32KB IMEM, 16KB DMEM)"

# Add board clock input and MMCM
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 $ecs_clock_300_mhz
set_property -dict [list \
    CONFIG.AUTO_PRIMITIVE {PLL} \
    CONFIG.CLKIN1_JITTER_PS {100.0} \
    CONFIG.CLKOUT1_DRIVES {Buffer} \
    CONFIG.CLKOUT1_JITTER {144.719} \
    CONFIG.CLKOUT1_PHASE_ERROR {114.212} \
    CONFIG.CLKOUT2_DRIVES {Buffer} \
    CONFIG.CLKOUT3_DRIVES {Buffer} \
    CONFIG.CLKOUT4_DRIVES {Buffer} \
    CONFIG.CLKOUT5_DRIVES {Buffer} \
    CONFIG.CLKOUT6_DRIVES {Buffer} \
    CONFIG.CLKOUT7_DRIVES {Buffer} \
    CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {8} \
    CONFIG.MMCM_CLKIN1_PERIOD {10.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {8} \
    CONFIG.MMCM_COMPENSATION {AUTO} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.OPTIMIZE_CLOCKING_STRUCTURE_EN {true} \
    CONFIG.PRIMITIVE {Auto} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.RESET_BOARD_INTERFACE {system_resetn} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.USE_LOCKED {false} \
  CONFIG.USE_RESET {true} \
] [get_bd_cells $ecs_clock_300_mhz]

# Configure ECS 300MHz input board clock I/O
startgroup
    make_bd_intf_pins_external  [get_bd_intf_pins $ecs_clock_300_mhz/CLK_IN1_D]
    set_property name ecs_clk_in [get_bd_intf_ports CLK_IN1_D_0]
    set_property CONFIG.FREQ_HZ 300000000 [get_bd_intf_ports /ecs_clk_in]
    make_bd_pins_external  [get_bd_pins $ecs_clock_300_mhz/resetn]
    set_property name system_resetn [get_bd_ports resetn_0]
    set_property -dict [list \
    CONFIG.CLKIN1_JITTER_PS {33.330000000000005} \
    CONFIG.CLKOUT1_JITTER {143.207} \
    CONFIG.MMCM_CLKIN1_PERIOD {3.333} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
    CONFIG.MMCM_DIVCLK_DIVIDE {3} \
    CONFIG.PRIM_IN_FREQ {300.000} \
    ] [get_bd_cells $ecs_clock_300_mhz]
endgroup

# Create reset and clocking
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $cpu_sys_reset

# Create inverter for the NEORV32 active low input reset
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 $neorv32_cpu_input_reset
set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
] [get_bd_cells $neorv32_cpu_input_reset]

# Create the external UART signals
startgroup
    make_bd_pins_external  [get_bd_pins $neorv32_cpu/uart0_rxd_i]
    set_property name uart0_rxd [get_bd_ports uart0_rxd_i_0]
    make_bd_pins_external  [get_bd_pins $neorv32_cpu/uart0_txd_o]
    set_property name uart0_txd [get_bd_ports uart0_txd_o_0]
endgroup

# Create the main AXI CPU interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $axi_cpu_interconnect
set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
] [get_bd_cells $axi_cpu_interconnect]

# Create the AXI BRAM controller and the BRAM block itself
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 $axi_bram_controller
set_property CONFIG.SINGLE_PORT_BRAM {1} [get_bd_cells $axi_bram_controller]
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 $qpsk_snapshot_bram
set_property -dict [list CONFIG.Enable_32bit_Address.VALUE_SRC PROPAGATED] [get_bd_cells $qpsk_snapshot_bram]

# Load the BRAM initialization file
set coe_file [file normalize "$project_dir/sim/qpsk_bram_init.coe"]
set_property -dict [list \
    CONFIG.Coe_File $coe_file \
    CONFIG.Load_Init_File {true} \
    CONFIG.use_bram_block {Stand_Alone} \
    CONFIG.Fill_Remaining_Memory_Locations {true} \
    CONFIG.Remaining_Memory_Locations {FF} \
] [get_bd_cells $qpsk_snapshot_bram]

# Connect critical async resets and clocks for both reset blocks
connect_bd_net [get_bd_ports system_resetn] [get_bd_pins $cpu_sys_reset/ext_reset_in]
connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $cpu_sys_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $neorv32_cpu/clk]
connect_bd_net [get_bd_pins $cpu_sys_reset/mb_reset] [get_bd_pins $neorv32_cpu_input_reset/Op1]
connect_bd_net [get_bd_pins $neorv32_cpu_input_reset/Res] [get_bd_pins $neorv32_cpu/resetn]
connect_bd_net [get_bd_pins $axi_cpu_interconnect/aclk] [get_bd_pins $ecs_clock_300_mhz/clk_out1]
connect_bd_net [get_bd_pins $axi_cpu_interconnect/aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]
connect_bd_net [get_bd_pins $axi_bram_controller/s_axi_aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]
connect_bd_net [get_bd_pins $axi_bram_controller/s_axi_aclk] [get_bd_pins $ecs_clock_300_mhz/clk_out1]

# Connect internal AXI signals and BRAM memory signals
connect_bd_intf_net [get_bd_intf_pins $neorv32_cpu/m_axi] [get_bd_intf_pins $axi_cpu_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_bram_controller/S_AXI] [get_bd_intf_pins $axi_cpu_interconnect/M00_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_bram_controller/BRAM_PORTA] [get_bd_intf_pins $qpsk_snapshot_bram/BRAM_PORTA]

# Assign addressing for AXI peripherals and prepare the top level
assign_bd_address -target_address_space /NEORV32_RISC_V/m_axi [get_bd_addr_segs $axi_bram_controller/S_AXI/Mem0] -force
validate_bd_design
save_bd_design
set_property target_language VHDL [current_project]
make_wrapper -files [get_files $project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd] -top
add_files -norecurse $project_dir/$project_name.gen/$synth_sources_name/bd/$top_level_bd_name/hdl/${top_level_bd_name}_wrapper.vhd
save_bd_design

# Generate output products for all IP used so that it can be used for simulation
update_compile_order -fileset sources_1

# Build path to block design file using variables
set bd_file "$project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd"

# Create all of the synthesis HDL for subsequent simulation use
generate_target all [get_files $bd_file]
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${neorv32_cpu}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${ecs_clock_300_mhz}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${cpu_sys_reset}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${neorv32_cpu_input_reset}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${axi_cpu_interconnect}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${axi_bram_controller}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${qpsk_snapshot_bram}_0] }
export_ip_user_files -of_objects [get_files $bd_file] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $bd_file]
launch_runs ${top_level_bd_name}_${axi_bram_controller}_0_synth_1 ${top_level_bd_name}_${axi_cpu_interconnect}_0_synth_1 ${top_level_bd_name}_${cpu_sys_reset}_0_synth_1 ${top_level_bd_name}_${ecs_clock_300_mhz}_0_synth_1 ${top_level_bd_name}_${neorv32_cpu_input_reset}_0_synth_1 ${top_level_bd_name}_${neorv32_cpu}_0_synth_1 ${top_level_bd_name}_${qpsk_snapshot_bram}_0_synth_1 -jobs 16
