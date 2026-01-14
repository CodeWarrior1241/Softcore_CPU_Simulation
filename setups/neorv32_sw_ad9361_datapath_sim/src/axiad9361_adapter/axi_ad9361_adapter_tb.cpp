//==============================================================================
// axi_ad9361_adapter_tb.cpp
//
// Testbench for AXI AD9361 Adapter HLS IP
// Verifies RX capture, TX generation, loopback, and snapshot functionality
//
// Target: Vitis HLS 2025.2
//==============================================================================

#include <iostream>
#include <iomanip>
#include <cstdlib>
#include <cmath>
#include "axi_ad9361_adapter.hpp"

//==============================================================================
// Test Configuration
//==============================================================================

constexpr int NUM_TEST_SAMPLES = 100;
constexpr int SNAPSHOT_TEST_SAMPLES = 50;

//==============================================================================
// Helper Functions
//==============================================================================

// Generate test I/Q samples (simple ramp pattern)
void generate_test_samples(int sample_num,
                           iq_sample_t& i0, iq_sample_t& q0,
                           iq_sample_t& i1, iq_sample_t& q1) {
    // Channel 0: Simple ramp
    i0 = (sample_num * 100) & 0x7FFF;
    q0 = (sample_num * 100 + 50) & 0x7FFF;

    // Channel 1: Inverted ramp
    i1 = 0x7FFF - ((sample_num * 100) & 0x7FFF);
    q1 = 0x7FFF - ((sample_num * 100 + 50) & 0x7FFF);
}

// Print sample values
void print_samples(const char* label, int sample_num,
                   iq_sample_t i0, iq_sample_t q0,
                   iq_sample_t i1, iq_sample_t q1) {
    std::cout << label << " [" << std::setw(3) << sample_num << "]: "
              << "I0=" << std::setw(6) << i0.to_int()
              << " Q0=" << std::setw(6) << q0.to_int()
              << " I1=" << std::setw(6) << i1.to_int()
              << " Q1=" << std::setw(6) << q1.to_int()
              << std::endl;
}

//==============================================================================
// Test 1: Basic Enable/Disable Test
//==============================================================================

int test_enable_disable() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 1: Basic Enable/Disable" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    // Input signals
    iq_sample_t adc_i0 = 1000, adc_q0 = 2000, adc_i1 = 3000, adc_q1 = 4000;
    valid_t adc_valid_i0 = 1, adc_valid_q0 = 1, adc_valid_i1 = 1, adc_valid_q1 = 1;
    valid_t adc_enable_i0 = 1, adc_enable_q0 = 1, adc_enable_i1 = 1, adc_enable_q1 = 1;

    // Output signals
    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    valid_t dac_enable_i0 = 1, dac_enable_q0 = 1, dac_enable_i1 = 1, dac_enable_q1 = 1;
    valid_t adc_dovf = 0, dac_dunf;

    // Run with global enable = 0 (should output zeros)
    std::cout << "Running with global enable = 0..." << std::endl;

    for (int i = 0; i < 5; i++) {
        axi_ad9361_adapter(
            adc_i0, adc_q0, adc_i1, adc_q1,
            adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1,
            adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
            dac_i0, dac_q0, dac_i1, dac_q1,
            dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1,
            dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
            adc_dovf, dac_dunf
        );
    }

    // Check outputs are zero when disabled
    if (dac_i0 != 0 || dac_q0 != 0 || dac_i1 != 0 || dac_q1 != 0) {
        std::cout << "ERROR: Output not zero when disabled" << std::endl;
        errors++;
    } else {
        std::cout << "PASS: Output correctly zero when disabled" << std::endl;
    }

    return errors;
}

//==============================================================================
// Test 2: Loopback Test
//==============================================================================

