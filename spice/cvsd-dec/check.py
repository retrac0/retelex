#!/usr/bin/env python3
"""Score spice/cvsd-dec loopback: encoder Y, decoder Y, recon vs source."""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'sim'))

RATE = 64000
T = 1 / RATE
OUT = Path(__file__).parent / 'out' / 'loop'
SKIP = int(0.010 * RATE)


def load_loop(path):
    """wrdata time audio y_enc y_dec audio_out bit syl_enc syl_dec → 8 vectors."""
    d = np.loadtxt(path)
    # pairs (t, val) per vector
    return {
        't': d[:, 0],
        'audio': d[:, 3],
        'y_enc': d[:, 5],
        'y_dec': d[:, 7],
        'audio_out': d[:, 9],
        'bit': d[:, 11],
        'syl_enc': d[:, 13],
        'syl_dec': d[:, 15],
    }


def sinad_db(ref, est):
    g = np.dot(ref, est) / max(np.dot(est, est), 1e-30)
    err = ref - g * est
    return 10 * np.log10(np.dot(ref, ref) / max(np.dot(err, err), 1e-30)), g


def sinad_aligned(ref, est, max_lag=64):
    """Gain-matched SINAD after integer-sample delay of est."""
    best = (-1e9, 0, 0)
    for lag in range(max_lag + 1):
        if lag == 0:
            r, e = ref, est
        else:
            r, e = ref[lag:], est[:-lag]
        sn, g = sinad_db(r, e)
        if sn > best[0]:
            best = (sn, g, lag)
    return best


def main():
    if not OUT.exists():
        print(f'missing {OUT} — run: make loop', file=sys.stderr)
        return 1
    w = load_loop(OUT)
    t = w['t']
    nbits = int(t[-1] * RATE) - 2
    mid = 7.8125e-6 + np.arange(nbits) * T + 0.5 * T
    xs = np.interp(mid, t, w['audio'])
    ye = np.interp(mid, t, w['y_enc'])
    yd = np.interp(mid, t, w['y_dec'])
    ao = np.interp(mid, t, w['audio_out'])

    print(f'CVSD decoder A loopback — {t[-1]*1e3:.1f} ms, skip {SKIP} bits\n')
    print(f'{"path":<28} {"SINAD":>8} {"corr":>7} {"gain":>7}')
    rows = [
        ('encoder Y vs source', xs, ye, False),
        ('decoder Y vs source', xs, yd, False),
        ('decoder Y vs enc Y', ye, yd, False),
        ('recon AUDIO vs source', xs, ao, True),
    ]
    for label, ref, est, align in rows:
        if align:
            sn, g, lag = sinad_aligned(ref[SKIP:], est[SKIP:])
            corr = float(np.corrcoef(ref[SKIP + lag:], est[SKIP:-lag] if lag else est[SKIP:])[0, 1])
            print(f'{label:<28} {sn:7.2f}dB {corr:7.3f} {g:7.3f}  (lag {lag})')
        else:
            sn, g = sinad_db(ref[SKIP:], est[SKIP:])
            corr = float(np.corrcoef(ref[SKIP:], est[SKIP:])[0, 1])
            print(f'{label:<28} {sn:7.2f}dB {corr:7.3f} {g:7.3f}')

    se = float(np.interp(mid[SKIP:], t, w['syl_enc']).mean())
    sd = float(np.interp(mid[SKIP:], t, w['syl_dec']).mean())
    print(f'\nsyllabic mean  enc {se:.2f} V  dec {sd:.2f} V')
    print('Decoder is type A (no LM311); recon is 3.4 kHz 3rd-order (SPEC.md).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
