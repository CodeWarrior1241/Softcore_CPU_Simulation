###############################################################################
#
# Top-level build script for simulation-only project with AD9361 datapath
#
# Usage (from Vivado TCL console):
#   cd {C:/Work/Sandbox/QPSK_Triple_Comparison/deps/neorv32/setups/neorv32_sw_ad9361_datapath_sim}
#   source build_all.tcl
#   build_all
#
# Environment Variables (required):
#   ADI_IP_LOCATION - Path to ADI IP library root (e.g., deps/hdl/library)
#                     Set in ~/.bashrc:
#                       export ADI_IP_LOCATION=/path/to/deps/hdl/library
#
###############################################################################

###############################################################################
# Project configuration (global variables)
###############################################################################

variable project_name "NEORV32_Simulation"
variable part "xcau15p-ffvb676-2-e"
variable project_dir [file dirname [info script]]
variable top_level_bd_name "Top"

###############################################################################
# Block design component names
###############################################################################

# NEORV32 CPU and infrastructure
variable neorv32_cpu "NEORV32_RISC_V"
variable ecs_clock_300_mhz "ECS_Clock_300MHz"
variable cpu_sys_reset "CPU_Reset"
variable neorv32_cpu_input_reset "NEORV32_CPU_Input_Reset_Inv"
variable axi_cpu_interconnect "AXI_CPU_Interconnect"

# BRAM for IQ snapshot data
variable axi_bram_controller "AXI_BRAM_Controller"
variable qpsk_snapshot_bram "QPSK_Snapshot_BRAM"

# AD9361 core and datapath
variable axi_ad9361 "axi_ad9361"
variable axi_ad9361_adapter "axi_ad9361_adapter"

# Clock divider logic for AD9361 sampling clock
variable util_ad9361_divclk "util_ad9361_divclk"
variable util_ad9361_divclk_sel "util_ad9361_divclk_sel"
variable util_ad9361_divclk_sel_concat "util_ad9361_divclk_sel_concat"
variable util_ad9361_divclk_reset "util_ad9361_divclk_reset"

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
# Main build procedure
###############################################################################

