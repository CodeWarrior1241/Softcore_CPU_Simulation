//==============================================================================
// axi_ad9361_adapter.cpp
//
// Vitis HLS implementation of AXI AD9361 Adapter IP
// Free-running datapath for continuous RX/TX operation
//
// Features:
// - Free-running (ap_ctrl_none) - executes every clock cycle
// - TX: Continuously cycles through TX BRAM, outputting to DAC
// - RX: Continuously captures ADC samples until buffer full
// - RX buffer clears when software writes RX_CLEAR bit
// - Single AXI-Lite interface for all registers and BRAMs
//
// Target: Vitis HLS 2025.2
// Device: xcau15p-ffvb676-2-e (Ultrascale+)
//==============================================================================

#include "axi_ad9361_adapter.hpp"

//==============================================================================
// Top-Level Function
//==============================================================================

void axi_ad9361_adapter(
    // TX BRAM - 1024 samples, AXI-Lite accessible
    iq_pair_t tx_bram[IPInfo::BRAM_DEPTH],

    // RX BRAM - 1024 samples, AXI-Lite accessible
    iq_pair_t rx_bram[IPInfo::BRAM_DEPTH],

    // Control registers (directly mapped to AXI-Lite)
    axi_reg_t& reg_ctrl,
    axi_reg_t& reg_status,
    axi_reg_t& reg_scratch,
    axi_reg_t& reg_rx_ctrl,
    axi_reg_t& reg_rx_status,
    axi_reg_t& reg_rx_fill,
    axi_reg_t& reg_tx_ctrl,
    axi_reg_t& reg_tx_status,
    axi_reg_t& reg_loopback,

    // RX data from axi_ad9361
    iq_sample_t  adc_data_i0,
    iq_sample_t  adc_data_q0,
    iq_sample_t  adc_data_i1,
    iq_sample_t  adc_data_q1,
    valid_t      adc_valid_i0,
    valid_t      adc_valid_q0,
    valid_t      adc_valid_i1,
    valid_t      adc_valid_q1,
    valid_t      adc_enable_i0,
    valid_t      adc_enable_q0,
    valid_t      adc_enable_i1,
    valid_t      adc_enable_q1,

    // TX data to axi_ad9361
    iq_sample_t& dac_data_i0,
    iq_sample_t& dac_data_q0,
    iq_sample_t& dac_data_i1,
    iq_sample_t& dac_data_q1,
    valid_t&     dac_valid_i0,
    valid_t&     dac_valid_q0,
    valid_t&     dac_valid_i1,
    valid_t&     dac_valid_q1,
    valid_t      dac_enable_i0,
    valid_t      dac_enable_q0,
    valid_t      dac_enable_i1,
    valid_t      dac_enable_q1,

    // Overflow/Underflow status
    valid_t      adc_dovf,
    valid_t&     dac_dunf
) {
    //==========================================================================
    // Interface Pragmas
    //==========================================================================

    // Free-running datapath - no start/done handshake
#pragma HLS INTERFACE mode=ap_ctrl_none port=return

    // TX BRAM - map to AXI-Lite with offset for memory-mapped access
#pragma HLS INTERFACE mode=s_axilite port=tx_bram bundle=ctrl offset=0x1000

    // RX BRAM - map to AXI-Lite with offset for memory-mapped access
#pragma HLS INTERFACE mode=s_axilite port=rx_bram bundle=ctrl offset=0x2000

    // Control/status registers mapped to AXI-Lite
#pragma HLS INTERFACE mode=s_axilite port=reg_ctrl bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_status bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_scratch bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_rx_ctrl bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_rx_status bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_rx_fill bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_tx_ctrl bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_tx_status bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_loopback bundle=ctrl

    // RX inputs from axi_ad9361 - direct wire connections (no handshake)
#pragma HLS INTERFACE mode=ap_none port=adc_data_i0
#pragma HLS INTERFACE mode=ap_none port=adc_data_q0
#pragma HLS INTERFACE mode=ap_none port=adc_data_i1
#pragma HLS INTERFACE mode=ap_none port=adc_data_q1
#pragma HLS INTERFACE mode=ap_none port=adc_valid_i0
#pragma HLS INTERFACE mode=ap_none port=adc_valid_q0
#pragma HLS INTERFACE mode=ap_none port=adc_valid_i1
#pragma HLS INTERFACE mode=ap_none port=adc_valid_q1
#pragma HLS INTERFACE mode=ap_none port=adc_enable_i0
#pragma HLS INTERFACE mode=ap_none port=adc_enable_q0
#pragma HLS INTERFACE mode=ap_none port=adc_enable_i1
#pragma HLS INTERFACE mode=ap_none port=adc_enable_q1

    // TX outputs to axi_ad9361 - direct wire connections (no handshake)
#pragma HLS INTERFACE mode=ap_none port=dac_data_i0
#pragma HLS INTERFACE mode=ap_none port=dac_data_q0
#pragma HLS INTERFACE mode=ap_none port=dac_data_i1
#pragma HLS INTERFACE mode=ap_none port=dac_data_q1
#pragma HLS INTERFACE mode=ap_none port=dac_valid_i0
#pragma HLS INTERFACE mode=ap_none port=dac_valid_q0
#pragma HLS INTERFACE mode=ap_none port=dac_valid_i1
#pragma HLS INTERFACE mode=ap_none port=dac_valid_q1
#pragma HLS INTERFACE mode=ap_none port=dac_enable_i0
#pragma HLS INTERFACE mode=ap_none port=dac_enable_q0
#pragma HLS INTERFACE mode=ap_none port=dac_enable_i1
#pragma HLS INTERFACE mode=ap_none port=dac_enable_q1

    // Overflow/Underflow status signals
#pragma HLS INTERFACE mode=ap_none port=adc_dovf
#pragma HLS INTERFACE mode=ap_none port=dac_dunf

    // Pipeline the entire function for streaming operation
#pragma HLS PIPELINE II=1

    //==========================================================================
    // Static State (persists across calls)
    //==========================================================================

    static bram_addr_t tx_read_ptr = 0;
    static bram_addr_t rx_write_ptr = 0;
    static fill_level_t rx_fill_level = 0;
    static bool rx_overflow_sticky = false;
    static bool tx_underflow_sticky = false;

    // NOTE: TX BRAM must be loaded by software via AXI-Lite before enabling TX.
    // Workflow: 1) Load TX BRAM, 2) Enable TX, 3) Hardware cycles continuously
    // To update: Disable TX, reload BRAM, re-enable TX

    //==========================================================================
    // Local register copies (to avoid multiple AXI reads/writes)
    //==========================================================================

    axi_reg_t local_ctrl = reg_ctrl;
    axi_reg_t local_rx_ctrl = reg_rx_ctrl;
    axi_reg_t local_tx_ctrl = reg_tx_ctrl;
    axi_reg_t local_status = 0;
    axi_reg_t local_rx_status = 0;
    axi_reg_t local_tx_status = 0;

    //==========================================================================
    // Handle Soft Reset
    //==========================================================================

    if (local_ctrl[CtrlBits::SOFT_RESET]) {
        local_ctrl[CtrlBits::SOFT_RESET] = 0;
        tx_read_ptr = 0;
        rx_write_ptr = 0;
        rx_fill_level = 0;
        rx_overflow_sticky = false;
        tx_underflow_sticky = false;
    }

    //==========================================================================
    // Handle RX Clear
    //==========================================================================

    if (local_ctrl[CtrlBits::RX_CLEAR]) {
        local_ctrl[CtrlBits::RX_CLEAR] = 0;
        rx_write_ptr = 0;
        rx_fill_level = 0;
    }

    //==========================================================================
    // Extract control signals
    //==========================================================================

    bool global_enable = local_ctrl[CtrlBits::ENABLE];
    bool rx_enable = local_ctrl[CtrlBits::RX_ENABLE] && global_enable;
    bool tx_enable = local_ctrl[CtrlBits::TX_ENABLE] && global_enable;
    bool loopback_enable = reg_loopback[CtrlBits::LOOPBACK_EN] && global_enable;

    // RX channel enables (from registers AND external enable signals)
    bool rx_ch0_en = local_rx_ctrl[CtrlBits::RX_CH0_EN] && adc_enable_i0 && rx_enable;
    bool rx_ch1_en = local_rx_ctrl[CtrlBits::RX_CH1_EN] && adc_enable_q0 && rx_enable;
    bool rx_ch2_en = local_rx_ctrl[CtrlBits::RX_CH2_EN] && adc_enable_i1 && rx_enable;
    bool rx_ch3_en = local_rx_ctrl[CtrlBits::RX_CH3_EN] && adc_enable_q1 && rx_enable;

    // TX channel enables
    bool tx_ch0_en = local_tx_ctrl[CtrlBits::TX_CH0_EN] && dac_enable_i0 && tx_enable;
    bool tx_ch1_en = local_tx_ctrl[CtrlBits::TX_CH1_EN] && dac_enable_q0 && tx_enable;
    bool tx_ch2_en = local_tx_ctrl[CtrlBits::TX_CH2_EN] && dac_enable_i1 && tx_enable;
    bool tx_ch3_en = local_tx_ctrl[CtrlBits::TX_CH3_EN] && dac_enable_q1 && tx_enable;

    //==========================================================================
    // RX Data Processing - Continuous Capture
    //==========================================================================

    // Capture RX samples
    iq_sample_t rx_i0 = (rx_ch0_en && adc_valid_i0) ? adc_data_i0 : iq_sample_t(0);
    iq_sample_t rx_q0 = (rx_ch1_en && adc_valid_q0) ? adc_data_q0 : iq_sample_t(0);
    iq_sample_t rx_i1 = (rx_ch2_en && adc_valid_i1) ? adc_data_i1 : iq_sample_t(0);
    iq_sample_t rx_q1 = (rx_ch3_en && adc_valid_q1) ? adc_data_q1 : iq_sample_t(0);

    // RX valid - any channel has valid data
    bool rx_valid = (rx_ch0_en && adc_valid_i0) ||
                    (rx_ch1_en && adc_valid_q0) ||
                    (rx_ch2_en && adc_valid_i1) ||
                    (rx_ch3_en && adc_valid_q1);

    // Check if buffer is full
    bool rx_buffer_full = (rx_fill_level >= IPInfo::BRAM_DEPTH);

    // Capture RX data to BRAM (continuous until full)
    if (rx_valid && !rx_buffer_full) {
        // Pack I0/Q0 into 32-bit word (using channel 0)
        iq_pair_t packed_sample;
        packed_sample.range(15, 0) = rx_i0;
        packed_sample.range(31, 16) = rx_q0;

        rx_bram[rx_write_ptr] = packed_sample;
        rx_write_ptr++;
        rx_fill_level++;
    }

    // Capture overflow status (sticky - samples dropped when full)
    if (adc_dovf || (rx_valid && rx_buffer_full)) {
        rx_overflow_sticky = true;
    }

    // Clear overflow if requested
    if (local_rx_ctrl[CtrlBits::RX_CLR_OVF]) {
        local_rx_ctrl[CtrlBits::RX_CLR_OVF] = 0;
        rx_overflow_sticky = false;
    }

    // Recompute buffer full status after potential increment
    rx_buffer_full = (rx_fill_level >= IPInfo::BRAM_DEPTH);

    // Build RX status
    local_rx_status[StatusBits::RX_VALID] = rx_valid;
    local_rx_status[StatusBits::RX_OVERFLOW] = rx_overflow_sticky;

    //==========================================================================
    // TX Data Generation - Continuous Cycling
    //==========================================================================

    iq_sample_t tx_i0, tx_q0, tx_i1, tx_q1;
    bool tx_valid_out = false;

    if (loopback_enable) {
        // Internal loopback: RX -> TX
        tx_i0 = rx_i0;
        tx_q0 = rx_q0;
        tx_i1 = rx_i1;
        tx_q1 = rx_q1;
        tx_valid_out = rx_valid;
    } else if (tx_enable) {
        // Continuous cycling through TX BRAM
        iq_pair_t tx_sample = tx_bram[tx_read_ptr];
        tx_i0 = tx_sample.range(15, 0);
        tx_q0 = tx_sample.range(31, 16);
        tx_i1 = 0;  // Only using channel 0 for TX BRAM playback
        tx_q1 = 0;

        // Advance pointer (wraps around)
        tx_read_ptr++;
        if (tx_read_ptr >= IPInfo::BRAM_DEPTH) {
            tx_read_ptr = 0;
        }
        tx_valid_out = true;
    } else {
        // Disabled - output zeros
        tx_i0 = 0;
        tx_q0 = 0;
        tx_i1 = 0;
        tx_q1 = 0;
        tx_valid_out = false;
    }

    // Clear underflow if requested
    if (local_tx_ctrl[CtrlBits::TX_CLR_UNF]) {
        local_tx_ctrl[CtrlBits::TX_CLR_UNF] = 0;
        tx_underflow_sticky = false;
    }

    // Drive TX outputs
    dac_data_i0 = tx_ch0_en ? tx_i0 : iq_sample_t(0);
    dac_data_q0 = tx_ch1_en ? tx_q0 : iq_sample_t(0);
    dac_data_i1 = tx_ch2_en ? tx_i1 : iq_sample_t(0);
    dac_data_q1 = tx_ch3_en ? tx_q1 : iq_sample_t(0);

    // TX valid signals
    dac_valid_i0 = tx_ch0_en && tx_valid_out;
    dac_valid_q0 = tx_ch1_en && tx_valid_out;
    dac_valid_i1 = tx_ch2_en && tx_valid_out;
    dac_valid_q1 = tx_ch3_en && tx_valid_out;

    // Build TX status
    local_tx_status[StatusBits::TX_READY] = tx_enable;
    local_tx_status[StatusBits::TX_UNDERFLOW] = tx_underflow_sticky;

    // TX underflow - not applicable with continuous BRAM cycling
    dac_dunf = 0;

    //==========================================================================
    // Update Global Status
    //==========================================================================

    local_status[StatusBits::ENABLED] = global_enable;
    local_status[StatusBits::RX_ACTIVE] = rx_enable && rx_valid;
    local_status[StatusBits::TX_ACTIVE] = tx_enable && tx_valid_out;
    local_status[StatusBits::LOOPBACK_ON] = loopback_enable;
    local_status[StatusBits::RX_FULL] = rx_buffer_full;

    //==========================================================================
    // Write all registers once at the end
    //==========================================================================

    reg_ctrl = local_ctrl;
    reg_rx_ctrl = local_rx_ctrl;
    reg_tx_ctrl = local_tx_ctrl;
    reg_status = local_status;
    reg_rx_status = local_rx_status;
    reg_tx_status = local_tx_status;
    reg_rx_fill = rx_fill_level;
}