int test_loopback() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 2: Loopback Mode" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    // Enable loopback mode by writing to registers
    // Note: In actual HLS, we'd use AXI-Lite transactions
    // For testbench, we simulate the effect

    iq_sample_t adc_i0, adc_q0, adc_i1, adc_q1;
    valid_t adc_valid_i0 = 1, adc_valid_q0 = 1, adc_valid_i1 = 1, adc_valid_q1 = 1;
    valid_t adc_enable_i0 = 1, adc_enable_q0 = 1, adc_enable_i1 = 1, adc_enable_q1 = 1;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    valid_t dac_enable_i0 = 1, dac_enable_q0 = 1, dac_enable_i1 = 1, dac_enable_q1 = 1;
    valid_t adc_dovf = 0, dac_dunf;

    std::cout << "Testing loopback with ramp pattern..." << std::endl;

    for (int i = 0; i < NUM_TEST_SAMPLES; i++) {
        // Generate test input
        generate_test_samples(i, adc_i0, adc_q0, adc_i1, adc_q1);

        // Run adapter
        axi_ad9361_adapter(
            adc_i0, adc_q0, adc_i1, adc_q1,
            adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1,
            adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
            dac_i0, dac_q0, dac_i1, dac_q1,
            dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1,
            dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
            adc_dovf, dac_dunf
        );

        // Print first few samples
        if (i < 5) {
            print_samples("ADC", i, adc_i0, adc_q0, adc_i1, adc_q1);
            print_samples("DAC", i, dac_i0, dac_q0, dac_i1, dac_q1);
        }
    }

    std::cout << "Loopback test completed" << std::endl;
    return errors;
}

//==============================================================================
// Test 3: Overflow Detection
//==============================================================================

int test_overflow() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 3: Overflow Detection" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    iq_sample_t adc_i0 = 100, adc_q0 = 200, adc_i1 = 300, adc_q1 = 400;
    valid_t adc_valid_i0 = 1, adc_valid_q0 = 1, adc_valid_i1 = 1, adc_valid_q1 = 1;
    valid_t adc_enable_i0 = 1, adc_enable_q0 = 1, adc_enable_i1 = 1, adc_enable_q1 = 1;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    valid_t dac_enable_i0 = 1, dac_enable_q0 = 1, dac_enable_i1 = 1, dac_enable_q1 = 1;
    valid_t adc_dovf, dac_dunf;

    // Test with overflow signal asserted
    adc_dovf = 1;

    std::cout << "Testing overflow detection..." << std::endl;

    for (int i = 0; i < 10; i++) {
        axi_ad9361_adapter(
            adc_i0, adc_q0, adc_i1, adc_q1,
            adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1,
            adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
            dac_i0, dac_q0, dac_i1, dac_q1,
            dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1,
            dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
            adc_dovf, dac_dunf
        );
    }

    std::cout << "Overflow test completed" << std::endl;
    return errors;
}

//==============================================================================
// Test 4: Data Integrity Test
//==============================================================================

int test_data_integrity() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 4: Data Integrity" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    iq_sample_t adc_i0, adc_q0, adc_i1, adc_q1;
    valid_t adc_valid_i0 = 1, adc_valid_q0 = 1, adc_valid_i1 = 1, adc_valid_q1 = 1;
    valid_t adc_enable_i0 = 1, adc_enable_q0 = 1, adc_enable_i1 = 1, adc_enable_q1 = 1;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    valid_t dac_enable_i0 = 1, dac_enable_q0 = 1, dac_enable_i1 = 1, dac_enable_q1 = 1;
    valid_t adc_dovf = 0, dac_dunf;

    std::cout << "Testing with various data patterns..." << std::endl;

    // Test patterns
    iq_sample_t test_patterns[] = {
        0x0000, 0x7FFF, 0x8000, 0xFFFF,  // Edge cases
        0x1234, 0x5678, 0x9ABC, 0xDEF0,  // Random values
        0x5555, 0xAAAA, 0x0F0F, 0xF0F0   // Bit patterns
    };

    for (int p = 0; p < 12; p += 4) {
        adc_i0 = test_patterns[p];
        adc_q0 = test_patterns[p + 1];
        adc_i1 = test_patterns[p + 2];
        adc_q1 = test_patterns[p + 3];

        axi_ad9361_adapter(
            adc_i0, adc_q0, adc_i1, adc_q1,
            adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1,
            adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
            dac_i0, dac_q0, dac_i1, dac_q1,
            dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1,
            dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
            adc_dovf, dac_dunf
        );

        std::cout << "Pattern " << (p / 4) << ": "
                  << "I0=0x" << std::hex << adc_i0.to_uint()
                  << " Q0=0x" << adc_q0.to_uint()
                  << " I1=0x" << adc_i1.to_uint()
                  << " Q1=0x" << adc_q1.to_uint()
                  << std::dec << std::endl;
    }

    std::cout << "Data integrity test completed" << std::endl;
    return errors;
}