proc build_all {} {
    # Import global variables
    global project_name part project_dir top_level_bd_name
    global neorv32_cpu ecs_clock_300_mhz cpu_sys_reset neorv32_cpu_input_reset axi_cpu_interconnect
    global axi_bram_controller qpsk_snapshot_bram
    global axi_ad9361 axi_ad9361_adapter
    global util_ad9361_divclk util_ad9361_divclk_sel util_ad9361_divclk_sel_concat util_ad9361_divclk_reset

    # Read ADI IP directory from environment variable
    if {![info exists ::env(ADI_IP_LOCATION)]} {
        puts ""
        puts "==============================================================================="
        puts "  ERROR: ADI_IP_LOCATION environment variable not set"
        puts "==============================================================================="
        puts ""
        puts "  Set it to point to the ADI HDL IP library root:"
        puts ""
        puts "    Windows: set ADI_IP_LOCATION=C:\\Work\\QPSK_Triple_Comparison\\deps\\hdl\\library"
        puts "    Linux:   export ADI_IP_LOCATION=/path/to/deps/hdl/library"
        puts ""
        puts "  The ADI library IPs must be built first:"
        puts ""
        puts "    cd deps/hdl/projects/fmcomms2/kcu105"
        puts "    make"
        puts ""
        puts "==============================================================================="
        return -1
    }
    set adi_ip_dir [file normalize $::env(ADI_IP_LOCATION)]
    if {![file exists $adi_ip_dir]} {
        puts "ERROR: ADI IP directory does not exist: $adi_ip_dir"
        return -1
    }
    puts "INFO: Using ADI IP directory: $adi_ip_dir"

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
        return -1
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

###############################################################################
# Install NEORV32 Software Image (ad9361_loopback)
###############################################################################
# Copy the pre-built ad9361_loopback application image into rtl/core/
# so that IP packaging picks up the correct program.
# If the pre-built image is missing, fall back to compiling from source.

set sw_app_dir  "$neorv32_home/sw/ad9361_loopback"
set prebuilt    "$sw_app_dir/neorv32_imem_image.vhd"
set app_image   "$neorv32_home/rtl/core/neorv32_imem_image.vhd"

if {[file exists $prebuilt]} {
    puts "INFO: Installing pre-built ad9361_loopback image..."
    file copy -force $prebuilt $app_image
    puts "INFO: $prebuilt → $app_image"
} else {
    # No pre-built image — compile from source (requires RISC-V GCC in PATH)
    if {![file exists "$sw_app_dir/main.c"]} {
        puts "ERROR: ad9361_loopback source not found: $sw_app_dir/main.c"
        return -1
    }
    puts "INFO: Pre-built image not found, compiling ad9361_loopback from source..."
    if {[catch {exec make -C $sw_app_dir clean_all image install 2>@1} build_log]} {
        puts $build_log
        puts ""
        puts "ERROR: Failed to build ad9361_loopback application."
        puts "  Ensure the RISC-V GCC toolchain is in your PATH:"
        puts "    riscv-none-elf-gcc --version"
        return -1
    }
    puts $build_log
}

if {![file exists $app_image]} {
    puts "ERROR: Application image not found: $app_image"
    return -1
}

# Package NEORV32 as Vivado IP (using existing script)
# Note: neorv32_vivado_ip.tcl creates its own project, packages the IP, then closes it
puts "INFO: Packaging NEORV32 as Vivado IP..."
set neorv32_ip_output_dir "$neorv32_home/rtl/system_integration/neorv32_vivado_ip_work"
source $neorv32_home/rtl/system_integration/neorv32_vivado_ip.tcl

# The neorv32_vivado_ip.tcl script creates/closes its own project for packaging.
# Our project should still be current, but the block design may need reopening.

###############################################################################
# AXI AD9361 Adapter HLS IP
###############################################################################

# Use pre-built HLS IP from the project-level src directory
# Navigate up 4 levels: neorv32_sw_ad9361_datapath_sim -> setups -> neorv32 -> deps -> project root
set hls_ip_dir [file normalize "$project_dir/../../../../src/axiad9361_adapter/axiad9361_adapter/hls/impl/ip"]

if {![file exists $hls_ip_dir]} {
    puts "ERROR: HLS IP directory not found: $hls_ip_dir"
    puts "       Please build the HLS IP first using Vitis HLS."
    return -1
}
puts "INFO: Using pre-built HLS IP from: $hls_ip_dir"

# Add NEORV32 IP, ADI IP, and HLS IP to our project's repository paths
#
# ADI IPs must be added as individual directories rather than using the parent
# library/ path. The ADI library/ tree contains ~90 subdirectories, most without
# a valid component.xml (only built IPs have one). Pointing Vivado at the parent
# causes the IP catalog scan to fail silently when it encounters the unpackaged
# directories, resulting in none of the ADI IPs being found.
#
# Additionally, Xilinx-specific ADI IPs live under library/xilinx/ (two levels
# deep), which is beyond Vivado's single-level ip_repo_paths scan depth.
#
# Required ADI IPs for this build (from FMCOMMS2 reference design):
#   - axi_ad9361       (library/axi_ad9361)            - AD9361 transceiver core
#   - axi_dmac         (library/axi_dmac)              - AXI DMA controller
#   - axi_sysid        (library/axi_sysid)             - System identification
#   - sysid_rom        (library/sysid_rom)             - System ID ROM
#   - util_cdc         (library/util_cdc)              - Clock domain crossing
#   - util_axis_fifo   (library/util_axis_fifo)        - AXI-Stream FIFO
#   - util_rfifo       (library/util_rfifo)            - Read FIFO
#   - util_wfifo       (library/util_wfifo)            - Write FIFO
#   - util_tdd_sync    (library/util_tdd_sync)         - TDD synchronization
#   - util_cpack2      (library/util_pack/util_cpack2) - Channel pack
#   - util_upack2      (library/util_pack/util_upack2) - Channel unpack
#   - util_clkdiv      (library/xilinx/util_clkdiv)    - Clock divider
puts "INFO: Adding NEORV32 IP, ADI IP, and HLS IP to repository..."

# ADI IP directories that contain component.xml directly
set adi_direct_ips [list \
    axi_ad9361 \
    axi_dmac \
    axi_sysid \
    sysid_rom \
    util_cdc \
    util_axis_fifo \
    util_rfifo \
    util_wfifo \
    util_tdd_sync \
]

# ADI IP parent directories scanned one level deep by Vivado
# (covers IPs nested two levels below library/)
set adi_scan_dirs [list \
    "$adi_ip_dir/util_pack" \
    "$adi_ip_dir/xilinx" \
]

# Validate that all required ADI IPs are packaged (component.xml exists)
foreach ip $adi_direct_ips {
    if {![file exists "$adi_ip_dir/$ip/component.xml"]} {
        puts ""
        puts "==============================================================================="
        puts "  ERROR: ADI $ip IP not packaged"
        puts "==============================================================================="
        puts ""
        puts "  Expected: $adi_ip_dir/$ip/component.xml"
        puts ""
        puts "  The ADI library IPs must be built before this project."
        puts "  Build the FMCOMMS2 reference design to package all required IPs:"
        puts ""
        puts "    cd deps/hdl/projects/fmcomms2/kcu105"
        puts "    make"
        puts ""
        puts "==============================================================================="
        return -1
    }
}

# Validate scan directories exist
foreach scan_dir $adi_scan_dirs {
    if {![file isdirectory $scan_dir]} {
        puts ""
        puts "==============================================================================="
        puts "  ERROR: ADI IP directory not found: $scan_dir"
        puts "==============================================================================="
        puts ""
        puts "  Build the FMCOMMS2 reference design to package all required IPs:"
        puts ""
        puts "    cd deps/hdl/projects/fmcomms2/kcu105"
        puts "    make"
        puts ""
        puts "==============================================================================="
        return -1
    }
}

set current_ip_paths [get_property ip_repo_paths [current_project]]
lappend current_ip_paths "$neorv32_ip_output_dir/packaged_ip"
foreach ip $adi_direct_ips {
    lappend current_ip_paths "$adi_ip_dir/$ip"
}
foreach scan_dir $adi_scan_dirs {
    lappend current_ip_paths $scan_dir
}
lappend current_ip_paths $hls_ip_dir
set_property ip_repo_paths $current_ip_paths [current_project]
update_ip_catalog -rebuild

puts "INFO: IP repo paths:"
foreach p [get_property ip_repo_paths [current_project]] {
    puts "  $p"
}

# Reopen the block design
open_bd_design ./$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd

# Instantiate NEORV32 in block design
puts "INFO: Instantiating NEORV32 in block design..."
create_bd_cell -type ip -vlnv NEORV32:user:neorv32_vivado_ip:1.0 $neorv32_cpu

# Configure NEORV32 for AU15P / FMCOMMS4 application
set_property -dict [list \
    CONFIG.CLOCK_FREQUENCY {100000000} \
    CONFIG.BOOT_MODE_SELECT {2} \
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
    CONFIG.IO_TRACER_EN {true} \
    CONFIG.IO_TRACER_BUFFER {32} \
    CONFIG.IO_TRACER_SIMLOG_EN {true} \
] [get_bd_cells $neorv32_cpu]

puts "INFO: NEORV32 configured (RV32IMC, 32KB IMEM, 16KB DMEM, TRACER enabled)"

# Add board clock input and MMCM
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 $ecs_clock_300_mhz
set_property -dict [list \
    CONFIG.AUTO_PRIMITIVE {PLL} \
    CONFIG.CLKOUT1_JITTER {101.573} \
    CONFIG.CLKOUT1_PHASE_ERROR {84.323} \
    CONFIG.CLKOUT2_JITTER {81.816} \
    CONFIG.CLKOUT2_PHASE_ERROR {84.323} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_DRIVES {Buffer} \
    CONFIG.CLKOUT3_DRIVES {Buffer} \
    CONFIG.CLKOUT4_DRIVES {Buffer} \
    CONFIG.CLKOUT5_DRIVES {Buffer} \
    CONFIG.CLKOUT6_DRIVES {Buffer} \
    CONFIG.CLKOUT7_DRIVES {Buffer} \
    CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {3} \
    CONFIG.MMCM_CLKIN1_PERIOD {10.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {9} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {3} \
    CONFIG.NUM_OUT_CLKS {2} \
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
    CONFIG.USE_LOCKED {true} \
    ] [get_bd_cells $ecs_clock_300_mhz]
    make_bd_pins_external  [get_bd_pins $ecs_clock_300_mhz/locked]
    set_property name sim_clock_100MHz_locked [get_bd_ports locked_0]
    make_bd_pins_external  [get_bd_pins $ecs_clock_300_mhz/clk_out1]
    set_property name sim_clock_100MHz [get_bd_ports clk_out1_0]
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
# NUM_MI = 3: BRAM controller, axi_ad9361, axi_ad9361_adapter
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $axi_cpu_interconnect
set_property -dict [list \
    CONFIG.NUM_MI {3} \
    CONFIG.NUM_SI {1} \
] [get_bd_cells $axi_cpu_interconnect]

###############################################################################
# QPSK Snapshot BRAM (same as bram_sw_readback_sim)
###############################################################################

# Create the AXI BRAM controller and the BRAM block itself
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 $axi_bram_controller
set_property CONFIG.SINGLE_PORT_BRAM {1} [get_bd_cells $axi_bram_controller]
set_property CONFIG.READ_LATENCY {2} [get_bd_cells $axi_bram_controller]
set_property CONFIG.PROTOCOL {AXI4} [get_bd_cells $axi_bram_controller]
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 $qpsk_snapshot_bram
set_property -dict [list CONFIG.Enable_32bit_Address.VALUE_SRC PROPAGATED] [get_bd_cells $qpsk_snapshot_bram]

# Load the BRAM initialization file
# BRAM cannot be pre-loaded with a COE if in BRAM Controller mode, so leave as Stand Alone
# With this the case, the BRAM Controller can't handle latency of the BRAM if it's greater than 1, so leave in Always Enabled instead of strobed
set coe_file [file normalize "$project_dir/sim/qpsk_bram_init.coe"]
set_property -dict [list \
    CONFIG.Coe_File $coe_file \
    CONFIG.Load_Init_File {true} \
    CONFIG.use_bram_block {Stand_Alone} \
    CONFIG.Enable_32bit_Address {true} \
    CONFIG.Enable_A {Always_Enabled} \
    CONFIG.EN_SAFETY_CKT {false} \
    CONFIG.Register_PortA_Output_of_Memory_Core {false} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {true} \
    CONFIG.Use_RSTA_Pin {false} \
    CONFIG.Fill_Remaining_Memory_Locations {true} \
    CONFIG.Remaining_Memory_Locations {FF} \
] [get_bd_cells $qpsk_snapshot_bram]

###############################################################################
# AD9361 Core
###############################################################################

puts "INFO: Instantiating AD9361 core and datapath..."

# Create AD9361 core
create_bd_cell -type ip -vlnv analog.com:user:axi_ad9361:1.0 $axi_ad9361
set_property -dict [list \
    CONFIG.ID {0} \
    CONFIG.DAC_DDS_TYPE {1} \
    CONFIG.DAC_DDS_CORDIC_DW {14} \
] [get_bd_cells $axi_ad9361]

# Create external ports for AD9361 LVDS interface
# RX ports
create_bd_port -dir I rx_clk_in_p
create_bd_port -dir I rx_clk_in_n
create_bd_port -dir I rx_frame_in_p
create_bd_port -dir I rx_frame_in_n
create_bd_port -dir I -from 5 -to 0 rx_data_in_p
create_bd_port -dir I -from 5 -to 0 rx_data_in_n

# TX ports
create_bd_port -dir O tx_clk_out_p
create_bd_port -dir O tx_clk_out_n
create_bd_port -dir O tx_frame_out_p
create_bd_port -dir O tx_frame_out_n
create_bd_port -dir O -from 5 -to 0 tx_data_out_p
create_bd_port -dir O -from 5 -to 0 tx_data_out_n

# Control ports (directly from axi_ad9361)
create_bd_port -dir O enable
create_bd_port -dir O txnrx

# Connect AD9361 LVDS ports
connect_bd_net [get_bd_ports rx_clk_in_p] [get_bd_pins $axi_ad9361/rx_clk_in_p]
connect_bd_net [get_bd_ports rx_clk_in_n] [get_bd_pins $axi_ad9361/rx_clk_in_n]
connect_bd_net [get_bd_ports rx_frame_in_p] [get_bd_pins $axi_ad9361/rx_frame_in_p]
connect_bd_net [get_bd_ports rx_frame_in_n] [get_bd_pins $axi_ad9361/rx_frame_in_n]
connect_bd_net [get_bd_ports rx_data_in_p] [get_bd_pins $axi_ad9361/rx_data_in_p]
connect_bd_net [get_bd_ports rx_data_in_n] [get_bd_pins $axi_ad9361/rx_data_in_n]
connect_bd_net [get_bd_ports tx_clk_out_p] [get_bd_pins $axi_ad9361/tx_clk_out_p]
connect_bd_net [get_bd_ports tx_clk_out_n] [get_bd_pins $axi_ad9361/tx_clk_out_n]
connect_bd_net [get_bd_ports tx_frame_out_p] [get_bd_pins $axi_ad9361/tx_frame_out_p]
connect_bd_net [get_bd_ports tx_frame_out_n] [get_bd_pins $axi_ad9361/tx_frame_out_n]
connect_bd_net [get_bd_ports tx_data_out_p] [get_bd_pins $axi_ad9361/tx_data_out_p]
connect_bd_net [get_bd_ports tx_data_out_n] [get_bd_pins $axi_ad9361/tx_data_out_n]
connect_bd_net [get_bd_ports enable] [get_bd_pins $axi_ad9361/enable]
connect_bd_net [get_bd_ports txnrx] [get_bd_pins $axi_ad9361/txnrx]

# Connect delay_clk for IODELAY calibration
connect_bd_net [get_bd_pins $axi_ad9361/delay_clk] [get_bd_pins $ecs_clock_300_mhz/clk_out2]

# Connect l_clk to itself (AD9361 uses recovered clock internally)
connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $axi_ad9361/clk]

# Connect AXI clock and reset
connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $axi_ad9361/s_axi_aclk]
connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $axi_ad9361/s_axi_aresetn]

