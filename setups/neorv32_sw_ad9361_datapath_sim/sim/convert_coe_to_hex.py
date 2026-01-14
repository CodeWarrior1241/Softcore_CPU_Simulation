#!/usr/bin/env python3
"""
Convert COE file to plain hex format for Verilog $readmemh

COE file format:
  memory_initialization_radix=16;
  memory_initialization_vector=
  DEADBEEF,
  12345678,
  ...

Output hex file format (no header, no commas):
  DEADBEEF
  12345678
  ...
"""

import sys
import os

def convert_coe_to_hex(coe_file, hex_file):
    """Convert COE file to plain hex format."""

    with open(coe_file, 'r') as f:
        content = f.read()

    # Find the start of the data (after memory_initialization_vector=)
    marker = 'memory_initialization_vector='
    start_idx = content.find(marker)
    if start_idx == -1:
        print(f"Error: Could not find '{marker}' in {coe_file}")
        return False

    # Extract the data portion
    data_str = content[start_idx + len(marker):]

    # Parse hex values (comma or newline separated)
    hex_values = []
    for line in data_str.split('\n'):
        # Remove comments
        if ';' in line:
            line = line[:line.index(';')]

        # Split by comma and clean up
        parts = line.split(',')
        for part in parts:
            value = part.strip().upper()
            if value and all(c in '0123456789ABCDEF' for c in value):
                hex_values.append(value)

    # Write to output file
    with open(hex_file, 'w') as f:
        for value in hex_values:
            f.write(value + '\n')

    print(f"Converted {len(hex_values)} values from {coe_file} to {hex_file}")
    return True

if __name__ == '__main__':
    # Default file paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    coe_file = os.path.join(script_dir, 'qpsk_bram_init.coe')
    hex_file = os.path.join(script_dir, 'qpsk_bram_data.hex')

    # Allow command line override
    if len(sys.argv) >= 2:
        coe_file = sys.argv[1]
    if len(sys.argv) >= 3:
        hex_file = sys.argv[2]

    success = convert_coe_to_hex(coe_file, hex_file)
    sys.exit(0 if success else 1)
