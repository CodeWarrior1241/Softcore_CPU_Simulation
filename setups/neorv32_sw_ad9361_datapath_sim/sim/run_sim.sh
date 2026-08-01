#!/usr/bin/env bash
# ================================================================================
# AD9361 Datapath Simulation - Questa Prime Launcher (Unix/Linux/macOS)
# ================================================================================
# This script launches Questa Prime simulation for the AD9361 datapath test.
#
# Two simulation modes are available:
#
#   DEFAULT (fast):   +acc=rn optimization, no waveform logging.
#                     Suitable for functional pass/fail runs where only
#                     UART output is needed. Significantly faster.
#
#  ./run_sim.sh                    # +acc=rn, no waveforms
#  ./run_sim.sh --batch            # same, headless
#
#   DETAILED:         +acc=npr optimization, full waveform logging for all
#                     internal signals (clocks, resets, LVDS, AXI-Stream,
#                     CDC FIFOs, adapter control/status, CPU).
#                     Use for debugging and signal-level analysis.
#
#  ./run_sim.sh --detailed         # +acc=npr, full waveforms
#  ./run_sim.sh --detailed --batch # same, headless
#
# ================================================================================

set -e

# Configuration
VSIM="${VSIM:-vsim}"
SIM_MODE="gui"
# 15ms: the directed power-gate cycle (l_clk stop/restart + re-config + re-prime
# + re-readback) pushes the GPIO auto-terminate out past the old 5ms default.
# The TB still $finishes early on PASS/FAIL, so this is just an upper bound.
SIM_TIME="15ms"
DETAILED="no"

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
        --detailed)
            DETAILED="yes"
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
            echo "  --time TIME    Set simulation time (default: 5ms)"
            echo "  --gui          Run in GUI mode (default)"
            echo "  --batch        Run in batch/command-line mode"
            echo "  --detailed     Full signal visibility (+acc=npr) with waveforms"
            echo "  --clean        Remove work directories and generated files"
            echo "  --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_sim.sh                       Run fast (5ms, GUI, +acc=rn)"
            echo "  ./run_sim.sh --detailed            Run with full waveforms"
            echo "  ./run_sim.sh --time 5ms --batch    Run 5ms in batch mode"
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

# Sync NEORV32 IMEM image to ipshared locations used by Vivado's compile.do.
# The Vivado IP packaging creates snapshots under ipshared/ which go stale
# when firmware is rebuilt. Copy the current image so the simulation always
# uses the latest build.
# Prefer the platform-correct prebuilt (sw/ad9361_loopback, Xilinx bridge
# map, fits the BD's 32KB IMEM) — rtl/core may hold an image for another
# platform (e.g. the MPF300 SmartHLS build, ~108KB, which overflows IMEM
# and leaves the CPU silent). Fall back to rtl/core if no prebuilt exists.
NEORV32_HOME="$(cd "../../.." && pwd)"
IMEM_SRC="$NEORV32_HOME/sw/ad9361_loopback/neorv32_imem_image.vhd"
if [ ! -f "$IMEM_SRC" ]; then
    IMEM_SRC="$NEORV32_HOME/rtl/core/neorv32_imem_image.vhd"
fi
# Find ipshared directories dynamically (hash changes on each project rebuild)
IPSHARED_DIR=$(find ../NEORV32_Simulation.ip_user_files/bd/Top/ipshared -name "neorv32_imem_image.vhd" -printf '%h\n' 2>/dev/null | head -1)
IPSHARED_GEN=$(find ../NEORV32_Simulation.gen/sources_1/bd/Top/ipshared -name "neorv32_imem_image.vhd" -printf '%h\n' 2>/dev/null | head -1)

if [ -f "$IMEM_SRC" ]; then
    echo "Syncing IMEM image from source..."
    [ -d "$IPSHARED_DIR" ] && cp -f "$IMEM_SRC" "$IPSHARED_DIR/neorv32_imem_image.vhd"
    [ -d "$IPSHARED_GEN" ] && cp -f "$IMEM_SRC" "$IPSHARED_GEN/neorv32_imem_image.vhd"
else
    echo "WARNING: IMEM image not found at $IMEM_SRC"
    echo "  Build firmware first: cd sw/ad9361_loopback && make clean_all exe install"
fi

echo "=========================================="
echo "AD9361 Datapath Questa Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
echo "Simulation mode: $SIM_MODE"
echo "Detailed:        $DETAILED"
echo "=========================================="

SIM_VARS="set SIM_TIME {$SIM_TIME}; set DETAILED {$DETAILED}"

if [[ "$SIM_MODE" == "batch" ]]; then
    echo "Running in batch mode..."
    $VSIM -c -do "$SIM_VARS; do simulate.do; quit -f"

    echo ""
    echo "=========================================="
    echo "Simulation complete!"
    echo "=========================================="
else
    echo "Running in GUI mode..."
    $VSIM -do "$SIM_VARS; do simulate.do"
fi
