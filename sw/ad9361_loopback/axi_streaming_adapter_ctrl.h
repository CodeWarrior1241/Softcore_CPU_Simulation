/*
 * axi_streaming_adapter_ctrl.h - Register-level control for the
 * axi_lite_to_streaming_adapter HLS IP (v3.0)
 *
 * State-machine bridge: IDLE → INIT → SEND_AND_RECEIVE → RECEIVE
 * ap_ctrl_none, II=1.  Control via ctrl_regs_t struct, status via
 * status_regs_t struct, both on a single s_axi_ctrl AXI-Lite port.
 *
 * Register map (from HLS-generated ctrl_s_axi.v):
 *   ctrl_r (CPU writes):
 *     0x0010: enable          [31:0]
 *     0x0014: rx_read_done    [63:32]
 *     0x0018: reset           [95:64]
 *   status (CPU reads):
 *     0x0020: state           [31:0]
 *     0x0024: tx_sample_count [63:32]
 *     0x0028: rx_sample_count [95:64]
 *   tx_data[1024]:  0x1000-0x1FFF
 *   rx_data[1024]:  0x2000-0x2FFF
 *
 * CPU protocol for ctrl pulses (edge-detect arming in HLS):
 *   Write 1, wait for effect, write 0 to re-arm.
 */

#ifndef AXI_STREAMING_ADAPTER_CTRL_H
#define AXI_STREAMING_ADAPTER_CTRL_H

#include <stdint.h>

/* ---------- Base address ---------- */
#define AXI_STREAMING_ADAPTER_BASE  0x44A10000UL

/* ---------- Helper macros ---------- */
#define BRIDGE_REG(off)  (*(volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + (off)))

/* ---------- ctrl_r registers (CPU writes) ---------- */
/* One register map for BOTH platforms: the Microchip SmartHLS port of the
 * bridge (src/axi_lite_to_streaming_adapter_microchip) decodes the same
 * offsets as the Vitis HLS v3.0 s_axilite layout, so this driver is fully
 * portable between the axau15 (Xilinx) and mpf300 (Microchip) systems. */
#define BRIDGE_REG_ENABLE           0x0010
#define BRIDGE_REG_RX_READ_DONE     0x0014
#define BRIDGE_REG_RESET            0x0018

/* ---------- status registers (CPU reads) ---------- */
#define BRIDGE_REG_STATE            0x0020
#define BRIDGE_REG_TX_COUNT         0x0024
#define BRIDGE_REG_RX_COUNT         0x0028

/* ---------- State enum values ---------- */
#define BRIDGE_STATE_IDLE           0
#define BRIDGE_STATE_INIT           1
#define BRIDGE_STATE_SEND_AND_RX    2
#define BRIDGE_STATE_RECEIVE        3

/* ---------- Data memory arrays ---------- */
#define BRIDGE_TX_DATA_BASE         0x1000
#define BRIDGE_RX_DATA_BASE         0x2000
#define BRIDGE_SAMPLE_DEPTH         1024

/* ---------- Inline helpers ---------- */

/* Pulse a ctrl register: write 1, brief delay, write 0.
 * HLS edge-detect arming ensures one trigger per 0→1→0 transition. */
static inline void bridge_ctrl_pulse(uint32_t offset)
{
    BRIDGE_REG(offset) = 1;
    for (volatile int i = 0; i < 10; i++) {}
    BRIDGE_REG(offset) = 0;
}

/* Load TX sample buffer. */
static inline void bridge_load_tx_data(const uint32_t *data, uint32_t num_samples)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_TX_DATA_BASE);
    for (uint32_t i = 0; i < num_samples; i++) {
        bram[i] = data[i];
    }
}

/* Enable bridge: assert enable, wait for RECEIVE state, then re-arm.
 *
 * The re-arm write (enable=0) is deliberately issued AFTER the state poll,
 * not immediately after enable=1: the Microchip SmartHLS port of the
 * bridge is a single pipeline that serves the TX burst ahead of AXI write
 * DATA beats, so a write issued during SEND_AND_RECEIVE stalls for the
 * whole 1024-word burst — far past the NEORV32 XBUS timeout, whose abort
 * deasserts WVALID mid-handshake and wedges the write channel.  Reads are
 * served throughout, so the state poll is safe.  On the Vitis bridge
 * (independent ctrl_s_axi register file) both orderings behave
 * identically, so this single sequence is portable across platforms. */
static inline void bridge_enable_and_wait(void)
{
    BRIDGE_REG(BRIDGE_REG_ENABLE) = 1;
    while (BRIDGE_REG(BRIDGE_REG_STATE) != BRIDGE_STATE_RECEIVE) {}
    BRIDGE_REG(BRIDGE_REG_ENABLE) = 0;
}

/* Read one word from RX sample buffer. */
static inline uint32_t bridge_read_rx_sample(uint32_t index)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_RX_DATA_BASE);
    return bram[index];
}

/* Signal that SW has read all RX samples — release buffer. */
static inline void bridge_rx_read_done(void)
{
    bridge_ctrl_pulse(BRIDGE_REG_RX_READ_DONE);
}

/* Reset bridge to IDLE state. */
static inline void bridge_reset(void)
{
    bridge_ctrl_pulse(BRIDGE_REG_RESET);
}

#endif /* AXI_STREAMING_ADAPTER_CTRL_H */
