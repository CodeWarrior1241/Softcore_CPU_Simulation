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

## Troubleshooting

### Compilation Errors
- Ensure Questa Prime supports VHDL-2008
- Check that all paths are correct (relative to `sim/questa/` directory)

### Simulation Issues
- Verify that the neorv32 library is properly mapped
- Check for missing dependencies in compilation order
