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
}

# Preferred print order for the BOM table
ORDER = [
    "HC00", "HC02", "HC04", "HC08", "HC32", "HC74",
    "HC151", "HC164", "HC165", "HC259",
]


def walk(mod: dict, modules: dict, ssi: Counter, msi: Counter, skip: set[str]) -> None:
    """Accumulate SSI cells and MSI instances under mod (not descending into MSI)."""
    for cell in mod.get("cells", {}).values():
        t = cell.get("type", "")
        if t in MSI:
            msi.update(MSI[t])
            continue
        if t in SSI:
            ssi[t] += 1
            continue
        if t in modules and t not in skip:
            walk(modules[t], modules, ssi, msi, skip)
        # else: input/output/$scopeinfo/blackbox — ignore


def pack_ssi(ssi: Counter) -> Counter:
    """Bin gate/FF cells into whole packages (ceil)."""
    gates: Counter = Counter()  # package → gate count
    per: dict[str, int] = {}
    for cell, n in ssi.items():
        pkg, gpp = SSI[cell]
        gates[pkg] += n
        per[pkg] = gpp
    out: Counter = Counter()
    for pkg, n in gates.items():
        out[pkg] = math.ceil(n / per[pkg])
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} build/synth_<top>.json", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)

    modules = data["modules"]
    # Top = the only module that is not an MSI leaf and has the design name,
    # or the one marked top / the largest.  Prefer explicit attribute.
    top_name = None
    for name, mod in modules.items():
        attrs = mod.get("attributes", {})
        if attrs.get("top") in (1, "1", True):
            top_name = name
            break
    if top_name is None:
        # Yosys sometimes stores top as a module without submodules named after file
        candidates = [n for n in modules if n not in MSI and not n.startswith("$")]
        if not candidates:
            print("no top module found", file=sys.stderr)
            return 1
        top_name = max(candidates, key=lambda n: len(modules[n].get("cells", {})))

    ssi: Counter = Counter()
    msi: Counter = Counter()
    walk(modules[top_name], modules, ssi, msi, skip=set(MSI))
    pkgs = pack_ssi(ssi)
    pkgs.update(msi)

    # Also report raw SSI gate counts for honesty
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
    # Recount raw MSI module instances for the report
    raw_msi: Counter = Counter()

    def count_msi(mod: dict) -> None:
        for cell in mod.get("cells", {}).values():
            t = cell.get("type", "")
            if t in MSI:
                raw_msi[t] += 1
            elif t in modules and t not in MSI:
                count_msi(modules[t])

    count_msi(modules[top_name])
    if raw_msi:
        for t, n in sorted(raw_msi.items()):
            bill = ", ".join(f"{c}×{p}" for p, c in MSI[t].items())
            print(f"  {t:24s} {n:6d}  → {bill}")
    else:
        print("  (none)")
    print()
    print("Package BOM:")
    print(f"  {'part':8s} {'qty':>6s}")
    total = 0
    seen = set()
    for part in ORDER:
        if part in pkgs:
            q = pkgs[part]
            print(f"  {part:8s} {q:6d}")
            total += q
            seen.add(part)
    for part, q in sorted(pkgs.items()):
        if part not in seen:
            print(f"  {part:8s} {q:6d}")
            total += q
    print(f"  {'TOTAL':8s} {total:6d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
