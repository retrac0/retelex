"""
MF8 end to end: six talkers, real CVSD, over a real line, in both line codes.

This closes docs/mf8-spec.md 13's first two gaps -- "audio end to end through
this frame" and "anything about impulse noise".  Everything upstream of here
(mf8.py) is bit level: it shows the framer holds, and has never listened to a
channel or put a waveform on a wire.

Chain, per direction:

    6 LibriSpeech talkers -> CVSD 64 kbps -> mf8 frame (8 bits, 64 kHz)
      -> differential Manchester or AMI -> cable -> impairment -> receiver
      -> mf8 framer -> per-channel CVSD decode -> segSNR and isolation

Two measurement rules this repository learned the hard way, both applied here:

  * A slip re-phases the recovered stream AND can rotate the channel slots,
    so audio is scored inside the longest CONTIGUOUS LOCKED RUN, against the
    codec over the SAME window, with the frame offset found rather than assumed.
    Scoring a whole clip against one alignment reports a collapse that is
    mostly bookkeeping (mf-vs-16bit.md 10.2).
  * Isolation uses ONE lag per recovered channel, applied across the row.
    Re-aligning per (i,j) pair maximises correlation over thousands of lags
    before measuring it and cannot come out at zero (seven-channel.md 4.1).

Usage:  python3 mf8_line.py            everything, ~25 min
        python3 mf8_line.py clean      clean line, both codes, per channel
        python3 mf8_line.py noise      Gaussian sweep
        python3 mf8_line.py plant      impulse and attenuation
"""
import sys, gc, time, numpy as np
from scipy import signal
import audio, cvsd, fast, phy, mf8

RATE = 64000                      # per channel = frame rate
LINE = 8 * RATE                   # 512 kbps
NCH = 6
OS = 32                           # samples per line bit
FS = LINE * OS                    # 16.384 MHz
CABLE = 1.8e6
SECS = 1.0


# ------------------------------------------------------------------ sources

def sources(secs=SECS):
    """Six independent talkers, band-limited and level-normalised."""
    src, bits = [], []
    p = mf8.params(RATE)
    for j in range(NCH):
        x, fs = audio.read_wav(f'talker{j + 1}.wav', seconds=secs + 0.5)
        x = audio.bandlimit(x, fs)
        x = x * (mf8.NOMINAL_RMS / max(x.std(), 1e-9))
        x = audio.resample_to(x, fs, RATE)[:int(secs * RATE)]
        src.append(x)
        bits.append(cvsd.encode(x, p))
    return src, bits, p


# ----------------------------------------------------------------- the line

