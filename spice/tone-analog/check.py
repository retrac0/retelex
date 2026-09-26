#!/usr/bin/env python3
"""Score spice/tone-analog out/{pure,soft,hard,cadence}.

Reports carrier Hz, RMS vs NOMINAL_RMS, and in-band FFT line count — the
soft-vs-hard trade from tones.md §5 / sim/tones.py warble.
"""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'sim'))
import mf8  # noqa: E402

OUT = Path(__file__).parent / 'out'
SKIP_S = 0.100          # let Wien / Schmitt start
RATE = 64000            # same grid as sim/tones.py
BAND = (250.0, 3400.0)
LINE_DB = -40.0


def load_wrdata(path, ncols=1):
    """ngspice wrdata ascii: each vector is (scale, value); shared time in col 0."""
    d = np.loadtxt(path)
    t = d[:, 0]
    cols = [d[:, 3 + 2 * i] for i in range(ncols)]
    return t, cols


def zero_cross_hz(t, x):
    x = x - np.mean(x)
    s = np.sign(x)
    s[s == 0] = 1
    idx = np.where(np.diff(s) > 0)[0]
    if len(idx) < 2:
        return float('nan')
    periods = np.diff(t[idx])
    periods = periods[(periods > 1e-4) & (periods < 0.05)]
    if len(periods) < 2:
        return float('nan')
    return 1.0 / float(np.median(periods))


def resample(t, x, fs=RATE):
    tt = np.arange(t[0], t[-1], 1.0 / fs)
    return tt, np.interp(tt, t, x)


def inband_lines(t, x):
    """Local-peak count after resample to 64 kHz — sim/tones.py in_band_lines."""
    _, y = resample(t, x)
    n = 8192
    if len(y) < n:
        return 0, float('nan'), []
    seg = y[-n:]
    S = np.abs(np.fft.rfft(seg * np.hanning(n)))
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    m = (f >= BAND[0]) & (f <= BAND[1])
    S, f = S[m], f[m]
    thr = S.max() * 10 ** (LINE_DB / 20)
    idx = [i for i in range(1, len(S) - 1)
           if S[i] > S[i - 1] and S[i] > S[i + 1] and S[i] > thr]
    f0 = float(f[int(np.argmax(S))])
    return len(idx), f0, [float(f[i]) for i in idx[:8]]


def main():
    print('Analog tone front-end — ngspice (tones.md §5)\n')
    print(f'{"deck":<10} {"carrier Hz":>11} {"fft f0":>8} {"rms":>7} '
          f'{"vs nom":>7} {"lines":>6}  peaks')

    for tag, want_lines in [
        ('pure', '1'),
        ('soft', 'few'),
        ('hard', 'many'),
    ]:
        path = OUT / tag
        if not path.exists():
            print(f'{tag:<10}  (missing — run make {tag})')
            continue
        t, (audio,) = load_wrdata(path, 1)
        m = t >= SKIP_S
        t, audio = t[m], audio[m]
        hz = zero_cross_hz(t, audio)
        lines, f0, peaks = inband_lines(t, audio)
        rms = float(np.std(audio))
        vs = 20 * np.log10(rms / mf8.NOMINAL_RMS + 1e-30)
        pk = ' '.join(f'{p:.0f}' for p in peaks)
        print(f'{tag:<10} {hz:11.1f} {f0:8.1f} {rms:7.3f} {vs:6.1f}dB {lines:6d}'
              f'   ({want_lines})  {pk}')

    path = OUT / 'cadence'
    if path.exists():
        t, (audio, cad) = load_wrdata(path, 2)
        m = t >= SKIP_S
        on = np.std(audio[m & (cad > 2.5)])
        off = np.std(audio[m & (cad < 2.5)])
        print(f'\ncadence    on-rms={on:.3f}  off-rms={off:.3f}  '
              f'mute ratio={on / max(off, 1e-9):.0f}:1')
    else:
        print('\ncadence    (missing — run make cadence)')

    print(f'''
NOMINAL_RMS = {mf8.NOMINAL_RMS}
Band {BAND[0]:.0f}–{BAND[1]:.0f} Hz; a "line" is a local FFT peak within
{LINE_DB:.0f} dB of the in-band max (sim/tones.py in_band_lines). Soft should
stay near a few lines; hard sprays many (tones.md §5). Cadence mutes AUDIO,
not a bit stream.
''')
    return 0


if __name__ == '__main__':
    sys.exit(main())
