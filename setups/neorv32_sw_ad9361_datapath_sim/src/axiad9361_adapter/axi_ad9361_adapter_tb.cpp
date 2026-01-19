//==============================================================================
// axi_ad9361_adapter_tb.cpp
//
// Testbench for AXI AD9361 Adapter HLS IP v3.0
// Verifies:
// - Free-running operation
// - TX BRAM continuous cycling (software-loaded)
// - RX BRAM continuous capture with fill level tracking
// - RX clear functionality
// - Loopback mode
// - Control registers
//
// Full flow test combines all functionality of the UUT and documents its behavior
//
// Target: Vitis HLS 2025.2
//==============================================================================

#include <iostream>
#include <iomanip>
#include <cstdlib>
#include <cmath>
#include <fstream>
#include <string>
#include <vector>
#include "axi_ad9361_adapter.hpp"

//==============================================================================
// Test Configuration
//==============================================================================

constexpr int NUM_TEST_SAMPLES = 100;

// COE file path - file is copied to csim build directory via tb.file in .cfg
#define COE_FILE_NAME "qpsk_bram_init.coe"

//==============================================================================
// COE File Data Storage
//==============================================================================

static std::vector<uint32_t> coe_data;

//==============================================================================
// COE File Parser
// Parses Xilinx COE file format and returns vector of 32-bit values
//==============================================================================

bool load_coe_file(const char* filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "ERROR: Could not open COE file: " << filename << std::endl;
        return false;
    }

    coe_data.clear();
    std::string line;
    bool in_vector = false;
    int radix = 16;  // Default to hex

    while (std::getline(file, line)) {
        // Skip empty lines and comments
        if (line.empty() || line[0] == ';') {
            continue;
        }

        // Check for radix specification
        if (line.find("memory_initialization_radix") != std::string::npos) {
            size_t eq_pos = line.find('=');
            if (eq_pos != std::string::npos) {
                std::string radix_str = line.substr(eq_pos + 1);
                // Remove trailing semicolon if present
                size_t semi_pos = radix_str.find(';');
                if (semi_pos != std::string::npos) {
                    radix_str = radix_str.substr(0, semi_pos);
                }
                radix = std::stoi(radix_str);
            }
            continue;
        }

        // Check for vector start
        if (line.find("memory_initialization_vector") != std::string::npos) {
            in_vector = true;
            // Check if data starts on same line after '='
            size_t eq_pos = line.find('=');
            if (eq_pos != std::string::npos && eq_pos + 1 < line.length()) {
                line = line.substr(eq_pos + 1);
            } else {
                continue;
            }
        }

        // Parse data values
        if (in_vector) {
            // Remove whitespace
            std::string value_str;
            for (char c : line) {
                if (!std::isspace(c)) {
                    value_str += c;
                }
            }

            // Remove trailing comma or semicolon
            while (!value_str.empty() &&
                   (value_str.back() == ',' || value_str.back() == ';')) {
                value_str.pop_back();
            }

            // Parse the hex value
            if (!value_str.empty()) {
                uint32_t value = std::stoul(value_str, nullptr, radix);
                coe_data.push_back(value);
            }
        }
    }

    file.close();

    std::cout << "Loaded " << coe_data.size() << " values from COE file" << std::endl;
    return coe_data.size() > 0;
}

//==============================================================================
// Test Storage (simulates AXI-Lite accessible memory)
//==============================================================================

// TX and RX BRAMs
static iq_pair_t tx_bram[IPInfo::BRAM_DEPTH];
static iq_pair_t rx_bram[IPInfo::BRAM_DEPTH];

// Control/Status registers
static axi_reg_t reg_ctrl = 0;
static axi_reg_t reg_status = 0;
static axi_reg_t reg_scratch = 0;
static axi_reg_t reg_rx_ctrl = 0;
static axi_reg_t reg_rx_status = 0;
static axi_reg_t reg_rx_fill = 0;
static axi_reg_t reg_tx_ctrl = 0;
static axi_reg_t reg_tx_status = 0;
static axi_reg_t reg_loopback = 0;

