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
