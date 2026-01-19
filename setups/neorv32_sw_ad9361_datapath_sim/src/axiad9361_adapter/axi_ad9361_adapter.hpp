//==============================================================================
// axi_ad9361_adapter.hpp
//
// Header file for AXI AD9361 Adapter HLS IP
// Provides register definitions and data types for interfacing with the
// ADI axi_ad9361 block.
//
// Features:
// - Free-running datapath (continuous TX/RX operation)
// - 1024-sample TX BRAM (software-loaded via AXI-Lite)
// - 1024-sample RX BRAM (continuous capture, fills until full)
// - AXI-Lite control registers and memory access
// - Internal loopback mode
//
// TX Operation:
// 1. Software loads TX BRAM with IQ data via AXI-Lite (0x1000-0x1FFF)
// 2. Software enables TX (CTRL.TX_ENABLE)
// 3. Hardware continuously cycles through TX BRAM
// 4. To update TX data: disable TX, reload BRAM, re-enable TX
//
// Target: Vitis HLS 2025.2
// Device: xcau15p-ffvb676-2-e (Ultrascale+)
//==============================================================================

#ifndef AXI_AD9361_ADAPTER_HPP
#define AXI_AD9361_ADAPTER_HPP

#include <ap_int.h>
#include <hls_stream.h>

//==============================================================================
// Data Types
//==============================================================================

// I/Q sample data width (matches axi_ad9361 output)
typedef ap_int<16> iq_sample_t;

// Packed I/Q pair for single channel (I in lower 16 bits, Q in upper 16 bits)
typedef ap_uint<32> iq_pair_t;

// 4-channel packed data (I0, Q0, I1, Q1) - 64 bits total
typedef ap_uint<64> iq_packed_t;

// AXI-Lite register data type
typedef ap_uint<32> axi_reg_t;

// BRAM address type (10 bits for 1024 entries)
typedef ap_uint<10> bram_addr_t;

// RX fill level type (11 bits for 0-1024 range)
typedef ap_uint<11> fill_level_t;

// Valid/enable signals
typedef ap_uint<1> valid_t;
typedef ap_uint<4> enable_mask_t;

//==============================================================================
// Register Map Definitions
//==============================================================================

// Memory map (all via single AXI-Lite 'ctrl' bundle):
//   0x0000 - 0x003F: Control/Status registers
//   0x1000 - 0x1FFF: TX BRAM (1024 x 32-bit = 4KB)
//   0x2000 - 0x2FFF: RX BRAM (1024 x 32-bit = 4KB)

namespace RegMap {
    // Control/Status Registers (0x00 - 0x3F)
    constexpr unsigned int CTRL        = 0x00;  // Control register
    constexpr unsigned int STATUS      = 0x04;  // Status register
    constexpr unsigned int VERSION     = 0x08;  // IP version register
    constexpr unsigned int SCRATCH     = 0x0C;  // Scratch register for testing

    // RX Configuration (0x10 - 0x1F)
    constexpr unsigned int RX_CTRL     = 0x10;  // RX control
    constexpr unsigned int RX_STATUS   = 0x14;  // RX status (overflow, etc.)
    constexpr unsigned int RX_FILL     = 0x18;  // RX fill level (0-1024)

    // TX Configuration (0x20 - 0x2F)
    constexpr unsigned int TX_CTRL     = 0x20;  // TX control
    constexpr unsigned int TX_STATUS   = 0x24;  // TX status (underflow, etc.)

    // Loopback/Debug (0x30 - 0x3F)
    constexpr unsigned int LOOPBACK    = 0x30;  // Loopback control

    // TX BRAM region (0x1000 - 0x1FFF)
    // Each sample is 32 bits: [31:16] = Q, [15:0] = I
    // Address = TX_BRAM_BASE + (sample_index * 4)
    constexpr unsigned int TX_BRAM_BASE = 0x1000;
    constexpr unsigned int TX_BRAM_END  = 0x1FFF;

    // RX BRAM region (0x2000 - 0x2FFF)
    // Each sample is 32 bits: [31:16] = Q, [15:0] = I
    // Address = RX_BRAM_BASE + (sample_index * 4)
    constexpr unsigned int RX_BRAM_BASE = 0x2000;
    constexpr unsigned int RX_BRAM_END  = 0x2FFF;
}

//==============================================================================
// Control Register Bit Definitions
//==============================================================================

namespace CtrlBits {
    // CTRL register (0x00)
    constexpr unsigned int ENABLE      = 0;     // Global enable
    constexpr unsigned int SOFT_RESET  = 1;     // Soft reset (self-clearing)
    constexpr unsigned int RX_ENABLE   = 2;     // RX path enable
    constexpr unsigned int TX_ENABLE   = 3;     // TX path enable
    constexpr unsigned int RX_CLEAR    = 8;     // Clear RX buffer (self-clearing, resets fill level to 0)

