#!/usr/bin/env python3
"""
QPSK Simulation Time Calculator

Calculates the minimum simulation time required to transmit all IQ samples
over UART at a given baud rate.

Usage:
    python calculate_sim_time.py [--baud RATE] [--samples NUM]

Arguments:
    --baud RATE     UART baud rate (default: 115200)
    --samples NUM   Number of IQ samples (default: 1024)
"""

import sys

def calculate_sim_time(baud_rate=115200, num_samples=1024):
    """
    Calculate minimum simulation time for QPSK IQ data transmission.

    Args:
        baud_rate: UART baud rate in bits per second
        num_samples: Number of IQ samples to transmit

    Returns:
        dict with timing breakdown
    """
    # UART parameters (8N1 = 10 bits per byte)
    bits_per_byte = 10  # 1 start + 8 data + 1 stop

    # Data sizes
    ascii_responses = (
        len('rf_disabled\n') +
        len('rf_enabled\n') +
        len('snapshot_enabled\n')
    )
    iq_data_bytes = num_samples * 4  # 4 bytes per IQ sample (I16 + Q16)
    total_bytes = ascii_responses + iq_data_bytes
    total_bits = total_bytes * bits_per_byte

    # UART transmission time
    uart_time_sec = total_bits / baud_rate
    uart_time_ms = uart_time_sec * 1000

    # Overhead estimates
    boot_time_ms = 10       # CPU boot and initialization
    cmd_delay_ms = 30       # Delays between testbench commands (3 x 10ms)
    processing_ms = 20      # CPU time to read BRAM and prepare data

    total_min_ms = uart_time_ms + boot_time_ms + cmd_delay_ms + processing_ms
    recommended_ms = total_min_ms * 1.2  # 20% safety margin

    return {
        'baud_rate': baud_rate,
        'num_samples': num_samples,
        'ascii_bytes': ascii_responses,
        'iq_bytes': iq_data_bytes,
        'total_bytes': total_bytes,
        'total_bits': total_bits,
        'uart_time_ms': uart_time_ms,
        'boot_time_ms': boot_time_ms,
        'cmd_delay_ms': cmd_delay_ms,
        'processing_ms': processing_ms,
        'total_min_ms': total_min_ms,
        'recommended_ms': recommended_ms
    }


def print_timing(timing):
    """Print timing breakdown in a formatted table."""
    print("=" * 50)
    print("QPSK Simulation Time Calculator")
    print("=" * 50)
    print()
    print(f"UART Configuration:")
    print(f"  Baud rate:        {timing['baud_rate']:,} bps")
    print(f"  Bits per byte:    10 (8N1)")
    print()
    print(f"Data Sizes:")
    print(f"  ASCII responses:  {timing['ascii_bytes']} bytes")
    print(f"  IQ data:          {timing['iq_bytes']:,} bytes ({timing['num_samples']} samples x 4)")
    print(f"  Total:            {timing['total_bytes']:,} bytes ({timing['total_bits']:,} bits)")
    print()
    print(f"Time Breakdown:")
    print(f"  UART transmission: {timing['uart_time_ms']:.1f} ms")
    print(f"  CPU boot:          {timing['boot_time_ms']:.0f} ms")
    print(f"  Command delays:    {timing['cmd_delay_ms']:.0f} ms")
    print(f"  Processing:        {timing['processing_ms']:.0f} ms")
    print(f"  " + "-" * 30)
    print(f"  Minimum total:     {timing['total_min_ms']:.0f} ms")
    print()
    print(f"RECOMMENDED: --time {int(timing['recommended_ms'])}ms")
    print("=" * 50)


def main():
    baud_rate = 115200
    num_samples = 1024

    # Parse arguments
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == '--baud' and i + 1 < len(args):
            baud_rate = int(args[i + 1])
            i += 2
        elif args[i] == '--samples' and i + 1 < len(args):
            num_samples = int(args[i + 1])
            i += 2
        elif args[i] in ('--help', '-h'):
            print(__doc__)
            return 0
        else:
            print(f"Unknown option: {args[i]}")
            return 1

    timing = calculate_sim_time(baud_rate, num_samples)
    print_timing(timing)
    return 0


if __name__ == '__main__':
    sys.exit(main())
