#!/usr/bin/env python3
"""Pack a Yosys write_json netlist into a 74HC DIP package BOM.

SSI cells from tech/hc/hc_ssi.lib are binned into packages (4 NANDs per HC00,
2 FFs per HC74, ...).  Preserved hierarchy modules map to MSI packages:

  mux8 / hc151  → 1 × HC151
  hc259         → 1 × HC259
  ctl_write     → 2 × HC165
  hc164         → 1 × HC164
  hc165         → 1 × HC165

Usage: pack.py build/synth_<top>.json
"""
from __future__ import annotations

import json
import math
import sys
from collections import Counter

# Liberty cell name → (package, gates_per_package)
SSI = {
    "HC00_NAND2": ("HC00", 4),
    "HC02_NOR2": ("HC02", 4),
    "HC04_INV": ("HC04", 6),
    "HC08_AND2": ("HC08", 4),
    "HC32_OR2": ("HC32", 4),
    "HC74_DFF": ("HC74", 2),
    "HC74_DFF_NCLR": ("HC74", 2),
    "HC74_DFF_NPRE": ("HC74", 2),
    "HC74_DFF_NCLR_NPRE": ("HC74", 2),
}

# Module type kept hierarchical → package count to add per instance
MSI = {
    "mux8": Counter({"HC151": 1}),
    "hc151": Counter({"HC151": 1}),
    "hc259": Counter({"HC259": 1}),
    "ctl_write": Counter({"HC165": 2}),
    "hc164": Counter({"HC164": 1}),
    "hc165": Counter({"HC165": 1}),
    "hc393": Counter({"HC393": 1}),
    "hc4040": Counter({"HC4040": 1}),
    "hc163": Counter({"HC163": 1}),
    "hc175": Counter({"HC175": 1}),
    "hc670": Counter({"HC670": 1}),
    "hc174": Counter({"HC174": 1}),
    "hc157": Counter({"HC157": 1}),
    "hc138": Counter({"HC138": 1}),
    # Hand BOM for the shared register (register.md §4), ≈ 15 packages.
    # HC174 is 2 latches (PORT, SRC) plus 3 for the parallel mirror of the
    # store: the '670 has one addressed read port, so the marker cannot read
    # four digits off it at once and dig_r has to shadow it.
    "pulse_reg": Counter({
        "HC393": 1, "HC151": 1, "HC175": 1, "HC86": 1,
        "HC4040": 1, "HC74": 2, "HC163": 1, "HC670": 1,
        "HC174": 5, "HC08": 1,
    }),
    # Hand BOM for mini-marker core without the register (mvp.md §2 sketch).
    # The write queue is four 15-bit slots, which is four '670s and a pointer
    # pair, not the one '670 this entry used to claim.
    "mini_core": Counter({
        "HC393": 1, "HC151": 1, "HC74": 3, "HC157": 2,
        "HC163": 1, "HC138": 1, "HC08": 2, "HC244": 1,
        "HC670": 4,
    }),
    # Hand BOM for the nanomarker's three-bit register (nano-marker.md §3).
    # Against pulse_reg: no '163 (the count is half the '393), no '670 and no
    # mirror (the store is six bits in a '174 and reads out in parallel), no
    # SRC latch.  One more '74 for the wrap FF the three-bit count needs.
    "nano_reg": Counter({
        "HC393": 1, "HC151": 1, "HC175": 1, "HC86": 1,
        "HC4040": 1, "HC74": 3, "HC174": 2, "HC08": 1,
    }),
    # Hand BOM for the nanomarker core without the register (nano-marker.md
    # §4).  Against mini_core: no write queue at all, and one '174 for the far
    # end of a pair write.
    "nano_core": Counter({
        "HC393": 1, "HC151": 1, "HC74": 2, "HC157": 2,
        "HC163": 1, "HC138": 1, "HC08": 2, "HC244": 1,
        "HC174": 1,
    }),
}

# Partial-package MSI: count instances, then ceil into packages
MSI_PART = {
    "hc74_dff": ("HC74", 2),    # 2 FFs per HC74
    "hc86_xor2": ("HC86", 4),   # 4 XOR per HC86
}

# Preferred print order for the BOM table
ORDER = [
    "HC00", "HC02", "HC04", "HC08", "HC32", "HC74", "HC86",
    "HC138", "HC151", "HC157", "HC163", "HC164", "HC165", "HC174", "HC175",
    "HC244", "HC259", "HC393", "HC4040", "HC670",
]


