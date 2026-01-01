# ==============================================================================
# BRAM Readback Testbench - Vivado xsim Runner
# ==============================================================================
# Run this script from Vivado Tcl Console:
#   cd C:/Work/Sandbox/Softcore_CPU_Simulation/setups/vivado
#   source sim/run_bram_tb.tcl
#
# Or from command line:
#   vivado -mode batch -source sim/run_bram_tb.tcl
#
# This script sets up and runs the BRAM readback testbench simulation
# in order to validate that data from the pre-loaded .coe file into the BRAM
# can be read back correctly. For convenience it is run right from Vivado,
# so a complete Vivado project is expected to already exist.
#
# ==============================================================================

# Get the directory where this script is located
set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]

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

# Add the blk_mem_gen simulation library first (the underlying IP model)
set blk_mem_gen_lib "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ipshared/42f3/simulation/blk_mem_gen_v8_4.v"
puts "Adding blk_mem_gen simulation library: $blk_mem_gen_lib"
add_files -fileset sim_bram_tb -norecurse $blk_mem_gen_lib

# Add the BRAM simulation Verilog file directly (not the XCI, which is already in the project)
# This avoids the "IP name already in use" error
set bram_sim_v "$project_dir/NEORV32_Simulation.gen/sources_1/bd/Top/ip/Top_QPSK_Snapshot_BRAM_0/sim/Top_QPSK_Snapshot_BRAM_0.v"
puts "Adding BRAM simulation model: $bram_sim_v"
add_files -fileset sim_bram_tb -norecurse $bram_sim_v

# Set the top module
set_property top snapshot_bram_readback_tb [get_filesets sim_bram_tb]
set_property top_lib xil_defaultlib [get_filesets sim_bram_tb]

# Set simulation runtime
set_property -name {xsim.simulate.runtime} -value {100us} -objects [get_filesets sim_bram_tb]

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
puts "============================================"
launch_simulation -simset sim_bram_tb

# Wait a moment for simulation to initialize
after 1000

# Add signals to waveform
puts "Adding signals to waveform..."
add_wave {{/snapshot_bram_readback_tb/clk}}
add_wave {{/snapshot_bram_readback_tb/ena}}
add_wave {{/snapshot_bram_readback_tb/addra}}
add_wave {{/snapshot_bram_readback_tb/douta}}
add_wave {{/snapshot_bram_readback_tb/sample_idx}}
add_wave {{/snapshot_bram_readback_tb/i_out}}
add_wave {{/snapshot_bram_readback_tb/q_out}}
add_wave {{/snapshot_bram_readback_tb/iq_word}}
add_wave {{/snapshot_bram_readback_tb/good_count}}
add_wave {{/snapshot_bram_readback_tb/bad_count}}
add_wave {{/snapshot_bram_readback_tb/test_pass}}

# Run simulation
puts "Running simulation for 50us..."
run 50us

puts "============================================"
puts "BRAM Testbench Simulation Complete"
puts "Check the Tcl Console for PASS/FAIL results"
puts "============================================"
