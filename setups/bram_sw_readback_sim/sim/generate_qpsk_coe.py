#!/usr/bin/env python3
"""
Generate QPSK BRAM initialization .coe file

This script generates the same QPSK constellation data as sim/iq_bram.vhd
using the same 32-bit LFSR algorithm for pseudo-random symbol and noise generation.

LFSR: 32-bit maximal-length polynomial x^32 + x^22 + x^2 + x + 1
Seed: 0xDEADBEEF
"""

import struct

def lfsr_next(lfsr):
    """32-bit LFSR with polynomial x^32 + x^22 + x^2 + x + 1"""
    # Feedback: bits 31, 21, 1, 0
    fb = ((lfsr >> 31) ^ (lfsr >> 21) ^ (lfsr >> 1) ^ lfsr) & 1
    return ((lfsr << 1) | fb) & 0xFFFFFFFF

def signed_16bit(val):
    """Convert to signed 16-bit value"""
    if val >= 0x8000:
        return val - 0x10000
    return val

def to_unsigned_16bit(val):
    """Convert signed value to unsigned 16-bit representation"""
    if val < 0:
        return val + 0x10000
    return val & 0xFFFF

def generate_qpsk_data(num_samples=1024):
    """
    Generate QPSK IQ samples matching iq_bram.vhd algorithm.

    Args:
        num_samples: Number of 32-bit words (default 1024 for 4KB BRAM)

    Returns:
        List of 32-bit unsigned integers
    """
    lfsr = 0xDEADBEEF
    data = []

    for idx in range(num_samples):
        # Generate pseudo-random symbol (0-3 for QPSK)
        lfsr = lfsr_next(lfsr)
        symbol = lfsr & 0x3

        # QPSK constellation points (Gray-coded)
        # Symbol 00 -> +I, +Q (45 degrees)
        # Symbol 01 -> -I, +Q (135 degrees)
        # Symbol 10 -> +I, -Q (315 degrees)
        # Symbol 11 -> -I, -Q (225 degrees)
        if symbol == 0:
            i_val = 16384
            q_val = 16384
        elif symbol == 1:
            i_val = -16384
            q_val = 16384
        elif symbol == 2:
            i_val = 16384
            q_val = -16384
        else:  # symbol == 3
            i_val = -16384
            q_val = -16384

        # Add AWGN-like noise (+/- 256, ~1.5% of signal amplitude)
        # Use different bit ranges from 32-bit LFSR for I and Q to decorrelate
        lfsr = lfsr_next(lfsr)
        noise_i = (lfsr & 0x1FF) - 256  # bits 8:0
        noise_q = ((lfsr >> 16) & 0x1FF) - 256  # bits 24:16

        i_val = i_val + noise_i
        q_val = q_val + noise_q

        # Clamp to 16-bit signed range
        i_val = max(-32768, min(32767, i_val))
        q_val = max(-32768, min(32767, q_val))

        # Pack into 32-bit word: I in lower 16 bits, Q in upper 16 bits
        i_unsigned = to_unsigned_16bit(i_val)
        q_unsigned = to_unsigned_16bit(q_val)
        iq_word = (q_unsigned << 16) | i_unsigned

        data.append(iq_word)

    return data

def write_coe_file(filename, data):
    """Write data to Xilinx .coe file format"""
    with open(filename, 'w') as f:
        f.write("; QPSK Snapshot BRAM Initialization File\n")
        f.write("; Generated with same algorithm as sim/iq_bram.vhd\n")
        f.write(";\n")
        f.write("; Memory layout:\n")
        f.write(f";   - {len(data)} x 32-bit words ({len(data)*4//1024}KB total)\n")
        f.write(";   - Each word: {Q[31:16], I[15:0]} signed 16-bit values\n")
        f.write(";   - QPSK constellation at +/- 16384 with +/- 256 noise\n")
        f.write(";\n")
        f.write("; LFSR: 32-bit maximal-length polynomial x^32 + x^22 + x^2 + x + 1\n")
        f.write("; Seed: 0xDEADBEEF\n")
        f.write("\n")
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")

        for i, word in enumerate(data):
            if i < len(data) - 1:
                f.write(f"{word:08X},\n")
            else:
                f.write(f"{word:08X};\n")

def main():
    # Generate 1024 samples for 4KB BRAM (1024 x 32-bit = 4096 bytes)
    num_samples = 1024

    print(f"Generating {num_samples} QPSK IQ samples...")
    data = generate_qpsk_data(num_samples)

    # Write .coe file
    coe_filename = "qpsk_bram_init.coe"
    write_coe_file(coe_filename, data)
    print(f"Written to: {coe_filename}")

    # Print first few samples for verification
    print("\nFirst 8 samples (hex):")
    for i in range(min(8, len(data))):
        word = data[i]
        i_val = word & 0xFFFF
        q_val = (word >> 16) & 0xFFFF
        # Convert to signed
        if i_val >= 0x8000:
            i_val -= 0x10000
        if q_val >= 0x8000:
            q_val -= 0x10000
        print(f"  [{i}] 0x{word:08X}  I={i_val:+6d}  Q={q_val:+6d}")

if __name__ == "__main__":
    main()
