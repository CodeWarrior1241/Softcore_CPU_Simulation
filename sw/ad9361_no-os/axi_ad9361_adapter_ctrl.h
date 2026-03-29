/*
 * axi_ad9361_adapter_ctrl.h - Register-level control for the
 * axi_lite_to_streaming_adapter HLS IP (v1.0)
 *
 * This replaces the old direct-register axi_ad9361_adapter interface.
 * The v4.0 adapter uses AXI-Stream + ap_none, so all CPU access goes
 * through this streaming adapter bridge at 0x44A10000.
 *
 * The bridge uses ap_ctrl_chain: software must write AP_START + AUTO_RESTART
 * once at init to start continuous operation.
 *
 * Register offsets from HLS-generated xaxi_lite_to_streaming_adapter_hw.h.
 */

#ifndef AXI_AD9361_ADAPTER_CTRL_H
#define AXI_AD9361_ADAPTER_CTRL_H

#include <stdint.h>
#include "parameters.h"

/* ---------- Helper macros ---------- */
#define BRIDGE_REG(off)  (*(volatile uint32_t *)(AXI_AD9361_ADAPTER_BASE + (off)))

/* ---------- AP control (ap_ctrl_chain handshake) ---------- */
#define BRIDGE_REG_AP_CTRL            0x0000
#define BRIDGE_AP_START               (1U << 0)
#define BRIDGE_AP_DONE                (1U << 1)
#define BRIDGE_AP_IDLE                (1U << 2)
#define BRIDGE_AP_READY               (1U << 3)
#define BRIDGE_AP_AUTO_RESTART        (1U << 7)

/* ---------- Control registers (R/W, passed through to adapter) ---------- */
#define BRIDGE_REG_CTRL               0x0010
#define BRIDGE_REG_RX_CTRL            0x0018
#define BRIDGE_REG_TX_CTRL            0x0020
#define BRIDGE_REG_LOOPBACK           0x0028
#define BRIDGE_REG_SCRATCH            0x0030

/* ---------- Status registers (read-only, from adapter) ---------- */
#define BRIDGE_REG_STATUS             0x0038
#define BRIDGE_REG_RX_STATUS          0x0048
#define BRIDGE_REG_RX_FILL            0x0058
#define BRIDGE_REG_TX_STATUS          0x0068

/* ---------- Bridge internal registers ---------- */
#define BRIDGE_REG_TX_COUNT_I         0x0078  /* Write: set to 1024 to trigger TX burst */
#define BRIDGE_REG_TX_COUNT_O         0x0080  /* Read: current TX counter (0 when idle) */
#define BRIDGE_REG_RX_READ_CNT_I      0x0088  /* Write: set to 1024 to free RX slot */
#define BRIDGE_REG_RX_READ_CNT_O      0x0090  /* Read: current RX read counter */
#define BRIDGE_REG_BRIDGE_STATUS      0x0098  /* Read: bridge state bits */

/* ---------- Data memory arrays ---------- */
#define BRIDGE_TX_DATA_BASE           0x1000  /* TX sample buffer (1024 x 32-bit) */
#define BRIDGE_RX_DATA_BASE           0x2000  /* RX sample buffer (1024 x 32-bit) */
#define BRIDGE_SAMPLE_DEPTH           1024

/* ---------- CTRL register bit positions ---------- */
#define BRIDGE_CTRL_ENABLE            (1U << 0)
#define BRIDGE_CTRL_SOFT_RESET        (1U << 1)
#define BRIDGE_CTRL_RX_ENABLE         (1U << 2)
#define BRIDGE_CTRL_TX_ENABLE         (1U << 3)
#define BRIDGE_CTRL_RX_CLEAR          (1U << 8)
#define BRIDGE_CTRL_RX_DRAIN          (1U << 9)

