"""
Line receiver parameters the spec has not yet measured on their own.

  1  dead time (edges ignored after an accepted edge): usable window
  2  slicer hysteresis on a single span
  3  input low-pass corner relative to the symbol rate, at a fixed noise floor --
     what an UNSTRAPPED filter costs a low-rate mode
  4  input filter shape: second-order Butterworth vs a passive RC-RC
  5  carrier-detect timeout: no false alarms on signal, catches the quiet-noise case
  6  the receiver chain end to end with the spec §7 framer, three line rates

Usage:  python3 rx_review.py
"""
import numpy as np, gc
from scipy import signal
import fast, link, framing_review as fr, s4_simple as ss

OS = 32
S4 = fr.SCHEMES['S4 T=1110 period 4']


def lp(x, fc, FS, kind='butter2'):
    if kind == 'butter2':
        b, a = signal.butter(2, min(0.99, 2 * fc / FS)); return signal.lfilter(b, a, x)
    if kind == 'butter1':
        b, a = signal.butter(1, min(0.99, 2 * fc / FS)); return signal.lfilter(b, a, x)
    if kind == 'rcrc':                                   # two buffered first-order sections
        b, a = signal.butter(1, min(0.99, 2 * fc / FS)); return signal.lfilter(b, a, signal.lfilter(b, a, x))


def link_line(n, rate, secs, cv):
    L = int(secs * rate)
    C = np.array([np.roll(cv, 977 * j)[:L] for j in range(n)])
    A = np.array([np.full(L, j % 2, np.uint8) for j in range(n)])
    return fr.gbuild(C, A, S4), C


def wave(line, line_rate, sigma, seed=1, cable_fc=None, rx_fc=None, rx_kind='butter2', h=0.05):
    FS = line_rate * OS; SYM = 2 * line_rate
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    x = lp(x, cable_fc or 1.7578 * SYM, FS, 'butter1'); x /= np.abs(x).max()
    if sigma:
        x += rng.normal(0, sigma, len(x))
    w = fast.slice_hyst(lp(x, rx_fc or SYM, FS, rx_kind), h)
    del x; gc.collect()
    return w


def chan_bits(rb, n):
    flen = 2 + 2 * n
    st = ss.framer_single(rb, n)
    if st['lock_bit'] is None or len(st['pos']) < 200:
        return None
    pos = st['pos']
    return np.array([rb[pos + 2 * j + 1] for j in range(n)])


def ber(rb, n, C, probe=8000, hi=400):
    got = chan_bits(rb, n)
    if got is None:
        return 1.0
    c, ref = got[0], C[0]; best = 1.0; bo = None
    for o in range(hi):
        if o + probe > len(ref) or probe > len(c): break
        e = float((c[:probe] != ref[o:o + probe]).mean())
        if e < best: best, bo = e, o
        if best == 0.0: break
    if bo is None: return 1.0
    m = min(len(ref) - bo, len(c))
    return float((c[:m] != ref[bo:bo + m]).mean())


