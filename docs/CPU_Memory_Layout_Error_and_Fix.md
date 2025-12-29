# CPU Memory Layout Error and Fix

## Summary

During development of the QPSK handler application, a memory configuration mismatch between the application linker settings and the testbench hardware caused the CPU to fail silently. This document describes the error, its root cause, how it was diagnosed, and the corrective actions taken.

## Background: NEORV32 Memory Architecture

The NEORV32 processor has two internal memory regions:

| Memory | Purpose | Default Base Address |
|--------|---------|---------------------|
| IMEM | Instruction Memory (code) | `0x00000000` |
| DMEM | Data Memory (stack, heap, globals) | `0x80000000` |

The sizes of these memories are configured in two places that **must match**:

1. **Hardware (VHDL)**: Testbench generic parameters
2. **Software (Linker)**: Symbols passed to the linker via `--defsym`

## The Error

### Symptom

The simulation ran without errors, but the CPU produced no UART output. Commands were sent to the processor, but no responses were received. The UART log file (`tb.uart0_rx.log`) remained empty.

### Root Cause

A mismatch between the linker's assumed RAM size and the actual hardware RAM size:

| Configuration | Expected | Actual |
|---------------|----------|--------|
| Application linker (`__neorv32_ram_size`) | 16 KB | - |
| Testbench DMEM (`DMEM_SIZE`) | - | 8 KB |

### Why This Causes Failure

The NEORV32 linker script uses `__neorv32_ram_size` to determine where to place the stack pointer at startup. The stack is placed at the **top of RAM** and grows downward:

```
With 16KB RAM setting:
  Stack pointer initialized to: ~0x80004000

With 8KB actual RAM:
  Valid address range: 0x80000000 - 0x80001FFF

  0x80004000 is OUTSIDE valid memory!
```

When the CPU executed its first function call (which pushes to the stack), it attempted to write to address `~0x80004000`. Since this address doesn't exist in the 8KB DMEM, a bus error occurred. The CPU entered an exception handler, but without proper exception handling configured, it effectively hung.

## How the Error Was Introduced

When creating the `qpsk_handler` application makefile, a 16KB RAM setting was added:

```makefile
# sw/qpsk_handler/makefile (INCORRECT)
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
```

The reasoning was that the 4KB `iq_buffer` array needed "extra space." However, this was unnecessary because:

1. The `iq_buffer` is in the `.bss` section, which starts at the **bottom** of RAM
2. The existing 8KB DMEM had sufficient space for BSS (~4.3KB) plus stack (~3.7KB)
3. The `hello_world` example worked correctly with 8KB because it didn't override this setting

## Diagnosis Process

1. **Observed**: Simulation showed commands being sent but no UART responses
2. **Checked**: UART log file was empty (0 bytes)
3. **Examined**: CPU tracer log showed execution stopping very early (during crt0 startup)
4. **Analyzed**: Tracer showed CPU stuck in BSS clearing loop at low cycle count
5. **Inspected**: ELF symbols revealed `__neorv32_ram_size = 0x4000` (16KB)
6. **Compared**: Testbench `DMEM_SIZE = 8*1024` (8KB)
7. **Identified**: Stack pointer would be at ~0x80004000, outside 8KB boundary

## The Fix

### Option A: Increase Testbench DMEM (Not Recommended)

Change testbench to match application:
```vhdl
-- sim/neorv32_tb.vhd
DMEM_SIZE : natural := 16*1024;  -- Changed from 8*1024
```

This works but diverges from the standard NEORV32 examples.

### Option B: Fix Application to Match Testbench (Recommended)

Change application to use standard 8KB:
```makefile
# sw/qpsk_handler/makefile
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k  -- Changed from 16k
```

This maintains consistency with `hello_world` and other NEORV32 examples.

**Option B was chosen.**

## Files Modified

### 1. `sw/qpsk_handler/makefile`

**Change**: RAM size from 16KB to 8KB

```makefile
# Before (INCORRECT)
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k

# After (CORRECT)
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k
```

### 2. `sw/qpsk_handler/build.bat`

**Change**: RAM size from 16KB to 8KB (Windows build script must match makefile)

```batch
REM Before (INCORRECT)
set CC_FLAGS=%CC_FLAGS% -Wl,--defsym,__neorv32_ram_size=16k

REM After (CORRECT)
set CC_FLAGS=%CC_FLAGS% -Wl,--defsym,__neorv32_ram_size=8k
```

