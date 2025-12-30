# NEORV32 NVC Simulation

This directory contains simulation scripts for running the NEORV32 RISC-V processor testbench using the [NVC](https://www.nickg.me.uk/nvc/) VHDL simulator.

> **Note:** This simulation is functionally identical to the Questa simulation in `sim/Questa/`. Both use the same testbench and produce the same results. Choose based on your toolchain:
> - **NVC** - Free, open-source alternative
> - **Questa Prime** - Commercial simulator (requires license)

## Prerequisites

- **NVC 1.8+** - Open-source VHDL simulator with VHDL-2008 support
- **GTKWave** (optional) - Waveform viewer for FST files

### Installation

**Windows (winget):**
```
winget install nickg.nvc
```

**Linux (Ubuntu/Debian):**
```
sudo apt install nvc
```

**macOS (Homebrew):**
```
brew install nvc
```

## Changing the Application Program

The simulation runs whatever program is compiled into `rtl/core/neorv32_application_image.vhd`. To simulate a different program:

### Step 1: Build the Program

Navigate to the program directory and build it:

```batch
cd sw\example\hello_world
make clean_all exe
```

This generates `neorv32_application_image.vhd` in `rtl/core/`.

### Step 2: Clean and Re-run Simulation

The simulator must re-analyze the updated VHDL file:

```batch
cd sim\NVC
run_sim.bat --clean
run_sim.bat --time 500ms
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
| `--time TIME` | Simulation duration | `150ms` |
| `--wave FILE` | Waveform output filename | `neorv32_tb.fst` |
| `--quiet` | Suppress simulation progress output | - |
| `--clean` | Remove work directory and exit | - |
| `--help` | Display help message | - |

### Examples

Run with default settings (150ms simulation):
```
run_sim.bat
```

Run for 50ms:
```
run_sim.bat --time 50ms
```

Run with custom waveform output:
```
run_sim.bat --time 20ms --wave my_simulation.fst
```

Clean up work directory:
```
run_sim.bat --clean
```

## Overriding Testbench Generics

You can customize the CPU configuration by passing generic values during elaboration. This allows testing software that requires different CPU features without modifying the testbench.

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

Generics are passed during the elaboration phase using the `-g` flag:

```bash
# Single generic
nvc --std=2008 --work=work:work/work -L work -e neorv32_tb -gIMEM_SIZE=65536

# Multiple generics
nvc --std=2008 --work=work:work/work -L work -e neorv32_tb \
    -gIMEM_SIZE=65536 \
    -gDUAL_CORE_EN=false \
    -gRISCV_ISA_M=false
```

### Examples

```bash
# Simulate with 64KB instruction memory
nvc -e neorv32_tb -gIMEM_SIZE=65536
nvc -r neorv32_tb --stop-time=10ms

# Simulate single-core configuration
nvc -e neorv32_tb -gDUAL_CORE_EN=false
nvc -r neorv32_tb --stop-time=10ms

# Minimal configuration (no caches, no FPU)
nvc -e neorv32_tb -gICACHE_EN=false -gDCACHE_EN=false -gRISCV_ISA_Zfinx=false
nvc -r neorv32_tb --stop-time=10ms
```

**Note:** When using generics, you must run the elaboration and simulation steps manually rather than using the `run_sim` scripts.

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

## Viewing Waveforms

After simulation completes, view the waveform with GTKWave:

```
gtkwave neorv32_tb.fst
```

## Simulation Workflow

The scripts perform three phases:

1. **Analyze** (`nvc -a`) - Parse and analyze all VHDL source files in dependency order
2. **Elaborate** (`nvc -e`) - Elaborate the top-level testbench entity
3. **Run** (`nvc -r`) - Execute the simulation

## Directory Structure

```
sim/NVC/
├── README.md       # This file
├── run_sim.bat     # Windows simulation script
├── run_sim.sh      # Unix/Linux/macOS simulation script
└── work/           # Generated - NVC work library (git-ignored)

sim/                # Parent directory (shared scripts)
├── calculate_sim_time.py           # QPSK simulation timing calculator
├── display_qpsk_constellation.py   # QPSK constellation plot generator
└── ...
```

## About NVC

NVC is a free, open-source VHDL compiler and simulator that:

- Supports VHDL-1993, VHDL-2002, VHDL-2008, and VHDL-2019
- Uses LLVM for native code generation (fast simulation)
- Produces FST waveform files (compact, GTKWave-compatible)
- Runs on Windows, Linux, and macOS

For more information, visit: https://www.nickg.me.uk/nvc/