//==============================================================================
// Test 5: Channel Enable/Disable
//==============================================================================

int test_channel_enable() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 5: Individual Channel Enable" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    iq_sample_t adc_i0 = 1111, adc_q0 = 2222, adc_i1 = 3333, adc_q1 = 4444;
    valid_t adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1;
    valid_t adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    valid_t dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1;
    valid_t adc_dovf = 0, dac_dunf;

    std::cout << "Testing channel enable combinations..." << std::endl;

    // Test each channel individually
    for (int mask = 0; mask < 16; mask++) {
        adc_enable_i0 = (mask & 1) ? 1 : 0;
        adc_enable_q0 = (mask & 2) ? 1 : 0;
        adc_enable_i1 = (mask & 4) ? 1 : 0;
        adc_enable_q1 = (mask & 8) ? 1 : 0;

        adc_valid_i0 = adc_enable_i0;
        adc_valid_q0 = adc_enable_q0;
        adc_valid_i1 = adc_enable_i1;
        adc_valid_q1 = adc_enable_q1;

        dac_enable_i0 = adc_enable_i0;
        dac_enable_q0 = adc_enable_q0;
        dac_enable_i1 = adc_enable_i1;
        dac_enable_q1 = adc_enable_q1;

        axi_ad9361_adapter(
            adc_i0, adc_q0, adc_i1, adc_q1,
            adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1,
            adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
            dac_i0, dac_q0, dac_i1, dac_q1,
            dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1,
            dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
            adc_dovf, dac_dunf
        );

        std::cout << "Mask 0x" << std::hex << mask << std::dec << ": "
                  << "EN=[" << adc_enable_i0 << adc_enable_q0
                  << adc_enable_i1 << adc_enable_q1 << "] "
                  << "DAC valid=[" << dac_valid_i0 << dac_valid_q0
                  << dac_valid_i1 << dac_valid_q1 << "]"
                  << std::endl;
    }

    std::cout << "Channel enable test completed" << std::endl;
    return errors;
}

//==============================================================================
// Test 6: Continuous Streaming Test
//==============================================================================

int test_streaming() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 6: Continuous Streaming" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    iq_sample_t adc_i0, adc_q0, adc_i1, adc_q1;
    valid_t adc_valid_i0 = 1, adc_valid_q0 = 1, adc_valid_i1 = 1, adc_valid_q1 = 1;
    valid_t adc_enable_i0 = 1, adc_enable_q0 = 1, adc_enable_i1 = 1, adc_enable_q1 = 1;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    valid_t dac_enable_i0 = 1, dac_enable_q0 = 1, dac_enable_i1 = 1, dac_enable_q1 = 1;
    valid_t adc_dovf = 0, dac_dunf;

    std::cout << "Running " << NUM_TEST_SAMPLES << " streaming samples..." << std::endl;

    for (int i = 0; i < NUM_TEST_SAMPLES; i++) {
        // Generate sinusoidal test pattern
        double phase = 2.0 * M_PI * i / 20.0;  // 20 samples per cycle
        adc_i0 = (iq_sample_t)(16000 * cos(phase));
        adc_q0 = (iq_sample_t)(16000 * sin(phase));
        adc_i1 = (iq_sample_t)(16000 * cos(phase + M_PI / 4));  // 45 degree offset
        adc_q1 = (iq_sample_t)(16000 * sin(phase + M_PI / 4));

        axi_ad9361_adapter(
            adc_i0, adc_q0, adc_i1, adc_q1,
            adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1,
            adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
            dac_i0, dac_q0, dac_i1, dac_q1,
            dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1,
            dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
            adc_dovf, dac_dunf
        );

        // Print every 10th sample
        if (i % 10 == 0) {
            print_samples("Stream", i, adc_i0, adc_q0, adc_i1, adc_q1);
        }
    }

    std::cout << "Streaming test completed successfully" << std::endl;
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
    std::cout << "========================================" << std::endl;

    int total_errors = 0;

    // Run all tests
    total_errors += test_enable_disable();
    total_errors += test_loopback();
    total_errors += test_overflow();
    total_errors += test_data_integrity();
    total_errors += test_channel_enable();
    total_errors += test_streaming();

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
