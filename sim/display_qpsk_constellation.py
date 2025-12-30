#!/usr/bin/env python3
"""
QPSK Constellation Display Script

Parses the UART log file from NEORV32 simulation and displays the IQ samples
as a QPSK constellation diagram.

Usage:
    python display_qpsk_constellation.py [logfile] [--save filename.png] [--no-display] [--filter]

Arguments:
    logfile         Path to UART log file (default: tb.uart0_rx.log)
    --save FILE     Save plot to file instead of/in addition to displaying
    --no-display    Don't show interactive plot (useful for automated runs)
    --filter        Filter outlier samples far from ideal constellation points
"""

import sys
import struct
import os

def parse_iq_data(filepath):
    """
    Parse IQ samples from UART log file.

    The log file contains ASCII responses followed by binary IQ data:
    - "rf_disabled\n"
    - "rf_enabled\n"
    - "snapshot_enabled\n"
    - 4096 bytes of binary IQ data (1024 samples x 4 bytes each)

    IQ format (little-endian):
    - Bytes 0-1: I value (signed 16-bit)
    - Bytes 2-3: Q value (signed 16-bit)

    Returns:
        tuple: (I_data, Q_data) as lists of integers, or (None, None) on error
    """
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        return None, None

    with open(filepath, 'rb') as f:
        data = f.read()

    # Find the "snapshot_enabled" marker (handle both \n and \r\n line endings)
    marker_lf = b'snapshot_enabled\n'
    marker_crlf = b'snapshot_enabled\r\n'

    marker_pos = data.find(marker_crlf)
    if marker_pos != -1:
        marker = marker_crlf
    else:
        marker_pos = data.find(marker_lf)
        marker = marker_lf

    if marker_pos == -1:
        print("Error: 'snapshot_enabled' marker not found in log file")
        print("The simulation may not have completed the snapshot capture.")
        return None, None

    # Binary IQ data starts immediately after the marker
    iq_start = marker_pos + len(marker)
    iq_data = data[iq_start:]

    # We expect 4096 bytes (1024 samples x 4 bytes)
    expected_bytes = 1024 * 4
    if len(iq_data) < expected_bytes:
        print(f"Warning: Expected {expected_bytes} bytes of IQ data, got {len(iq_data)}")
        print("Proceeding with available data...")

    # Parse IQ samples
    num_samples = min(len(iq_data) // 4, 1024)
    I_data = []
    Q_data = []

    for i in range(num_samples):
        offset = i * 4
        # Little-endian: I_lo, I_hi, Q_lo, Q_hi
        i_val = struct.unpack('<h', iq_data[offset:offset+2])[0]
        q_val = struct.unpack('<h', iq_data[offset+2:offset+4])[0]
        I_data.append(i_val)
        Q_data.append(q_val)

    print(f"Parsed {len(I_data)} IQ samples from {filepath}")
    return I_data, Q_data


def plot_constellation(I_data, Q_data, save_path=None, show_display=True, filter_outliers=False):
    """
    Plot QPSK constellation diagram.

    Args:
        I_data: List of I (in-phase) values
        Q_data: List of Q (quadrature) values
        save_path: Optional path to save the plot
        show_display: Whether to show interactive plot
        filter_outliers: If True, filter samples far from ideal constellation points
    """
    try:
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError:
        print("Error: matplotlib and numpy are required.")
        print("Install with: pip install matplotlib numpy")
        return False

    # Convert to numpy arrays and normalize
    I = np.array(I_data, dtype=float)
    Q = np.array(Q_data, dtype=float)

    # Normalize to unit power
    power = np.mean(I**2 + Q**2)
    if power > 0:
        scale = np.sqrt(power)
        I = I / scale
        Q = Q / scale

    # Optional: Filter outliers (samples far from any ideal constellation point)
    if filter_outliers:
        ideal_amp = 1.0 / np.sqrt(2)
        ideal_points = np.array([
            complex(ideal_amp, ideal_amp),
            complex(-ideal_amp, ideal_amp),
            complex(-ideal_amp, -ideal_amp),
            complex(ideal_amp, -ideal_amp)
        ])
        samples = I + 1j * Q
        # Keep samples within threshold distance of any ideal point
        threshold = 0.4  # Adjust as needed
        mask = np.zeros(len(samples), dtype=bool)
        for ideal in ideal_points:
            mask |= (np.abs(samples - ideal) < threshold)
        I = I[mask]
        Q = Q[mask]
        print(f"Filtered to {len(I)} samples (removed {len(I_data) - len(I)} outliers)")

    # Create figure
    fig, ax = plt.subplots(figsize=(8, 8))

    # Plot received samples
    ax.scatter(I, Q, s=10, c='blue', alpha=0.5, label='Received')

    # Plot ideal QPSK constellation points (normalized)
    ideal_amp = 1.0 / np.sqrt(2)  # ~0.707
    ideal_I = [ideal_amp, -ideal_amp, -ideal_amp, ideal_amp]
    ideal_Q = [ideal_amp, ideal_amp, -ideal_amp, -ideal_amp]
    ax.scatter(ideal_I, ideal_Q, s=200, c='red', marker='x', linewidths=3, label='Ideal')

    # Draw reference lines
    ax.axhline(y=0, color='black', linestyle='--', linewidth=0.5)
    ax.axvline(x=0, color='black', linestyle='--', linewidth=0.5)

    # Draw unit circle
    theta = np.linspace(0, 2*np.pi, 100)
    ax.plot(np.cos(theta), np.sin(theta), 'g--', linewidth=0.5, label='Unit circle')

    # Format plot
    ax.set_xlim(-1.5, 1.5)
    ax.set_ylim(-1.5, 1.5)
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    ax.set_xlabel('In-Phase (I)')
    ax.set_ylabel('Quadrature (Q)')
    ax.set_title(f'QPSK Constellation ({len(I_data)} samples)')
    ax.legend(loc='upper right')

    # Calculate and display metrics
    # Map each point to nearest ideal and calculate EVM
    ideal_points = np.array([complex(i, q) for i, q in zip(ideal_I, ideal_Q)])
    received = I + 1j * Q

    errors = []
    for sample in received:
        distances = np.abs(sample - ideal_points)
        nearest_idx = np.argmin(distances)
        errors.append(sample - ideal_points[nearest_idx])

    errors = np.array(errors)
    evm = np.sqrt(np.mean(np.abs(errors)**2)) / np.sqrt(np.mean(np.abs(ideal_points)**2)) * 100

    # Add EVM text
    ax.text(0.02, 0.98, f'EVM: {evm:.2f}%', transform=ax.transAxes,
            verticalalignment='top', fontsize=10,
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

    plt.tight_layout()

    # Save if requested
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Plot saved to: {save_path}")

    # Show if requested
    if show_display:
        plt.show()

    return True


def main():
    # Default values
    logfile = 'tb.uart0_rx.log'
    save_path = None
    show_display = True
    filter_outliers = False

    # Parse command line arguments
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == '--save' and i + 1 < len(args):
            save_path = args[i + 1]
            i += 2
        elif args[i] == '--no-display':
            show_display = False
            i += 1
        elif args[i] == '--filter':
            filter_outliers = True
            i += 1
        elif args[i] == '--help' or args[i] == '-h':
            print(__doc__)
            return 0
        elif not args[i].startswith('-'):
            logfile = args[i]
            i += 1
        else:
            print(f"Unknown option: {args[i]}")
            print("Use --help for usage information")
            return 1

    # Parse IQ data from log file
    I_data, Q_data = parse_iq_data(logfile)

    if I_data is None or Q_data is None:
        return 1

    if len(I_data) == 0:
        print("Error: No IQ samples found")
        return 1

    # Plot constellation
    if not plot_constellation(I_data, Q_data, save_path, show_display, filter_outliers):
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
