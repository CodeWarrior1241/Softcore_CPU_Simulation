# ==============================================================================
# BRAM Readback Testbench - Vivado xsim Runner
# ==============================================================================
# 
# This script uses the Vivado simulator for convenience. The logic under test is
# small enough that performance gains from advanced third party simulators are minimal.
#
# Run this script from Vivado Tcl Console:
#   cd C:/Work/Sandbox/Softcore_CPU_Simulation/setups/vivado
#   source sim/run_bram_tb.tcl
#
# Or from command line:
#   vivado -mode batch -source sim/run_bram_tb.tcl
#
# This script sets up and runs the BRAM readback testbench simulation
# which verifies the complete AXI path to the BRAM.
# This mirrors the actual hardware path used by the CPU.
# The AXI-MM Master BFM was written specifically for this test.
#
# ==============================================================================
# Block Diagram
# ==============================================================================
#
#  +-------------------------------------------+
#  |       snapshot_bram_readback_tb           |
#  |            (AXI Master BFM)               |
#  |                                           |
#  |  - Generates clk/resetn                   |
#  |  - Issues AXI4 reads                      |
#  |  - Compares vs COE file                   |
#  +---------------------+---------------------+
#                        |
#                        | AXI4 (32-bit addr, 32-bit data)
#                        | S00_AXI
#                        v
#  +-------------------------------------------+
#  |       Top_AXI_CPU_Interconnect_0          |
#  |             (SmartConnect)                |
#  |                                           |
#  |  - Address decode                         |
#  |  - Protocol conversion                    |
#  |  - Internal reset sync                    |
#  +---------------------+---------------------+
#                        |
#                        | AXI4 (15-bit addr, 32-bit data)
#                        | M00_AXI
#                        v
#  +-------------------------------------------+
#  |       Top_AXI_BRAM_Controller_0           |
#  |          (AXI BRAM Controller)            |
#  |                                           |
#  |  - AXI4 to BRAM bridge                    |
#  |  - C_MEMORY_DEPTH=8192                    |
#  |  - C_BRAM_ADDR_WIDTH=13                   |
#  +---------------------+---------------------+
#                        |
#                        | BRAM_PORTA (15-bit byte addr)
#                        | -> zero-extended to 32-bit
#                        v
#  +-------------------------------------------+
#  |       Top_QPSK_Snapshot_BRAM_0            |
#  |    (Block Memory Gen - Standalone)        |
#  |                                           |
#  |  - 8192 x 32-bit words (32KB)             |
#  |  - Initialized from COE file              |
#  |  - QPSK IQ samples                        |
#  |  - 32-bit address, 4-bit byte enables     |
#  |  - Internal byte-to-word conversion       |
#  +-------------------------------------------+
#
# Address Map:
#   Base: 0xC0000000
#   Size: 32KB (8192 words x 4 bytes)
#   End:  0xC0007FFF
#
# BRAM Mode: Standalone with 32-bit addressing
#   The BRAM IP is configured for Standalone mode to allow COE initialization:
#   - It accepts 32-bit byte addresses (zero-extended from controller's 15-bit)
#   - It uses 4-bit byte-enable writes (wea[3:0])
#   - Internal logic handles byte-to-word address conversion
#   - COE file provides initial QPSK IQ data for simulation
#
# ==============================================================================

# Get the directory where this script is located
set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]
set vivado_dir "C:/Xilinx/2025.2/Vivado"

puts "Script directory: $script_dir"
puts "Project directory: $project_dir"

# Open the project if not already open
set project_file "$project_dir/NEORV32_Simulation.xpr"
if {[catch {current_project}]} {
    puts "Opening project: $project_file"
    open_project $project_file
} else {
    puts "Project already open: [current_project]"
}

# Delete sim_bram_tb if it exists (to recreate with correct settings)
set sim_filesets [get_filesets -filter {FILESET_TYPE == SimulationSrcs}]
puts "Existing simulation filesets: $sim_filesets"

if {[lsearch -exact $sim_filesets sim_bram_tb] != -1} {
    puts "Switching to sim_1 before deleting sim_bram_tb..."
    # Switch to default sim_1 fileset first
    current_fileset -simset [get_filesets sim_1]
    puts "Deleting existing sim_bram_tb fileset..."
    delete_fileset sim_bram_tb
}

puts "Creating sim_bram_tb fileset..."
create_fileset -simset sim_bram_tb

# Add the testbench file
set tb_file "$script_dir/snapshot_bram_readback_tb.vhd"
puts "Adding testbench: $tb_file"
add_files -fileset sim_bram_tb -norecurse $tb_file

# ==============================================================================
# Add Xilinx IP Simulation Libraries (required for SmartConnect sub-IPs)
# These must be compiled BEFORE the SmartConnect wrapper files
# ==============================================================================

puts "Adding SmartConnect simulation libraries..."

# SmartConnect utility library
set sc_util_lib "$vivado_dir/data/ip/xilinx/sc_util_v1_0/hdl/sc_util_v1_0_vl_rfs.sv"
if {[file exists $sc_util_lib]} {
    puts "  Adding sc_util library"
    add_files -fileset sim_bram_tb -norecurse $sc_util_lib
}

