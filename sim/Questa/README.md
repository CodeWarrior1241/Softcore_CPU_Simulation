# NEORV32 Questa Prime Simulation

This directory contains scripts for simulating the NEORV32 RISC-V processor using Questa Prime with VHDL-2008.

> **Note:** This simulation is functionally identical to the NVC simulation in `sim/NVC/`. Both use the same testbench and produce the same results. Choose based on your toolchain:
> - **Questa Prime** - Commercial simulator (requires license)
> - **NVC** - Free, open-source alternative

## Prerequisites

- Questa Prime (or ModelSim) with VHDL-2008 support
- `vsim` command available in PATH
- Python 3 with matplotlib/numpy (optional, for constellation plots)

## Changing the Application Program

The simulation runs whatever program is compiled into `rtl/core/neorv32_application_image.vhd`. To simulate a different program:

### Step 1: Build the Program

Navigate to the program directory and build it:

```batch
cd sw\example\hello_world
make clean_all exe
```

This generates `neorv32_application_image.vhd` in `rtl/core/`.

### Step 2: Recompile and Re-run Simulation

The simulator must recompile the updated VHDL file:

```batch
cd sim\questa
run_sim.bat
```

Or in the Questa GUI:
```tcl
do compile.do
do simulate.do
```

### Available Example Programs

| Program | Description |
|---------|-------------|
| `hello_world` | Prints "Hello World!" via UART |
| `demo_blink_led` | Blinks LEDs (not ideal for simulation - uses long delays) |
| `demo_crc` | CRC computation demo |
| `demo_trng` | True random number generator demo |

See `sw/example/` for more programs.

### Build Requirements

- RISC-V GCC toolchain (`riscv-none-elf-gcc` or `riscv32-unknown-elf-gcc`)
- `image_gen` utility (build with `sw/image_gen/build_msvc.bat` on Windows)

## Quick Start

### Windows
```batch
run_sim.bat --clean
run_sim.bat --time 500ms
```

### Linux/Unix
```bash
chmod +x run_sim.sh
./run_sim.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `compile.do` | Compiles all VHDL sources in correct dependency order |
| `simulate.do` | Loads design, adds waveforms, and runs simulation |
| `wave.do` | Custom waveform configuration for detailed analysis |
| `run_sim.bat` | Windows launcher script |
| `run_sim.sh` | Linux/Unix launcher script |

## Command Line Options

```
run_sim [-batch|-gui] [-time <simulation_time>]

Options:
  -batch    Run in batch mode (no GUI)
  -gui      Run in GUI mode (default)
  -time     Set simulation time (default: 10ms)
```

### Examples

```bash
# Run GUI simulation for 10ms (default)
./run_sim.sh

# Run batch simulation for 1ms
./run_sim.sh --batch --time 1ms

# Run GUI simulation for 100us
./run_sim.sh --gui --time 100us
```

## Manual Questa Usage

1. Open Questa Prime
2. Navigate to this directory
3. Run the compile script:
   ```tcl
   do compile.do
   ```
4. Run the simulation script:
   ```tcl
   do simulate.do
   ```
5. Optionally load custom waveforms:
   ```tcl
   do wave.do
   ```

## Overriding Testbench Generics

You can customize the CPU configuration by passing generic values to `vsim`. This allows testing software that requires different CPU features without modifying the testbench.

### Available Generics

| Generic | Type | Default | Description |
|---------|------|---------|-------------|
| `CLOCK_FREQUENCY` | natural | 100000000 | Clock frequency in Hz |
| `DUAL_CORE_EN` | boolean | true | Enable dual-core SMP |
| `BOOT_MODE_SELECT` | natural | 2 | Boot mode (2 = IMEM) |
| `IMEM_SIZE` | natural | 32768 | Instruction memory size (bytes) |
| `DMEM_SIZE` | natural | 8192 | Data memory size (bytes) |
| `RISCV_ISA_C` | boolean | true | Compressed instructions |
| `RISCV_ISA_M` | boolean | true | Multiply/divide extension |
| `RISCV_ISA_U` | boolean | true | User mode extension |
| `RISCV_ISA_Zfinx` | boolean | true | Floating-point extension |
| `ICACHE_EN` | boolean | true | Instruction cache enable |
| `DCACHE_EN` | boolean | true | Data cache enable |

See `sim/neorv32_tb.vhd` for the complete list of available generics.

### Passing Generics via Command Line

Generics are passed to `vsim` using the `-g` flag with the hierarchical path:

```tcl
# Single generic
vsim -g/neorv32_tb/IMEM_SIZE=65536 work.neorv32_tb

# Multiple generics
vsim -g/neorv32_tb/IMEM_SIZE=65536 \
     -g/neorv32_tb/DUAL_CORE_EN=false \
     -g/neorv32_tb/RISCV_ISA_M=false \
     work.neorv32_tb
```

### Using vopt for Optimized Simulation

For better performance with generics, use `vopt`:

```tcl
# Compile first
do compile.do

# Optimize with generic overrides
vopt +acc neorv32_tb -G IMEM_SIZE=65536 -G DUAL_CORE_EN=false -o neorv32_tb_opt

