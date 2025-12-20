# NEORV32 NVC Simulation

This directory contains simulation scripts for running the NEORV32 RISC-V processor testbench using the [NVC](https://www.nickg.me.uk/nvc/) VHDL simulator.

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
run_sim.bat --time 10ms
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
| `--time TIME` | Simulation duration | `10ms` |
| `--wave FILE` | Waveform output filename | `neorv32_tb.fst` |
| `--clean` | Remove work directory and exit | - |
| `--help` | Display help message | - |

### Examples

Run with default settings (10ms simulation):
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
```

## About NVC

NVC is a free, open-source VHDL compiler and simulator that:

- Supports VHDL-1993, VHDL-2002, VHDL-2008, and VHDL-2019
- Uses LLVM for native code generation (fast simulation)
- Produces FST waveform files (compact, GTKWave-compatible)
- Runs on Windows, Linux, and macOS

For more information, visit: https://www.nickg.me.uk/nvc/
