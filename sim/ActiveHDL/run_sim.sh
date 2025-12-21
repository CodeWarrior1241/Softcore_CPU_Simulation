#!/bin/bash
# ================================================================================
# NEORV32 - Aldec Active-HDL Simulation Launcher (Linux/Unix)
# ================================================================================
# This script launches Active-HDL simulation for the NEORV32 processor
# ================================================================================

set -e

# Configuration
VSIM="${VSIM:-vsimsa}"
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
            rm -f *.asdb *.wlf *.log transcript
            rm -f neorv32.tracer*.log tb.uart*.log
            echo "Done."
            exit 0
            ;;
        --help)
            echo "NEORV32 Aldec Active-HDL Simulation Script"
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

# Check if Active-HDL is available
if ! command -v "$VSIM" &> /dev/null; then
    echo "ERROR: Active-HDL vsimsa not found in PATH"
    echo "Please ensure Active-HDL is installed and added to PATH"
    echo "Or set VSIM environment variable to the full path"
    exit 1
fi

echo "=========================================="
echo "NEORV32 Aldec Active-HDL Simulation"
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
