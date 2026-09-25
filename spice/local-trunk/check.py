#!/usr/bin/env python3
"""Score spice/local-trunk: the local highway trunk's wire, one direction.

For each driver corner and length, at the far end, through a 74HC14 at three
threshold corners (NXP 74HC14, VCC 4.5 V: VT+ 1.7 / 2.38 / 3.15, VT- 0.9 /
1.4 / 2.0, min / typ / max):

  HCLK       exactly one Schmitt edge per clock edge.  Anything more clocks
             the receive counter twice (local_trunk.v's '163 and '259s) and
             every channel after it lands on the wrong port
  C, TX_CLK  sampled at the far HCLK's fall, as the '259s and the quarter
             '74 do: the value must be the one sent for that cell, and the
             margin to the nearest C or TX_CLK edge either side is reported
  clamp      peak current in the far input's upper clamp, against the
             74HC's 20 mA absolute maximum

Exit status is non-zero if any corner double-clocks, samples a wrong value,
leaves less than MIN_MARGIN either side, or drives a clamp past 20 mA.
"""
import sys
from pathlib import Path
import numpy as np

OUT = Path(__file__).parent / 'out'
CELL = 1953.125e-9
VCC = 5.0
MIN_MARGIN = 200e-9          # a '259's setup and hold are ~25 ns; leave a wide berth
CLAMP_MAX = 20e-3
CORNERS = {'min': (1.7, 0.9), 'typ': (2.38, 1.4), 'max': (3.15, 2.0)}
RS = (25, 50)
LENS = ('0.5', '2', '5', '10', '30', '100')


def schmitt(v, vtp, vtn):
    """The '14's output (non-inverted here), and the sample indices of each edge."""
    out = np.empty(len(v), dtype=bool)
    s = v[0] > vtp
    for i, x in enumerate(v):
        if s and x < vtn:
            s = False
        elif not s and x > vtp:
            s = True
        out[i] = s
    edges = np.flatnonzero(np.diff(out.astype(np.int8)))
    return out, edges + 1


def score(path, vtp, vtn):
    d = np.loadtxt(path, skiprows=1)
    t, hf, cf, kf, idc = d[:, 0], d[:, 2], d[:, 3], d[:, 4], d[:, 5]
    h, he = schmitt(hf, vtp, vtn)
    c, ce = schmitt(cf, vtp, vtn)
    k, ke = schmitt(kf, vtp, vtn)

    # HCLK: the sender's edges are at n * CELL/2.  Every far edge must be
    # the only one within a half cell of its predecessor's successor.
    gaps = np.diff(t[he])
    double = int(np.sum(gaps < CELL / 4))

    # C and TX_CLK sampled at the far HCLK's falls.  Fall n (n = 0, 1, ...)
    # is mid-cell of cell n: C was sent high in even cells, TX_CLK high in
    # cells 0-3 of each eight.
    falls = he[~h[he]]
    wrong, margin = 0, np.inf
    tc, tk = t[ce], t[ke]
    for i in falls:
        ts = t[i]
        # flight is under a cell even at 100 m (520 ns): the sample belongs
        # to the cell the SENDER was in half a cell plus the flight earlier
        n = int(np.round((ts - CELL / 2 - 5.2e-9 * float(path.name.split('_l')[1])) / CELL))
        if n < 0:
            continue
        if c[i] != (n % 2 == 0) or k[i] != ((n % 8) < 4):
            wrong += 1
        for te in (tc, tk):
            if len(te):
                margin = min(margin, np.min(np.abs(te - ts)))
    return double, wrong, margin, float(np.max(idc)), float(np.max(hf)), float(np.min(hf))


def main():
    bad = 0
    print(f'{"rout":>4} {"len m":>6} {"corner":>6} {"dbl":>4} {"wrong":>5} '
          f'{"margin ns":>9} {"clamp mA":>8} {"peak V":>7} {"min V":>6}')
    for r in RS:
        for ln in LENS:
            p = OUT / f'cable_r{r}_l{ln}'
            if not p.exists():
                print(f'{r:>4} {ln:>6}   missing: {p.name}')
                bad += 1
                continue
            for name, (vtp, vtn) in CORNERS.items():
                dbl, wrong, m, ic, pk, lo = score(p, vtp, vtn)
                ok = dbl == 0 and wrong == 0 and m >= MIN_MARGIN and ic <= CLAMP_MAX
                bad += not ok
                print(f'{r:>4} {ln:>6} {name:>6} {dbl:>4} {wrong:>5} {m * 1e9:>9.0f} '
                      f'{ic * 1e3:>8.1f} {pk:>7.2f} {lo:>6.2f}  {"ok" if ok else "FAIL"}')
    print('PASS' if bad == 0 else f'FAIL: {bad} corner(s)')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
