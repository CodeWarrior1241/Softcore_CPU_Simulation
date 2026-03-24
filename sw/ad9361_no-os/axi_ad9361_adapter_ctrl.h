/*
 * axi_ad9361_adapter_ctrl.h - Register-level control for the HLS axi_ad9361_adapter IP
 *
 * Bare-metal register access via volatile pointers.  No dependency on
 * Xilinx/Vitis driver infrastructure — just needs the base address from
 * parameters.h and stdint.h.
 *
 * Register offsets taken from the Vitis HLS generated xaxi_ad9361_adapter_hw.h.
 * Note: HLS splits bidirectional registers into _I (write) and _O (read) ports.
 */

#ifndef AXI_AD9361_ADAPTER_CTRL_H
#define AXI_AD9361_ADAPTER_CTRL_H

#include <stdint.h>
#include "parameters.h"

/* ---------- Helper macros ---------- */
#define ADAPTER_REG(off)  (*(volatile uint32_t *)(AXI_AD9361_ADAPTER_BASE + (off)))

/* ---------- Register offsets (from HLS-generated hw.h) ---------- */
#define ADAPTER_REG_CTRL_I        0x0010   /* CTRL write port */
#define ADAPTER_REG_CTRL_O        0x0018   /* CTRL read-back port */
#define ADAPTER_REG_STATUS        0x0020   /* STATUS (read-only) */
#define ADAPTER_REG_SCRATCH       0x0030   /* Scratch register (R/W) */
#define ADAPTER_REG_RX_CTRL_I     0x0038   /* RX_CTRL write port */
#define ADAPTER_REG_RX_CTRL_O     0x0040   /* RX_CTRL read-back port */
#define ADAPTER_REG_RX_STATUS     0x0048   /* RX_STATUS (read-only) */
#define ADAPTER_REG_RX_FILL       0x0058   /* RX fill level (read-only) */
#define ADAPTER_REG_TX_CTRL_I     0x0068   /* TX_CTRL write port */
#define ADAPTER_REG_TX_CTRL_O     0x0070   /* TX_CTRL read-back port */
#define ADAPTER_REG_TX_STATUS     0x0078   /* TX_STATUS (read-only) */
#define ADAPTER_REG_LOOPBACK      0x0088   /* Loopback control (R/W) */
#define ADAPTER_TX_BRAM_BASE      0x1000   /* TX BRAM start (1024 x 32-bit) */
#define ADAPTER_RX_BRAM_BASE      0x2000   /* RX BRAM start (1024 x 32-bit) */

/* ---------- CTRL register bit positions ---------- */
#define ADAPTER_CTRL_ENABLE      (1U << 0)
#define ADAPTER_CTRL_SOFT_RESET  (1U << 1)
#define ADAPTER_CTRL_RX_ENABLE   (1U << 2)
#define ADAPTER_CTRL_TX_ENABLE   (1U << 3)
#define ADAPTER_CTRL_RX_CLEAR    (1U << 8)

/* ---------- Channel enable masks (RX_CTRL / TX_CTRL) ---------- */
#define ADAPTER_CH_EN_I0   (1U << 0)
#define ADAPTER_CH_EN_Q0   (1U << 1)
#define ADAPTER_CH_EN_I1   (1U << 2)
#define ADAPTER_CH_EN_Q1   (1U << 3)
#define ADAPTER_CH_EN_ALL  (ADAPTER_CH_EN_I0 | ADAPTER_CH_EN_Q0 | ADAPTER_CH_EN_I1 | ADAPTER_CH_EN_Q1)
#define ADAPTER_CH_EN_CH0  (ADAPTER_CH_EN_I0 | ADAPTER_CH_EN_Q0)

/* ---------- STATUS register bit positions ---------- */
#define ADAPTER_STATUS_ENABLED    (1U << 0)
#define ADAPTER_STATUS_RX_ACTIVE  (1U << 1)
#define ADAPTER_STATUS_TX_ACTIVE  (1U << 2)
#define ADAPTER_STATUS_LOOPBACK   (1U << 3)
#define ADAPTER_STATUS_RX_FULL    (1U << 4)

/* ---------- RX_STATUS bits ---------- */
#define ADAPTER_RX_STATUS_OVERFLOW (1U << 0)
#define ADAPTER_RX_STATUS_VALID    (1U << 1)

/* ---------- Inline helpers ---------- */

/* Load TX BRAM from a uint32_t array (1024 words). */
static inline void adapter_load_tx_bram(const uint32_t *data, uint32_t num_samples)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_AD9361_ADAPTER_BASE + ADAPTER_TX_BRAM_BASE);
    for (uint32_t i = 0; i < num_samples; i++) {
        bram[i] = data[i];
    }
}

/* Read one word from RX BRAM. */
static inline uint32_t adapter_read_rx_sample(uint32_t index)
{
    volatile uint32_t *bram = (volatile uint32_t *)(AXI_AD9361_ADAPTER_BASE + ADAPTER_RX_BRAM_BASE);
    return bram[index];
}

#endif /* AXI_AD9361_ADAPTER_CTRL_H */