### 3. `sim/neorv32_tb.vhd`

**Change**: Reverted temporary 16KB fix back to original 8KB

```vhdl
-- Temporary fix (reverted)
DMEM_SIZE : natural := 16*1024;

-- Correct (restored)
DMEM_SIZE : natural := 8*1024;
```

### 4. `sw/qpsk_handler/README.md`

**Added**: Memory Configuration section documenting the memory layout and the importance of matching sizes.

## Files Created During This Development

| File | Purpose |
|------|---------|
| `sw/qpsk_handler/build.bat` | Windows build script (avoids Unix make issues) |
| `sim/iq_bram.vhd` | IQ sample BRAM for simulation |
| `docs/CPU_Memory_Layout_Error_and_Fix.md` | This document |

## Verification

After applying the fix:

```bash
# Verify ELF has correct RAM size
$ riscv-none-elf-objdump -t main.elf | grep __neorv32_ram_size
00002000 g       *ABS*   00000000 __neorv32_ram_size
```

`0x2000 = 8192 = 8KB` ✓

## Memory Layout Reference

### Configuration Files and Their Roles

```
┌─────────────────────────────────────────────────────────────────┐
│                    MEMORY SIZE CONFIGURATION                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────┐      ┌──────────────────────┐        │
│  │  APPLICATION SIDE    │      │   HARDWARE SIDE      │        │
│  │                      │      │                      │        │
│  │  sw/qpsk_handler/    │      │  sim/neorv32_tb.vhd  │        │
│  │  makefile            │      │                      │        │
│  │  ────────────────    │      │  ────────────────    │        │
│  │  __neorv32_ram_size  │ MUST │  DMEM_SIZE generic   │        │
│  │  = 8k                │ ==== │  = 8*1024            │        │
│  │                      │MATCH │                      │        │
│  └──────────┬───────────┘      └──────────┬───────────┘        │
│             │                              │                    │
│             ▼                              ▼                    │
│  ┌──────────────────────┐      ┌──────────────────────┐        │
│  │  Linker places       │      │  VHDL instantiates   │        │
│  │  stack at RAM top    │      │  actual RAM block    │        │
│  │  (0x80000000 + size) │      │  of specified size   │        │
│  └──────────────────────┘      └──────────────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### DMEM Address Space (8KB Configuration)

```
0x80000000  ┬─────────────────┬  RAM base
            │     .data       │  Initialized global variables (0 bytes)
            ├─────────────────┤
            │     .bss        │  Uninitialized globals
            │                 │  - iq_buffer[4096]
            │                 │  - rf_enabled
            │                 │  - __neorv32_rte_vector_lut[256]
            │                 │  Total: ~4,352 bytes (0x1100)
            ├─────────────────┤  0x80001100
            │     .heap       │  Dynamic allocation (grows ↓)
            │        ↓        │
            │                 │
            │   (free space)  │  ~3,840 bytes available
            │                 │
            │        ↑        │
            │     stack       │  Function calls (grows ↑)
            ├─────────────────┤
0x80002000  ┴─────────────────┴  RAM top (8KB = 0x2000)

Stack pointer initialized to: 0x80002000 (top of 8KB)
```

## Lessons Learned

1. **Match hardware and software configurations**: Memory sizes in the linker must match the actual hardware instantiation.

2. **Don't assume more memory is needed**: The default 8KB is sufficient for most applications. Only increase if you have verified the need.

3. **Use existing examples as templates**: The `hello_world` makefile works correctly and should be used as a starting point.

4. **Silent failures are hard to debug**: Memory mismatches don't produce obvious error messages. The CPU simply crashes on first stack access.

5. **Check ELF symbols**: Use `objdump -t` to verify linker symbols match hardware configuration:
   ```bash
   riscv-none-elf-objdump -t main.elf | grep __neorv32
   ```

## Related Files

- `sw/common/common.mk` - Main NEORV32 makefile with default settings
- `sw/common/neorv32.ld` - Linker script that uses `__neorv32_ram_size`
- `sw/common/crt0.S` - Startup code that initializes stack pointer
- `rtl/core/neorv32_dmem.vhd` - DMEM implementation
