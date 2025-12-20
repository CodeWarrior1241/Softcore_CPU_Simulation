#!/usr/bin/env bash
# ================================================================================
# NEORV32 - GHDL Simulation Script for Unix/Linux/macOS (VHDL-2008)
# ================================================================================
# This script compiles and runs the NEORV32 RISC-V processor simulation using GHDL
# ================================================================================

set -e

# Configuration
GHDL="${GHDL:-ghdl}"
WORK_DIR="work"
TOP_ENTITY="neorv32_tb"
SIM_TIME="150ms"
WAVE_FORMAT=""
WAVE_FILE=""
NO_LOG=0

# Change to script directory
cd "$(dirname "$0")"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --time)
            SIM_TIME="$2"
            shift 2
            ;;
        --vcd)
            WAVE_FORMAT="vcd"
            WAVE_FILE="${2:-neorv32_tb.vcd}"
            shift
            if [[ "$1" != --* ]] && [[ -n "$1" ]]; then
                WAVE_FILE="$1"
                shift
            fi
            ;;
        --ghw)
            WAVE_FORMAT="ghw"
            WAVE_FILE="${2:-neorv32_tb.ghw}"
            shift
            if [[ "$1" != --* ]] && [[ -n "$1" ]]; then
                WAVE_FILE="$1"
                shift
            fi
            ;;
        --fst)
            WAVE_FORMAT="fst"
            WAVE_FILE="${2:-neorv32_tb.fst}"
            shift
            if [[ "$1" != --* ]] && [[ -n "$1" ]]; then
                WAVE_FILE="$1"
                shift
            fi
            ;;
        --no-log)
            NO_LOG=1
            shift
            ;;
        --clean)
            echo "Cleaning work directory and simulation artifacts..."
            rm -rf "$WORK_DIR"
            rm -f *.vcd *.ghw *.fst *.log *.cf neorv32.tracer*.log tb.uart*.log
            echo "Done."
            exit 0
            ;;
        --help)
            echo "NEORV32 GHDL Simulation Script"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "Options:"
            echo "  --time TIME    Set simulation time (default: 10ms)"
            echo "  --vcd [FILE]   Generate VCD waveform (default: neorv32_tb.vcd)"
            echo "  --ghw [FILE]   Generate GHW waveform (default: neorv32_tb.ghw)"
            echo "  --fst [FILE]   Generate FST waveform (default: neorv32_tb.fst)"
            echo "  --no-log       Disable logging to ghdl.log"
            echo "  --clean        Remove work directory and generated files"
            echo "  --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_sim.sh                      Run with defaults (10ms, no waveform)"
            echo "  ./run_sim.sh --time 50ms          Run for 50ms"
            echo "  ./run_sim.sh --vcd                Generate VCD waveform"
            echo "  ./run_sim.sh --ghw sim.ghw        Generate GHW waveform with custom name"
            echo "  ./run_sim.sh --time 20ms --fst    Run 20ms with FST output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if GHDL is available
if ! command -v "$GHDL" &> /dev/null; then
    echo "ERROR: GHDL not found in PATH!"
    echo "Please ensure GHDL is installed and added to your system PATH."
    exit 1
fi

echo "=========================================="
echo "NEORV32 GHDL Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
if [[ -n "$WAVE_FILE" ]]; then
    echo "Waveform file:   $WAVE_FILE ($WAVE_FORMAT)"
else
    echo "Waveform:        disabled"
fi
echo "=========================================="

# Clean up previous simulation logs
rm -f tb.uart*.log neorv32.tracer*.log

# Create work directory
mkdir -p "$WORK_DIR"

echo ""
echo "[1/3] Importing VHDL sources..."
echo "=========================================="

# Import all VHDL files
find ../../rtl/core .. -maxdepth 1 -type f -name '*.vhd' -exec \
    $GHDL -i --std=08 --workdir=$WORK_DIR --ieee=standard --work=neorv32 {} \;

echo "Import complete."

echo ""
echo "[2/3] Analyzing and elaborating design..."
echo "=========================================="

$GHDL -m --work=neorv32 --workdir=$WORK_DIR --std=08 $TOP_ENTITY

echo "Elaboration complete."

echo ""
echo "[3/3] Running simulation..."
echo "=========================================="

# Build run command
RUN_CMD="$GHDL -r --work=neorv32 --workdir=$WORK_DIR --std=08 $TOP_ENTITY"
RUN_CMD="$RUN_CMD --max-stack-alloc=0"
RUN_CMD="$RUN_CMD --ieee-asserts=disable"
RUN_CMD="$RUN_CMD --assert-level=error"
RUN_CMD="$RUN_CMD --stop-time=$SIM_TIME"

# Add waveform option if requested
if [[ -n "$WAVE_FILE" ]]; then
    case $WAVE_FORMAT in
        vcd)
            RUN_CMD="$RUN_CMD --vcd=$WAVE_FILE"
            ;;
        ghw)
            RUN_CMD="$RUN_CMD --wave=$WAVE_FILE"
            ;;
        fst)
            RUN_CMD="$RUN_CMD --fst=$WAVE_FILE"
            ;;
    esac
fi

# Run simulation
if [[ $NO_LOG -eq 1 ]]; then
    eval "$RUN_CMD"
else
    eval "$RUN_CMD" 2>&1 | tee ghdl.log
fi

echo ""
echo "=========================================="
echo "Simulation complete!"
if [[ -n "$WAVE_FILE" ]]; then
    echo "Waveform saved to: $WAVE_FILE"
    echo ""
    echo "To view waveforms, run: gtkwave $WAVE_FILE"
fi
echo "=========================================="