def _lp(x, fc, order=2):
    b, a = signal.butter(order, min(0.99, 2 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def rx_dm(ln, sd=0.0, imp=0.0, atten=1.0, seed=1):
    """spec.md 5-6: differential Manchester, hysteretic slicer, 0.75-cell
    monostable interval classifier.  No clock anywhere on the timing path."""
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(ln).astype(np.float64) * 2 - 1, OS // 2)
    x = _lp(x, CABLE, 1); x /= np.abs(x).max()
    if atten != 1.0:
        x *= atten
    if sd:
        x += rng.normal(0, sd, len(x))
    if imp:
        x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
    w = fast.slice_hyst(_lp(x, 2 * LINE, 2), 0.05)
    del x; gc.collect()
    b = fast.mono_decode(w, OS, thr=0.75, dead=0.25)
    del w; gc.collect()
    return b


def rx_ami(ln, sd=0.0, imp=0.0, atten=1.0, seed=1):
    """AMI: one symbol per bit, so half the symbol rate and a receive filter
    at 512 kHz.  Clock is an 8x DPLL off the local 4.096 MHz crystal
    (line-codes.md 2.2 option C), modelled by sampling at FS/4."""
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.ami_encode(ln), OS)
    x = _lp(x, CABLE, 1); x /= np.abs(x).max()
    if atten != 1.0:
        x *= atten
    if sd:
        x += rng.normal(0, sd, len(x))
    if imp:
        x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
    x = _lp(x, LINE, 2)
    b = fast.ami_decode(x[::4], OS // 4, thresh=0.5)
    del x; gc.collect()
    return b


CODES = {'diff Manchester': rx_dm, 'AMI': rx_ami}


# -------------------------------------------------------------- measurement

def longest_run(pos, flen=8):
    if len(pos) == 0:
        return None
    brk = np.flatnonzero(np.diff(pos) != flen) + 1
    return max(np.split(pos, brk), key=len)


def isolation(outs, src):
    """One lag per recovered channel, applied across the row."""
    n = len(outs)
    cm = np.zeros((n, n))
    for i in range(n):
        _, _, lag = audio.align(src[i][:len(outs[i])], outs[i])
        lag = int(lag)
        for j in range(n):
            o, s = outs[i], src[j]
            if lag > 0:
                oo, ss = o[lag:], s[:len(o) - lag]
            elif lag < 0:
                oo, ss = o[:len(o) + lag], s[-lag:]
            else:
                oo, ss = o, s[:len(o)]
            m = min(len(oo), len(ss))
            cm[i, j] = np.corrcoef(oo[:m], ss[:m])[0, 1] if m > 100 else 0.0
    return cm


def measure(ln, rx, src, bits, p, want_iso=False, **kw):
    """One cell: PHY, framer, per-channel audio."""
    t0 = time.time()
    rb = rx(ln, **kw)
    st = mf8.framer(rb)
    out = dict(lof=st['lof_events'], locked=st['lock_bit'] is not None,
               false=bool(st['false_lock']), secs=time.time() - t0)
    g = longest_run(st['pos'])
    nfr = len(ln) // 8
    out['down'] = 100.0 * (1.0 - st['frames'] / nfr)
    if g is None or len(g) < 4000:
        del rb; gc.collect()
        out.update(seg=[float('nan')] * NCH, dseg=[float('nan')] * NCH,
                   ber=[1.0] * NCH, iso=None,
                   clean=0.0 if g is None else len(g) / RATE)
        return out
    g = g[:len(g) - 2]
    out['clean'] = len(g) / RATE
    got = [rb[g + mf8.CBIT[j]] for j in range(NCH)]
    del rb; gc.collect()
    # A slip before this run deletes line bits, so the recovered frame index no
    # longer maps to the source frame index.  Find the offset once, on channel
    # 1, and apply it to every channel -- assuming it is g[0]//8 reports a
    # near-random BER for a stream whose audio is fine, which is the same
    # bookkeeping trap as mf-vs-16bit.md 10.2.
    i0 = int(g[0]) // 8
    best = (1.0, i0)
    for d in range(max(0, i0 - 200), i0 + 200):
        n = min(len(got[0]), len(bits[0]) - d)
        if n < 1000:
            break
        e = float((got[0][:n] != bits[0][d:d + n]).mean())
        if e < best[0]:
            best = (e, d)
        if e == 0.0:
            break
    i0 = best[1]
    out['shift'] = i0 - int(g[0]) // 8
    ref = [bits[j][i0:i0 + len(got[j])] for j in range(NCH)]
    got = [got[j][:len(ref[j])] for j in range(NCH)]
    out['ber'] = [float((got[j] != ref[j]).mean()) for j in range(NCH)]
    seg, dseg, outs = [], [], []
    for j in range(NCH):
        y = audio.reconstruct(cvsd.decode(got[j], p), RATE)
        a, b, _ = audio.align(src[j][i0:i0 + len(got[j])], y)
        s1 = audio.seg_snr_db(a, audio.gain_match(a, b), RATE)
        # matched control: the SAME codec bits over the SAME window, no link
        yc = audio.reconstruct(cvsd.decode(ref[j], p), RATE)
        a2, b2, _ = audio.align(src[j][i0:i0 + len(got[j])], yc)
        s0 = audio.seg_snr_db(a2, audio.gain_match(a2, b2), RATE)
        seg.append(s1); dseg.append(s1 - s0); outs.append(y)
    out['seg'] = seg; out['dseg'] = dseg
    out['iso'] = isolation(outs, [src[j][i0:] for j in range(NCH)]) if want_iso else None
    return out


def row(label, r):
    if not r['locked'] or np.isnan(r['seg'][0]):
        # "no lock" and "locked repeatedly but chopped" are different failures
        tag = 'no lock' if not r['locked'] else 'chopped'
        print(f'  {label:26s} {tag:>9s} {r["down"]:8.2f}% {r["lof"]:>5d}'
              f'  {"-":>6s} {"-":>7s}  {"-":>8s} {1000 * r["clean"]:7.0f}ms',
              flush=True)
        return
    worst = min(r['dseg']); mean = float(np.mean(r['dseg']))
    mb = max(r['ber'])
    print(f'  {label:26s} {np.mean(r["seg"]):8.2f}dB {r["down"]:8.2f}% {r["lof"]:>5d}'
          f'  {mean:+6.2f} {worst:+7.2f}  {mb:8.1e} {1000 * r["clean"]:7.0f}ms',
          flush=True)


HDR = (f'  {"condition":26s} {"segSNR":>10s} {"down":>9s} {"LOF":>5s}'
       f'  {"d mean":>6s} {"d worst":>7s}  {"max BER":>8s} {"clean":>9s}')


# ------------------------------------------------------------- 1: clean line

def clean():
    src, bits, p = sources()
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf8.build(bits, A)
    print('CLEAN LINE -- six independent talkers through the whole chain')
    print(f'  {SECS:.1f} s, 64 kbps per channel, 512 kbps line, 1.8 MHz cable.')
    print('  "d" is this channel against the SAME codec bits over the SAME')
    print('  window with no link in the path, so it is what the CARRIER adds.\n')
    print(HDR)
    res = {}
    for cn, rx in CODES.items():
        r = measure(ln, rx, src, bits, p, want_iso=True)
        res[cn] = r
        row(cn, r)
    print('\n  Per channel, differential Manchester:\n')
    print(f'  {"channel":9s} ' + ' '.join(f'{j + 1:>8d}' for j in range(NCH)))
    r = res['diff Manchester']
    print(f'  {"segSNR":9s} ' + ' '.join(f'{v:8.2f}' for v in r['seg']))
    print(f'  {"vs codec":9s} ' + ' '.join(f'{v:+8.2f}' for v in r['dseg']))
    print(f'  {"bit BER":9s} ' + ' '.join(f'{v:8.0e}' for v in r['ber']))
    # the floor MUST be computed on the same window with the same estimator:
    # 1 s of unrelated speech correlates far more by chance than 30 s does,
    # and seven-channel.md 4.1 records what reading an off-diagonal against a
    # mismatched floor did last time.
    n = min(len(x) for x in src)
    fl = 0.0
    for i in range(NCH):
        for j in range(NCH):
            if i != j:
                fl = max(fl, abs(np.corrcoef(src[i][:n], src[j][:n])[0, 1]))
    print(f'\n  Source-correlation floor on this {SECS:.1f} s window: {fl:.3f}')
    print('  (seven-channel.md 4.2 measured 0.009 for the same talkers over 30 s;')
    print('  a short window correlates more by chance, so THIS is the number an')
    print('  off-diagonal has to be read against, not that one.)\n')
    for cn in CODES:
        cm = res[cn]['iso']
        if cm is None:
            continue
        off = np.abs(cm - np.diag(np.diag(cm))).max()
        print(f'  Isolation, {cn:16s} diagonal min {np.min(np.diag(cm)):.3f}, '
              f'off-diagonal max {off:.3f}, excess over floor {off - fl:+.3f}')
    print('\n  With BER identically zero the recovered bits ARE the transmitted')
    print('  bits, so carrier crosstalk is exactly zero by construction and the')
    print('  matrix can only report its own floor.  The measurement is a check on')
    print('  the estimator, not on the carrier; it earns its place by failing')
    print('  loudly if a slot ever rotates.')


# --------------------------------------------------------- 2: Gaussian noise

def noise():
    src, bits, p = sources()
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf8.build(bits, A)
    print('GAUSSIAN NOISE -- noise sd referred to the transmitted peak\n')
    print(HDR)
    for cn, rx in CODES.items():
        for sd in (0.0, 0.3, 0.4, 0.5, 0.6, 0.7):
            row(f'{cn}, sd {sd:.1f}', measure(ln, rx, src, bits, p, sd=sd))
        print()


# --------------------------------------------- 3: impulse noise, attenuation

def plant():
    src, bits, p = sources()
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf8.build(bits, A)
    print('IMPULSE NOISE -- damped rings 0.5-3x peak, 15-80 kHz, Poisson\n')
    print(HDR)
    for cn, rx in CODES.items():
        for imp in (0.0, 1.0, 10.0, 100.0, 1000.0):
            row(f'{cn}, {imp:.0f}/s', measure(ln, rx, src, bits, p, imp=imp))
        print()
    print('ATTENUATION -- signal scaled, sd 0.10 floor and 0.05 hysteresis fixed\n')
    print(HDR)
    for cn, rx in CODES.items():
        for at in (1.0, 0.5, 0.25, 0.12):
            row(f'{cn}, atten {at:.2f}', measure(ln, rx, src, bits, p,
                                                 atten=at, sd=0.10))
        print()


TARGETS = {'clean': clean, 'noise': noise, 'plant': plant}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