# Connect up_enable and up_txnrx from NEORV32 GPIO
# GPIO[0] = up_enable, GPIO[1] = up_txnrx
# Create slice for GPIO bits
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_up_enable_slice
set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells gpio_up_enable_slice]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_up_txnrx_slice
set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1}] [get_bd_cells gpio_up_txnrx_slice]

connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_up_enable_slice/Din]
connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_up_txnrx_slice/Din]
connect_bd_net [get_bd_pins gpio_up_enable_slice/Dout] [get_bd_pins $axi_ad9361/up_enable]
connect_bd_net [get_bd_pins gpio_up_txnrx_slice/Dout] [get_bd_pins $axi_ad9361/up_txnrx]

###############################################################################
# Clock Divider Logic for AD9361 Sampling Clock
# Interface runs at 4x in 2r2t mode, and 2x in 1r1t mode
###############################################################################

puts "INFO: Creating AD9361 clock divider logic..."

# Mode selection concatenation
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 $util_ad9361_divclk_sel_concat
set_property CONFIG.NUM_PORTS {2} [get_bd_cells $util_ad9361_divclk_sel_concat]
connect_bd_net [get_bd_pins $axi_ad9361/adc_r1_mode] [get_bd_pins $util_ad9361_divclk_sel_concat/In0]
connect_bd_net [get_bd_pins $axi_ad9361/dac_r1_mode] [get_bd_pins $util_ad9361_divclk_sel_concat/In1]

