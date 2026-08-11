#!/usr/bin/env bash
# ================================================================================
# AD9361 Datapath Simulation (Efinix ti375) - Questa Prime Launcher
# ================================================================================
# Efinix counterpart of ../neorv32_sw_ad9361_dapath_sim_microchip/run_sim.sh:
# boots the NEORV32 CPU with the ad9361_loopback firmware against the full
# ti375 FMCOMMS2 system — the REAL project system_top.v (axi_ad9361 Efinix
# LVDS + SmartHLS adapters + PULP interconnect + Bedrock-RTL CDC/resets)
# inside the Efinix-exported periphery netlist with the OFFICIAL EFX_*
# periphery models — in Questa Prime 2025.1 (from PATH).
#
#  ./run_sim.sh                    # fast (+acc=rn), GUI
#  ./run_sim.sh --batch            # fast, headless
#  ./run_sim.sh --detailed         # +acc=npr, full waveforms
#  ./run_sim.sh --clean            # remove generated files
#
# The firmware is (re)built here when the RISC-V GCC is on PATH:
#   make MARCH=rv32im_zicsr_zifencei clean_all image
# The register map is identical across all three vendor ports, so the
# firmware is byte-identical to the Xilinx and Microchip runs; rv32im makes
# mul_selftest() exercise the pipelined fast multiplier enabled in the
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
            rm -rf work neorv32
            rm -f *.wlf *.log *.vstf transcript *.mem qpsk_bram_data.hex modelsim.ini
            echo "Done."
            exit 0
            ;;
        --help)
            echo "AD9361 Datapath (Efinix ti375) Questa Prime Simulation Script"
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
# identical on all three platforms), rv32im for the multiplier self-test.
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
# Periphery simulation netlist (official Efinix models): a build product of
# the ti375 project's gen_interface.py. Regenerate when Efinity is
# available; otherwise require a previously generated copy.
# --------------------------------------------------------------------------------
TI375_DIR="../../../hdl/projects/fmcomms2/ti375"
PERI_NETLIST="$TI375_DIR/outflow/ti375c529_pt_interface.v"
EFINITY_HOME="${EFINITY_HOME:-/media/fpgadev/Dev_Tools/Efinity/2026.1}"
if [ -f "$EFINITY_HOME/bin/setup.sh" ]; then
    echo "Generating periphery sim netlist (official Efinix models)..."
    ( export PYTHONPATH="${PYTHONPATH:-}"
      set +o pipefail
      source "$EFINITY_HOME/bin/setup.sh" >/dev/null 2>&1 || true
      cd "$TI375_DIR" && efx_py scripts/gen_interface.py >/dev/null 2>&1 ) || true
fi
if [ ! -f "$PERI_NETLIST" ]; then
    echo "ERROR: periphery sim netlist not found: $PERI_NETLIST"
    echo "  Generate it: cd $TI375_DIR && source \$EFINITY_HOME/bin/setup.sh && efx_py scripts/gen_interface.py"
    exit 1
fi
# Stage a sim-local copy with the LVDS FASTCLK connections the official
# models require (see patch_peri_netlist.py for the vendor-gap details)
python3 patch_peri_netlist.py "$PERI_NETLIST" ti375c529_pt_interface_sim.v

# --------------------------------------------------------------------------------
# COE stimulus data (shared with the Xilinx 5.7 and Microchip simulations)
# --------------------------------------------------------------------------------
if [ ! -f "qpsk_bram_data.hex" ]; then
    cp -f ../neorv32_sw_ad9361_datapath_sim/sim/qpsk_bram_data.hex . 2>/dev/null || \
    cp -f ../neorv32_sw_ad9361_dapath_sim_microchip/qpsk_bram_data.hex . 2>/dev/null || {
        echo "ERROR: qpsk_bram_data.hex not found (generate it in ../neorv32_sw_ad9361_datapath_sim/sim first)"
        exit 1
    }
fi

echo "=========================================="
echo "AD9361 Datapath Questa Simulation (ti375)"
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
