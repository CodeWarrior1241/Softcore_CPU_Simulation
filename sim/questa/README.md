# NEORV32 Questa Prime Simulation

This directory contains scripts for simulating the NEORV32 RISC-V processor using Questa Prime with VHDL-2008.

## Prerequisites

- Questa Prime (or ModelSim) with VHDL-2008 support
- `vsim` command available in PATH

## Quick Start

### Windows
```batch
run_sim.bat
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
./run_sim.sh -batch -time 1ms

# Run GUI simulation for 100us
./run_sim.sh -gui -time 100us
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

## Testbench Configuration

The testbench (`neorv32_tb.vhd`) supports various generics for configuration:

- `CLOCK_FREQUENCY` - System clock frequency (default: 100 MHz)
- `DUAL_CORE_EN` - Enable dual-core SMP
- `RISCV_ISA_*` - Enable/disable RISC-V extensions
- `IMEM_SIZE` / `DMEM_SIZE` - Memory sizes
- `ICACHE_EN` / `DCACHE_EN` - Enable caches

## Troubleshooting

### Compilation Errors
- Ensure Questa Prime supports VHDL-2008
- Check that all paths are correct (relative to `sim/questa/` directory)

### Simulation Issues
- Verify that the neorv32 library is properly mapped
- Check for missing dependencies in compilation order