# Reduced logic for clock selection
create_bd_cell -type ip -vlnv xilinx.com:ip:util_reduced_logic:2.0 $util_ad9361_divclk_sel
set_property CONFIG.C_SIZE {2} [get_bd_cells $util_ad9361_divclk_sel]
connect_bd_net [get_bd_pins $util_ad9361_divclk_sel_concat/dout] [get_bd_pins $util_ad9361_divclk_sel/Op1]

# Clock divider (ADI IP)
create_bd_cell -type ip -vlnv analog.com:user:util_clkdiv:1.0 $util_ad9361_divclk
connect_bd_net [get_bd_pins $util_ad9361_divclk_sel/Res] [get_bd_pins $util_ad9361_divclk/clk_sel]
connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $util_ad9361_divclk/clk]

# Reset synchronizer for divided clock domain
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $util_ad9361_divclk_reset
connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $util_ad9361_divclk_reset/ext_reset_in]
connect_bd_net [get_bd_pins $util_ad9361_divclk/clk_out] [get_bd_pins $util_ad9361_divclk_reset/slowest_sync_clk]

###############################################################################
# AXI AD9361 Adapter (HLS IP)
# Replaces: util_ad9361_adc_fifo, util_ad9361_adc_pack,
#           axi_ad9361_dac_fifo, util_ad9361_dac_upack
# Provides: Internal TX/RX BRAMs, loopback capability, AXI-Lite control
###############################################################################