if __name__ == '__main__':
    cv, sil = fr.load(4.0)
    n, rate = 3, 32000; LR = rate * (2 + 2 * n)
    line, C = link_line(n, rate, 1.5, cv)

    print('1. DEAD TIME: BER vs the ignore-window after an accepted edge (fraction of a cell), 256 kbps')
    DEAD = (0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45)
    print('   dead     ' + ' '.join(f'{d:>7.2f}' for d in DEAD))
    for sd in (0.0, 0.4, 0.5):
        w = wave(line, LR, sd)
        r = [ber(fast.mono_decode(w, OS, thr=0.75, dead=d), n, C) for d in DEAD]
        print(f'   sd {sd:.1f}   ' + ' '.join(('     ok' if e == 0 else f'{e:7.0e}') for e in r), flush=True)
        del w; gc.collect()

    print('\n2. SLICER HYSTERESIS (fraction of received amplitude), single span, 256 kbps')
    HYS = (0.0, 0.02, 0.05, 0.10, 0.20, 0.30)
    print('   h        ' + ' '.join(f'{h:>7.2f}' for h in HYS))
    for sd in (0.4, 0.5, 0.6):
        r = []
        for h in HYS:
            w = wave(line, LR, sd, h=h); r.append(ber(fast.mono_decode(w, OS), n, C)); del w; gc.collect()
        print(f'   sd {sd:.1f}   ' + ' '.join(('     ok' if e == 0 else f'{e:7.0e}') for e in r), flush=True)

    print('\n3+4. INPUT FILTER: error-free noise sd vs RX corner / symbol rate, fixed cable (1 MHz), 256 kbps')
    FC = (0.5, 0.75, 1.0, 1.5, 2.0, 4.0, 8.0)
    SDS = (0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1.0, 1.2)
    print('   corner/SYM   ' + ' '.join(f'{f:>6.2f}' for f in FC))
    for kind in ('butter2', 'rcrc'):
        row = []
        for f in FC:
            best = 0.0
            for sd in SDS:
                w = wave(line, LR, sd, cable_fc=1.0e6, rx_fc=f * 2 * LR, rx_kind=kind)
                e = ber(fast.mono_decode(w, OS), n, C); del w; gc.collect()
                if e == 0: best = sd
                else: break
            row.append(best)
        print(f'   {kind:10s}   ' + ' '.join(f'{b:>6.1f}' for b in row), flush=True)
    print('   (entry = largest sd error-free; 20*log10 ratios give dB of margin)')

    print('\n5. CARRIER DETECT: fraction of time with no transition for longer than T (cells), 256 kbps')
    TCD = (1.5, 2.0, 4.0, 8.0)
    print('   input                ' + ' '.join(f'T={t:>4.1f}' for t in TCD))
    def gaps(w):
        e = np.flatnonzero(np.diff(w.astype(np.int8)) != 0)
        return np.diff(e) / OS if len(e) > 1 else np.array([len(w) / OS])
    def frac_dead(w, T):
        g = gaps(w); tot = len(w) / OS
        return float(np.clip(g - T, 0, None).sum() / tot)
    for label, w in (('signal, sd 0.0', wave(line, LR, 0.0)), ('signal, sd 0.6', wave(line, LR, 0.6)),
                     ('signal, sd 0.9', wave(line, LR, 0.9))):
        print(f'   {label:20s} ' + ' '.join(f'{frac_dead(w, t):6.3f}' for t in TCD), flush=True); del w; gc.collect()
    FS = LR * OS
    for sd in (0.05, 0.2, 1.0):
        rng = np.random.default_rng(1)
        w = fast.slice_hyst(lp(rng.normal(0, sd, int(1.5 * FS)), 2 * LR, FS), 0.05)
        print(f'   noise only, sd {sd:4.2f}  ' + ' '.join(f'{frac_dead(w, t):6.3f}' for t in TCD), flush=True); del w; gc.collect()

    print('\n6. END TO END, spec §7 framer on the monostable receiver, clean and at sd 0.4')
    for n2, rate2, secs in ((1, 16000, 3.0), (3, 32000, 1.5), (7, 64000, 0.6)):
        LR2 = rate2 * (2 + 2 * n2)
        ln2, C2 = link_line(n2, rate2, secs, cv)
        r = []
        for sd in (0.0, 0.4):
            w = wave(ln2, LR2, sd); rb = fast.mono_decode(w, OS)
            st = ss.framer_single(rb, n2)
            r.append(f'sd {sd}: lock={st["lock_bit"] is not None} LOF={st["lof_events"]} BER={ber(rb, n2, C2):.0e}')
            del w; gc.collect()
        print(f'   N={n2} @ {rate2//1000}k ({LR2//1000} kbps line): ' + ';  '.join(r), flush=True)