# Match both plain and $paramod$…\name elaborations
def msi_key(t: str) -> str | None:
    if t in MSI:
        return t
    if t in MSI_PART:
        return t
    # Yosys paramod: $paramod$<hash>\pulse_reg
    if "\\" in t:
        base = t.rsplit("\\", 1)[-1]
        if base in MSI:
            return base
        if base in MSI_PART:
            return base
    return None


def walk(mod: dict, modules: dict, ssi: Counter, msi: Counter,
         part: Counter, skip: set[str]) -> None:
    """Accumulate SSI cells and MSI instances under mod (not descending into MSI)."""
    for cell in mod.get("cells", {}).values():
        t = cell.get("type", "")
        key = msi_key(t)
        if key is not None and key in MSI:
            msi.update(MSI[key])
            continue
        if key is not None and key in MSI_PART:
            part[key] += 1
            continue
        if t in SSI:
            ssi[t] += 1
            continue
        if t in modules and t not in skip:
            walk(modules[t], modules, ssi, msi, part, skip)


def pack_ssi(ssi: Counter) -> Counter:
    """Bin gate/FF cells into whole packages (ceil)."""
    gates: Counter = Counter()
    per: dict[str, int] = {}
    for cell, n in ssi.items():
        pkg, gpp = SSI[cell]
        gates[pkg] += n
        per[pkg] = gpp
    out: Counter = Counter()
    for pkg, n in gates.items():
        out[pkg] = math.ceil(n / per[pkg])
    return out


def pack_part(part: Counter) -> Counter:
    gates: Counter = Counter()
    per: dict[str, int] = {}
    for cell, n in part.items():
        pkg, gpp = MSI_PART[cell]
        gates[pkg] += n
        per[pkg] = gpp
    return Counter({pkg: math.ceil(n / per[pkg]) for pkg, n in gates.items()})


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} build/synth_<top>.json", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)

    modules = data["modules"]
    top_name = None
    for name, mod in modules.items():
        attrs = mod.get("attributes", {})
        if attrs.get("top") in (1, "1", True):
            top_name = name
            break
    if top_name is None:
        skip = set(MSI) | set(MSI_PART)
        candidates = [n for n in modules if n not in skip and not n.startswith("$")]
        if not candidates:
            print("no top module found", file=sys.stderr)
            return 1
        top_name = max(candidates, key=lambda n: len(modules[n].get("cells", {})))

    ssi: Counter = Counter()
    msi: Counter = Counter()
    part: Counter = Counter()
    skip = set(MSI) | set(MSI_PART)
    walk(modules[top_name], modules, ssi, msi, part, skip)
    pkgs = pack_ssi(ssi)
    pkgs.update(msi)
    pkgs.update(pack_part(part))

    print(f"top: {top_name}")
    print(f"source: {path}")
    print()
    print("SSI cells (pre-pack):")
    if ssi:
        for cell, n in sorted(ssi.items()):
            print(f"  {cell:24s} {n:6d}")
    else:
        print("  (none)")
    print()
    print("MSI instances:")
    raw_msi: Counter = Counter()

    def count_msi(mod: dict) -> None:
        for cell in mod.get("cells", {}).values():
            t = cell.get("type", "")
            key = msi_key(t)
            if key is not None:
                raw_msi[key] += 1
            elif t in modules and msi_key(t) is None and t not in skip:
                count_msi(modules[t])

    count_msi(modules[top_name])
    if raw_msi:
        for t, n in sorted(raw_msi.items()):
            if t in MSI:
                bill = ", ".join(f"{c}×{p}" for p, c in MSI[t].items())
            else:
                pkg, gpp = MSI_PART[t]
                bill = f"{pkg} (÷{gpp})"
            print(f"  {t:24s} {n:6d}  → {bill}")
    else:
        print("  (none)")
    print()
    print("Package BOM:")
    print(f"  {'part':8s} {'qty':>6s}")
    total = 0
    seen = set()
    for part_name in ORDER:
        if part_name in pkgs:
            q = pkgs[part_name]
            print(f"  {part_name:8s} {q:6d}")
            total += q
            seen.add(part_name)
    for part_name, q in sorted(pkgs.items()):
        if part_name not in seen:
            print(f"  {part_name:8s} {q:6d}")
            total += q
    print(f"  {'TOTAL':8s} {total:6d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