/* ---------- Channel enable masks (RX_CTRL / TX_CTRL) ---------- */
#define BRIDGE_CH_EN_I0               (1U << 0)
#define BRIDGE_CH_EN_Q0               (1U << 1)
#define BRIDGE_CH_EN_I1               (1U << 2)
#define BRIDGE_CH_EN_Q1               (1U << 3)
#define BRIDGE_CH_EN_ALL              (BRIDGE_CH_EN_I0 | BRIDGE_CH_EN_Q0 | BRIDGE_CH_EN_I1 | BRIDGE_CH_EN_Q1)
#define BRIDGE_CH_EN_CH0              (BRIDGE_CH_EN_I0 | BRIDGE_CH_EN_Q0)
#define BRIDGE_CH_CLR_OVF             (1U << 8)
#define BRIDGE_CH_CLR_UNF             (1U << 8)

/* ---------- Bridge status bit positions ---------- */
#define BRIDGE_STATUS_TX_SENDING      (1U << 0)
#define BRIDGE_STATUS_RX_READY        (1U << 1)
#define BRIDGE_STATUS_RX_READING      (1U << 2)

/* ---------- Adapter status bit positions (from status_out) ---------- */
#define ADAPTER_STATUS_ENABLED        (1U << 0)
#define ADAPTER_STATUS_RX_ACTIVE      (1U << 1)
#define ADAPTER_STATUS_TX_ACTIVE      (1U << 2)
#define ADAPTER_STATUS_LOOPBACK       (1U << 3)
#define ADAPTER_STATUS_RX_FULL        (1U << 4)
#define ADAPTER_STATUS_TX_LOADED      (1U << 5)

/* ---------- RX_STATUS bits ---------- */
#define ADAPTER_RX_STATUS_OVERFLOW    (1U << 0)
#define ADAPTER_RX_STATUS_VALID       (1U << 1)

/* ---------- Timeout for polling ---------- */
#define BRIDGE_POLL_TIMEOUT           500000

/* ---------- Inline helpers ---------- */

/* Start the bridge (ap_ctrl_chain): call once at init. */
static inline void bridge_start(void)
{
    BRIDGE_REG(BRIDGE_REG_AP_CTRL) = BRIDGE_AP_START | BRIDGE_AP_AUTO_RESTART;
}

/* Load TX sample buffer from a uint32_t array. */
static inline void bridge_load_tx_data(const uint32_t *data, uint32_t num_samples)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_AD9361_ADAPTER_BASE + BRIDGE_TX_DATA_BASE);
    for (uint32_t i = 0; i < num_samples; i++) {
        bram[i] = data[i];
    }
}

/* Trigger TX burst after loading samples. Returns 1 on success, 0 on timeout. */
static inline int bridge_trigger_tx(uint32_t num_samples)
{
    BRIDGE_REG(BRIDGE_REG_TX_COUNT_I) = num_samples;
    for (int i = 0; i < BRIDGE_POLL_TIMEOUT; i++) {
        if (BRIDGE_REG(BRIDGE_REG_TX_COUNT_O) == 0)
            return 1;
    }
    return 0;
}

/* Wait for RX data to be ready. Returns 1 on success, 0 on timeout. */
static inline int bridge_wait_rx_ready(void)
{
    for (int i = 0; i < BRIDGE_POLL_TIMEOUT; i++) {
        if (BRIDGE_REG(BRIDGE_REG_BRIDGE_STATUS) & BRIDGE_STATUS_RX_READY)
            return 1;
    }
    return 0;
}

/* Read one word from RX sample buffer. */
static inline uint32_t bridge_read_rx_sample(uint32_t index)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_AD9361_ADAPTER_BASE + BRIDGE_RX_DATA_BASE);
    return bram[index];
}

/* Signal that all RX samples have been read, freeing the slot. */
static inline void bridge_release_rx(void)
{
    BRIDGE_REG(BRIDGE_REG_RX_READ_CNT_I) = BRIDGE_SAMPLE_DEPTH;
}

#endif /* AXI_AD9361_ADAPTER_CTRL_H */
