#!/bin/bash
#==============================================================================
# build_hls.sh
#
# Build script for AXI AD9361 Adapter HLS IP
# Runs C simulation, synthesis, and exports IP for Vivado integration
#
# Prerequisites:
#   - Vitis 2025.2 installed
#   - Source settings64.sh before running
#
# Usage:
#   ./build_hls.sh [csim|csynth|cosim|package|all|clean]
#
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/work"
CONFIG_FILE="${SCRIPT_DIR}/axi_ad9361_adapter.cfg"
IP_OUTPUT_DIR="${SCRIPT_DIR}/../../../hls_ip"

# Check for Vitis installation
if ! command -v vitis-run &> /dev/null; then
    echo "ERROR: vitis-run not found in PATH"
    echo "Please source Vitis settings64.sh first"
    exit 1
fi

# Parse command line argument
TARGET="${1:-all}"

echo "=============================================================================="
echo "AXI AD9361 Adapter HLS Build Script"
echo "=============================================================================="
echo "Target:     ${TARGET}"
echo "Work Dir:   ${WORK_DIR}"
echo "Config:     ${CONFIG_FILE}"
echo "IP Output:  ${IP_OUTPUT_DIR}"
echo "=============================================================================="

# Function definitions
clean() {
    echo ""
    echo "[CLEAN] Removing work directory..."
    rm -rf "${WORK_DIR}"
    echo "Clean complete."
}

csim() {
    echo ""
    echo "[CSIM] Running C Simulation..."
    cd "${SCRIPT_DIR}"
    vitis-run --mode hls --csim --config "${CONFIG_FILE}" --work_dir "${WORK_DIR}"
    echo "C Simulation complete."
}

csynth() {
    echo ""
    echo "[CSYNTH] Running C Synthesis..."
    cd "${SCRIPT_DIR}"
    v++ --compile --mode hls --config "${CONFIG_FILE}" --work_dir "${WORK_DIR}"
    echo "C Synthesis complete."
}

cosim() {
    echo ""
    echo "[COSIM] Running Co-Simulation..."
    cd "${SCRIPT_DIR}"
    vitis-run --mode hls --cosim --config "${CONFIG_FILE}" --work_dir "${WORK_DIR}"
    echo "Co-Simulation complete."
}

package_ip() {
    echo ""
    echo "[PACKAGE] Exporting IP..."
    cd "${SCRIPT_DIR}"
    v++ --package --mode hls --config "${CONFIG_FILE}" --work_dir "${WORK_DIR}"

    # Copy IP to output directory
    echo ""
    echo "[PACKAGE] Copying IP to output directory..."
    mkdir -p "${IP_OUTPUT_DIR}"

    # Find and copy the generated IP zip file
    find "${WORK_DIR}" -name "*.zip" -exec cp -v {} "${IP_OUTPUT_DIR}/" \;

    echo "IP Export complete."
    echo "IP available at: ${IP_OUTPUT_DIR}"
}

build_all() {
    echo ""
    echo "[ALL] Running full build flow..."
    csim
    csynth
    package_ip
    echo ""
    echo "=============================================================================="
    echo "Full build complete!"
    echo "=============================================================================="
}

# Execute requested target
case "${TARGET}" in
    clean)
        clean
        ;;
    csim)
        csim
        ;;
    csynth)
        csynth
        ;;
    cosim)
        cosim
        ;;
    package)
        package_ip
        ;;
    all)
        build_all
        ;;
    *)
        echo "ERROR: Unknown target: ${TARGET}"
        echo "Valid targets: csim, csynth, cosim, package, all, clean"
        exit 1
        ;;
esac

exit 0
