#!/usr/bin/env bash
# ================================================================================
# AD9361 Datapath Simulation - Questa Prime Launcher (Unix/Linux/macOS)
# ================================================================================
# This script launches Questa Prime simulation for the AD9361 datapath test
# ================================================================================

set -e

# Configuration
VSIM="${VSIM:-vsim}"
SIM_MODE="gui"
SIM_TIME="10ms"

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
            rm -f *.wlf *.log *.vstf transcript
            echo "Done."
            exit 0
            ;;
        --help)
            echo "AD9361 Datapath Questa Prime Simulation Script"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "Options:"
            echo "  --time TIME    Set simulation time (default: 10ms)"
            echo "  --gui          Run in GUI mode (default)"
            echo "  --batch        Run in batch/command-line mode"
            echo "  --clean        Remove work directories and generated files"
            echo "  --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_sim.sh                    Run with defaults (10ms, GUI)"
            echo "  ./run_sim.sh --time 5ms         Run for 5ms"
            echo "  ./run_sim.sh --batch            Run in batch mode"
            echo "  ./run_sim.sh --time 20ms --batch  Run 20ms in batch mode"
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

# Check if hex file exists
if [ ! -f "qpsk_bram_data.hex" ]; then
    echo "WARNING: qpsk_bram_data.hex not found!"
    echo "Attempting to generate from COE file..."
    PYTHON_CMD=$(command -v python3 || command -v python || echo "")
    if [ -z "$PYTHON_CMD" ]; then
        echo "ERROR: Python not found. Cannot generate hex file."
        echo "Please run: python convert_coe_to_hex.py qpsk_bram_init.coe qpsk_bram_data.hex"
        exit 1
    fi
    $PYTHON_CMD convert_coe_to_hex.py qpsk_bram_init.coe qpsk_bram_data.hex
    echo "Generated qpsk_bram_data.hex successfully"
fi

echo "=========================================="
echo "AD9361 Datapath Questa Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
echo "Simulation mode: $SIM_MODE"
echo "=========================================="

if [[ "$SIM_MODE" == "batch" ]]; then
    echo "Running in batch mode..."
    $VSIM -c -do "set SIM_TIME {$SIM_TIME}; do simulate.do; quit -f"

    echo ""
    echo "=========================================="
    echo "Simulation complete!"
    echo "=========================================="
else
    echo "Running in GUI mode..."
    $VSIM -do "set SIM_TIME {$SIM_TIME}; do simulate.do"
fi
