# QPSK Handler - NEORV32 UART Command Interface

This application implements a UART command interface for the QPSK Triple Comparison project. It communicates with a MATLAB GUI application to control RF hardware and capture IQ sample data from the FPGA.

## Prerequisites

### RISC-V GCC Toolchain

A RISC-V cross-compiler toolchain is required to build applications for the NEORV32.

**Linux (Ubuntu/Debian):**
```bash
sudo apt install gcc-riscv64-unknown-elf
```

**Linux (Fedora):**
```bash
sudo dnf install gcc-riscv64-linux-gnu
```

**Windows/Linux/macOS (Pre-built):**

Download the SiFive Freedom Tools or xPack RISC-V toolchain:
- [xPack RISC-V GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases) (recommended)
- [SiFive Freedom Tools](https://github.com/sifive/freedom-tools/releases)

Extract and add the `bin` directory to your PATH. The toolchain prefix should be `riscv-none-elf-` or `riscv64-unknown-elf-`.

If your toolchain uses a different prefix, set it in the makefile or environment:
```bash
export RISCV_PREFIX=riscv64-unknown-elf-
```

### Image Generator

The `image_gen` utility converts compiled binaries to VHDL memory images. It is built automatically on first compile, but requires a native C compiler.

**Linux/macOS:**
```bash
# GCC is typically pre-installed; if not:
sudo apt install gcc    # Debian/Ubuntu
sudo dnf install gcc    # Fedora
brew install gcc        # macOS with Homebrew
```

**Windows:**

Option 1 - Use GCC (MinGW/MSYS2):
```bash
# From MSYS2 shell
pacman -S mingw-w64-x86_64-gcc
```

Option 2 - Use MSVC:
```cmd
cd sw\image_gen
build_msvc.bat
```

Option 3 - Use pre-built executable (if available in `sw/image_gen/image_gen.exe`)

## Overview

The NEORV32 processor acts as a bridge between the MATLAB host application and the FPGA-based QPSK signal processing hardware. It receives ASCII commands over UART, controls RF enable/disable via GPIO, and transmits captured IQ constellation data back to the host.

## Hardware Requirements

- NEORV32 processor with UART0 enabled
- GPIO module for RF control output
- IQ sample BRAM at address `0xC0000000` (memory-mapped via XBUS)

## Memory Configuration

The application is configured for the following memory layout:

| Memory | Size | Address Range |
|--------|------|---------------|
| IMEM (code) | 16 KB | `0x00000000` - `0x00003FFF` |
| DMEM (data) | 8 KB | `0x80000000` - `0x80001FFF` |
| IQ BRAM | 8 KB | `0xC0000000` - `0xC0001FFF` |

### DMEM Layout

The 8KB internal data memory is organized as follows:

```
0x80000000  +─────────────────+  RAM base
            │     .data       │  Initialized global variables that are explicitly initialized
            ├─────────────────┤
            │     .bss        │  Uninitialized globals (iq_buffer, etc.)
            │                 │  ~4.3 KB
            ├─────────────────┤
            │     .heap       │  Dynamic allocation such as malloc() etc. (grows upward)
            │        ↓        │
            │                 │
            │    (free)       │  ~3.7 KB available
            │                 │
            │        ↑        │
            │     stack       │  Function calls, local vars (grows downward)
            ├─────────────────┤
0x80002000  +─────────────────+  RAM top (8 KB)
```

**Important:** The `__neorv32_ram_size` linker symbol must match the testbench `DMEM_SIZE` generic. A mismatch causes the stack pointer to be placed outside valid memory, resulting in bus errors.

## UART Configuration

| Parameter | Value |
|-----------|-------|
| Baud Rate | 115200 |
| Data Bits | 8 |
| Stop Bits | 1 |
| Parity | None |
| Line Terminator | LF (`\n`, 0x0A) |

## Command Protocol

All commands are ASCII strings terminated with a newline character (`\n`).

### Commands Received

| Command | Description |
|---------|-------------|
| `enable_rf\n` | Enable RF circuitry via GPIO |
| `disable_rf\n` | Disable RF circuitry via GPIO |
| `enable_snapshot\n` | Capture and transmit 1024 IQ samples |

### Responses Sent

| Command Received | Response Sent | Additional Data |
|------------------|---------------|-----------------|
| `enable_rf` | `rf_enabled\n` | None |
| `disable_rf` | `rf_disabled\n` | None |
| `enable_snapshot` | `snapshot_enabled\n` | 4096 bytes binary IQ data |

## IQ Data Format

After sending the `snapshot_enabled\n` response, the application transmits 4096 bytes of raw binary IQ sample data:

| Parameter | Value |
|-----------|-------|
| Number of Samples | 1024 |
| Bytes per Sample | 4 (32-bit) |
| Total Data Size | 4096 bytes |
| Byte Order | Little-endian |

### Per-Sample Byte Layout

Each 32-bit sample contains a 16-bit I (in-phase) and 16-bit Q (quadrature) value:

```
Byte 0: I[7:0]   (I low byte)
Byte 1: I[15:8]  (I high byte)
Byte 2: Q[7:0]   (Q low byte)
Byte 3: Q[15:8]  (Q high byte)
```

Both I and Q are 16-bit signed integers (two's complement format).

## GPIO Pin Mapping

| GPIO Pin | Function | Active State |
|----------|----------|--------------|
| GPIO[0] | RF Enable | High = Enabled |

## Building

```bash
cd sw/snapshot_handler
make clean all
```

## Simulation

### Step 1: Build and Install Application Image

```bash
cd sw/snapshot_handler
make install
```

This compiles the application and installs `neorv32_application_image.vhd` to `rtl/core/`.

> **Windows Users:** If `make install` fails with a `-e` error, see the [Windows Troubleshooting](#windows-troubleshooting) section below.

### Step 2: Run Simulation

**Using NVC:**
```bash
cd sim/NVC
./run_sim.sh --time 200ms
```

**Using Questa:**
```bash
cd sim/Questa
./run_sim.sh --time 200ms
```

**Using Questa (Windows):**
```cmd
cd sim\Questa
run_sim.bat --time 200ms
```

### Step 3: Check Results

UART output is captured to `tb.uart0_rx.log` in the simulation directory.

## Programming

Upload the generated executable image to the NEORV32 using your preferred method (bootloader, JTAG, etc.):

```bash
make exe
# Upload neorv32_exe.bin via bootloader
```

## Windows Troubleshooting

### "Environment variable -e not defined" Error

When running `make install` on Windows cmd, you may see:
```
Environment variable -e not defined
make: *** [../../sw/common/common.mk:243: neorv32_application_image.vhd] Error 1
```

This occurs because the makefile uses `set -e` (a Unix shell command) which Windows cmd interprets as setting an environment variable named `-e`.

**Workaround:** After `make all` succeeds, manually run the image generator and copy the result:

```cmd
cd sw\snapshot_handler

REM Generate the VHDL image
..\..\sw\image_gen\image_gen.exe -t app_vhd -i build\main.bin -o neorv32_application_image.vhd

REM Install to rtl/core
copy neorv32_application_image.vhd ..\..\rtl\core\
```

**Alternative:** Use Git Bash, MSYS2, or WSL instead of Windows cmd, where the makefile works correctly.

## Related Projects

- **MATLAB GUI**: `QPSK_Triple_Comparison/sim/matlab/QPSK_GUI.m`
- **NEORV32 Documentation**: https://github.com/stnolting/neorv32

## License

BSD-3-Clause (same as NEORV32)