# SmartConnect node library
set sc_node_lib "$vivado_dir/data/ip/xilinx/sc_node_v1_0/hdl/sc_node_v1_0_vl_rfs.sv"
if {[file exists $sc_node_lib]} {
    puts "  Adding sc_node library"
    add_files -fileset sim_bram_tb -norecurse $sc_node_lib
}

# SmartConnect MMU library
set sc_mmu_lib "$vivado_dir/data/ip/xilinx/sc_mmu_v1_0/hdl/sc_mmu_v1_0_vl_rfs.sv"
if {[file exists $sc_mmu_lib]} {
    puts "  Adding sc_mmu library"
    add_files -fileset sim_bram_tb -norecurse $sc_mmu_lib
}

# SmartConnect SI converter library
set sc_si_lib "$vivado_dir/data/ip/xilinx/sc_si_converter_v1_0/hdl/sc_si_converter_v1_0_vl_rfs.sv"
if {[file exists $sc_si_lib]} {
    puts "  Adding sc_si_converter library"
    add_files -fileset sim_bram_tb -norecurse $sc_si_lib
}

# SmartConnect transaction regulator library
set sc_tr_lib "$vivado_dir/data/ip/xilinx/sc_transaction_regulator_v1_0/hdl/sc_transaction_regulator_v1_0_vl_rfs.sv"
if {[file exists $sc_tr_lib]} {
    puts "  Adding sc_transaction_regulator library"
    add_files -fileset sim_bram_tb -norecurse $sc_tr_lib
}

# SmartConnect AXI to SC library
set sc_axi2sc_lib "$vivado_dir/data/ip/xilinx/sc_axi2sc_v1_0/hdl/sc_axi2sc_v1_0_vl_rfs.sv"
if {[file exists $sc_axi2sc_lib]} {
    puts "  Adding sc_axi2sc library"
    add_files -fileset sim_bram_tb -norecurse $sc_axi2sc_lib
}

# SmartConnect SC to AXI library
set sc_sc2axi_lib "$vivado_dir/data/ip/xilinx/sc_sc2axi_v1_0/hdl/sc_sc2axi_v1_0_vl_rfs.sv"
if {[file exists $sc_sc2axi_lib]} {
    puts "  Adding sc_sc2axi library"
    add_files -fileset sim_bram_tb -norecurse $sc_sc2axi_lib
}

# SmartConnect exit library
set sc_exit_lib "$vivado_dir/data/ip/xilinx/sc_exit_v1_0/hdl/sc_exit_v1_0_vl_rfs.sv"
if {[file exists $sc_exit_lib]} {
    puts "  Adding sc_exit library"
    add_files -fileset sim_bram_tb -norecurse $sc_exit_lib
}

# SmartConnect switchboard library
set sc_switch_lib "$vivado_dir/data/ip/xilinx/sc_switchboard_v1_0/hdl/sc_switchboard_v1_0_vl_rfs.sv"
if {[file exists $sc_switch_lib]} {
    puts "  Adding sc_switchboard library"
    add_files -fileset sim_bram_tb -norecurse $sc_switch_lib
}

# Processor System Reset library
set psr_lib "$vivado_dir/data/ip/xilinx/proc_sys_reset_v5_0/hdl/proc_sys_reset_v5_0_vh_rfs.vhd"
if {[file exists $psr_lib]} {
    puts "  Adding proc_sys_reset library"
    add_files -fileset sim_bram_tb -norecurse $psr_lib
}

# AXI BRAM Controller library
set axi_bram_ctrl_lib "$vivado_dir/data/ip/xilinx/axi_bram_ctrl_v4_1/hdl/axi_bram_ctrl_v4_1_rfs.vhd"
if {[file exists $axi_bram_ctrl_lib]} {
    puts "  Adding axi_bram_ctrl library"
    add_files -fileset sim_bram_tb -norecurse $axi_bram_ctrl_lib
}

# ==============================================================================
# Add IP Simulation Models
# ==============================================================================

puts "Adding IP simulation models..."

# Add the blk_mem_gen simulation library first (the underlying IP model)
set blk_mem_gen_lib "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ipshared/42f3/simulation/blk_mem_gen_v8_4.v"
puts "Adding blk_mem_gen simulation library: $blk_mem_gen_lib"
add_files -fileset sim_bram_tb -norecurse $blk_mem_gen_lib

# Add the BRAM simulation Verilog file directly (not the XCI, which is already in the project)
# This avoids the "IP name already in use" error
set bram_sim_v "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_QPSK_Snapshot_BRAM_0/sim/Top_QPSK_Snapshot_BRAM_0.v"
puts "Adding BRAM simulation model: $bram_sim_v"
add_files -fileset sim_bram_tb -norecurse $bram_sim_v

# Add the AXI BRAM Controller simulation model
set bram_ctrl_vhd "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_BRAM_Controller_0/sim/Top_AXI_BRAM_Controller_0.vhd"
puts "Adding AXI BRAM Controller: $bram_ctrl_vhd"
add_files -fileset sim_bram_tb -norecurse $bram_ctrl_vhd

