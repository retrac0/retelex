#!/usr/bin/env python3
"""Score spice/mf2-ami loopback and 50 V surge runs."""
from pathlib import Path
import numpy as np

OUT = Path(__file__).parent / 'out'
CELL = 3.90625e-6


def load_wrdata(path, names):
    d = np.loadtxt(path)
    assert d.shape[1] == 2 * len(names), (d.shape, names)
    t = d[:, 0]
    return t, {n: d[:, 2 * i + 1] for i, n in enumerate(names)}


def sample_on_strobe(t, strobe, bit, b, t_min=15e-6):
    rise = np.where(np.diff((strobe > 2.5).astype(int)) == 1)[0]
    rise = rise[t[rise] > t_min]
    rec = (bit[rise] > 2.5).astype(int)
    src = (b[rise] > 2.5).astype(int)
    return src, rec


def check_loop():
    t, v = load_wrdata(OUT / 'loop', 'time b ep em tip mark bit strobe'.split())
    tip_p = np.percentile(np.abs(v['tip']), 99)
    assert tip_p > 3.0, f'tip amplitude too small: {tip_p}'
    src, rec = sample_on_strobe(t, v['strobe'], v['bit'], v['b'])
    assert len(rec) >= 16, f'too few strobes: {len(rec)}'
    # all-ones region then pattern — compare with ±1 sample shift
    best = 0.0
    for s in range(-1, 2):
        a = rec[max(s, 0):len(rec) + min(s, 0)]
        b = src[max(-s, 0):len(src) + min(-s, 0)]
        m = min(len(a), len(b))
        if m >= 12:
            best = max(best, float(np.mean(a[:m] == b[:m])))
    print(f'loop: tip_p99={tip_p:.2f} V  strobes={len(rec)}  bit_match={best:.3f}')
    assert best >= 0.90, f'bit match {best} < 0.90'
    # EP/EM mutually exclusive
    both = (v['ep'] > 2.5) & (v['em'] > 2.5)
    assert both.mean() < 0.01, 'EP and EM overlap'
    print('loop: PASS')


def check_surge():
    t, v = load_wrdata(OUT / 'surge', 'time tip ring mark bit vdd'.split())
    # during surge window tip may hit TVS; after 50 µs ones must recover
    post = t > 80e-6
    tip_p = np.percentile(np.abs(v['tip'][post]), 99)
    vdd_ok = np.max(np.abs(v['vdd'][post] - 5)) < 0.5
    bits = v['bit'][post]
    ones = (bits > 2.5).mean()
    print(f'surge: post tip_p99={tip_p:.2f} V  Vdd stable={vdd_ok}  bit-high={ones:.2f}')
    assert tip_p > 3.0, 'no AMI after surge'
    assert vdd_ok, 'Vdd collapsed'
    assert ones > 0.7, 'decoder not recovering ones after surge'
    print('surge: PASS')


def main():
    check_loop()
    check_surge()
    print('ALL PASS')


if __name__ == '__main__':
    main()
