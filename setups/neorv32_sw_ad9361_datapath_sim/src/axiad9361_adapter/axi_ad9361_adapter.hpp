//==============================================================================
// axi_ad9361_adapter.hpp
//
// Header file for AXI AD9361 Adapter HLS IP
// Provides register definitions and data types for interfacing with the
// ADI axi_ad9361 block.
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

// Packed I/Q pair for single channel
typedef ap_uint<32> iq_pair_t;

// 4-channel packed data (I0, Q0, I1, Q1) - 64 bits total
typedef ap_uint<64> iq_packed_t;

// AXI-Lite register data type
typedef ap_uint<32> axi_reg_t;

// Valid/enable signals
typedef ap_uint<1> valid_t;
typedef ap_uint<4> enable_mask_t;

//==============================================================================
// Register Map Definitions
//==============================================================================

// Register offsets (byte addresses, 32-bit aligned)
namespace RegMap {
    // Control/Status Registers (0x00 - 0x0F)
    constexpr unsigned int CTRL        = 0x00;  // Control register
    constexpr unsigned int STATUS      = 0x04;  // Status register
    constexpr unsigned int VERSION     = 0x08;  // IP version register
    constexpr unsigned int SCRATCH     = 0x0C;  // Scratch register for testing

    // RX Configuration (0x10 - 0x1F)
    constexpr unsigned int RX_CTRL     = 0x10;  // RX control
    constexpr unsigned int RX_STATUS   = 0x14;  // RX status (overflow, etc.)
    constexpr unsigned int RX_COUNT_LO = 0x18;  // RX sample count (low 32 bits)
    constexpr unsigned int RX_COUNT_HI = 0x1C;  // RX sample count (high 32 bits)

    // TX Configuration (0x20 - 0x2F)
    constexpr unsigned int TX_CTRL     = 0x20;  // TX control
    constexpr unsigned int TX_STATUS   = 0x24;  // TX status (underflow, etc.)
    constexpr unsigned int TX_COUNT_LO = 0x28;  // TX sample count (low 32 bits)
    constexpr unsigned int TX_COUNT_HI = 0x2C;  // TX sample count (high 32 bits)

    // Loopback/Debug (0x30 - 0x3F)
    constexpr unsigned int LOOPBACK    = 0x30;  // Loopback control
    constexpr unsigned int DEBUG_CTRL  = 0x34;  // Debug control
    constexpr unsigned int DEBUG_DATA  = 0x38;  // Debug data capture

    // Snapshot Buffer (0x40 - 0x4F)
    constexpr unsigned int SNAP_CTRL   = 0x40;  // Snapshot control
    constexpr unsigned int SNAP_STATUS = 0x44;  // Snapshot status
    constexpr unsigned int SNAP_ADDR   = 0x48;  // Snapshot read address
    constexpr unsigned int SNAP_DATA   = 0x4C;  // Snapshot data output
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
    constexpr unsigned int LOOPBACK_CH = 4;     // Loopback channel select (2 bits)

    // SNAP_CTRL register (0x40)
    constexpr unsigned int SNAP_ARM    = 0;     // Arm snapshot capture
    constexpr unsigned int SNAP_TRIG   = 1;     // Manual trigger
    constexpr unsigned int SNAP_SRC    = 4;     // Source select (2 bits): 0=RX, 1=TX
    constexpr unsigned int SNAP_CH     = 8;     // Channel select (2 bits)
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

    // RX_STATUS register (0x14)
    constexpr unsigned int RX_OVERFLOW = 0;     // RX overflow occurred
    constexpr unsigned int RX_VALID    = 1;     // RX data valid

    // TX_STATUS register (0x24)
    constexpr unsigned int TX_UNDERFLOW = 0;    // TX underflow occurred
    constexpr unsigned int TX_READY    = 1;     // TX ready for data

    // SNAP_STATUS register (0x44)
    constexpr unsigned int SNAP_ARMED  = 0;     // Snapshot armed
    constexpr unsigned int SNAP_DONE   = 1;     // Snapshot capture complete
    constexpr unsigned int SNAP_FULL   = 2;     // Snapshot buffer full
}

//==============================================================================
// IP Version and Constants
//==============================================================================

namespace IPInfo {
    constexpr unsigned int VERSION_MAJOR = 1;
    constexpr unsigned int VERSION_MINOR = 0;
    constexpr unsigned int VERSION_PATCH = 0;

    // Packed version: 0x00010000 = v1.0.0
    constexpr unsigned int VERSION = (VERSION_MAJOR << 16) |
                                     (VERSION_MINOR << 8) |
                                     VERSION_PATCH;

    // Snapshot buffer depth (number of 64-bit samples)
    constexpr unsigned int SNAP_DEPTH = 1024;

    // Number of I/Q channels (2 for 1R1T, 4 for 2R2T)
    constexpr unsigned int NUM_CHANNELS = 4;
}

//==============================================================================
// Function Declarations
//==============================================================================

// Top-level HLS function
void axi_ad9361_adapter(
    // AXI-Lite Slave Interface (directly connected via pragma)
    // Register reads/writes handled internally

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

    // Overflow/Underflow status from/to axi_ad9361
    valid_t      adc_dovf,
    valid_t&     dac_dunf
);

#endif // AXI_AD9361_ADAPTER_HPP