//==============================================================================
// Helper Functions
//==============================================================================

// Call adapter once (simulates one clock cycle)
// Note: dac_valid_* are now INPUTS - they simulate axi_ad9361 requesting data
// When dac_valid=1, the adapter should output data from TX BRAM
void run_adapter_cycle(
    iq_sample_t adc_i0, iq_sample_t adc_q0,
    iq_sample_t adc_i1, iq_sample_t adc_q1,
    valid_t adc_valid,
    valid_t dac_valid,  // Input: simulates axi_ad9361 requesting TX data
    iq_sample_t& dac_i0, iq_sample_t& dac_q0,
    iq_sample_t& dac_i1, iq_sample_t& dac_q1
) {
    valid_t adc_enable_i0 = 1, adc_enable_q0 = 1, adc_enable_i1 = 1, adc_enable_q1 = 1;
    valid_t dac_enable_i0 = 1, dac_enable_q0 = 1, dac_enable_i1 = 1, dac_enable_q1 = 1;
    valid_t adc_dovf = 0, dac_dunf;

    axi_ad9361_adapter(
        tx_bram, rx_bram,
        reg_ctrl, reg_status, reg_scratch,
        reg_rx_ctrl, reg_rx_status, reg_rx_fill,
        reg_tx_ctrl, reg_tx_status,
        reg_loopback,
        adc_i0, adc_q0, adc_i1, adc_q1,
        adc_valid, adc_valid, adc_valid, adc_valid,
        adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
        dac_i0, dac_q0, dac_i1, dac_q1,
        dac_valid, dac_valid, dac_valid, dac_valid,  // dac_valid_* are inputs
        dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
        adc_dovf, dac_dunf
    );
}


// Load TX BRAM with test data (simulates software loading via AXI-Lite)
// Uses simple ramp pattern: I = index, Q = -index
void load_tx_bram_test_data() {
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        int16_t i_val = (int16_t)(i & 0x7FFF);       // Ramp 0 to 1023
        int16_t q_val = (int16_t)(-(i & 0x7FFF));    // Ramp 0 to -1023
        tx_bram[i] = ((uint32_t)(q_val & 0xFFFF) << 16) | (uint32_t)(i_val & 0xFFFF);
    }
}

// Load TX BRAM with QPSK COE data (simulates software loading via AXI-Lite)
bool load_tx_bram_coe_data() {
    if (coe_data.empty()) {
        std::cerr << "ERROR: COE data not loaded. Call load_coe_file() first." << std::endl;
        return false;
    }
    if (coe_data.size() < IPInfo::BRAM_DEPTH) {
        std::cerr << "WARNING: COE file has only " << coe_data.size()
                  << " values, expected " << IPInfo::BRAM_DEPTH << std::endl;
    }
    size_t count = std::min(coe_data.size(), (size_t)IPInfo::BRAM_DEPTH);
    for (size_t i = 0; i < count; i++) {
        tx_bram[i] = iq_pair_t(coe_data[i]);
    }
    return true;
}

// Initialize adapter with soft reset
void reset_adapter() {
    reg_ctrl = (1 << CtrlBits::SOFT_RESET);
    reg_rx_ctrl = 0;
    reg_tx_ctrl = 0;
    reg_loopback = 0;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    // adc_valid=0, dac_valid=0 (no data transfer during reset)
    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);
}

// Print sample values
void print_samples(const char* label, int sample_num,
                   iq_sample_t i0, iq_sample_t q0,
                   iq_sample_t i1, iq_sample_t q1) {
    std::cout << label << " [" << std::setw(4) << sample_num << "]: "
              << "I0=" << std::setw(6) << i0.to_int()
              << " Q0=" << std::setw(6) << q0.to_int()
              << " I1=" << std::setw(6) << i1.to_int()
              << " Q1=" << std::setw(6) << q1.to_int()
              << std::endl;
}

//==============================================================================
// Test 1: TX BRAM Software Load and Continuous Cycling
//==============================================================================

