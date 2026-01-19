# Vivado Block Design Simulation

This directory contains simulation scripts for running the Vivado block design testbench using [Questa Prime](https://www.siemens.com/eda/questa).

## Prerequisites

- **Vivado 2025.2** (or compatible version) - For block design IP generation
- **Questa Prime** - Intel/Siemens FPGA simulation tool
- **Pre-compiled Xilinx simulation libraries** - See [Questa Library Requirements](#questa-library-requirements)
- **Python 3** with matplotlib/numpy (optional) - For constellation plotting

### Library Symlink Setup (One-Time)

After running `compile_simlib`, create a junction/symlink from `sim/libraries` to your compiled libraries directory:

**Windows (run as Administrator or with Developer Mode enabled):**
```batch
cd setups\vivado\sim
mklink /J libraries C:\Work\Questa_Libraries_Vivado
```

**Linux/macOS:**
```bash
cd setups/vivado/sim
ln -s /path/to/questa_libraries libraries
```

This symlink is required because the `modelsim.ini` from `compile_simlib` references library paths relative to this location.

## Directory Structure

```
setups/vivado/sim/
├── README.md               # This file
├── run_sim.bat             # Windows simulation launcher
├── run_sim.sh              # Unix/Linux/macOS simulation launcher
├── compile.do              # Questa compilation script
├── simulate.do             # Questa simulation script
├── vivado_tb.vhd           # VHDL-2008 testbench for Top_wrapper
├── generate_qpsk_coe.py    # QPSK BRAM initialization generator
└── qpsk_bram_init.coe      # Generated BRAM initialization file
```

## Block Design Overview

The Vivado block design (`Top_wrapper`) contains:

- **NEORV32 RISC-V Processor** - Configured for RV32IMC, 32KB IMEM, 16KB DMEM
- **Clock Wizard (PLL)** - Converts 300 MHz differential input to 100 MHz CPU clock
- **Processor System Reset** - Synchronizes reset across clock domains
- **AXI SmartConnect** - Connects CPU to AXI peripherals
- **AXI BRAM Controller** - Interfaces with QPSK snapshot BRAM
- **Block RAM** - 4KB QPSK sample storage (initialized with .coe file)

## Usage

### Windows

```batch
run_sim.bat [options]
```

### Linux/macOS

```bash
chmod +x run_sim.sh
./run_sim.sh [options]
```

### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--time TIME` | Simulation duration | `500ms` |
| `--gui` | Run in GUI mode | (default) |
| `--batch` | Run in batch/command-line mode | - |
| `--clean` | Remove work directories and generated files | - |
| `--help` | Display help message | - |

### Examples

```bash
# Run with default 500ms simulation time in GUI mode
./run_sim.sh

# Run for 100ms in batch mode
./run_sim.sh --time 100ms --batch

# Clean up generated files
./run_sim.sh --clean
```

## BRAM Initialization

The QPSK snapshot BRAM is initialized using `qpsk_bram_init.coe`, which contains 1024 x 32-bit QPSK IQ samples. To regenerate the initialization file:

```bash
python generate_qpsk_coe.py
```

The generator uses the same LFSR algorithm as `sim/iq_bram.vhd`:
- **LFSR Polynomial**: x^32 + x^22 + x^2 + x + 1 (maximal-length)
- **Seed**: 0xDEADBEEF
- **Constellation**: QPSK at ±16384 with ±256 noise

After regenerating, update the BRAM IP in Vivado:
1. Open the block design
2. Double-click the QPSK_Snapshot_BRAM IP
3. Point to the new .coe file
4. Regenerate output products

## Simulation Timing

For QPSK data transmission over UART at 115200 baud:

| Samples | Data Size | UART Time | Recommended |
|---------|-----------|-----------|-------------|
| 256     | 1 KB      | ~90 ms    | 150 ms      |
| 512     | 2 KB      | ~180 ms   | 250 ms      |
| 1024    | 4 KB      | ~360 ms   | **500 ms**  |
| 2048    | 8 KB      | ~720 ms   | 900 ms      |

The default `--time 500ms` is recommended for full QPSK snapshot capture (1024 samples).

## QPSK Constellation Display

After simulation, if `tb.uart0_rx.log` is generated, the run scripts automatically attempt to create a constellation plot:

```bash
# Manual usage
python ../../../sim/display_qpsk_constellation.py --save qpsk_constellation.png --no-display
```

### Requirements

```bash
pip install matplotlib numpy
```

## Testbench Details

The testbench (`vivado_tb.vhd`) provides:

1. **300 MHz Differential Clock** - Matches the AU15P board ECS clock input
2. **Active-low Reset** - 100ns reset pulse at startup
3. **UART Monitoring** - Uses `sim_uart_rx` to capture CPU output
4. **Simulation Clock Output** - The block design exposes `sim_clock_100MHz` for the UART receiver

### Clock Configuration

- Input: 300 MHz differential (ecs_clk_in_clk_p/n)
- PLL output: 100 MHz to CPU (exposed as `sim_clock_100MHz` for simulation)
- UART baud rate: 115200

## Compilation Order

The `compile.do` script compiles sources in the following order:

1. **Vivado's generated `compile.do`** - Compiles all IP cores and block design components
2. **`sim_uart_rx.vhd`** - UART receiver for capturing CPU serial output
3. **`Top.vhd`** - Block design entity (recompiled to pick up port changes like `sim_clock_100MHz`)
4. **`Top_wrapper.vhd`** - Block design wrapper
5. **`vivado_tb.vhd`** - Top-level testbench

The explicit recompilation of `Top.vhd` and `Top_wrapper.vhd` after running Vivado's compile script ensures that any modifications to the block design ports (such as exposing the `sim_clock_100MHz` output for simulation) are picked up, overwriting stale cached versions in the library.

## Questa Library Requirements

The simulation requires pre-compiled Xilinx simulation libraries. These must be compiled once using Vivado's `compile_simlib` command.

### One-Time Library Setup

Run this command in Vivado's Tcl console to compile all Xilinx simulation libraries for Questa:

```tcl
compile_simlib -simulator questa \
    -simulator_exec_path {/path/to/questa/bin} \
    -family all \
    -language all \
    -library all \
    -dir {/path/to/Questa_Libraries_Vivado}
```

This takes 15-30 minutes and creates libraries in the specified directory.

### Library Configuration

Create a symlink named `libraries` in the `sim/` directory pointing to your pre-compiled Xilinx libraries:

```bash
# Linux/macOS
ln -s /path/to/Questa_Libraries_Vivado libraries

# Windows (run as Administrator)
mklink /D libraries C:\path\to\Questa_Libraries_Vivado
```

The `compile.do` script will automatically use this symlink.

### Required Libraries

The following libraries are used by the simulation:

| Library | Purpose |
|---------|---------|
| `unisim` | VHDL simulation primitives (BUFG, MMCM, etc.) |
| `unisims_ver` | Verilog simulation primitives |
| `unimacro` | VHDL macro library |
| `unimacro_ver` | Verilog macro library |
| `secureip` | Encrypted IP simulation models |
| `xpm` | Xilinx Parameterized Macros |
| `xilinx_vip` | Xilinx Verification IP |

## Troubleshooting

### "Questa Prime not found"

Update the `VSIM` path in `run_sim.bat` or set the `VSIM` environment variable:

```bash
export VSIM=/path/to/vsim
```

### Compilation errors

Ensure the Vivado project has been built and output products generated:

```tcl
# In Vivado
generate_target all [get_files Top.bd]
```

### "Library unisim not found"

The pre-compiled Xilinx libraries are not set up correctly. Either:

1. Run `compile_simlib` as described above
2. Verify the library path in `compile.do` matches your library location
3. Ensure the `sim/libraries` junction/symlink points to the correct location

### BRAM initialization file not found

The simulation must run from the Vivado questa directory where `.mif` files are located. The `simulate.do` script handles this automatically by changing to `$vivado_questa_dir` before running vsim.

### Time resolution mismatch

If you see "minimum time resolution limit (1ps)" errors, ensure the `vsim` command includes `-t 1ps`:

```tcl
vsim -t 1ps -lib xil_defaultlib vivado_tb_opt
```

## Related Files

- `../build_all.tcl` - Vivado project generation script
- `../../../sim/display_qpsk_constellation.py` - Constellation plot generator
- `../../../sim/sim_uart_rx.vhd` - UART receiver simulation component