# Add all SmartConnect sub-IP simulation files (including VHDL files like psr_aclk)
set sc_ip_dir "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_CPU_Interconnect_0/bd_0/ip"
foreach ip_subdir [glob -directory $sc_ip_dir -type d *] {
    # Add SystemVerilog and Verilog files
    set sim_files [glob -nocomplain -directory "$ip_subdir/sim" *.sv *.v]
    foreach sim_file $sim_files {
        puts "Adding SC sub-IP: $sim_file"
        add_files -fileset sim_bram_tb -norecurse $sim_file
    }
    # Add VHDL files (for psr_aclk and similar)
    set vhd_files [glob -nocomplain -directory "$ip_subdir/sim" *.vhd]
    foreach vhd_file $vhd_files {
        puts "Adding SC sub-IP (VHDL): $vhd_file"
        add_files -fileset sim_bram_tb -norecurse $vhd_file
    }
}

# Add SmartConnect internal BD wrapper
set sc_bd "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_CPU_Interconnect_0/bd_0/sim/bd_e51e.v"
puts "Adding SmartConnect BD: $sc_bd"
add_files -fileset sim_bram_tb -norecurse $sc_bd

# Add the SmartConnect simulation model (top-level wrapper)
set smartconnect_sv "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_AXI_CPU_Interconnect_0/sim/Top_AXI_CPU_Interconnect_0.sv"
puts "Adding SmartConnect: $smartconnect_sv"
add_files -fileset sim_bram_tb -norecurse $smartconnect_sv

# Set the top module
set_property top snapshot_bram_readback_tb [get_filesets sim_bram_tb]
set_property top_lib xil_defaultlib [get_filesets sim_bram_tb]

# Set simulation runtime (longer for AXI transactions)
set_property -name {xsim.simulate.runtime} -value {1000us} -objects [get_filesets sim_bram_tb]

# Make sim_bram_tb the active simulation set
puts "Setting active simulation fileset to sim_bram_tb..."
current_fileset -simset [get_filesets sim_bram_tb]

# Update compile order
puts "Updating compile order..."
update_compile_order -fileset sim_bram_tb

# Close any running simulation
close_sim -quiet

# Launch simulation
puts "============================================"
puts "Launching BRAM testbench simulation..."
puts "Path: AXI Master -> SmartConnect -> BRAM Ctrl -> BRAM"
puts "============================================"
launch_simulation -simset sim_bram_tb

# Wait a moment for simulation to initialize
after 1000

# Add signals to waveform
puts "Adding signals to waveform..."

# Clock and Reset
add_wave {{/snapshot_bram_readback_tb/clk}}
add_wave {{/snapshot_bram_readback_tb/resetn}}

# AXI Master Read Address Channel
add_wave_divider "AXI Master Read"
add_wave {{/snapshot_bram_readback_tb/m_axi_araddr}}
add_wave {{/snapshot_bram_readback_tb/m_axi_arvalid}}
add_wave {{/snapshot_bram_readback_tb/m_axi_arready}}
add_wave {{/snapshot_bram_readback_tb/m_axi_rdata}}
add_wave {{/snapshot_bram_readback_tb/m_axi_rvalid}}
add_wave {{/snapshot_bram_readback_tb/m_axi_rready}}
add_wave {{/snapshot_bram_readback_tb/m_axi_rresp}}

# Interconnect to Controller
add_wave_divider "IC to BRAM Ctrl"
add_wave {{/snapshot_bram_readback_tb/ic_to_ctrl_araddr}}
add_wave {{/snapshot_bram_readback_tb/ic_to_ctrl_arvalid}}
add_wave {{/snapshot_bram_readback_tb/ic_to_ctrl_arready}}
add_wave {{/snapshot_bram_readback_tb/ic_to_ctrl_rdata}}
add_wave {{/snapshot_bram_readback_tb/ic_to_ctrl_rvalid}}

# BRAM Interface
add_wave_divider "BRAM Interface"
add_wave {{/snapshot_bram_readback_tb/bram_en_a}}
add_wave {{/snapshot_bram_readback_tb/bram_addr_a}}
add_wave {{/snapshot_bram_readback_tb/bram_rddata_a}}

# Test Results
add_wave_divider "Test Results"
add_wave {{/snapshot_bram_readback_tb/sample_idx}}
add_wave {{/snapshot_bram_readback_tb/i_out}}
add_wave {{/snapshot_bram_readback_tb/q_out}}
add_wave {{/snapshot_bram_readback_tb/iq_word}}
add_wave {{/snapshot_bram_readback_tb/expected_word}}
add_wave {{/snapshot_bram_readback_tb/good_count}}
add_wave {{/snapshot_bram_readback_tb/bad_count}}
add_wave {{/snapshot_bram_readback_tb/mismatch_count}}
add_wave {{/snapshot_bram_readback_tb/test_pass}}

# Run simulation
puts "Running simulation for 100us..."
run 100us

puts "============================================"
puts "BRAM Testbench Simulation Complete"
puts "Check the Tcl Console for PASS/FAIL results"
puts "============================================"
