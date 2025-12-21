# NEORV32 Aldec Active-HDL Simulation

This directory contains simulation scripts for running the NEORV32 processor simulation using Aldec Active-HDL.

## Prerequisites

- Aldec Active-HDL (tested with version 15 SE)
- VHDL-2008 support enabled

## Quick Start

### Windows
```batch
run_sim.bat
```

### Linux/Unix
```bash
./run_sim.sh
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--time TIME` | Set simulation time (default: 150ms) |
| `--gui` | Run in GUI mode (default) |
| `--batch` | Run in batch/command-line mode |
| `--clean` | Remove work directory and generated files |
| `--help` | Show help message |

## Examples

```batch
# Run with defaults (150ms, GUI mode)
run_sim.bat

# Run for 50ms
run_sim.bat --time 50ms

# Run in batch mode
run_sim.bat --batch

# Run 20ms in batch mode
run_sim.bat --time 20ms --batch

# Clean all generated files
run_sim.bat --clean
```

## Script Files

| File | Description |
|------|-------------|
| `run_sim.bat` | Windows launcher script |
| `run_sim.sh` | Linux/Unix launcher script |
| `compile.do` | VHDL compilation script |
| `simulate.do` | Simulation execution script |

## Output Files

After simulation, the following files are generated:

- `tb.uart0_rx.log` - UART0 receive log (console output)
- `tb.uart1_rx.log` - UART1 receive log
- `neorv32.tracer*.log` - CPU trace logs (if tracer enabled)

## Configuration

The default Active-HDL path in `run_sim.bat` is:
```
C:\Aldec\Active-HDL_15_SE\bin\vsim.exe
```

If your installation is in a different location, edit the `VSIM` variable in `run_sim.bat`.

## Differences from Questa

Active-HDL uses different command names:
- `alib` instead of `vlib` (create library)
- `amap` instead of `vmap` (map library)
- `acom` instead of `vcom` (compile VHDL)
- `asim` instead of `vsim` (simulate)
- `endsim` instead of `quit -sim` (end simulation)