puts "INFO: Instantiating AXI AD9361 Adapter..."

# Create the HLS adapter IP
create_bd_cell -type ip -vlnv user:hls:axi_ad9361_adapter:3.0 $axi_ad9361_adapter

# Connect adapter clock and reset (uses AXI clock domain)
connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $axi_ad9361_adapter/ap_clk]
connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $axi_ad9361_adapter/ap_rst_n]

# Connect ADC data from axi_ad9361 to adapter
# Channel 0 I/Q
connect_bd_net [get_bd_pins $axi_ad9361/adc_data_i0] [get_bd_pins $axi_ad9361_adapter/adc_data_i0]
connect_bd_net [get_bd_pins $axi_ad9361/adc_data_q0] [get_bd_pins $axi_ad9361_adapter/adc_data_q0]
connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_i0] [get_bd_pins $axi_ad9361_adapter/adc_enable_i0]
connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_q0] [get_bd_pins $axi_ad9361_adapter/adc_enable_q0]
connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_i0] [get_bd_pins $axi_ad9361_adapter/adc_valid_i0]
connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_q0] [get_bd_pins $axi_ad9361_adapter/adc_valid_q0]

# Channel 1 I/Q
connect_bd_net [get_bd_pins $axi_ad9361/adc_data_i1] [get_bd_pins $axi_ad9361_adapter/adc_data_i1]
connect_bd_net [get_bd_pins $axi_ad9361/adc_data_q1] [get_bd_pins $axi_ad9361_adapter/adc_data_q1]
connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_i1] [get_bd_pins $axi_ad9361_adapter/adc_enable_i1]
connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_q1] [get_bd_pins $axi_ad9361_adapter/adc_enable_q1]
connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_i1] [get_bd_pins $axi_ad9361_adapter/adc_valid_i1]
connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_q1] [get_bd_pins $axi_ad9361_adapter/adc_valid_q1]

