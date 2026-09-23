#!/usr/bin/env python3
"""Score spice/formant-cell out/{tone,loop}.

Tone: LINE should peak near 800 Hz with energy inside 400–1200 Hz.
Loop: decode RMS while driven; quiet-ish when source is weak.
"""
import sys
from pathlib import Path

import numpy as np

OUT = Path(__file__).parent / 'out'
SKIP_S = 0.050
RATE = 16000
LINE_BAND = (400.0, 1200.0)
CARRIER_HZ = 800.0


def load_wrdata_vecs(path, nvecs):
    """Parse ngspice `wrdata file time v1 v2 ...` ascii.

    Each named vector is (scale, value); with `time` first that is 2·(1+nvecs)
    columns: t=col0, v_i at col 3+2·i (same as spice/tone-analog/check.py).
    """
    d = np.loadtxt(path)
    t = d[:, 0]
    cols = [d[:, 3 + 2 * i] for i in range(nvecs)]
    return t, cols


def resample(t, x, fs=RATE):
    m = t >= (t[0] + SKIP_S)
    t, x = t[m], x[m]
    if len(t) < 8:
        return np.array([]), np.array([])
    tt = np.arange(t[0], t[-1], 1.0 / fs)
    return tt, np.interp(tt, t, x)


def peak_hz(t, x, band=None):
    _, y = resample(t, x)
    if len(y) < 256:
        return float('nan'), 0.0
    n = min(4096, len(y) & ~1)
    seg = y[-n:]
    w = np.hanning(n)
    S = np.abs(np.fft.rfft(seg * w))
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    if band is not None:
        m = (f >= band[0]) & (f <= band[1])
        S, f = S[m], f[m]
    if len(S) == 0:
        return float('nan'), 0.0
    i = int(np.argmax(S))
    return float(f[i]), float(np.std(y))


def band_power_frac(t, x, band=LINE_BAND):
    """Fraction of AC spectral power inside band (DC / <50 Hz excluded)."""
    _, y = resample(t, x)
    if len(y) < 256:
        return float('nan')
    y = y - np.mean(y)
    n = min(4096, len(y) & ~1)
    seg = y[-n:]
    S2 = np.abs(np.fft.rfft(seg * np.hanning(n))) ** 2
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    ac = f >= 50.0
    tot = S2[ac].sum() + 1e-30
    m = (f >= band[0]) & (f <= band[1])
    return float(S2[m].sum() / tot)


def main():
    print('Formant cell — ngspice (SPEC.md)\n')
    ok = True

    tone = OUT / 'tone'
    if not tone.exists():
        print('tone: missing — run make tone')
        ok = False
    else:
        t, (line, audio) = load_wrdata_vecs(tone, 2)
        f0, rms = peak_hz(t, line, LINE_BAND)
        frac = band_power_frac(t, line)
        print(f'tone  LINE peak {f0:7.1f} Hz  rms {rms:.4f}  '
              f'in-band power {100 * frac:.1f}%  (want ~{CARRIER_HZ:.0f} Hz)')
        if not (CARRIER_HZ - 80 <= f0 <= CARRIER_HZ + 80):
            print('  FAIL: carrier not near 800 Hz')
            ok = False
        if frac < 0.5:
            print('  FAIL: most LINE energy outside 400–1200 Hz')
            ok = False
        if rms < 1e-4:
            print('  FAIL: LINE nearly silent')
            ok = False

    loop = OUT / 'loop'
    if not loop.exists():
        print('loop: missing — run make loop')
        ok = False
    else:
        t, (out, line, audio) = load_wrdata_vecs(loop, 3)
        _, rms_out = peak_hz(t, out)
        _, rms_line = peak_hz(t, line)
        _, rms_in = peak_hz(t, audio)
        f_line, _ = peak_hz(t, line, LINE_BAND)
        print(f'loop  AUDIO_in rms {rms_in:.4f}  LINE rms {rms_line:.4f} '
              f'(peak {f_line:.0f} Hz)  AUDIO_out rms {rms_out:.4f}')
        if rms_line < 1e-4 or rms_out < 1e-5:
            print('  FAIL: loop too quiet')
            ok = False
        if rms_out > 1e-5 and rms_in > 1e-4:
            print('  ok: decode alive while driven')

    if not ok:
        sys.exit(1)
    print('\nPASS')
    return 0


if __name__ == '__main__':
    sys.exit(main() or 0)
