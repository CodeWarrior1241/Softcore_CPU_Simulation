# AD9361 Datapath Simulation — Efinix Titanium (ti375), Questa

Efinix counterpart of `../neorv32_sw_ad9361_dapath_sim_microchip/` (and of
`../neorv32_sw_ad9361_datapath_sim/sim/`, README section 5.7): the NEORV32
CPU boots the **`sw/ad9361_loopback` firmware** against the full ti375
FMCOMMS2 system and drives the whole test itself — AD9361 register config
over AXI, TX burst through the SmartHLS bridge and CDC FIFOs, LVDS TX→RX
loopback, RX readback, a directed power-gate cycle, and a
hardware-multiplier self-test — reporting PASS/FAIL via GPIO.

Runs in **Questa Prime 2025.1** (from `PATH`).

## DUT — official Efinix periphery models

The periphery uses **Efinix's official simulation models wherever
possible**. The ti375 project's `gen_interface.py` exports
`outflow/ti375c529_pt_interface.v` via the Interface Designer's
`export_periphery_sim_netlist` API: a pad-level chip wrapper
(`\system_top_shim~chip`) that instantiates the shipped periphery models —
**`EFX_FPLL_V1`** (both PLLs), **`EFX_LVDS_RX_V2` / `EFX_LVDS_TX_V2`**
(all 16 data lanes + the FB_CLK lane), **`EFX_GPIO_V3`** (every single) —
from `$EFINITY_HOME/pt/sim_models/verilog`, configured exactly as
`ti375c529.peri.xml`. Inside it sits the sim-local `system_top_shim.v`:
the **real synthesis top** (`deps/hdl/projects/fmcomms2/ti375/hdl/
system_top.v`, unmodified) plus ties for the optional per-lane `RX_ENA`
pins. `run_sim.sh` regenerates the netlist through the project's
generator whenever an Efinity install is reachable (`EFINITY_HOME`,
dev-box default probed) — the same install-dependency pattern as the
Microchip sim's Libero `polarfire.v`.

The per-lane `INRST`/`RST`/`OE` controls connect to `system_top`'s real
ports, so the `serdes_rst` (l_clk-domain reset OR PLL-unlock) and `tx_oe`
logic added for the Efinity P&R is exercised against the official SERDES
models. Everything else in the DUT is the same synthesis source the
Efinity flow compiles: ADI core + the **efinix `axi_ad9361_lvds_if`**
(pure RTL), SmartHLS adapter RTL, PULP interconnect, Bedrock-RTL
CDC/resets (compiled with `BR_ASSERT_ON`), and the ti375 project HDL.

What this sim pins down ahead of the bench: the ×2 deserializer word order
against the delineation logic **using Efinix's own model of the
deserializer** — the thing the board bring-up would otherwise discover by
PRBS trial and error.

Model-behavior notes (vs. the mpf300 sim's stand-ins):

- `EFX_FPLL_V1` measures its reference period once and then free-runs, so
  l_clk keeps toggling while the TB parks DATA_CLK in the power-gate
  window — the TB's `l_clk stopped` warning therefore does **not** appear
  on this platform (the firmware's power-gate test gates on
  datapath/relock status, not on l_clk dying); `LOCKED` asserts after 2
  reference cycles and stays.
- **FASTCLK vendor gap** (`patch_peri_netlist.py`): for ×2 half-rate
  lanes the exported netlist leaves `FASTCLK` unconnected (the design
  check says width 2 "only requires the parallel clock"), but the
  official LVDS models run their DDR capture/launch **exclusively on
  FASTCLK**. The patcher stages a sim-local netlist copy with each lane's
  `FASTCLK` tied to its `SLOWCLK` — for the ×2 DDIO configuration
  FASTCLK *is* the parallel-rate DDR clock. Simulation-only transform;
  the synthesized periphery keeps the DRC-recommended setting.
- The TB's **5 ns loopback delay** (1 ns pad + half a UI) centers the RX
  capture in the eye; without it the zero-delay vendor models sample at
  the bit boundaries and the ×2 words straddle (see the comment block in
  `ti375_tb.v`). In hardware this role is played by the AD9361's
  +90° FB_CLK sampling and the programmable delays.
- Loopback symmetry note: TX and RX of the same system cancel any
  consistent bit-labeling convention, so this test pins down word
  *grouping* and the datapath, not the absolute first-bit polarity —
  that last knob remains a bench item against the real AD9361.

**This simulation caught a real hardware bug** before any board existed:
with the periphery generator's original `auto_calc_pll_clock` settings,
the official `EFX_FPLL_V1` produced a 10 ns `clk_125mhz` (garbled UART,
1.25×-slow CPU) — the solver had silently delivered **100 MHz instead of
125 MHz** (confirmed by the interface report). The generator now sets the
sys_pll dividers manually (CLK1 feedback, ×5) and read-back-verifies
every PLL output. Hand-written stand-ins would have masked this forever.

## Firmware

Rebuilt automatically by `run_sim.sh` when `riscv-none-elf-gcc` is on PATH:

```sh
make MARCH=rv32im_zicsr_zifencei clean_all image
```

The register map is identical across all three vendor ports (regs
`0x0010..0x0028`, `tx_data 0x1000`, `rx_data 0x2000`), so the firmware is
byte-identical to the Xilinx and Microchip runs; `rv32im` makes
`mul_selftest()` exercise the pipelined fast multiplier
(`CPU_FAST_MUL_REG => true` in the project wrapper).

## Run

```sh
./run_sim.sh --batch          # headless pass/fail
./run_sim.sh                  # GUI
./run_sim.sh --detailed       # +acc=npr, waveform logging
./run_sim.sh --clean
```

A successful run prints the GPIO milestones (`AD9361 core configured`,
`TX burst complete`, `RX readback done`) and ends with
`TEST PASSED (GPIO result)` (auto-terminates; 20 ms safety timeout).
Unlike the Xilinx/Microchip runs there is no `l_clk stopped` warning —
see the model-behavior notes above.