    // RX_CTRL register (0x10)
    constexpr unsigned int RX_CH0_EN   = 0;     // RX Channel 0 (I0) enable
    constexpr unsigned int RX_CH1_EN   = 1;     // RX Channel 1 (Q0) enable
    constexpr unsigned int RX_CH2_EN   = 2;     // RX Channel 2 (I1) enable
    constexpr unsigned int RX_CH3_EN   = 3;     // RX Channel 3 (Q1) enable
    constexpr unsigned int RX_CLR_OVF  = 8;     // Clear overflow flag

    // TX_CTRL register (0x20)
    constexpr unsigned int TX_CH0_EN   = 0;     // TX Channel 0 (I0) enable
    constexpr unsigned int TX_CH1_EN   = 1;     // TX Channel 1 (Q0) enable
    constexpr unsigned int TX_CH2_EN   = 2;     // TX Channel 2 (I1) enable
    constexpr unsigned int TX_CH3_EN   = 3;     // TX Channel 3 (Q1) enable
    constexpr unsigned int TX_CLR_UNF  = 8;     // Clear underflow flag

    // LOOPBACK register (0x30)
    constexpr unsigned int LOOPBACK_EN = 0;     // Enable internal loopback
}

//==============================================================================
// Status Register Bit Definitions
//==============================================================================

namespace StatusBits {
    // STATUS register (0x04)
    constexpr unsigned int ENABLED     = 0;     // Global enabled status
    constexpr unsigned int RX_ACTIVE   = 1;     // RX path active
    constexpr unsigned int TX_ACTIVE   = 2;     // TX path active
    constexpr unsigned int LOOPBACK_ON = 3;     // Loopback active
    constexpr unsigned int RX_FULL     = 4;     // RX buffer full (fill level == 1024)

    // RX_STATUS register (0x14)
    constexpr unsigned int RX_OVERFLOW = 0;     // RX overflow occurred
    constexpr unsigned int RX_VALID    = 1;     // RX data valid

    // TX_STATUS register (0x24)
    constexpr unsigned int TX_UNDERFLOW = 0;    // TX underflow occurred
    constexpr unsigned int TX_READY    = 1;     // TX ready for data
}

//==============================================================================
// IP Version and Constants
//==============================================================================

namespace IPInfo {
    constexpr unsigned int VERSION_MAJOR = 3;
    constexpr unsigned int VERSION_MINOR = 0;
    constexpr unsigned int VERSION_PATCH = 0;

    // Packed version: 0x00030000 = v3.0.0
    constexpr unsigned int VERSION = (VERSION_MAJOR << 16) |
                                     (VERSION_MINOR << 8) |
                                     VERSION_PATCH;

    // BRAM depth (number of 32-bit samples per buffer)
    constexpr unsigned int BRAM_DEPTH = 1024;

    // Number of I/Q channels (2 for 1R1T, 4 for 2R2T)
    constexpr unsigned int NUM_CHANNELS = 4;
}

//==============================================================================
// Function Declarations
//==============================================================================

// Top-level HLS function (free-running datapath)
void axi_ad9361_adapter(
    // TX BRAM - 1024 samples, AXI-Lite accessible at offset 0x1000
    iq_pair_t tx_bram[IPInfo::BRAM_DEPTH],

    // RX BRAM - 1024 samples, AXI-Lite accessible at offset 0x2000
    iq_pair_t rx_bram[IPInfo::BRAM_DEPTH],

    // Control registers (AXI-Lite mapped)
    axi_reg_t& reg_ctrl,
    axi_reg_t& reg_status,
    axi_reg_t& reg_scratch,
    axi_reg_t& reg_rx_ctrl,
    axi_reg_t& reg_rx_status,
    axi_reg_t& reg_rx_fill,
    axi_reg_t& reg_tx_ctrl,
    axi_reg_t& reg_tx_status,
    axi_reg_t& reg_loopback,

    // RX data from axi_ad9361 (directly driven, no AXI-Stream)
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

    // TX data to axi_ad9361 (directly driven, no AXI-Stream)
    // Note: dac_valid_* and dac_enable_* are INPUTS from axi_ad9361
    // The axi_ad9361 drives dac_valid to indicate "I want data now"
    // We respond by providing data on dac_data_* when dac_valid is asserted
    iq_sample_t& dac_data_i0,
    iq_sample_t& dac_data_q0,
    iq_sample_t& dac_data_i1,
    iq_sample_t& dac_data_q1,
    valid_t      dac_valid_i0,
    valid_t      dac_valid_q0,
    valid_t      dac_valid_i1,
    valid_t      dac_valid_q1,
    valid_t      dac_enable_i0,
    valid_t      dac_enable_q0,
    valid_t      dac_enable_i1,
    valid_t      dac_enable_q1,

    // Overflow/Underflow status from/to axi_ad9361
    valid_t      adc_dovf,
    valid_t&     dac_dunf
);

#endif // AXI_AD9361_ADAPTER_HPP
