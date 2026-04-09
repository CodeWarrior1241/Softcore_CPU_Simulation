/*
 * axi_streaming_adapter_ctrl.h - Register-level control for the
 * axi_lite_to_streaming_adapter HLS IP (v3.0)
 *
 * Bare-metal register access via volatile pointers.
 * Register offsets from HLS-generated xaxi_lite_to_streaming_adapter_hw.h.
 *
 * v3.0 uses ap_ctrl_none: no AP handshake needed, the IP runs continuously.
 * Control/status is via struct-based AXI-Lite registers.
 *
 * State machine:
 *   IDLE -> INIT_QPSK_DATA -> SEND_AND_RECEIVE_QPSK_DATA -> RECEIVE_QPSK_DATA
 *   Reset returns from RECEIVE_QPSK_DATA -> IDLE.
 */

#ifndef AXI_STREAMING_ADAPTER_CTRL_H
#define AXI_STREAMING_ADAPTER_CTRL_H

#include <stdint.h>

/* ---------- Base address ---------- */
#define AXI_STREAMING_ADAPTER_BASE  0x44A10000UL

/* ---------- Helper macros ---------- */
#define BRIDGE_REG(off)  (*(volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + (off)))

/* ---------- Control registers (R/W, ctrl_regs_t struct) ---------- */
#define BRIDGE_REG_CTRL_ENABLE        0x0010  /* Write non-zero to transition IDLE -> INIT */
#define BRIDGE_REG_CTRL_RX_READ_DONE  0x0014  /* Write non-zero to release RX buffer */
#define BRIDGE_REG_CTRL_RESET         0x0018  /* Write non-zero to return to IDLE */

/* ---------- Status registers (read-only, status_regs_t struct) ---------- */
#define BRIDGE_REG_STATUS_STATE       0x0020  /* Current state_t value */
#define BRIDGE_REG_STATUS_TX_COUNT    0x0024  /* TX samples sent so far */
#define BRIDGE_REG_STATUS_RX_COUNT    0x0028  /* RX samples captured so far */
#define BRIDGE_REG_STATUS_VLD         0x002C  /* Status valid (bit 0, COR) */

/* ---------- Data memory arrays ---------- */
#define BRIDGE_TX_DATA_BASE           0x1000  /* TX sample buffer (1024 x 32-bit) */
#define BRIDGE_RX_DATA_BASE           0x2000  /* RX sample buffer (1024 x 32-bit) */
#define BRIDGE_SAMPLE_DEPTH           1024

/* ---------- State enumeration (status.state values) ---------- */
#define BRIDGE_STATE_IDLE                      0
#define BRIDGE_STATE_INIT_QPSK_DATA            1
#define BRIDGE_STATE_SEND_AND_RECEIVE_QPSK_DATA 2
#define BRIDGE_STATE_RECEIVE_QPSK_DATA         3

/* ---------- Polling timeout ---------- */
#define BRIDGE_POLL_TIMEOUT           500000

/* ---------- Inline helpers ---------- */

/* Load TX sample buffer from a uint32_t array. */
static inline void bridge_load_tx_data(const uint32_t *data, uint32_t num_samples)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_TX_DATA_BASE);
    for (uint32_t i = 0; i < num_samples; i++) {
        bram[i] = data[i];
    }
}

/* Read one word from RX sample buffer. */
static inline uint32_t bridge_read_rx_sample(uint32_t index)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_RX_DATA_BASE);
    return bram[index];
}

/*
 * Reset the bridge state machine back to IDLE.
 * Only effective from RECEIVE_QPSK_DATA state.
 */
static inline void bridge_reset(void)
{
    BRIDGE_REG(BRIDGE_REG_CTRL_RESET) = 1;
    /* Wait for state to return to IDLE */
    for (int i = 0; i < BRIDGE_POLL_TIMEOUT; i++) {
        if (BRIDGE_REG(BRIDGE_REG_STATUS_STATE) == BRIDGE_STATE_IDLE) {
            BRIDGE_REG(BRIDGE_REG_CTRL_RESET) = 0;
            return;
        }
    }
    BRIDGE_REG(BRIDGE_REG_CTRL_RESET) = 0;
}

/*
 * Enable the bridge: transitions IDLE -> INIT -> SEND_AND_RECEIVE -> RECEIVE.
 * TX data must be loaded into tx_data[] before calling this.
 * Returns 1 if TX burst completes (state reaches RECEIVE), 0 on timeout.
 */
static inline int bridge_enable(void)
{
    BRIDGE_REG(BRIDGE_REG_CTRL_ENABLE) = 1;
    /* Wait for transition out of IDLE */
    for (int i = 0; i < BRIDGE_POLL_TIMEOUT; i++) {
        if (BRIDGE_REG(BRIDGE_REG_STATUS_STATE) != BRIDGE_STATE_IDLE)
            break;
    }
    BRIDGE_REG(BRIDGE_REG_CTRL_ENABLE) = 0;

    /* Wait for TX burst to complete (state reaches RECEIVE_QPSK_DATA) */
    for (int i = 0; i < BRIDGE_POLL_TIMEOUT; i++) {
        if (BRIDGE_REG(BRIDGE_REG_STATUS_STATE) == BRIDGE_STATE_RECEIVE_QPSK_DATA)
            return 1;
    }
    return 0;
}

/*
 * Wait for RX buffer to fill (1024 samples captured).
 * Returns 1 on success, 0 on timeout.
 */
static inline int bridge_wait_rx_full(void)
{
    for (int i = 0; i < BRIDGE_POLL_TIMEOUT; i++) {
        if (BRIDGE_REG(BRIDGE_REG_STATUS_RX_COUNT) >= BRIDGE_SAMPLE_DEPTH)
            return 1;
    }
    return 0;
}

/*
 * Signal that software has finished reading the RX buffer.
 * This releases the buffer so the adapter can capture the next 1024 samples.
 */
static inline void bridge_release_rx(void)
{
    BRIDGE_REG(BRIDGE_REG_CTRL_RX_READ_DONE) = 1;
    /* Brief pulse — wait for rx_count to reset */
    for (int i = 0; i < BRIDGE_POLL_TIMEOUT; i++) {
        if (BRIDGE_REG(BRIDGE_REG_STATUS_RX_COUNT) < BRIDGE_SAMPLE_DEPTH)
            break;
    }
    BRIDGE_REG(BRIDGE_REG_CTRL_RX_READ_DONE) = 0;
}

#endif /* AXI_STREAMING_ADAPTER_CTRL_H */
