# AD9361 Datapath Simulation — Microchip PolarFire (mpf300), Questa

Microchip counterpart of `../neorv32_sw_ad9361_datapath_sim/sim/` (README
section 5.7): the NEORV32 CPU boots the **`sw/ad9361_loopback` firmware**
against the full mpf300 FMCOMMS2 system and drives the whole test itself —
AD9361 register config over AXI, TX burst through the SmartHLS bridge and
CDC FIFOs, LVDS TX→RX loopback, RX readback, a directed power-gate cycle,
and a hardware-multiplier self-test — reporting PASS/FAIL via GPIO.

Runs in **Questa Prime 2025.1** (from `PATH`), *not* the QuestaSim bundled
with Libero.

## DUT

`mpf300_sim_top.v` is a hand-written HDL transcription of the Libero
SmartDesign built by `deps/hdl/projects/fmcomms2/mpf300/build_all.tcl`
(every instance/net mirrors an `sd_instantiate`/`sd_wire`/`sd_tie` call):

| Instance | Source |
|---|---|
| `NEORV32_RISC_V` | sim-local `neorv32_mpf300_top.vhd` — the mpf300 wrapper **plus `CPU_FAST_MUL_PIPELINE => true`** ([neorv32 PR #1603](https://github.com/stnolting/neorv32/pull/1603), applied in `deps/neorv32`) |
| `axi_cpu_interconnect` | mpf300 `axi_1to3_decoder.sv` (PULP `axi_lite_xbar`) |
| `axi_ad9361_0` | ADI core + PolarFire LVDS interface (primitives compiled from the Libero install) |
| `axi_ad9361_adapter_0`, `axi_streaming_adapter_0` | SmartHLS generated RTL (`src/*_microchip`) |
| `ad9361_cdc_tx/rx_fifo`, `sys_ctrl_0`, `lclk_reset_sync_0` | mpf300 HDL (Bedrock-RTL inside since the migration) |
| `qpsk_snapshot_bram`, `dac_hold_0`, `refclk_ibuf_0` | mpf300 HDL |
| `clk_gen`, `init_monitor` | behavioral stand-ins (`pf_ccc_sim.v`) for the generated PF_CCC / PF_CCC_C1 / PF_INIT_MONITOR cores |

## Firmware

Rebuilt automatically by `run_sim.sh` when `riscv-none-elf-gcc` is on PATH:

```sh
make MARCH=rv32im_zicsr_zifencei clean_all image
```

- The firmware source is byte-identical to the Xilinx run: the SmartHLS
  bridge decodes the SAME register map as the Vitis IP (regs
  `0x0010..0x0028`, `tx_data 0x1000`, `rx_data 0x2000`), so
  `axi_streaming_adapter_ctrl.h` has a single, portable map.
- `rv32im` makes `mul_selftest()` execute real MUL/MULH/MULHU
  instructions, exercising the PR #1603 pipelined fast multiplier (a
  wrong-phase result fails the run).

## Run

```sh
./run_sim.sh --batch          # headless pass/fail, ~40 s wall clock
./run_sim.sh                  # GUI
./run_sim.sh --detailed       # +acc=npr, waveform logging
./run_sim.sh --clean
```

A successful run prints the GPIO milestones (`AD9361 core configured`,
`TX burst complete`, `RX readback done`), one expected
`WARNING: l_clk stopped` during the power-gate window, and ends with
`TEST PASSED (GPIO result)` at ~7.4 ms simulated (auto-terminates; 20 ms
safety timeout).

## Integration bugs this simulation caught during bring-up

1. **Bridge address decode** — the SmartHLS bridge decodes its full
   32-bit `axi_aw/ar_addr` (`addr >> 2`, no masking), so the interconnect
   must present window offsets on M2; `axi_1to3_decoder.sv` now masks to
   the low 14 bits.
2. **Deferred write beats vs. XBUS** — the bridge defers AXI write DATA
   beats while the datapath owns `tx_data` during SEND; the enable
   pulse's immediate re-arm write stalled past the NEORV32 XBUS timeout,
   wedging the W channel. `bridge_enable_and_wait()` now re-arms after
   RECEIVE is reached (a single portable sequence — behavior on the Vitis
   bridge is identical either way).
3. **Status reads during a burst** — reads are served but can stall for
   the burst duration (~10 µs); `XBUS_TIMEOUT` raised 255 → 32768 in both
   NEORV32 wrappers (sim copy and the mpf300 project).