# ADC overflow handling
# Note: Both axi_ad9361 and adapter have adc_dovf as INPUTS (from external FIFO in ADI designs)
# In our simplified design without external FIFOs, tie to constant 0 (no overflow source)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 adc_dovf_const
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] [get_bd_cells adc_dovf_const]
connect_bd_net [get_bd_pins adc_dovf_const/dout] [get_bd_pins $axi_ad9361/adc_dovf]
connect_bd_net [get_bd_pins adc_dovf_const/dout] [get_bd_pins $axi_ad9361_adapter/adc_dovf]

# Connect DAC data from adapter to axi_ad9361 (adapter OUTPUT -> axi_ad9361 INPUT)
# Channel 0 I/Q
connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_i0] [get_bd_pins $axi_ad9361/dac_data_i0]
connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_q0] [get_bd_pins $axi_ad9361/dac_data_q0]

# Channel 1 I/Q
connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_i1] [get_bd_pins $axi_ad9361/dac_data_i1]
connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_q1] [get_bd_pins $axi_ad9361/dac_data_q1]

# Connect DAC control signals from axi_ad9361 to adapter (axi_ad9361 OUTPUT -> adapter INPUT)
# dac_valid_* indicates "axi_ad9361 wants data now"
# dac_enable_* indicates which channels are active
# Channel 0 I/Q
connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_i0] [get_bd_pins $axi_ad9361_adapter/dac_valid_i0]
connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_q0] [get_bd_pins $axi_ad9361_adapter/dac_valid_q0]
connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_i0] [get_bd_pins $axi_ad9361_adapter/dac_enable_i0]
connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_q0] [get_bd_pins $axi_ad9361_adapter/dac_enable_q0]

# Channel 1 I/Q
connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_i1] [get_bd_pins $axi_ad9361_adapter/dac_valid_i1]
connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_q1] [get_bd_pins $axi_ad9361_adapter/dac_valid_q1]
connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_i1] [get_bd_pins $axi_ad9361_adapter/dac_enable_i1]
connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_q1] [get_bd_pins $axi_ad9361_adapter/dac_enable_q1]

# Connect DAC underflow from adapter to axi_ad9361 (adapter OUTPUT -> axi_ad9361 INPUT)
connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_dunf] [get_bd_pins $axi_ad9361/dac_dunf]

###############################################################################
# AXI and Reset Connections
###############################################################################

puts "INFO: Connecting clocks, resets, and AXI interfaces..."

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

# Connect axi_ad9361 AXI interface
connect_bd_intf_net [get_bd_intf_pins $axi_ad9361/s_axi] [get_bd_intf_pins $axi_cpu_interconnect/M01_AXI]

# Connect axi_ad9361_adapter AXI-Lite control interface
connect_bd_intf_net [get_bd_intf_pins $axi_ad9361_adapter/s_axi_ctrl] [get_bd_intf_pins $axi_cpu_interconnect/M02_AXI]

###############################################################################
# Address Assignment
###############################################################################

puts "INFO: Assigning addresses..."

# BRAM at 0xC0000000 (32KB range)
assign_bd_address -target_address_space /$neorv32_cpu/m_axi [get_bd_addr_segs $axi_bram_controller/S_AXI/Mem0] -force
set_property offset 0xC0000000 [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_AXI_BRAM_Controller_Mem0}]
set_property range 32K [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_AXI_BRAM_Controller_Mem0}]

