"""
Can CVSD itself produce a period-4 T pattern?

Speech is random and silence is 1010, and every framing test so far used those.
But a CVSD encoder driven by something DETERMINISTIC -- a steady tone, or its
own comparator offset with no input -- runs a limit cycle, and a limit cycle is
a periodic bit pattern.  If that pattern is 1100 (or 1110), an on-hook channel
(A = 0) carrying it imitates the pair (or S4) header indefinitely.

Idle E&M trunks do carry steady tones: 2600 Hz SF signalling, 1004 Hz test tone.

For every rate, input and level: the longest run of consecutive frames each
header check passes on the channel's C bits.  A run of 32 or more is a possible
acquisition false lock; a pass fraction of 2/3 or more is a slip the one-counter
pair policy would not detect.  Flagged cases are then simulated end to end.

Usage:  python3 cvsd_tones.py
"""
import numpy as np, cvsd, run, link, t_pattern as tp

SECS = 4.0


def checks(b):
    b = b.astype(np.int8); n = len(b)
    tog = np.zeros(n, bool); tog[1:] = b[1:] != b[:-1]
    pair = np.zeros(n, bool); pair[2:] = b[2:] != b[:-2]
    s4 = np.zeros(n, bool)
    z = (b == 0).astype(np.int8)
    w = np.convolve(z, np.ones(4, np.int8), 'valid')          # zeros in each 4-window
    s4[3:] = (w == 1)
    return dict(toggle=tog, pair=pair, S4=s4)


def longest(x):
    r = link.runs_of(x.astype(np.uint8), 1)
    return int(r.max()) if len(r) else 0


def inputs(rate):
    t = np.arange(int(SECS * rate)) / rate
    out = []
    for off in (0.0, 1e-4, 1e-3, 3e-3, 1e-2, 3e-2, 1e-1):
        out.append((f'DC offset {off:g}', np.full(len(t), off)))
    for f in (300.0, 1004.0, 2600.0, 3400.0):
        for db in (-40, -20, 0):
            a = run.NOMINAL_RMS * 10 ** (db / 20) * np.sqrt(2)
            out.append((f'{f:.0f} Hz {db:+d} dB', a * np.sin(2 * np.pi * f * t)))
    return out


if __name__ == '__main__':
    flagged = []
    for rate in (16000, 32000, 64000):
        p = run.params(rate)
        print(f'\nCVSD {rate // 1000} kbps: longest consecutive pass run (frames) / pass fraction')
        print(f'  {"input":22s} {"toggle":>14s} {"pair 1100":>14s} {"S4 1110":>14s}')
        for name, x in inputs(rate):
            b = cvsd.encode(x, p)[int(0.5 * rate):]           # skip the start-up transient
            c = checks(b)
            cells = []
            for k in ('toggle', 'pair', 'S4'):
                lr, fr_ = longest(c[k]), float(c[k].mean())
                mark = '!' if (lr >= 32 or (k == 'pair' and fr_ >= 2 / 3)) else ' '
                cells.append(f'{lr:>6d}/{fr_:4.2f}{mark}')
                if mark == '!' and k != 'toggle':
                    flagged.append((rate, name, k, b))
            print(f'  {name:22s} ' + ' '.join(f'{c_:>14s}' for c_ in cells), flush=True)

    print('\nFLAGGED CASES, simulated: N=3, the tone on channel 1 with A1 = 0 (on-hook),'
          ' speech on channels 2-3; false locks over 8 skews')
    import framing_review as fr
    cv, sil = fr.load(SECS - 0.5)
    seen = set()
    for rate, name, k, b in flagged:
        key = (rate, name, k)
        if key in seen:
            continue
        seen.add(key)
        L = min(len(b), len(cv))
        C = np.array([b[:L], np.roll(cv, 977)[:L], np.roll(cv, 1954)[:L]])
        A = np.zeros((3, L), np.uint8)
        nm = {'pair': 'pair 1100', 'S4': 'S4 1110'}[k]
        fl = tp.falses(nm, C, A)
        print(f'  {rate // 1000:2d}k {name:22s} {nm:10s}: {fl}/8 false locks', flush=True)
    if not flagged:
        print('  none flagged')