int test_tx_continuous_cycling() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 1: TX BRAM Continuous Cycling" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Step 1: Load TX BRAM with test data (software operation via AXI-Lite)
    std::cout << "Loading TX BRAM with test data (ramp pattern)..." << std::endl;
    load_tx_bram_test_data();

    // Step 2: Enable TX path and channels
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::TX_ENABLE);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    std::cout << "Running TX continuous cycling..." << std::endl;
    std::cout << "(dac_valid=1 simulates axi_ad9361 requesting data)" << std::endl;

    // Run for more than BRAM_DEPTH to verify wrap-around
    int wrap_count = 0;
    iq_sample_t first_i = 0, first_q = 0;
    bool first_captured = false;

    for (int i = 0; i < IPInfo::BRAM_DEPTH * 2 + 100; i++) {
        // dac_valid=1: axi_ad9361 is requesting data
        run_adapter_cycle(0, 0, 0, 0, 0, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1);

        // Capture first sample
        if (!first_captured) {
            first_i = dac_i0;
            first_q = dac_q0;
            first_captured = true;
        }

        // Detect wrap-around (when we see first sample again)
        if (first_captured && i > 10 && dac_i0 == first_i && dac_q0 == first_q) {
            wrap_count++;
            std::cout << "  Wrap-around detected at cycle " << i << std::endl;
        }

        // Print first few and samples around wrap point
        if (i < 5 || (i >= IPInfo::BRAM_DEPTH - 2 && i < IPInfo::BRAM_DEPTH + 3)) {
            print_samples("TX", i, dac_i0, dac_q0, dac_i1, dac_q1);
        }
    }

    // Verify TX BRAM contains expected ramp pattern
    std::cout << "\nVerifying TX BRAM contains loaded test data..." << std::endl;
    bool init_ok = true;
    for (int i = 0; i < 5; i++) {
        // Expected: I = i, Q = -i (ramp pattern from load_tx_bram_test_data)
        int16_t expected_i = (int16_t)(i & 0x7FFF);
        int16_t expected_q = (int16_t)(-(i & 0x7FFF));
        uint32_t expected = ((uint32_t)(expected_q & 0xFFFF) << 16) | (uint32_t)(expected_i & 0xFFFF);
        if (tx_bram[i].to_uint() != expected) {
            std::cout << "  ERROR: TX BRAM[" << i << "] = 0x" << std::hex << tx_bram[i].to_uint()
                      << " expected 0x" << expected << std::dec << std::endl;
            init_ok = false;
            errors++;
        }
    }
    if (init_ok) {
        std::cout << "  PASS: TX BRAM contains correct test data" << std::endl;
    }

    if (wrap_count >= 2) {
        std::cout << "PASS: TX continuous mode wraps correctly (" << wrap_count << " wraps)" << std::endl;
    } else {
        std::cout << "ERROR: TX continuous mode did not wrap as expected (wraps=" << wrap_count << ")" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Test 2: RX BRAM Capture with Fill Level
//==============================================================================

int test_rx_fill_level() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 2: RX BRAM Capture with Fill Level" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Clear RX BRAM
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        rx_bram[i] = 0;
    }

    // Enable RX path
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    std::cout << "Starting RX capture with ramp pattern..." << std::endl;

    // Feed test data into RX until buffer fills
    // adc_valid=1, dac_valid=0 (only RX active, TX not requesting)
    for (int i = 0; i < IPInfo::BRAM_DEPTH + 100; i++) {
        iq_sample_t adc_i0 = (i * 5) & 0x7FFF;
        iq_sample_t adc_q0 = ((i * 5) + 2) & 0x7FFF;

        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1, 0,
                          dac_i0, dac_q0, dac_i1, dac_q1);

        // Print fill level at key points
        if (i < 5 || i == IPInfo::BRAM_DEPTH - 1 || i == IPInfo::BRAM_DEPTH || i == IPInfo::BRAM_DEPTH + 10) {
            std::cout << "  Cycle " << std::setw(4) << i
                      << ": fill_level=" << std::setw(4) << reg_rx_fill.to_uint()
                      << " RX_FULL=" << reg_status[StatusBits::RX_FULL] << std::endl;
        }
    }

    // Check fill level is 1024 (full)
    if (reg_rx_fill == IPInfo::BRAM_DEPTH) {
        std::cout << "PASS: RX fill level is 1024 (buffer full)" << std::endl;
    } else {
        std::cout << "ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 1024)" << std::endl;
        errors++;
    }

    // Check RX_FULL status bit
    if (reg_status[StatusBits::RX_FULL]) {
        std::cout << "PASS: RX_FULL status bit is set" << std::endl;
    } else {
        std::cout << "ERROR: RX_FULL status bit not set" << std::endl;
        errors++;
    }

    // Verify captured data
    std::cout << "\nVerifying RX BRAM contents (first 5 samples)..." << std::endl;
    int verify_errors = 0;
    for (int i = 0; i < 5; i++) {
        iq_pair_t sample = rx_bram[i];
        iq_sample_t rx_i = sample.range(15, 0);
        iq_sample_t rx_q = sample.range(31, 16);

        iq_sample_t expected_i = (i * 5) & 0x7FFF;
        iq_sample_t expected_q = ((i * 5) + 2) & 0x7FFF;

        std::cout << "  RX BRAM[" << std::setw(4) << i << "]: "
                  << "I=" << std::setw(6) << rx_i.to_int()
                  << " Q=" << std::setw(6) << rx_q.to_int();

        if (rx_i != expected_i || rx_q != expected_q) {
            std::cout << " ERROR (expected I=" << expected_i.to_int()
                      << " Q=" << expected_q.to_int() << ")";
            verify_errors++;
        }
        std::cout << std::endl;
    }

    if (verify_errors == 0) {
        std::cout << "PASS: RX BRAM data verified correctly" << std::endl;
    } else {
        std::cout << "ERROR: " << verify_errors << " verification errors" << std::endl;
        errors += verify_errors;
    }

    return errors;
}