# axi_ad9361 at 0x44A00000 (64KB range)
assign_bd_address -target_address_space /$neorv32_cpu/m_axi [get_bd_addr_segs $axi_ad9361/s_axi/axi_lite] -force
set_property offset 0x44A00000 [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_axi_lite}]
set_property range 64K [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_axi_lite}]

# axi_ad9361_adapter at 0x44A10000 (16KB range)
assign_bd_address -target_address_space /$neorv32_cpu/m_axi [get_bd_addr_segs $axi_ad9361_adapter/s_axi_ctrl/Reg] -force
set_property offset 0x44A10000 [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_adapter_Reg}]
set_property range 16K [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_adapter_Reg}]

###############################################################################
# Save and Generate
###############################################################################

validate_bd_design
save_bd_design
set_property target_language VHDL [current_project]
make_wrapper -files [get_files $project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd] -top
add_files -norecurse $project_dir/$project_name.gen/$synth_sources_name/bd/$top_level_bd_name/hdl/${top_level_bd_name}_wrapper.vhd
add_files -fileset constrs_1 -norecurse $project_dir/NEORV32_Simulation.xdc
save_bd_design

# Generate output products for all IP used so that it can be used for simulation
update_compile_order -fileset sources_1

# Build path to block design file using variables
set bd_file "$project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd"

# Create all of the synthesis HDL for subsequent simulation use
generate_target all [get_files $bd_file]

# Export IP cache for all blocks
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${neorv32_cpu}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${ecs_clock_300_mhz}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${cpu_sys_reset}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${neorv32_cpu_input_reset}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${axi_cpu_interconnect}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${axi_bram_controller}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${qpsk_snapshot_bram}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${axi_ad9361}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${axi_ad9361_adapter}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${util_ad9361_divclk}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${util_ad9361_divclk_sel}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${util_ad9361_divclk_sel_concat}_0] }
catch { config_ip_cache -export [get_ips -all ${top_level_bd_name}_${util_ad9361_divclk_reset}_0] }

export_ip_user_files -of_objects [get_files $bd_file] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $bd_file]
set ip_synth_runs [list \
    ${top_level_bd_name}_${neorv32_cpu}_0_synth_1 \
    ${top_level_bd_name}_${ecs_clock_300_mhz}_0_synth_1 \
    ${top_level_bd_name}_${cpu_sys_reset}_0_synth_1 \
    ${top_level_bd_name}_${neorv32_cpu_input_reset}_0_synth_1 \
    ${top_level_bd_name}_${axi_cpu_interconnect}_0_synth_1 \
    ${top_level_bd_name}_${axi_bram_controller}_0_synth_1 \
    ${top_level_bd_name}_${qpsk_snapshot_bram}_0_synth_1 \
    ${top_level_bd_name}_${axi_ad9361}_0_synth_1 \
    ${top_level_bd_name}_${axi_ad9361_adapter}_0_synth_1 \
    ${top_level_bd_name}_${util_ad9361_divclk}_0_synth_1 \
    ${top_level_bd_name}_${util_ad9361_divclk_sel}_0_synth_1 \
    ${top_level_bd_name}_${util_ad9361_divclk_sel_concat}_0_synth_1 \
    ${top_level_bd_name}_${util_ad9361_divclk_reset}_0_synth_1 \
]
launch_runs {*}$ip_synth_runs -jobs 16
wait_on_runs {*}$ip_synth_runs
update_compile_order -fileset sources_1

# Add testbench to simulation fileset
add_files -fileset sim_1 -norecurse $project_dir/sim/vivado_tb.v
set_property top vivado_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

# Make sure the BD and design is exported for third-party simulators to run with
set_property top vivado_tb [current_fileset -simset]
#export_simulation -simulator questa -directory NEORV32_Simulation.ip_user_files/sim_scripts -use_ip_compiled_libs -force
export_simulation -directory NEORV32_Simulation.ip_user_files/sim_scripts -use_ip_compiled_libs -force

# Apply the Questa compile.do fix
fix_questa_compile_do $project_dir

puts ""
puts "==============================================================================="
puts "  Build complete!"
puts "==============================================================================="
puts ""

return 0
}
# End of build_all procedure

###############################################################################
# Questa compile.do library fix
###############################################################################
#
# Vivado's export_simulation command generates compile.do scripts that don't
# properly handle library dependencies for certain Xilinx IP. Specifically:
#
#   - axi_bram_ctrl_v4_1_rfs.vhd must be compiled into axi_bram_ctrl_v4_1_13
#   - proc_sys_reset_v5_0_vh_rfs.vhd must be compiled into proc_sys_reset_v5_0_17
#
# Without this fix, Questa reports errors like:
#   "Recompile axi_bram_ctrl_v4_1_13.axi_bram_ctrl because xpm.vcomponents has changed"
#   "Cannot find expanded name axi_bram_ctrl_v4_1_13.axi_bram_ctrl"
#
# This proc patches the generated compile.do to add proper library mappings.
###############################################################################

