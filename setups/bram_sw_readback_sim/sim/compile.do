# ================================================================================
# Vivado Block Design Testbench - Questa Prime Compilation Script
# ================================================================================
# This script compiles the Vivado-generated IP sources plus our custom testbench
# ================================================================================

# Quit any existing simulation
quit -sim

# Save the current directory (setups/vivado/sim)
set sim_dir [pwd]

# Path to Vivado-generated Questa scripts (relative to sim directory)
set vivado_questa_dir "$sim_dir/../NEORV32_Simulation.ip_user_files/sim_scripts/questa"

# ================================================================================
# Pre-compiled Xilinx Simulation Libraries (from compile_simlib)
# ================================================================================
# These libraries are pre-compiled using Vivado's compile_simlib command:
#   compile_simlib -simulator questa -simulator_exec_path {path_to_questa} ...
#
# Set the XILINX_QUESTA_LIBS environment variable to point to your libraries:
#   Windows: set XILINX_QUESTA_LIBS=C:\Work\Questa_Libraries_Vivado
#   Linux:   export XILINX_QUESTA_LIBS=/path/to/Questa_Libraries_Vivado
# ================================================================================

if {[info exists ::env(XILINX_QUESTA_LIBS)]} {
    set XILINX_QUESTA_LIBS $::env(XILINX_QUESTA_LIBS)
} else {
    error "XILINX_QUESTA_LIBS environment variable not set.\n  Set it to point to your pre-compiled Xilinx simulation libraries.\n  Windows: set XILINX_QUESTA_LIBS=C:\\Work\\Questa_Libraries_Vivado\n  Linux:   export XILINX_QUESTA_LIBS=/path/to/Questa_Libraries_Vivado"
}

# ================================================================================
# Validate pre-compiled libraries exist
# ================================================================================

if {![file exists $XILINX_QUESTA_LIBS]} {
    puts ""
    puts "==============================================================================="
    puts "  ERROR: Pre-compiled Xilinx simulation libraries not found!"
    puts "==============================================================================="
    puts ""
    puts "  Expected location: $XILINX_QUESTA_LIBS"
    puts ""
    puts "  These libraries must be compiled once using Vivado's compile_simlib command."
    puts ""
    puts "  To generate them, run the following in Vivado Tcl Console:"
    puts ""
    puts "    compile_simlib -simulator questa \\"
    puts "      -simulator_exec_path {C:/Program Files/Mentor_Graphics/Questa_Prime_2025.1/win64} \\"
    puts "      -family all -language all -library all \\"
    puts "      -dir {$XILINX_QUESTA_LIBS}"
    puts ""
    puts "  This takes 30-60 minutes but only needs to be done once per Vivado version."
    puts ""
    puts "==============================================================================="
    puts ""
    error "Pre-compiled Xilinx libraries not found at $XILINX_QUESTA_LIBS"
}

if {![file exists $XILINX_QUESTA_LIBS/modelsim.ini]} {
    puts ""
    puts "==============================================================================="
    puts "  ERROR: modelsim.ini not found in pre-compiled libraries!"
    puts "==============================================================================="
    puts ""
    puts "  Expected: $XILINX_QUESTA_LIBS/modelsim.ini"
    puts ""
    puts "  The compile_simlib command may not have completed successfully."
    puts "  Please re-run compile_simlib in Vivado."
    puts ""
    puts "==============================================================================="
    puts ""
    error "modelsim.ini not found in $XILINX_QUESTA_LIBS"
}

if {![file exists $XILINX_QUESTA_LIBS/unisim]} {
    puts ""
    puts "==============================================================================="
    puts "  ERROR: UNISIM library not found in pre-compiled libraries!"
    puts "==============================================================================="
    puts ""
    puts "  Expected: $XILINX_QUESTA_LIBS/unisim"
    puts ""
    puts "  The compile_simlib command may not have completed successfully."
    puts "  Please re-run compile_simlib in Vivado."
    puts ""
    puts "==============================================================================="
    puts ""
    error "UNISIM library not found in $XILINX_QUESTA_LIBS"
}

puts "INFO: Using pre-compiled Xilinx libraries from: $XILINX_QUESTA_LIBS"

# Change to Vivado's questa directory
cd $vivado_questa_dir

# Create the questa_lib directory if it doesn't exist
file mkdir questa_lib

# Copy the pre-compiled libraries modelsim.ini as base, then add our project libraries
# This ensures all Xilinx simulation libraries are available
file copy -force $XILINX_QUESTA_LIBS/modelsim.ini modelsim.ini

# ================================================================================
# Run Vivado's generated compile script
# ================================================================================

puts "=========================================="
puts "Running Vivado-generated compile script..."
puts "=========================================="

# Vivado's compile.do expects bin_path to point to the Questa bin directory
# It uses commands like: $bin_path/vlib, $bin_path/vcom, etc.
# We need to find where Questa is installed
set bin_path [file dirname [exec which vsim]]

do compile.do

# Return to our sim directory
cd $sim_dir

# ================================================================================
# Compile Additional Testbench Components
# ================================================================================

puts "=========================================="
puts "Compiling Testbench Components..."
puts "=========================================="

# Map the libraries created by Vivado's compile script (they're in the questa dir)
vmap xil_defaultlib $vivado_questa_dir/questa_lib/msim/xil_defaultlib
vmap neorv32 $vivado_questa_dir/questa_lib/msim/neorv32

# Map UNISIM library from pre-compiled Xilinx libraries (needed for Top.vhd)
vmap unisim $XILINX_QUESTA_LIBS/unisim

# Compile UART components (need VHDL-2008 for math_real)
set VCOM_TB_OPTS "-2008 -explicit -work xil_defaultlib"

# Simulation UART receiver and transmitter from the main sim directory
vcom {*}$VCOM_TB_OPTS $sim_dir/../../../sim/sim_uart_rx.vhd
vcom {*}$VCOM_TB_OPTS $sim_dir/../../../sim/sim_uart_tx.vhd

# Block design entity and wrapper (recompile to pick up any port changes like sim_clock_100MHz)
# Top.vhd must be compiled before Top_wrapper.vhd since wrapper depends on entity
vcom {*}$VCOM_TB_OPTS $sim_dir/../NEORV32_Simulation.gen/sources_1/bd/Top/sim/Top.vhd
vcom {*}$VCOM_TB_OPTS $sim_dir/../NEORV32_Simulation.gen/sources_1/bd/Top/hdl/Top_wrapper.vhd

# Our custom testbench
vcom {*}$VCOM_TB_OPTS $sim_dir/vivado_tb.vhd

puts "=========================================="
puts "Compilation Complete!"
puts "=========================================="
