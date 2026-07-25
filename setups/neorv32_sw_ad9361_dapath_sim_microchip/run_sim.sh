#!/usr/bin/env bash
# ================================================================================
# AD9361 Datapath Simulation (Microchip mpf300) - Questa Prime Launcher
# ================================================================================
# Microchip counterpart of ../neorv32_sw_ad9361_datapath_sim/sim/run_sim.sh:
# boots the NEORV32 CPU with the ad9361_loopback firmware against the full
# mpf300 FMCOMMS2 system (axi_ad9361 PolarFire LVDS + SmartHLS adapters +
# PULP interconnect + open-logic CDC/resets), in Questa Prime 2025.1 (from
# PATH — NOT the QuestaSim bundled with Libero).
#
#  ./run_sim.sh                    # fast (+acc=rn), GUI
#  ./run_sim.sh --batch            # fast, headless
#  ./run_sim.sh --detailed         # +acc=npr, full waveforms
#  ./run_sim.sh --clean            # remove generated files
#
# The firmware is (re)built here when the RISC-V GCC is on PATH:
#   make MARCH=rv32im_zicsr_zifencei clean_all image
# The SmartHLS bridge decodes the SAME register map as the Vitis IP, so the
# firmware is fully portable; rv32im makes the firmware's mul_selftest()
# exercise the PR #1603 pipelined fast multiplier enabled in this sim's
# NEORV32 wrapper.
# ================================================================================

set -e

VSIM="${VSIM:-vsim}"
SIM_MODE="gui"
SIM_TIME="20ms"
DETAILED="no"

cd "$(dirname "$0")"

while [[ $# -gt 0 ]]; do
    case $1 in
        --time)     SIM_TIME="$2"; shift 2 ;;
        --gui)      SIM_MODE="gui"; shift ;;
        --batch)    SIM_MODE="batch"; shift ;;
        --detailed) DETAILED="yes"; shift ;;
        --clean)
            echo "Cleaning work directories and simulation artifacts..."
            rm -rf work neorv32 polarfire
            rm -f *.wlf *.log *.vstf transcript *.mem qpsk_bram_data.hex modelsim.ini
            echo "Done."
            exit 0
            ;;
        --help)
            echo "AD9361 Datapath (Microchip mpf300) Questa Prime Simulation Script"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "Options:"
            echo "  --time TIME    Set simulation time (default: 20ms)"
            echo "  --gui          Run in GUI mode (default)"
            echo "  --batch        Run in batch/command-line mode"
            echo "  --detailed     Full signal visibility (+acc=npr) with waveforms"
            echo "  --clean        Remove work directories and generated files"
            echo "  --help         Show this help message"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if ! command -v "$VSIM" &> /dev/null; then
    echo "ERROR: Questa Prime (vsim) not found in PATH!"
    exit 1
fi

# --------------------------------------------------------------------------------
# Firmware: build the ad9361_loopback image (register map is portable —
# identical on both platforms), rv32im for the multiplier self-test.
# Falls back to a previously staged image.
# --------------------------------------------------------------------------------
FW_DIR="../../sw/ad9361_loopback"
if command -v riscv-none-elf-gcc &> /dev/null; then
    echo "Building ad9361_loopback firmware (rv32im)..."
    make -C "$FW_DIR" MARCH=rv32im_zicsr_zifencei \
        clean_all image > fw_build.log 2>&1
    cp -f "$FW_DIR/neorv32_imem_image.vhd" ./neorv32_imem_image.vhd
    echo "Firmware image staged: neorv32_imem_image.vhd"
else
    if [ -f "neorv32_imem_image.vhd" ]; then
        echo "WARNING: riscv-none-elf-gcc not found; using previously staged image."
    else
        echo "ERROR: no RISC-V GCC and no staged neorv32_imem_image.vhd."
        exit 1
    fi
fi

# --------------------------------------------------------------------------------
# COE stimulus data (shared with the Xilinx 5.7 simulation)
# --------------------------------------------------------------------------------
if [ ! -f "qpsk_bram_data.hex" ]; then
    cp -f ../neorv32_sw_ad9361_datapath_sim/sim/qpsk_bram_data.hex . 2>/dev/null || {
        echo "ERROR: qpsk_bram_data.hex not found (generate it in ../neorv32_sw_ad9361_datapath_sim/sim first)"
        exit 1
    }
fi

echo "=========================================="
echo "AD9361 Datapath Questa Simulation (mpf300)"
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
