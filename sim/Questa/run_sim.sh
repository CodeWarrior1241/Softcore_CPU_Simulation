#!/bin/bash
# ================================================================================
# NEORV32 - Questa Prime Simulation Launcher (Linux/Unix)
# ================================================================================
# This script launches Questa Prime simulation for the NEORV32 processor
# ================================================================================

set -e

# Configuration
VSIM="${VSIM:-vsim}"
SIM_MODE="gui"
SIM_TIME="150ms"

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --batch)
            SIM_MODE="batch"
            shift
            ;;
        --gui)
            SIM_MODE="gui"
            shift
            ;;
        --time)
            SIM_TIME="$2"
            shift 2
            ;;
        --clean)
            echo "Cleaning work directory and simulation artifacts..."
            rm -rf work neorv32
            rm -f *.wlf *.log *.vstf transcript
            rm -f neorv32.tracer*.log tb.uart*.log
            echo "Done."
            exit 0
            ;;
        --help)
            echo "NEORV32 Questa Prime Simulation Script"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "Options:"
            echo "  --time TIME    Set simulation time (default: 150ms)"
            echo "  --gui          Run in GUI mode (default)"
            echo "  --batch        Run in batch/command-line mode"
            echo "  --clean        Remove work directory and generated files"
            echo "  --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_sim.sh                    Run with defaults (150ms, GUI)"
            echo "  ./run_sim.sh --time 50ms        Run for 50ms"
            echo "  ./run_sim.sh --batch            Run in batch mode"
            echo "  ./run_sim.sh --time 20ms --batch"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if Questa is available
if ! command -v "$VSIM" &> /dev/null; then
    echo "ERROR: vsim not found in PATH"
    echo "Please ensure Questa Prime is installed and added to PATH"
    echo "Or set VSIM environment variable to the full path"
    exit 1
fi

echo "=========================================="
echo "NEORV32 Questa Prime Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
echo "Simulation mode: $SIM_MODE"
echo "=========================================="

# Clean up previous simulation logs
rm -f tb.uart*.log neorv32.tracer*.log

if [ "$SIM_MODE" == "batch" ]; then
    echo "Running in batch mode..."
    "$VSIM" -c -do "set SIM_TIME {$SIM_TIME}; do simulate.do; quit -f"
else
    echo "Running in GUI mode..."
    "$VSIM" -do "set SIM_TIME {$SIM_TIME}; do simulate.do"
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
        if $PYTHON_CMD ../display_qpsk_constellation.py --save qpsk_constellation.png --no-display 2>/dev/null; then
            echo "Constellation saved to: qpsk_constellation.png"
        else
            echo "Note: Could not generate constellation plot"
            echo "      Install matplotlib/numpy: pip install matplotlib numpy"
        fi
    fi
fi
