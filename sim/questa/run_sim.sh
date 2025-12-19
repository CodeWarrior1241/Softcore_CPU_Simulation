#!/bin/bash
# ================================================================================
# NEORV32 - Questa Prime Simulation Launcher (Linux/Unix)
# ================================================================================
# This script launches Questa Prime simulation for the NEORV32 processor
# ================================================================================

set -e

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "NEORV32 Questa Prime Simulation"
echo "=========================================="

# Check if Questa is available
if ! command -v vsim &> /dev/null; then
    echo "ERROR: vsim not found in PATH"
    echo "Please ensure Questa Prime is installed and added to PATH"
    exit 1
fi

# Default values
SIM_MODE="gui"
SIM_TIME="10ms"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -batch)
            SIM_MODE="batch"
            shift
            ;;
        -gui)
            SIM_MODE="gui"
            shift
            ;;
        -time)
            SIM_TIME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-batch|-gui] [-time <time>]"
            exit 1
            ;;
    esac
done

echo "Simulation Mode: $SIM_MODE"
echo "Simulation Time: $SIM_TIME"
echo "=========================================="

if [ "$SIM_MODE" == "batch" ]; then
    echo "Running in batch mode..."
    vsim -c -do "set SIM_TIME {$SIM_TIME}; do simulate.do; quit -f"
else
    echo "Running in GUI mode..."
    vsim -do "set SIM_TIME {$SIM_TIME}; do simulate.do"
fi