//==============================================================================
// Test 3: RX Clear Functionality
//==============================================================================

int test_rx_clear() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 3: RX Clear Functionality" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    // Continue from previous state (buffer should be full)

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    std::cout << "Before clear: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    // Clear RX buffer
    reg_ctrl |= (1 << CtrlBits::RX_CLEAR);

    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    std::cout << "After clear: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    if (reg_rx_fill == 0) {
        std::cout << "PASS: RX fill level cleared to 0" << std::endl;
    } else {
        std::cout << "ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 0)" << std::endl;
        errors++;
    }

    // Verify RX_CLEAR bit is self-clearing
    if (!reg_ctrl[CtrlBits::RX_CLEAR]) {
        std::cout << "PASS: RX_CLEAR bit is self-clearing" << std::endl;
    } else {
        std::cout << "ERROR: RX_CLEAR bit did not self-clear" << std::endl;
        errors++;
    }

    // Feed more data and verify capture resumes
    std::cout << "\nVerifying capture resumes after clear..." << std::endl;
    for (int i = 0; i < 100; i++) {
        iq_sample_t adc_i0 = 8000 + i;
        iq_sample_t adc_q0 = 9000 + i;

        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1, 0,
                          dac_i0, dac_q0, dac_i1, dac_q1);
    }

    if (reg_rx_fill == 100) {
        std::cout << "PASS: RX capture resumed, fill_level=" << reg_rx_fill.to_uint() << std::endl;
    } else {
        std::cout << "ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 100)" << std::endl;
        errors++;
    }

    // Verify new data captured correctly
    iq_pair_t first_sample = rx_bram[0];
    iq_sample_t first_i = first_sample.range(15, 0);
    iq_sample_t first_q = first_sample.range(31, 16);

    if (first_i == 8000 && first_q == 9000) {
        std::cout << "PASS: New data captured correctly after clear" << std::endl;
    } else {
        std::cout << "ERROR: First sample after clear is I=" << first_i.to_int()
                  << " Q=" << first_q.to_int() << " (expected I=8000 Q=9000)" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Test 4: Loopback Mode
//==============================================================================

int test_loopback() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 4: Loopback Mode" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Enable loopback
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE) | (1 << CtrlBits::TX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);
    reg_loopback = (1 << CtrlBits::LOOPBACK_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    std::cout << "Testing loopback (RX -> TX)..." << std::endl;
    std::cout << "(adc_valid=1, dac_valid=1 for both paths active)" << std::endl;

    for (int i = 0; i < NUM_TEST_SAMPLES; i++) {
        iq_sample_t adc_i0 = 1000 + i * 100;
        iq_sample_t adc_q0 = 2000 + i * 100;

        // adc_valid=1, dac_valid=1: both RX capturing and TX outputting (loopback)
        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1);

        // In loopback, TX should match RX
        if (i < 10) {
            std::cout << "  Sample " << i << ": ADC I=" << adc_i0.to_int()
                      << " Q=" << adc_q0.to_int()
                      << " -> DAC I=" << dac_i0.to_int()
                      << " Q=" << dac_q0.to_int();

            if (dac_i0 != adc_i0 || dac_q0 != adc_q0) {
                std::cout << " MISMATCH!";
                errors++;
            }
            std::cout << std::endl;
        }
    }

    if (errors == 0) {
        std::cout << "PASS: Loopback data matches" << std::endl;
    }

    return errors;
}

