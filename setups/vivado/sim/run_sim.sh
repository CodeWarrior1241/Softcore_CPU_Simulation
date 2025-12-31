#!/usr/bin/env bash
# ================================================================================
# Vivado Block Design - Questa Prime Simulation Launcher (Unix/Linux/macOS)
# ================================================================================
# This script launches Questa Prime simulation for the Vivado block design
# ================================================================================

set -e

# Configuration
VSIM="${VSIM:-vsim}"
SIM_MODE="gui"
SIM_TIME="500ms"

# Change to script directory
cd "$(dirname "$0")"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --time)
            SIM_TIME="$2"
            shift 2
            ;;
        --gui)
            SIM_MODE="gui"
            shift
            ;;
        --batch)
            SIM_MODE="batch"
            shift
            ;;
        --clean)
            echo "Cleaning work directories and simulation artifacts..."
            rm -rf questa_lib work
            rm -f *.wlf *.log *.vstf transcript tb.uart*.log *.png
            echo "Done."
            exit 0
            ;;
        --help)
            echo "Vivado Block Design Questa Prime Simulation Script"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "Options:"
            echo "  --time TIME    Set simulation time (default: 500ms)"
            echo "  --gui          Run in GUI mode (default)"
            echo "  --batch        Run in batch/command-line mode"
            echo "  --clean        Remove work directories and generated files"
            echo "  --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_sim.sh                    Run with defaults (500ms, GUI)"
            echo "  ./run_sim.sh --time 100ms       Run for 100ms"
            echo "  ./run_sim.sh --batch            Run in batch mode"
            echo "  ./run_sim.sh --time 1s --batch  Run 1s in batch mode"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if Questa/Vsim is available
if ! command -v "$VSIM" &> /dev/null; then
    echo "ERROR: Questa Prime (vsim) not found in PATH!"
    echo "Please ensure Questa Prime is installed and added to your system PATH."
    exit 1
fi

echo "=========================================="
echo "Vivado Block Design Questa Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
echo "Simulation mode: $SIM_MODE"
echo "=========================================="

# Clean up previous simulation logs
rm -f tb.uart*.log

if [[ "$SIM_MODE" == "batch" ]]; then
    echo "Running in batch mode..."
    $VSIM -c -do "set SIM_TIME {$SIM_TIME}; do simulate.do; quit -f"
else
    echo "Running in GUI mode..."
    $VSIM -do "set SIM_TIME {$SIM_TIME}; do simulate.do"
fi

echo ""
echo "=========================================="
echo "Simulation complete!"
echo "=========================================="

# Display QPSK constellation if Python is available and log file exists
if [ -f "tb.uart0_rx.log" ]; then
    if command -v python3 &> /dev/null || command -v python &> /dev/null; then
        echo ""
        echo "Generating QPSK constellation plot..."
        echo "=========================================="
        PYTHON_CMD=$(command -v python3 || command -v python)
        if $PYTHON_CMD ../../../sim/display_qpsk_constellation.py --save qpsk_constellation.png --no-display 2>/dev/null; then
            echo "Constellation saved to: qpsk_constellation.png"
        else
            echo "Note: Could not generate constellation plot"
            echo "      Install matplotlib/numpy: pip install matplotlib numpy"
        fi
    fi
fi
