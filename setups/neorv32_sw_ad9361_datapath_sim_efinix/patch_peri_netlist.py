#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# patch_peri_netlist.py — stage the Efinix periphery simulation netlist with
# the LVDS FASTCLK connections the official models need.
#
# Vendor model/exporter gap (Efinity 2026.1): for x2 half-rate SERDES lanes
# the Interface Designer's design check says "Deserialization width 2 only
# requires the parallel clock name", and the exported simulation netlist
# accordingly leaves FASTCLK unconnected — but the official EFX_LVDS_RX_V2 /
# EFX_LVDS_TX_V2 models shift their (de)serializers EXCLUSIVELY on FASTCLK
# (both edges in half-rate mode). With FASTCLK floating, the deserializer
# never shifts: RX words stay 0, the AD9361 delineation sees a stuck frame,
# and the loopback test hangs.
#
# For width 2 specifically the models bypass the shift register and use a
# dedicated DDR path clocked by FASTCLK (capture on both FASTCLK edges,
# output word registered once per FASTCLK period) -- i.e. for the x2
# half-rate DDIO configuration FASTCLK IS the DDR capture clock and must
# run at the parallel rate: FASTCLK = SLOWCLK reproduces exactly the
# hardware DDIO behavior (word[0] = rising-edge sample, word[1] = the
# following falling-edge sample, presented on the next SLOWCLK edge).
# This is a SIMULATION-ONLY transform of a build product: the synthesized
# periphery keeps the DRC-recommended parallel-clock-only setting.
#
# Usage: patch_peri_netlist.py <in_netlist.v> <out_netlist.v>
# ------------------------------------------------------------------------------

import re
import sys


def patch(text):
    out = []
    pos = 0
    n_patched = 0
    # every LVDS model instance: parameter block ") name(" ... ");"
    for m in re.finditer(
            r'EFX_LVDS_(?:RX|TX)_V\d+\s*#\([^;]*?\)\s*\S+\s*\(([^;]*?)\);',
            text, re.S):
        body = m.group(1)
        if ".FASTCLK" in body:
            continue
        slow = re.search(r'\.SLOWCLK\s*\(\s*([^)]+?)\s*\)', body)
        if not slow:
            continue  # e.g. the GCLK-mode rx_clk_in lane (no SERDES)
        insert_at = m.start(1)
        out.append(text[pos:insert_at])
        out.append(f"\n\t.FASTCLK ( {slow.group(1)} ),")
        out.append(body)
        pos = m.end(1)
        n_patched += 1
    out.append(text[pos:])
    return "".join(out), n_patched


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src) as f:
        text = f.read()
    patched, n = patch(text)
    with open(dst, "w") as f:
        f.write(patched)
    print(f"patched {n} LVDS lane instances (FASTCLK <- SLOWCLK) -> {dst}")
    if n == 0:
        print("WARNING: no instances patched - netlist format changed?")
        sys.exit(1)


if __name__ == "__main__":
    main()