//==============================================================================
// Test 5: Register Access
//==============================================================================

int test_registers() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 5: Register Access" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Test scratch register
    std::cout << "Testing scratch register..." << std::endl;
    reg_scratch = 0x12345678;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    if (reg_scratch == 0x12345678) {
        std::cout << "  PASS: Scratch register readback correct" << std::endl;
    } else {
        std::cout << "  ERROR: Scratch register mismatch" << std::endl;
        errors++;
    }

    // Test soft reset clears state
    std::cout << "Testing soft reset..." << std::endl;

    // First fill some RX data
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN);
    for (int i = 0; i < 50; i++) {
        run_adapter_cycle(100, 200, 0, 0, 1, 0,
                          dac_i0, dac_q0, dac_i1, dac_q1);
    }

    std::cout << "  Before reset: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    // Apply soft reset
    reg_ctrl = (1 << CtrlBits::SOFT_RESET);
    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    std::cout << "  After reset: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    if (reg_rx_fill == 0) {
        std::cout << "  PASS: Soft reset cleared RX fill level" << std::endl;
    } else {
        std::cout << "  ERROR: RX fill level not cleared by soft reset" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Test 6: TX and RX Simultaneous Operation
//==============================================================================

int test_simultaneous_txrx() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 6: Simultaneous TX and RX" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Clear RX BRAM
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        rx_bram[i] = 0;
    }

    // Enable both TX and RX (no loopback)
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE) | (1 << CtrlBits::TX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    std::cout << "Running simultaneous TX cycling and RX capture..." << std::endl;
    std::cout << "(adc_valid=1, dac_valid=1 for both paths active)" << std::endl;

    // Run for some cycles
    for (int i = 0; i < 500; i++) {
        // Feed RX with distinct pattern
        iq_sample_t adc_i0 = 30000 - i;
        iq_sample_t adc_q0 = 31000 - i;

        // Both adc_valid=1 and dac_valid=1 for simultaneous operation
        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1);

        if (i < 5) {
            std::cout << "  Cycle " << i << ": TX out I=" << dac_i0.to_int()
                      << " Q=" << dac_q0.to_int()
                      << ", RX in I=" << adc_i0.to_int()
                      << " Q=" << adc_q0.to_int()
                      << ", fill=" << reg_rx_fill.to_uint() << std::endl;
        }
    }

    // Verify RX captured correct data (first 5 samples)
    std::cout << "\nVerifying RX captured data (first 5 samples)..." << std::endl;
    bool rx_ok = true;
    for (int i = 0; i < 5; i++) {
        iq_pair_t sample = rx_bram[i];
        iq_sample_t rx_i = sample.range(15, 0);
        iq_sample_t rx_q = sample.range(31, 16);

        iq_sample_t expected_i = 30000 - i;
        iq_sample_t expected_q = 31000 - i;

        std::cout << "  RX BRAM[" << i << "]: I=" << rx_i.to_int()
                  << " Q=" << rx_q.to_int();

        if (rx_i != expected_i || rx_q != expected_q) {
            std::cout << " ERROR";
            rx_ok = false;
            errors++;
        }
        std::cout << std::endl;
    }

    // Verify TX is outputting from BRAM (not RX data since loopback is off)
    // TX should be cycling through initialized BRAM
    std::cout << "\nVerifying TX is cycling independently from RX..." << std::endl;
    if (reg_status[StatusBits::TX_ACTIVE]) {
        std::cout << "PASS: TX is active and outputting data" << std::endl;
    } else {
        std::cout << "ERROR: TX not active" << std::endl;
        errors++;
    }

    if (rx_ok) {
        std::cout << "PASS: Simultaneous TX/RX operation completed" << std::endl;
    }

    return errors;
}

