//==============================================================================
// axi_ad9361_adapter.cpp
//
// Vitis HLS implementation of AXI AD9361 Adapter IP
// Interfaces with ADI axi_ad9361 block for RX/TX data streaming
//
// Target: Vitis HLS 2025.2
// Device: xcau15p-ffvb676-2-e (Ultrascale+)
//==============================================================================

#include "axi_ad9361_adapter.hpp"

//==============================================================================
// Internal Register Storage
//==============================================================================

// Register file - accessible via AXI-Lite
static axi_reg_t reg_ctrl       = 0;
static axi_reg_t reg_status     = 0;
static axi_reg_t reg_scratch    = 0;
static axi_reg_t reg_rx_ctrl    = 0;
static axi_reg_t reg_rx_status  = 0;
static ap_uint<64> reg_rx_count = 0;
static axi_reg_t reg_tx_ctrl    = 0;
static axi_reg_t reg_tx_status  = 0;
static ap_uint<64> reg_tx_count = 0;
static axi_reg_t reg_loopback   = 0;
static axi_reg_t reg_debug_ctrl = 0;
static axi_reg_t reg_debug_data = 0;
static axi_reg_t reg_snap_ctrl  = 0;
static axi_reg_t reg_snap_status = 0;
static axi_reg_t reg_snap_addr  = 0;

// Snapshot buffer
static iq_packed_t snap_buffer[IPInfo::SNAP_DEPTH];

//==============================================================================
// AXI-Lite Register Read Function
//==============================================================================

axi_reg_t axi_read_reg(ap_uint<8> addr) {
#pragma HLS INLINE
    axi_reg_t data = 0;

    switch (addr.to_uint()) {
        case RegMap::CTRL:
            data = reg_ctrl;
            break;
        case RegMap::STATUS:
            data = reg_status;
            break;
        case RegMap::VERSION:
            data = IPInfo::VERSION;
            break;
        case RegMap::SCRATCH:
            data = reg_scratch;
            break;
        case RegMap::RX_CTRL:
            data = reg_rx_ctrl;
            break;
        case RegMap::RX_STATUS:
            data = reg_rx_status;
            break;
        case RegMap::RX_COUNT_LO:
            data = reg_rx_count.range(31, 0);
            break;
        case RegMap::RX_COUNT_HI:
            data = reg_rx_count.range(63, 32);
            break;
        case RegMap::TX_CTRL:
            data = reg_tx_ctrl;
            break;
        case RegMap::TX_STATUS:
            data = reg_tx_status;
            break;
        case RegMap::TX_COUNT_LO:
            data = reg_tx_count.range(31, 0);
            break;
        case RegMap::TX_COUNT_HI:
            data = reg_tx_count.range(63, 32);
            break;
        case RegMap::LOOPBACK:
            data = reg_loopback;
            break;
        case RegMap::DEBUG_CTRL:
            data = reg_debug_ctrl;
            break;
        case RegMap::DEBUG_DATA:
            data = reg_debug_data;
            break;
        case RegMap::SNAP_CTRL:
            data = reg_snap_ctrl;
            break;
        case RegMap::SNAP_STATUS:
            data = reg_snap_status;
            break;
        case RegMap::SNAP_ADDR:
            data = reg_snap_addr;
            break;
        case RegMap::SNAP_DATA:
            // Read from snapshot buffer at current address
            if (reg_snap_addr < IPInfo::SNAP_DEPTH) {
                // Return lower or upper 32 bits based on LSB of address
                data = snap_buffer[reg_snap_addr].range(31, 0);
            }
            break;
        default:
            data = 0xDEADBEEF;  // Invalid register
            break;
    }
    return data;
}

//==============================================================================
// AXI-Lite Register Write Function
//==============================================================================

