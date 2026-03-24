/*
 * qpsk_tx_data.h - TX BRAM initialization data for axi_ad9361_adapter
 *
 * 1024 x 32-bit QPSK IQ samples, each word: {Q[31:16], I[15:0]}
 * Generated from qpsk_bram_init.coe (LFSR seed 0xDEADBEEF, +/-16384 +/-256 noise)
 *
 * Data lives in qpsk_tx_data.c to avoid duplication across translation units.
 */

#ifndef QPSK_TX_DATA_H
#define QPSK_TX_DATA_H

#include <stdint.h>

#define QPSK_TX_NUM_SAMPLES 1024

extern const uint32_t qpsk_tx_samples[QPSK_TX_NUM_SAMPLES];

#endif /* QPSK_TX_DATA_H */