# Run optimized simulation
vsim neorv32_tb_opt
run 10ms
```

### Examples

```tcl
# After running compile.do, simulate with 64KB instruction memory
vsim -g/neorv32_tb/IMEM_SIZE=65536 work.neorv32_tb
run 10ms

# Single-core configuration
vsim -g/neorv32_tb/DUAL_CORE_EN=false work.neorv32_tb
run 10ms

# Minimal configuration (no caches, no FPU)
vsim -g/neorv32_tb/ICACHE_EN=false \
     -g/neorv32_tb/DCACHE_EN=false \
     -g/neorv32_tb/RISCV_ISA_Zfinx=false \
     work.neorv32_tb
run 10ms
```

### In a .do Script

Create a custom configuration script (e.g., `sim_custom.do`):

```tcl
# Load design with custom generics
vsim -g/neorv32_tb/IMEM_SIZE=65536 -g/neorv32_tb/DUAL_CORE_EN=false work.neorv32_tb

# Add waves and run
do wave.do
run 10ms
```

**Note:** When using generics, you must run `vsim` manually rather than using the `run_sim` scripts.

## QPSK Simulation Timing

When running the QPSK handler application, sufficient simulation time is needed to transmit all IQ samples over UART. Use the included calculator to determine the minimum required time.

### Timing Calculator

```bash
python ../calculate_sim_time.py
```

Output:
```
==================================================
QPSK Simulation Time Calculator
==================================================

UART Configuration:
  Baud rate:        115,200 bps
  Bits per byte:    10 (8N1)

Data Sizes:
  ASCII responses:  40 bytes
  IQ data:          4,096 bytes (1024 samples x 4)
  Total:            4,136 bytes (41,360 bits)

Time Breakdown:
  UART transmission: 359.0 ms
  CPU boot:          10 ms
  Command delays:    30 ms
  Processing:        20 ms
  ------------------------------
  Minimum total:     419 ms

RECOMMENDED: --time 503ms
==================================================
```

### Quick Reference

| Samples | IQ Data | UART Time | Recommended |
|---------|---------|-----------|-------------|
| 256     | 1 KB    | ~90 ms    | 150 ms      |
| 512     | 2 KB    | ~180 ms   | 250 ms      |
| 1024    | 4 KB    | ~360 ms   | **500 ms**  |
| 2048    | 8 KB    | ~720 ms   | 900 ms      |

The default `--time 150ms` is only sufficient for basic tests. For full QPSK snapshot capture (1024 samples), use:

```bash
run_sim.bat --time 500ms
```

### Timing Formula

```
UART_time = (total_bytes x 10 bits) / baud_rate

For 1024 IQ samples at 115200 baud:
  = (4136 bytes x 10) / 115200
  = 359 ms

Add ~60ms overhead for CPU boot, command processing, and testbench delays.
Total minimum: ~420 ms
With 20% safety margin: ~500 ms
```

## QPSK Constellation Display

After simulation, the run scripts automatically generate a QPSK constellation plot from the captured IQ data (requires Python with matplotlib/numpy).

### Manual Usage

```bash
python ../display_qpsk_constellation.py [options]
```

| Option | Description |
|--------|-------------|
| `--save FILE` | Save plot to PNG file |
| `--no-display` | Don't show interactive window |
| `--filter` | Remove outlier samples |

### Examples

Display constellation interactively:
```bash
python ../display_qpsk_constellation.py
```

Save to file without display:
```bash
python ../display_qpsk_constellation.py --save qpsk.png --no-display
```

Filter outliers for cleaner plot:
```bash
python ../display_qpsk_constellation.py --save qpsk.png --filter
```

### Requirements

```bash
pip install matplotlib numpy
```

## Simulation Workflow

The scripts perform two phases:

1. **Compile** (`compile.do`) - Compile all VHDL source files in dependency order into the work library
2. **Simulate** (`simulate.do`) - Load the design, configure waveforms, and run simulation

## Directory Structure

```
sim/Questa/
├── README.md       # This file
├── compile.do      # VHDL compilation script
├── simulate.do     # Simulation launch script
├── wave.do         # Custom waveform configuration
├── run_sim.bat     # Windows simulation script
├── run_sim.sh      # Unix/Linux/macOS simulation script
└── work/           # Generated - Questa work library (git-ignored)

sim/                # Parent directory (shared scripts)
├── calculate_sim_time.py           # QPSK simulation timing calculator
├── display_qpsk_constellation.py   # QPSK constellation plot generator
└── ...
```

## About Questa

Questa Prime is a commercial VHDL/Verilog simulator from Siemens EDA (formerly Mentor Graphics) that:

- Supports VHDL-1993, VHDL-2002, VHDL-2008, and SystemVerilog
- Provides advanced debugging with integrated waveform viewer
- Offers high-performance simulation with optimizations
- Includes code coverage and assertion-based verification

For more information, visit: https://eda.sw.siemens.com/en-US/ic/questa/

## Troubleshooting

### Compilation Errors
- Ensure Questa Prime supports VHDL-2008
- Check that all paths are correct (relative to `sim/Questa/` directory)

### Simulation Issues
- Verify that the neorv32 library is properly mapped
- Check for missing dependencies in compilation order
