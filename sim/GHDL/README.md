# NEORV32 GHDL Simulation

This directory contains simulation scripts for running the NEORV32 RISC-V processor testbench using the [GHDL](https://ghdl.github.io/ghdl/) open-source VHDL simulator.

## Prerequisites

- **GHDL** - Open-source VHDL simulator with VHDL-2008 support
- **GTKWave** (optional) - Waveform viewer for VCD/GHW/FST files

### Installing GHDL

**Windows:**

Download the latest release from [GHDL Releases](https://github.com/ghdl/ghdl/releases) and add to PATH.

Using MSYS2:
```
pacman -S mingw-w64-x86_64-ghdl-llvm
```

**Linux (Ubuntu/Debian):**
```
sudo apt install ghdl
```

**Linux (from source with LLVM backend):**
```
git clone https://github.com/ghdl/ghdl.git
cd ghdl
./configure --with-llvm-config
make
sudo make install
```

**macOS (Homebrew):**
```
brew install ghdl
```

### Installing GTKWave (Optional)

GTKWave is used to view simulation waveforms.

**Windows:**

Download from [GTKWave SourceForge](http://gtkwave.sourceforge.net/) or use winget:
```
winget install gtkwave
```

**Linux (Ubuntu/Debian):**
```
sudo apt install gtkwave
```

**macOS (Homebrew):**
```
brew install gtkwave
```

## Changing the Application Program

The simulation runs whatever program is compiled into `rtl/core/neorv32_application_image.vhd`. To simulate a different program:

### Step 1: Build the Program

Navigate to the program directory and build it:

```bash
cd sw/example/hello_world
make clean_all exe
```

This generates `neorv32_application_image.vhd` in `rtl/core/`.

### Step 2: Clean and Re-run Simulation

The simulator must re-analyze the updated VHDL file:

```bash
cd sim/GHDL
./run_sim.sh --clean
./run_sim.sh --time 10ms
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
| `--vcd [FILE]` | Generate VCD waveform | `neorv32_tb.vcd` |
| `--ghw [FILE]` | Generate GHW waveform (GHDL native) | `neorv32_tb.ghw` |
| `--fst [FILE]` | Generate FST waveform (compact) | `neorv32_tb.fst` |
| `--no-log` | Disable logging to ghdl.log | - |
| `--quiet` | Suppress simulation progress output | - |
| `--clean` | Remove work directory and generated files | - |
| `--help` | Display help message | - |

## Examples

### Running Without Waveforms

For fast simulation when you only need console output:

```bash
# Run with default 150ms simulation time
./run_sim.sh

# Run for 50ms
./run_sim.sh --time 50ms

# Run without creating a log file
./run_sim.sh --no-log

# Run with suppressed output (quiet mode)
./run_sim.sh --quiet
```

### Running With Waveforms

To capture signal waveforms for debugging:

```bash
# Generate VCD waveform (widely compatible)
./run_sim.sh --vcd

# Generate GHW waveform (GHDL native format, more detailed)
./run_sim.sh --ghw

# Generate FST waveform (compact, fast loading)
./run_sim.sh --fst

# Custom filename and simulation time
./run_sim.sh --time 20ms --ghw my_simulation.ghw
```

### Viewing Waveforms with GTKWave

After generating waveforms, view them with GTKWave:

```bash
# View VCD file
gtkwave neorv32_tb.vcd

# View GHW file (GHDL native)
gtkwave neorv32_tb.ghw

# View FST file
gtkwave neorv32_tb.fst
```

### Cleaning Up

Remove all generated files:

```bash
./run_sim.sh --clean
```

## Overriding Testbench Generics

You can customize the CPU configuration by passing generic values at runtime. This allows testing software that requires different CPU features without modifying the testbench.

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

Generics are passed during the run phase using the `-g` flag:

```bash
# Single generic
ghdl -r --work=neorv32 --workdir=work --std=08 neorv32_tb -gIMEM_SIZE=65536 --stop-time=10ms

# Multiple generics
ghdl -r --work=neorv32 --workdir=work --std=08 neorv32_tb \
    -gIMEM_SIZE=65536 \
    -gDUAL_CORE_EN=false \
    -gRISCV_ISA_M=false \
    --stop-time=10ms
```

### Examples

```bash
# First, analyze the design (run once)
./run_sim.sh --time 0ms  # This analyzes but exits immediately

# Then run with custom generics
ghdl -r --work=neorv32 --workdir=work --std=08 neorv32_tb \
    -gIMEM_SIZE=65536 --stop-time=10ms

# Single-core configuration
ghdl -r --work=neorv32 --workdir=work --std=08 neorv32_tb \
    -gDUAL_CORE_EN=false --stop-time=10ms

# Minimal configuration with waveform output
ghdl -r --work=neorv32 --workdir=work --std=08 neorv32_tb \
    -gICACHE_EN=false -gDCACHE_EN=false -gRISCV_ISA_Zfinx=false \
    --stop-time=10ms --wave=minimal_config.ghw
```

**Note:** When using generics, you must run GHDL manually rather than using the `run_sim` scripts.

## Waveform Format Comparison

| Format | Extension | Description | Best For |
|--------|-----------|-------------|----------|
| VCD | `.vcd` | Value Change Dump (IEEE standard) | Compatibility with any viewer |
| GHW | `.ghw` | GHDL Waveform (native format) | Full VHDL type support, smaller files |
| FST | `.fst` | Fast Signal Trace | Large simulations, fast loading |

**Recommendations:**
- Use **GHW** for detailed debugging (preserves all VHDL types)
- Use **FST** for long simulations (10x smaller than VCD)
- Use **VCD** when sharing with tools other than GTKWave

## Simulation Workflow

The scripts perform three phases:

1. **Import** (`ghdl -i`) - Import all VHDL source files into the work library
2. **Make/Elaborate** (`ghdl -m`) - Analyze dependencies and elaborate the design
3. **Run** (`ghdl -r`) - Execute the simulation

## Directory Structure

```
sim/GHDL/
├── README.md       # This file
├── run_sim.bat     # Windows simulation script
├── run_sim.sh      # Unix/Linux/macOS simulation script
└── work/           # Generated - GHDL work library (git-ignored)
```

## GHDL Runtime Options

The simulation uses these GHDL options:

| Option | Purpose |
|--------|---------|
| `--std=08` | Enable VHDL-2008 standard |
| `--max-stack-alloc=0` | Disable stack allocation limit |
| `--ieee-asserts=disable` | Suppress IEEE library assertion messages |
| `--assert-level=error` | Only stop on error-level assertions |
| `--stop-time=TIME` | Set maximum simulation time |

## Troubleshooting

### GHDL not found
Ensure GHDL is in your system PATH:
```bash
ghdl --version
```

### Missing IEEE libraries
Some GHDL installations require explicit IEEE library path. Check your installation documentation.

### Out of memory
For large designs, increase stack size or use the LLVM backend which handles memory more efficiently.

## About GHDL

GHDL is a free, open-source VHDL simulator that:

- Supports VHDL-1987, VHDL-1993, VHDL-2002, and VHDL-2008
- Offers multiple backends: mcode (interpreted), GCC, and LLVM
- Generates native executables for fast simulation
- Produces VCD, GHW, and FST waveform files

For more information, visit: https://ghdl.github.io/ghdl/
