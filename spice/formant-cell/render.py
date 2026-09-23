#!/usr/bin/env python3
"""Render out/loop wrdata decode to out/loop.wav for a quick listen."""
import wave
from pathlib import Path

import numpy as np

OUT = Path(__file__).parent / 'out'
RATE = 16000
SKIP_S = 0.050


def load_wrdata_vecs(path, nvecs):
    d = np.loadtxt(path)
    t = d[:, 0]
    cols = [d[:, 3 + 2 * i] for i in range(nvecs)]
    return t, cols


def main():
    path = OUT / 'loop'
    if not path.exists():
        raise SystemExit('missing out/loop — run make loop')
    t, (out, _line, _audio) = load_wrdata_vecs(path, 3)
    m = t >= (t[0] + SKIP_S)
    t, x = t[m], out[m]
    tt = np.arange(t[0], t[-1], 1.0 / RATE)
    y = np.interp(tt, t, x)
    peak = np.max(np.abs(y)) + 1e-12
    y = (0.8 * y / peak).clip(-1, 1)
    pcm = (y * 32767).astype('<i2')
    wav = OUT / 'loop.wav'
    with wave.open(str(wav), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f'wrote {wav}  {len(pcm) / RATE:.3f} s  peak {peak:.4f}')


if __name__ == '__main__':
    main()