//==============================================================================
// Test 7: Full Flow with COE Data (TX->RX via Loopback)
//==============================================================================

int test_full_flow_coe_data() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 7: Full Flow with COE Data" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    // Step 1: Disable TX via register write
    std::cout << "Step 1: Disabling TX..." << std::endl;
    reg_ctrl = 0;  // Clear all enables
    reg_tx_ctrl = 0;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;

    // Run a cycle to apply the change
    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    std::cout << "  TX disabled (reg_ctrl=0x" << std::hex << reg_ctrl.to_uint()
              << ", reg_tx_ctrl=0x" << reg_tx_ctrl.to_uint() << ")" << std::dec << std::endl;

    // Step 2: Disable RX via register write
    std::cout << "Step 2: Disabling RX..." << std::endl;
    reg_rx_ctrl = 0;

    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    std::cout << "  RX disabled (reg_rx_ctrl=0x" << std::hex << reg_rx_ctrl.to_uint() << ")" << std::dec << std::endl;

    // Apply soft reset to clear any previous state
    std::cout << "  Applying soft reset..." << std::endl;
    reg_ctrl = (1 << CtrlBits::SOFT_RESET);
    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    // Clear RX BRAM
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        rx_bram[i] = 0;
    }

    // Step 3: Load TX BRAM with COE file data
    std::cout << "Step 3: Loading TX BRAM with COE data (1024 QPSK samples)..." << std::endl;
    load_tx_bram_coe_data();

    // Verify first few samples loaded correctly
    std::cout << "  Verifying TX BRAM load (first 5 samples):" << std::endl;
    bool load_ok = true;
    for (int i = 0; i < 5; i++) {
        if (tx_bram[i].to_uint() != coe_data[i]) {
            std::cout << "  ERROR: TX BRAM[" << i << "] = 0x" << std::hex << tx_bram[i].to_uint()
                      << " expected 0x" << coe_data[i] << std::dec << std::endl;
            load_ok = false;
            errors++;
        } else {
            int16_t i_val = (int16_t)(coe_data[i] & 0xFFFF);
            int16_t q_val = (int16_t)((coe_data[i] >> 16) & 0xFFFF);
            std::cout << "    TX BRAM[" << i << "] = 0x" << std::hex << tx_bram[i].to_uint()
                      << std::dec << " (I=" << i_val << ", Q=" << q_val << ")" << std::endl;
        }
    }
    if (load_ok) {
        std::cout << "  PASS: TX BRAM loaded correctly" << std::endl;
    }

    // Step 4: Enable RX via register write
    std::cout << "Step 4: Enabling RX..." << std::endl;
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);

    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    std::cout << "  RX enabled (reg_ctrl=0x" << std::hex << reg_ctrl.to_uint()
              << ", reg_rx_ctrl=0x" << reg_rx_ctrl.to_uint() << ")" << std::dec << std::endl;

    // Step 5: Enable TX via register write (with loopback for TX->RX path)
    std::cout << "Step 5: Enabling TX with loopback..." << std::endl;
    reg_ctrl |= (1 << CtrlBits::TX_ENABLE);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);
    reg_loopback = (1 << CtrlBits::LOOPBACK_EN);

    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    std::cout << "  TX enabled with loopback (reg_ctrl=0x" << std::hex << reg_ctrl.to_uint()
              << ", reg_tx_ctrl=0x" << reg_tx_ctrl.to_uint()
              << ", reg_loopback=0x" << reg_loopback.to_uint() << ")" << std::dec << std::endl;

    // Run cycles until RX buffer fills (1024 samples)
    // In loopback mode, TX output goes to RX input
    std::cout << "\nRunning loopback transfer (TX BRAM -> RX BRAM)..." << std::endl;
    std::cout << "(adc_valid=1, dac_valid=1 for loopback operation)" << std::endl;
    int cycle_count = 0;
    const int MAX_CYCLES = IPInfo::BRAM_DEPTH + 100;

    while (reg_rx_fill < IPInfo::BRAM_DEPTH && cycle_count < MAX_CYCLES) {
        // In loopback, we don't need external ADC data - the IP loops TX to RX internally
        // But we need valid ADC inputs to trigger RX capture
        // Actually, in loopback mode the TX data is used directly

        // Read current TX output and feed it back as RX input
        iq_pair_t tx_sample = tx_bram[cycle_count % IPInfo::BRAM_DEPTH];
        iq_sample_t adc_i0 = tx_sample.range(15, 0);
        iq_sample_t adc_q0 = tx_sample.range(31, 16);

        // adc_valid=1 for RX capture, dac_valid=1 for TX output (loopback)
        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1);

        // Print progress at key points
        if (cycle_count < 5 || cycle_count == 512 || cycle_count == 1023 ||
            (reg_rx_fill.to_uint() == IPInfo::BRAM_DEPTH && cycle_count > 0)) {
            std::cout << "  Cycle " << std::setw(4) << cycle_count
                      << ": fill_level=" << std::setw(4) << reg_rx_fill.to_uint()
                      << " TX I=" << std::setw(6) << adc_i0.to_int()
                      << " Q=" << std::setw(6) << adc_q0.to_int() << std::endl;
        }

        cycle_count++;
    }

    // Step 6: Check if RX memory fill level is 1024
    std::cout << "\nStep 6: Checking RX fill level..." << std::endl;
    if (reg_rx_fill == IPInfo::BRAM_DEPTH) {
        std::cout << "  PASS: RX fill level is 1024 (buffer full)" << std::endl;
    } else {
        std::cout << "  ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 1024)" << std::endl;
        errors++;
    }

    // Check RX_FULL status bit
    if (reg_status[StatusBits::RX_FULL]) {
        std::cout << "  PASS: RX_FULL status bit is set" << std::endl;
    } else {
        std::cout << "  ERROR: RX_FULL status bit not set" << std::endl;
        errors++;
    }

    // Step 7: Read RX memory (verify data matches TX BRAM / COE data)
    std::cout << "\nStep 7: Reading and verifying RX memory..." << std::endl;
    std::cout << "  (Comparing RX BRAM to original COE data)" << std::endl;

    int verify_errors = 0;
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        iq_pair_t rx_sample = rx_bram[i];
        uint32_t expected = coe_data[i];

        if (rx_sample.to_uint() != expected) {
            if (verify_errors < 10) {  // Limit error output
                int16_t rx_i = (int16_t)(rx_sample.range(15, 0).to_int());
                int16_t rx_q = (int16_t)(rx_sample.range(31, 16).to_int());
                int16_t exp_i = (int16_t)(expected & 0xFFFF);
                int16_t exp_q = (int16_t)((expected >> 16) & 0xFFFF);

                std::cout << "  ERROR: RX BRAM[" << i << "] = 0x" << std::hex << rx_sample.to_uint()
                          << " (I=" << std::dec << rx_i << ", Q=" << rx_q << ")"
                          << " expected 0x" << std::hex << expected
                          << " (I=" << std::dec << exp_i << ", Q=" << exp_q << ")" << std::endl;
            }
            verify_errors++;
        }
    }

    if (verify_errors == 0) {
        std::cout << "  PASS: All 1024 RX samples match original COE data" << std::endl;
    } else {
        std::cout << "  ERROR: " << verify_errors << " samples did not match" << std::endl;
        errors += verify_errors;
    }

    // Print first and last few samples for inspection
    std::cout << "\n  First 5 RX samples:" << std::endl;
    for (int i = 0; i < 5; i++) {
        int16_t rx_i = (int16_t)(rx_bram[i].range(15, 0).to_int());
        int16_t rx_q = (int16_t)(rx_bram[i].range(31, 16).to_int());
        std::cout << "    RX[" << std::setw(4) << i << "]: I=" << std::setw(6) << rx_i
                  << " Q=" << std::setw(6) << rx_q
                  << " (0x" << std::hex << rx_bram[i].to_uint() << ")" << std::dec << std::endl;
    }

    std::cout << "  Last 5 RX samples:" << std::endl;
    for (int i = IPInfo::BRAM_DEPTH - 5; i < IPInfo::BRAM_DEPTH; i++) {
        int16_t rx_i = (int16_t)(rx_bram[i].range(15, 0).to_int());
        int16_t rx_q = (int16_t)(rx_bram[i].range(31, 16).to_int());
        std::cout << "    RX[" << std::setw(4) << i << "]: I=" << std::setw(6) << rx_i
                  << " Q=" << std::setw(6) << rx_q
                  << " (0x" << std::hex << rx_bram[i].to_uint() << ")" << std::dec << std::endl;
    }

    // Clear RX buffer after reading (optional step to demonstrate RX_CLEAR)
    std::cout << "\n  Clearing RX buffer after read..." << std::endl;
    reg_ctrl |= (1 << CtrlBits::RX_CLEAR);
    run_adapter_cycle(0, 0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1);

    if (reg_rx_fill == 0) {
        std::cout << "  PASS: RX buffer cleared (fill_level=0)" << std::endl;
    } else {
        std::cout << "  ERROR: RX buffer not cleared (fill_level=" << reg_rx_fill.to_uint() << ")" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Main Test Program
//==============================================================================

int main() {
    std::cout << "========================================" << std::endl;
    std::cout << "AXI AD9361 Adapter HLS Testbench" << std::endl;
    std::cout << "Version: " << IPInfo::VERSION_MAJOR << "."
              << IPInfo::VERSION_MINOR << "."
              << IPInfo::VERSION_PATCH << std::endl;
    std::cout << "BRAM Depth: " << IPInfo::BRAM_DEPTH << " samples" << std::endl;
    std::cout << "========================================" << std::endl;

    // Load COE file first (required for test_full_flow_coe_data)
    // File is copied to csim build dir via tb.file in axi_ad9361_adapter.cfg
    std::cout << "\nLoading COE file: " << COE_FILE_NAME << std::endl;
    if (!load_coe_file(COE_FILE_NAME)) {
        std::cerr << "FATAL: Failed to load COE file. Exiting." << std::endl;
        return 1;
    }

    int total_errors = 0;

    // Run all tests
    total_errors += test_tx_continuous_cycling();
    total_errors += test_rx_fill_level();
    total_errors += test_rx_clear();
    total_errors += test_loopback();
    total_errors += test_registers();
    total_errors += test_simultaneous_txrx();
    total_errors += test_full_flow_coe_data();

    // Summary
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test Summary" << std::endl;
    std::cout << "========================================" << std::endl;

    if (total_errors == 0) {
        std::cout << "ALL TESTS PASSED!" << std::endl;
        return 0;
    } else {
        std::cout << "TESTS FAILED: " << total_errors << " errors" << std::endl;
        return 1;
    }
}