void axi_write_reg(ap_uint<8> addr, axi_reg_t data) {
#pragma HLS INLINE
    switch (addr.to_uint()) {
        case RegMap::CTRL:
            reg_ctrl = data;
            // Handle soft reset (self-clearing)
            if (data[CtrlBits::SOFT_RESET]) {
                reg_ctrl[CtrlBits::SOFT_RESET] = 0;
                reg_rx_count = 0;
                reg_tx_count = 0;
                reg_rx_status = 0;
                reg_tx_status = 0;
            }
            break;
        case RegMap::SCRATCH:
            reg_scratch = data;
            break;
        case RegMap::RX_CTRL:
            reg_rx_ctrl = data;
            // Handle clear overflow (self-clearing)
            if (data[CtrlBits::RX_CLR_OVF]) {
                reg_rx_ctrl[CtrlBits::RX_CLR_OVF] = 0;
                reg_rx_status[StatusBits::RX_OVERFLOW] = 0;
            }
            break;
        case RegMap::TX_CTRL:
            reg_tx_ctrl = data;
            // Handle clear underflow (self-clearing)
            if (data[CtrlBits::TX_CLR_UNF]) {
                reg_tx_ctrl[CtrlBits::TX_CLR_UNF] = 0;
                reg_tx_status[StatusBits::TX_UNDERFLOW] = 0;
            }
            break;
        case RegMap::LOOPBACK:
            reg_loopback = data;
            break;
        case RegMap::DEBUG_CTRL:
            reg_debug_ctrl = data;
            break;
        case RegMap::SNAP_CTRL:
            reg_snap_ctrl = data;
            break;
        case RegMap::SNAP_ADDR:
            reg_snap_addr = data;
            break;
        // Read-only registers - writes ignored
        case RegMap::STATUS:
        case RegMap::VERSION:
        case RegMap::RX_STATUS:
        case RegMap::RX_COUNT_LO:
        case RegMap::RX_COUNT_HI:
        case RegMap::TX_STATUS:
        case RegMap::TX_COUNT_LO:
        case RegMap::TX_COUNT_HI:
        case RegMap::DEBUG_DATA:
        case RegMap::SNAP_STATUS:
        case RegMap::SNAP_DATA:
        default:
            // Ignore writes to read-only or invalid registers
            break;
    }
}

//==============================================================================
// Top-Level Function
//==============================================================================

