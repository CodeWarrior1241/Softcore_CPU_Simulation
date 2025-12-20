#!/usr/bin/env bash
# ================================================================================
# NEORV32 - NVC Simulation Script for Unix/Linux/macOS (VHDL-2008)
# ================================================================================
# This script compiles and runs the NEORV32 RISC-V processor simulation using NVC
# ================================================================================

set -e

# Configuration
NVC="${NVC:-nvc}"
WORK_DIR="work"
TOP_ENTITY="neorv32_tb"
SIM_TIME="150ms"
WAVE_FILE="neorv32_tb.fst"

# Change to script directory
cd "$(dirname "$0")"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --time)
            SIM_TIME="$2"
            shift 2
            ;;
        --wave)
            WAVE_FILE="$2"
            shift 2
            ;;
        --clean)
            echo "Cleaning work directory and simulation artifacts..."
            rm -rf "$WORK_DIR"
            rm -f *.fst *.log neorv32.tracer*.log tb.uart*.log
            echo "Done."
            exit 0
            ;;
        --help)
            echo "NEORV32 NVC Simulation Script"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "Options:"
            echo "  --time TIME    Set simulation time (default: 10ms)"
            echo "  --wave FILE    Set waveform output file (default: neorv32_tb.fst)"
            echo "  --clean        Remove work directory and exit"
            echo "  --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_sim.sh                    Run with defaults (10ms)"
            echo "  ./run_sim.sh --time 50ms        Run for 50ms"
            echo "  ./run_sim.sh --wave sim.fst     Output waveform to sim.fst"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if NVC is available
if ! command -v "$NVC" &> /dev/null; then
    echo "ERROR: NVC not found in PATH!"
    echo "Please ensure NVC is installed and added to your system PATH."
    exit 1
fi

echo "=========================================="
echo "NEORV32 NVC Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
echo "Waveform file:   $WAVE_FILE"
echo "=========================================="

# Clean up previous simulation logs
rm -f tb.uart*.log neorv32.tracer*.log

# Create work directory
mkdir -p "$WORK_DIR"

echo ""
echo "[1/3] Analyzing VHDL sources..."
echo "=========================================="

# Analyze all VHDL files in dependency order
# Package (must be first)
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_package.vhd

# System/Core components
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_sys.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_prim.vhd

# CPU components
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_decompressor.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_frontend.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_control.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_hwtrig.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_counters.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_regfile.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_cp_shifter.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_cp_muldiv.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_cp_bitmanip.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_cp_fpu.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_cp_cfu.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_cp_cond.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_cp_crypto.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_alu.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_lsu.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_pmp.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu_trace.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cpu.vhd

# Cache and Bus
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cache.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_bus.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_dma.vhd

# Memory
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_application_image.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_imem.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_dmem.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_xbus.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_bootloader_image.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_boot_rom.vhd

# Peripherals
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_cfs.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_sdi.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_gpio.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_wdt.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_clint.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_uart.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_spi.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_twi.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_twd.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_pwm.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_trng.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_neoled.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_gptmr.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_onewire.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_slink.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_tracer.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_sysinfo.vhd

# Debug
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_debug_dtm.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_debug_auth.vhd
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_debug_dm.vhd

# Top-level
$NVC --std=2008 --work=neorv32:$WORK_DIR/neorv32 -a ../../rtl/core/neorv32_top.vhd

# Testbench support modules
$NVC --std=2008 --work=work:$WORK_DIR/work -L $WORK_DIR -a ../sim_uart_rx.vhd
$NVC --std=2008 --work=work:$WORK_DIR/work -L $WORK_DIR -a ../xbus_memory.vhd
$NVC --std=2008 --work=work:$WORK_DIR/work -L $WORK_DIR -a ../xbus_gateway.vhd
$NVC --std=2008 --work=work:$WORK_DIR/work -L $WORK_DIR -a ../xbus_fmem.vhd

# Main testbench
$NVC --std=2008 --work=work:$WORK_DIR/work -L $WORK_DIR -a ../neorv32_tb.vhd

echo "Analysis complete."

echo ""
echo "[2/3] Elaborating design..."
echo "=========================================="

$NVC --std=2008 --work=work:$WORK_DIR/work -L $WORK_DIR -e $TOP_ENTITY

echo "Elaboration complete."

echo ""
echo "[3/3] Running simulation..."
echo "=========================================="

$NVC --std=2008 --work=work:$WORK_DIR/work -L $WORK_DIR -r $TOP_ENTITY --stop-time=$SIM_TIME --wave=$WAVE_FILE --stats

echo ""
echo "=========================================="
echo "Simulation complete!"
echo "Waveform saved to: $WAVE_FILE"
echo "=========================================="
echo ""
echo "To view waveforms, run: gtkwave $WAVE_FILE"
