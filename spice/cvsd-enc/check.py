#!/usr/bin/env python3
"""Score solo spice/cvsd-enc out/{a,b,c} runs.

Y SINAD / corr — breadboard metric: the encoder's own integrator vs source.
"""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'sim'))
import mf8  # noqa: E402

RATE = 64000
T = 1 / RATE
OUT = Path(__file__).parent / 'out'
SKIP = int(0.010 * RATE)

VARIANTS = [
    ('a', 'a breadboard  LM311+TL072+LM13700'),
    ('b', 'b no LM311    TL072 as comparator'),
    ('c', 'c no LM13700  discrete ±Iabc steer'),
    ('d', 'd LM358       Iabc + follower'),
]


def load_solo(path):
    d = np.loadtxt(path)
    return d[:, 0], d[:, 3], d[:, 5], d[:, 7], d[:, 9]


def sinad_db(ref, est):
    g = np.dot(ref, est) / max(np.dot(est, est), 1e-30)
    err = ref - g * est
    return 10 * np.log10(np.dot(ref, ref) / max(np.dot(err, err), 1e-30))


def main():
    print(f'CVSD encoder implementations — solo ngspice runs, skip {SKIP} bits\n')
    print(f'{"variant":<42} {"Y SINAD":>8} {"corr":>6} {"run3":>6} {"syl":>6}')
    for tag, label in VARIANTS:
        path = OUT / tag
        if not path.exists():
            print(f'{label:<42}  (missing — run make {tag})')
            continue
        t, audio, y, bit, syl = load_solo(path)
        nbits = int(t[-1] * RATE) - 2
        mid = 7.8125e-6 + np.arange(nbits) * T + 0.5 * T
        bits = (np.interp(mid, t, bit) > 2.5).astype(np.uint8)
        xs = np.interp(mid, t, audio)
        ys = np.interp(mid, t, y)
        s_y = sinad_db(xs[SKIP:], ys[SKIP:])
        corr = float(np.corrcoef(xs[SKIP:], ys[SKIP:])[0, 1])
        run3 = float(np.mean((bits[SKIP:-2] == bits[SKIP + 1:-1]) &
                             (bits[SKIP + 1:-1] == bits[SKIP + 2:])))
        syl_m = float(np.interp(mid[SKIP:], t, syl).mean())
        print(f'{label:<42} {s_y:7.2f}dB {corr:6.3f} {run3:6.3f} {syl_m:5.2f}V')

    print('''
Verdict:
  A  works — breadboard baseline (circuit-review §2.4 / §4)
  B  fails — TL072 open-loop cannot recover from saturation at 64 kbps
  C  Y tracks (~A) but mirror/switch asymmetry shows up in the bit law
  D  LM358 for both op-amp halves — see score vs A (bias / Vos / slew)

Packages (encoder alone):
  A  LM311 + TL072 + LM13700 + 2×74HC74 + 74HC86 + ¼74HC32 + 2N3906
  B  A minus LM311 (not viable)
  C  A minus LM13700, plus 2×2N3904 + 2 analogue switches
  D  A with LM358 instead of TL072
''')
    return 0


if __name__ == '__main__':
    sys.exit(main())