proc fix_questa_compile_do {project_dir} {
    set compile_do "$project_dir/NEORV32_Simulation.ip_user_files/sim_scripts/questa/compile.do"

    if {![file exists $compile_do]} {
        puts "WARNING: compile.do not found at $compile_do"
        return
    }

    puts "Patching Questa compile.do for proper library dependencies..."

    # Read the original file
    set fp [open $compile_do r]
    set content [read $fp]
    close $fp

    # Check if already patched
    if {[string match "*vlib questa_lib/msim/axi_bram_ctrl_v4_1_13*" $content]} {
        puts "  compile.do already patched, skipping"
        return
    }

    # Add library creation commands after the existing vlib commands
    set old_vlib_block {vlib questa_lib/msim/xil_defaultlib}
    set new_vlib_block {vlib questa_lib/msim/xil_defaultlib
vlib questa_lib/msim/axi_bram_ctrl_v4_1_13
vlib questa_lib/msim/proc_sys_reset_v5_0_17}

    set content [string map [list $old_vlib_block $new_vlib_block] $content]

    # Add vmap commands after existing vmaps
    set old_vmap_block {vmap xil_defaultlib questa_lib/msim/xil_defaultlib}
    set new_vmap_block {vmap xil_defaultlib questa_lib/msim/xil_defaultlib
vmap axi_bram_ctrl_v4_1_13 questa_lib/msim/axi_bram_ctrl_v4_1_13
vmap proc_sys_reset_v5_0_17 questa_lib/msim/proc_sys_reset_v5_0_17}

    set content [string map [list $old_vmap_block $new_vmap_block] $content]

    # Fix the VHDL compilation: split out the library files into their own libraries
    # Original pattern compiles everything into xil_defaultlib
    # We need to compile axi_bram_ctrl and proc_sys_reset into their own libraries first

    # Find and replace the vcom block that has axi_bram_ctrl_v4_1_rfs.vhd
    set old_vcom_pattern {vcom -work xil_defaultlib  -93  \
"../../../../../../../../Xilinx/2025.2/Vivado/data/ip/xilinx/axi_bram_ctrl_v4_1/hdl/axi_bram_ctrl_v4_1_rfs.vhd" \
"../../../NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_BRAM_Controller_0/sim/Top_AXI_BRAM_Controller_0.vhd" \
"../../../../../../../../Xilinx/2025.2/Vivado/data/ip/xilinx/proc_sys_reset_v5_0/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \
"../../../NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_CPU_Interconnect_0/bd_0/ip/ip_1/sim/bd_e51e_psr_aclk_0.vhd"}

    set new_vcom_pattern {# Compile AXI BRAM Controller library (must be in its own library)
vcom -work axi_bram_ctrl_v4_1_13  -93  \
"../../../../../../../../Xilinx/2025.2/Vivado/data/ip/xilinx/axi_bram_ctrl_v4_1/hdl/axi_bram_ctrl_v4_1_rfs.vhd"

# Compile proc_sys_reset library (must be in its own library)
vcom -work proc_sys_reset_v5_0_17  -93  \
"../../../../../../../../Xilinx/2025.2/Vivado/data/ip/xilinx/proc_sys_reset_v5_0/hdl/proc_sys_reset_v5_0_vh_rfs.vhd"

# Compile design files that use the above libraries
vcom -work xil_defaultlib  -93  \
"../../../NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_BRAM_Controller_0/sim/Top_AXI_BRAM_Controller_0.vhd" \
"../../../NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_CPU_Interconnect_0/bd_0/ip/ip_1/sim/bd_e51e_psr_aclk_0.vhd"}

    set content [string map [list $old_vcom_pattern $new_vcom_pattern] $content]

    # Write back the patched file
    set fp [open $compile_do w]
    puts -nonewline $fp $content
    close $fp

    puts "  compile.do patched successfully"
}

puts ""
puts "==============================================================================="
puts "  build_all.tcl loaded successfully"
puts "==============================================================================="
puts ""
puts "  Usage: build_all"
puts ""
puts "  Requires ADI_IP_LOCATION environment variable to be set:"
puts "    export ADI_IP_LOCATION=/path/to/deps/hdl/library"
puts ""