void axi_ad9361_adapter(
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

    // AXI-Lite slave interface for register access
    // All static registers are mapped to s_axi_ctrl bundle
#pragma HLS INTERFACE mode=s_axilite port=return bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_ctrl bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_scratch bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_rx_ctrl bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=reg_tx_ctrl bundle=ctrl
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

    // Bind snapshot buffer to BRAM
#pragma HLS BIND_STORAGE variable=snap_buffer type=ram_1p impl=bram

    //==========================================================================
    // Extract control signals
    //==========================================================================

    bool global_enable = reg_ctrl[CtrlBits::ENABLE];
    bool rx_enable = reg_ctrl[CtrlBits::RX_ENABLE] && global_enable;
    bool tx_enable = reg_ctrl[CtrlBits::TX_ENABLE] && global_enable;
    bool loopback_enable = reg_loopback[CtrlBits::LOOPBACK_EN] && global_enable;

    // RX channel enables (from registers AND external enable signals)
    bool rx_ch0_en = reg_rx_ctrl[CtrlBits::RX_CH0_EN] && adc_enable_i0 && rx_enable;
    bool rx_ch1_en = reg_rx_ctrl[CtrlBits::RX_CH1_EN] && adc_enable_q0 && rx_enable;
    bool rx_ch2_en = reg_rx_ctrl[CtrlBits::RX_CH2_EN] && adc_enable_i1 && rx_enable;
    bool rx_ch3_en = reg_rx_ctrl[CtrlBits::RX_CH3_EN] && adc_enable_q1 && rx_enable;

    // TX channel enables
    bool tx_ch0_en = reg_tx_ctrl[CtrlBits::TX_CH0_EN] && dac_enable_i0 && tx_enable;
    bool tx_ch1_en = reg_tx_ctrl[CtrlBits::TX_CH1_EN] && dac_enable_q0 && tx_enable;
    bool tx_ch2_en = reg_tx_ctrl[CtrlBits::TX_CH2_EN] && dac_enable_i1 && tx_enable;
    bool tx_ch3_en = reg_tx_ctrl[CtrlBits::TX_CH3_EN] && dac_enable_q1 && tx_enable;

    //==========================================================================
    // RX Data Processing
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

    // Update RX sample counter
    if (rx_valid) {
        reg_rx_count++;
    }

    // Capture overflow status
    if (adc_dovf) {
        reg_rx_status[StatusBits::RX_OVERFLOW] = 1;
    }
    reg_rx_status[StatusBits::RX_VALID] = rx_valid;

    //==========================================================================
    // TX Data Generation
    //==========================================================================

    // TX samples - either from loopback or external source
    iq_sample_t tx_i0, tx_q0, tx_i1, tx_q1;

    if (loopback_enable) {
        // Internal loopback: RX -> TX
        tx_i0 = rx_i0;
        tx_q0 = rx_q0;
        tx_i1 = rx_i1;
        tx_q1 = rx_q1;
    } else {
        // Normal operation: generate test pattern or pass through
        // For now, output zeros (user can extend with DDS or other sources)
        tx_i0 = 0;
        tx_q0 = 0;
        tx_i1 = 0;
        tx_q1 = 0;
    }

    // Drive TX outputs
    dac_data_i0 = tx_ch0_en ? tx_i0 : iq_sample_t(0);
    dac_data_q0 = tx_ch1_en ? tx_q0 : iq_sample_t(0);
    dac_data_i1 = tx_ch2_en ? tx_i1 : iq_sample_t(0);
    dac_data_q1 = tx_ch3_en ? tx_q1 : iq_sample_t(0);

    // TX valid signals
    dac_valid_i0 = tx_ch0_en && (loopback_enable ? rx_valid : 1);
    dac_valid_q0 = tx_ch1_en && (loopback_enable ? rx_valid : 1);
    dac_valid_i1 = tx_ch2_en && (loopback_enable ? rx_valid : 1);
    dac_valid_q1 = tx_ch3_en && (loopback_enable ? rx_valid : 1);

    // TX valid for counting
    bool tx_valid = tx_ch0_en || tx_ch1_en || tx_ch2_en || tx_ch3_en;

    // Update TX sample counter
    if (tx_valid && (loopback_enable ? rx_valid : 1)) {
        reg_tx_count++;
    }

    // TX underflow (placeholder - would need FIFO to detect properly)
    dac_dunf = 0;
    reg_tx_status[StatusBits::TX_READY] = tx_enable;

    //==========================================================================
    // Snapshot Capture
    //==========================================================================

    static ap_uint<16> snap_write_ptr = 0;
    static bool snap_armed = false;
    static bool snap_capturing = false;

    // Arm snapshot on rising edge of ARM bit
    if (reg_snap_ctrl[CtrlBits::SNAP_ARM] && !snap_armed) {
        snap_armed = true;
        snap_capturing = false;
        snap_write_ptr = 0;
        reg_snap_status[StatusBits::SNAP_ARMED] = 1;
        reg_snap_status[StatusBits::SNAP_DONE] = 0;
        reg_snap_status[StatusBits::SNAP_FULL] = 0;
    }

    // Trigger capture (manual trigger or valid data)
    bool snap_trigger = reg_snap_ctrl[CtrlBits::SNAP_TRIG] || rx_valid;

    if (snap_armed && snap_trigger && !snap_capturing) {
        snap_capturing = true;
        reg_snap_ctrl[CtrlBits::SNAP_TRIG] = 0;  // Clear manual trigger
    }

    // Capture data to snapshot buffer
    if (snap_capturing && rx_valid && snap_write_ptr < IPInfo::SNAP_DEPTH) {
        // Pack all 4 channels into 64-bit word
        iq_packed_t packed_data;
        packed_data.range(15, 0)   = rx_i0;
        packed_data.range(31, 16)  = rx_q0;
        packed_data.range(47, 32)  = rx_i1;
        packed_data.range(63, 48)  = rx_q1;

        snap_buffer[snap_write_ptr] = packed_data;
        snap_write_ptr++;

        if (snap_write_ptr >= IPInfo::SNAP_DEPTH) {
            snap_capturing = false;
            snap_armed = false;
            reg_snap_status[StatusBits::SNAP_ARMED] = 0;
            reg_snap_status[StatusBits::SNAP_DONE] = 1;
            reg_snap_status[StatusBits::SNAP_FULL] = 1;
        }
    }

    // Debug data capture
    reg_debug_data = (rx_q0, rx_i0);  // Pack I0/Q0 into debug register

    //==========================================================================
    // Update Global Status
    //==========================================================================

    reg_status[StatusBits::ENABLED] = global_enable;
    reg_status[StatusBits::RX_ACTIVE] = rx_enable && rx_valid;
    reg_status[StatusBits::TX_ACTIVE] = tx_enable && tx_valid;
    reg_status[StatusBits::LOOPBACK_ON] = loopback_enable;
}
