#!/usr/bin/env python3
"""Render spice/tone-analog out/rbt → a 10 s WAV of the analog ringback."""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'sim'))
import audio  # noqa: E402
import mf8  # noqa: E402

OUT = Path(__file__).parent / 'out'
SKIP = 0.12          # Wien / Schmitt settle
SECS = 10.0          # ≥ two 4.096 s cadence periods
WAV_FS = 8000        # same as sim/tones.py render


def load_rbt(path):
    d = np.loadtxt(path)
    return d[:, 0], d[:, 3], d[:, 5]


def main():
    src = OUT / 'rbt'
    if not src.exists():
        print(f'missing {src} — run: make rbt-spice', file=sys.stderr)
        return 1

    t, a, cad = load_rbt(src)
    m = t >= SKIP
    t, a, cad = t[m] - t[m][0], a[m], cad[m]
    if t[-1] < SECS:
        print(f'run too short: {t[-1]:.3f}s < {SECS}s', file=sys.stderr)
        return 1

    # Resample AUDIO to WAV_FS over exactly SECS
    tt = np.arange(0.0, SECS, 1.0 / WAV_FS)
    y = np.interp(tt, t, a)
    # Peak-normalize for listening; keep a little headroom
    peak = np.max(np.abs(y)) or 1.0
    y = 0.8 * y / peak

    wav = OUT / 'rbt.wav'
    audio.write_wav(str(wav.resolve()), y, WAV_FS)

    on = float(np.std(a[cad > 2.5]))
    off = float(np.std(a[cad < 2.5]))
    print(f'wrote {wav}  {SECS:.0f}s @ {WAV_FS} Hz  '
          f'rms={y.std():.3f}  cadence on/off={on:.3f}/{off:.4f}  '
          f'(NOMINAL_RMS={mf8.NOMINAL_RMS})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
