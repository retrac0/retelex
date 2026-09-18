"""
Repeater study for the 3-channel carrier (docs/repeater.md).

The question: must a repeater reclock, or does digital regeneration -- slice and
re-drive -- suffice, and how many stages can be cascaded?

Three repeater models share one cascaded-span harness:

  amplify   linear gain only, no slicing.  Noise and ISI both accumulate.
  regen     comparator + driver.  Amplitude is restored every span; edge
            POSITION is not, so timing error accumulates.
  retime    regen + interval classifier + one-shot: the mid-cell edge is
            re-placed at a fixed delay after the recovered cell boundary, so
            pulse-width distortion is reset every span.  Boundary jitter still
            passes through -- there is no flywheel and no crystal.

A fourth option, decode to bits and re-encode from a local crystal, is not
modelled because it is architecturally forbidden: it would make the repeater a
timing boundary and reintroduce slips (spec 1).

Span model matches validate.py so the numbers are directly comparable: driver +
cable as a first-order lowpass at 900 kHz, peak normalisation, additive Gaussian
noise of standard deviation `sigma` referred to the launched peak, second-order
receive filter at the symbol rate, hysteretic comparator.  sigma = 0.4 is the
design limit of spec 5.2; the single-span link is error-free to 0.6.

`sigma` is a PER-SAMPLE amplitude, so what it means physically depends on the
sample rate: the noise surviving the receive filter scales as sigma*sqrt(BW/fs).
The harness therefore runs at OS = 32 samples per line bit -- exactly 8.192 MHz,
both the hardware master clock and the rate validate.py uses -- so an sd here is
the same impairment as an sd there.  On a finer grid, sigma must be scaled by
sqrt(OS/32) to mean the same thing; measured, that reproduces the same interval
jitter to within the coarse grid's own edge-quantisation dither, which is why
the 8.192 MHz results are slightly pessimistic rather than optimistic.
"""
import numpy as np, gc
from scipy import signal
import fast, link, cvsd, run, audio, phy

RATE, NCH, FLEN = 32000, 3, 8
LINE = RATE * FLEN                 # 256 kbps
SYM = 2 * LINE                     # 512 kbaud
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1)

OS = 32                            # samples per line bit == per biphase cell,
                                   # i.e. fs = 8.192 MHz, the hardware master clock
                                   # and the rate validate.py runs at
FC = 900_000.0                     # driver + cable first-order corner
HYST = 0.05                        # comparator hysteresis, fraction of launch peak


def fs(os=OS):
    return LINE * os


def lp(x, fc, order, os=OS):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / fs(os)), btype='low')
    return signal.lfilter(b, a, x)


def launch(line, os=OS):
    """TX card output: biphase half-cells -> +-1 waveform."""
    return np.repeat(fast.dm_encode(line).astype(np.float64) * 2.0 - 1.0, os // 2)


# ------------------------------------------------------------------ one span

def span(x, sigma=0.0, fc=FC, att=1.0, seed=0, os=OS, impulse=None,
         amp=(0.5, 3.0), gain=None):
    """Driver slew + cable + span loss + noise at the far end.

    `impulse`, if given, is the events/second rate of phy.plant_noise -- damped
    ringing transients of the kind subscriber loops actually carry.  Each span
    gets its OWN impulses, which is the point: they are a per-span impairment.

    `gain` is the amplifier ahead of this span, normally 1/peak so the launch
    level is restored.  It must be passed in when the input ALREADY carries
    noise -- an amplifier sets its gain from the signal, and normalising to the
    peak of signal-plus-noise would quietly attenuate the signal a little more
    on every span, which is not a real impairment.
    """
    y = lp(x, fc, 1, os)
    y = y * (1.0 / np.abs(y).max() if gain is None else gain)
    if att != 1.0:
        y *= att
    if sigma:
        y += np.random.default_rng(seed).normal(0, sigma, len(y))
    if impulse:
        y += phy.plant_noise(len(y), fs(os), rate_hz=impulse, amp=amp, seed=seed + 7)
    return y


def front_end(x, h=HYST, os=OS):
    """Receive filter + hysteretic comparator -> regenerated logic waveform."""
    return fast.slice_hyst(lp(x, SYM, 2, os), h)


# ------------------------------------------------------------ retiming stage

def retime(w, os=OS, thr=0.75, dead=0.25, mid=0.5):
    """
    Interval classifier + one flip-flop + one one-shot.

    Boundary edges are passed through with whatever jitter they carry (no
    flywheel).  The mid-cell edge is re-emitted at a FIXED delay `mid` cells
    after the boundary -- a one-shot RC, not a fraction of the measured cell --
    so pulse-width distortion does not accumulate.  The re-emitted cell is one
    cell late, because the bit is not known until the cell ends; that is the
    flip-flop.
    """
    d = np.flatnonzero(np.diff(w.astype(np.int8)) != 0) + 1
    thr_s, dead_s, mid_s = thr * os, dead * os, int(round(mid * os))
    bnd = np.empty(len(d), np.int64)
    bit = np.empty(len(d), np.uint8)
    n = 0
    last = 0
    at_mid = False
    for i in d:
        gap = i - last
        if gap < dead_s:               # monostable still held: glitch, ignore
            continue
        last = i
        if gap > thr_s:
            bnd[n] = i; bit[n] = 1; n += 1; at_mid = False
        elif at_mid:
            bnd[n] = i; bit[n] = 0; n += 1; at_mid = False
        else:
            at_mid = True
    bnd, bit = bnd[:n], bit[:n]

    out = np.zeros(len(w), np.uint8)
    tog = np.zeros(len(w) + 1, np.int8)
    if n:
        np.add.at(tog, bnd, 1)                       # boundary transition, every cell
        z = bnd[:-1][bit[1:] == 0]                   # re-emit the PREVIOUS cell's bit
        z = z + mid_s
        z = z[z < len(w)]
        np.add.at(tog, z, 1)
    out = (np.cumsum(tog[:len(w)]) & 1).astype(np.uint8)
    return out


# ------------------------------------------------------------------- cascade

def aggressor(n, seed=99, os=OS):
    """
    The other direction's outgoing driver, as it appears at this direction's
    receiver input: an independent biphase stream at the same rate, capacitively
    coupled, so first-order high-passed at the symbol rate.  Normalised to unit
    peak, i.e. `xt` in cascade() is near-end crosstalk relative to the WANTED
    signal's launch amplitude.
    """
    rng = np.random.default_rng(seed)
    b = rng.integers(0, 2, n // (os // 2) + 2).astype(np.uint8)
    x = np.repeat(fast.dm_encode(b).astype(np.float64) * 2 - 1, os // 2)[:n]
    bq, aq = signal.butter(1, min(0.99, 2.0 * SYM / fs(os)), btype='high')
    x = signal.lfilter(bq, aq, x)
    return x / x.std()


def cascade(line, n_rep, mode='regen', sigma=0.4, fc=FC, att=1.0, h=HYST,
            seed=0, os=OS, invert_at=(), mid=0.5, xt=0.0, impulse=None,
            amp=(0.5, 3.0)):
    """
    n_rep repeaters => n_rep + 1 spans.  Returns the logic waveform at the
    terminal receiver's comparator output, ready for fast.mono_decode.
    """
    x = launch(line, os)
    # an amplifying chain carries its noise forward, so the per-span gain has to
    # come from a noiseless reference travelling the same path (see span())
    ref = x.copy() if mode == 'amplify' else None
    agg = aggressor(len(x), 99, os) if xt else None
    for k in range(n_rep):
        g = None
        if ref is not None:
            ref = lp(ref, fc, 1, os)
            g = 1.0 / np.abs(ref).max()
            ref = ref * g
        x = span(x, sigma, fc, att, seed=seed * 1000 + k, os=os, impulse=impulse,
                 amp=amp, gain=g)
        if xt:
            x = x + xt * np.roll(agg, (k * 7919) % len(agg))
        if mode == 'amplify':
            if att != 1.0:
                x = x / att                          # linear gain only
            continue
        w = front_end(x, h, os)
        if mode == 'retime':
            w = retime(w, os, mid=mid)
        x = w.astype(np.float64) * 2.0 - 1.0
        if k in invert_at:
            x = -x                                   # tip/ring swapped on the next span
        del w
        gc.collect()
    g = None
    if ref is not None:
        ref = lp(ref, fc, 1, os)
        g = 1.0 / np.abs(ref).max()
    x = span(x, sigma, fc, att, seed=seed * 1000 + n_rep, os=os, impulse=impulse,
             amp=amp, gain=g)
    if xt:
        x = x + xt * np.roll(agg, (n_rep * 7919) % len(agg))
    w = front_end(x, h, os)
    del x
    gc.collect()
    return w


# --------------------------------------------------------------- measurement

def stream(secs=0.5, seed=7, speech=True):
    """Framed line bit stream plus the per-channel CVSD bits for scoring."""
    L = int(secs * RATE)
    if speech:
        try:
            p = run.params(RATE)
            src = []
            for f in ('speech30.wav', 'spk_300.wav', 'spk_600.wav'):
                a, sr = audio.read_wav(f, seconds=secs + 0.2)
                a = audio.bandlimit(a, sr)
                src.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), sr, RATE)[:L])
            L = min(map(len, src))
            ch = np.array([cvsd.encode(s[:L], p) for s in src])
        except FileNotFoundError:
            speech = False
    if not speech:
        rng = np.random.default_rng(seed)
        ch = rng.integers(0, 2, (NCH, L)).astype(np.uint8)
    rng = np.random.default_rng(seed + 1)
    sg = np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8), np.zeros(L, np.uint8)])
    return link.build(ch, sg), ch


def chan_ber(c, ref, probe=40_000, hi=3000):
    probe = min(probe, len(c), len(ref) - hi)
    bo, be = None, 1.0
    for o in range(hi):
        if o + probe > len(ref) or probe > len(c):
            break
        e = float((c[:probe] != ref[o:o + probe]).mean())
        if e < be:
            bo, be = o, e
        if be == 0.0:
            break
    if bo is None:
        return 1.0
    n = min(len(ref) - bo, len(c))
    return float((c[:n] != ref[bo:bo + n]).mean())


def track_ber(rb, line, blk=4000, maxshift=24):
    """
    Line BER with the alignment tracked block by block, plus the number of
    alignment changes (bit slips).  A misclassified interval inserts or deletes
    a bit, so a single global offset would score every bit after a slip as an
    error and hide the real error rate.
    """
    off, errs, tot, slips = None, 0.0, 0, 0
    n = min(len(rb), len(line))
    # skip the first block: filter start transient, framer acquisition, and the
    # cumulative group delay of the chain is still being taken up there
    for a in range(blk, n - blk - maxshift, blk):
        best = (None, 2.0)
        for o in range(-maxshift, maxshift + 1):
            if a + o < 0 or a + o + blk > len(line):
                continue
            e = float((rb[a:a + blk] != line[a + o:a + o + blk]).mean())
            if e < best[1]:
                best = (o, e)
        if off is not None and best[0] != off:
            slips += 1
        off = best[0]
        errs += best[1] * blk
        tot += blk
    return (errs / tot if tot else 1.0), slips


def score(w, ch, line, os=OS, thr=0.75):
    """Terminal receiver: monostable decode + framer, scored against the source."""
    rb = fast.mono_decode(w, os, thr=thr)
    if len(rb) < 5000:
        return dict(ber=1.0, slips=-1, locked=False, lof=-1)
    ber, slips = track_ber(rb, line)
    c, sg, st = link.framer(rb, NCH, **LOF)
    return dict(ber=ber, slips=slips, locked=st['lock_bit'] is not None,
                lof=st['lof_events'], frames=st['frames'], chan=c)


def intervals(w, os=OS):
    """Inter-transition gaps in cells -- what the monostable actually classifies."""
    d = np.flatnonzero(np.diff(w.astype(np.int8)) != 0) + 1
    return np.diff(d) / float(os)


def interval_stats(w, os=OS):
    g = intervals(w, os)
    short = g[g < 0.75]
    long_ = g[g >= 0.75]
    return dict(n=len(g),
                s_mean=short.mean() if len(short) else np.nan,
                s_sd=short.std() if len(short) else np.nan,
                s_max=short.max() if len(short) else np.nan,
                l_mean=long_.mean() if len(long_) else np.nan,
                l_sd=long_.std() if len(long_) else np.nan,
                l_min=long_.min() if len(long_) else np.nan)


# --------------------------------------------------------------- experiments

_CACHE = {}


def _stream(key):
    if key not in _CACHE:
        _CACHE[key] = stream(key[0], speech=key[1])
    return _CACHE[key]


def _job(a):
    """One cascade, scored.  Top level so it can be run in a process pool."""
    kind, key, kw = a
    line, ch = _stream(key)
    if kind == 'cascade':
        w = cascade(line, **kw)
        r = score(w, ch, line)
        r.pop('chan', None)
        r['istat'] = interval_stats(w)
        return r
    if kind == 'window':
        n = kw.pop('n_rep')
        w = cascade(line, n, **kw)
        out = {}
        for thr in (0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95):
            rb = fast.mono_decode(w, OS, thr=thr)
            out[thr] = track_ber(rb, line)[0] if len(rb) > 5000 else 1.0
        return out
    raise ValueError(kind)


def _pool_map(jobs, procs=8):
    import multiprocessing as mp
    if procs == 1:
        return [_job(j) for j in jobs]
    with mp.Pool(procs) as p:
        return p.map(_job, jobs)


def table(rows, hdr):
    print('| ' + ' | '.join(hdr) + ' |')
    print('|' + '|'.join('---' for _ in hdr) + '|')
    for r in rows:
        print('| ' + ' | '.join(str(x) for x in r) + ' |')
    print(flush=True)


def exp_cascade(secs=0.5, sigmas=(0.0, 0.2, 0.3, 0.4), Ns=(0, 1, 2, 4, 8, 16, 32),
                modes=('amplify', 'regen', 'retime'), procs=8):
    """Line BER and slips at the terminal versus repeater count."""
    print(f'\n== CASCADE: line BER (slips) at the far terminal, {secs}s stream ==')
    key = (secs, True)
    jobs, idx = [], []
    for sg in sigmas:
        for mode in modes:
            for n in Ns:
                jobs.append(('cascade', key, dict(n_rep=n, mode=mode, sigma=sg, seed=1)))
                idx.append((sg, mode, n))
    res = _pool_map(jobs, procs)
    got = dict(zip(idx, res))
    for sg in sigmas:
        rows = []
        for mode in modes:
            cells = []
            for n in Ns:
                r = got[(sg, mode, n)]
                if not r['locked']:
                    cells.append('no lock')
                else:
                    cells.append(f'{r["ber"]:.1e}' + (f' ({r["slips"]})' if r['slips'] else ''))
            rows.append([mode] + cells)
        print(f'per-span noise sd = {sg}')
        table(rows, ['repeater'] + [f'N={n}' for n in Ns])
    return got


def exp_jitter(secs=0.5, sigmas=(0.0, 0.3, 0.4), Ns=(0, 1, 2, 4, 8, 16, 32),
               mode='regen', procs=8):
    """How the interval distribution the monostable classifies degrades with N."""
    print(f'\n== JITTER: inter-transition intervals at the far terminal ({mode}) ==')
    key = (secs, True)
    jobs, idx = [], []
    for sg in sigmas:
        for n in Ns:
            jobs.append(('cascade', key, dict(n_rep=n, mode=mode, sigma=sg, seed=1)))
            idx.append((sg, n))
    got = dict(zip(idx, _pool_map(jobs, procs)))
    for sg in sigmas:
        rows = []
        for n in Ns:
            s = got[(sg, n)]['istat']
            rows.append([f'N={n}', f'{s["s_mean"]:.4f}', f'{s["s_sd"]:.4f}',
                         f'{s["s_max"]:.3f}', f'{s["l_mean"]:.4f}', f'{s["l_sd"]:.4f}',
                         f'{s["l_min"]:.3f}'])
        print(f'per-span noise sd = {sg}   (cells; half-cell = 0.5, full cell = 1.0, '
              f'decision threshold 0.75)')
        table(rows, ['', 'short mean', 'short sd', 'short max', 'long mean', 'long sd',
                     'long min'])
    return got


def exp_window(secs=0.5, sigma=0.4, Ns=(0, 1, 2, 4, 8), mode='regen', procs=8):
    """Usable monostable RC window at the terminal versus N -- spec 5.2 currency."""
    print(f'\n== WINDOW: terminal monostable threshold window ({mode}, sd={sigma}) ==')
    key = (secs, True)
    jobs = [('window', key, dict(n_rep=n, mode=mode, sigma=sigma, seed=1)) for n in Ns]
    res = _pool_map(jobs, procs)
    thrs = sorted(res[0])
    rows = []
    for n, r in zip(Ns, res):
        ok = [t for t in thrs if r[t] < 1e-3]
        if ok:
            m = min(abs(min(ok) - 0.75), abs(max(ok) - 0.75)) / 0.75
            rows.append([f'N={n}', f'{min(ok):.2f}-{max(ok):.2f}', f'+-{m:.0%}'])
        else:
            rows.append([f'N={n}', 'none', '-'])
    table(rows, ['', 'usable threshold', 'margin about 0.75'])
    return res


def exp_hyst(secs=0.5, hs=(0.02, 0.05, 0.10, 0.20, 0.30), Ns=(1, 4, 16),
             sigma=0.4, mode='regen', procs=8):
    """Comparator hysteresis at the repeater: noise immunity versus pulse-width loss."""
    print(f'\n== HYSTERESIS at the repeater ({mode}, sd={sigma}) ==')
    key = (secs, True)
    jobs, idx = [], []
    for h in hs:
        for n in Ns:
            jobs.append(('cascade', key, dict(n_rep=n, mode=mode, sigma=sigma, h=h, seed=1)))
            idx.append((h, n))
    got = dict(zip(idx, _pool_map(jobs, procs)))
    rows = []
    for h in hs:
        cells = []
        for n in Ns:
            r = got[(h, n)]
            cells.append('no lock' if not r['locked'] else f'{r["ber"]:.1e}')
        rows.append([f'{h:.2f}'] + cells)
    table(rows, ['hysteresis'] + [f'N={n}' for n in Ns])
    return got


def exp_reach(secs=0.5, atts=(1.0, 0.5, 0.25, 0.15, 0.10, 0.07), sigma=0.1,
              Ns=(1, 8), h=HYST, procs=8):
    """
    Span loss against a FIXED comparator threshold -- the 75176's +-200 mV is an
    absolute figure, so span loss eats hysteresis margin directly.
    """
    print(f'\n== SPAN LOSS with fixed hysteresis h={h} (sd={sigma} at the far end) ==')
    key = (secs, True)
    jobs, idx = [], []
    for a in atts:
        for n in Ns:
            jobs.append(('cascade', key, dict(n_rep=n, mode='regen', sigma=sigma,
                                              att=a, h=h, seed=1)))
            idx.append((a, n))
    got = dict(zip(idx, _pool_map(jobs, procs)))
    rows = []
    for a in atts:
        cells = []
        for n in Ns:
            r = got[(a, n)]
            cells.append('no lock' if not r['locked'] else f'{r["ber"]:.1e}')
        rows.append([f'{a:.2f}', f'{20 * np.log10(1 / a):.1f} dB'] + cells)
    table(rows, ['gain', 'span loss'] + [f'N={n}' for n in Ns])
    return got


def exp_squelch(secs=0.3, Ns=(1, 4), sigma=0.2, procs=1):
    """
    A dead span with induction on it, regenerated N times.  The terminal must
    still refuse to lock (spec 8.1) -- a repeater that re-squares noise hands the
    next span a FULL-amplitude junk signal, so this has to be checked, not assumed.
    """
    print(f'\n== SQUELCH: noise-only input, regenerated ==')
    rows = []
    for n in Ns:
        for nsd in (0.05, 0.2, 1.0):
            rng = np.random.default_rng(3)
            L = int(secs * LINE * OS / 2) * 2
            x = rng.normal(0, nsd, L)
            for k in range(n):
                w = front_end(x, HYST, OS)
                x = span(w.astype(np.float64) * 2 - 1, sigma, FC, 1.0, seed=50 + k, os=OS)
            w = front_end(x, HYST, OS)
            g = intervals(w, OS)
            rb = fast.mono_decode(w, OS)
            st = link.framer(rb, NCH, **LOF)[2] if len(rb) > 100 else dict(lock_bit=None)
            ones = float(rb.mean()) if len(rb) else float('nan')
            rows.append([f'N={n}', f'sd={nsd}', f'{len(rb)}',
                         f'{ones:.3f}', f'{np.mean(g):.2f}' if len(g) else '-',
                         'LOCKS' if st['lock_bit'] is not None else 'no'])
    table(rows, ['repeaters', 'line noise', 'bits recovered', 'fraction 1s',
                 'mean interval', 'terminal framer'])
    return rows


def exp_polarity(secs=0.3, n_rep=4, sigma=0.3):
    """Tip/ring swapped on one intermediate span."""
    print(f'\n== POLARITY: pair reversed at a repeater ==')
    line, ch = stream(secs)
    rows = []
    for inv in ((), (0,), (1,), (0, 2)):
        w = cascade(line, n_rep, mode='regen', sigma=sigma, seed=2, invert_at=inv)
        r = score(w, ch, line)
        rows.append([str(inv) if inv else 'none', f'{r["ber"]:.1e}',
                     'yes' if r['locked'] else 'NO', r['lof']])
    table(rows, ['spans reversed', 'line BER', 'framer locks', 'LOF events'])
    return rows


def exp_audio(secs=2.0, Ns=(0, 1, 4, 16), sigma=0.3, mode='regen'):
    """Real speech, whole chain, segmental SNR -- comparable with validate.py."""
    print(f'\n== AUDIO through the chain (sd={sigma}/span, {mode}) ==')
    p = run.params(RATE)
    src = []
    for f in ('speech30.wav', 'spk_300.wav', 'spk_600.wav'):
        a, sr = audio.read_wav(f, seconds=secs)
        a = audio.bandlimit(a, sr)
        src.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), sr, RATE))
    L = min(map(len, src))
    src = [s[:L] for s in src]
    ch = np.array([cvsd.encode(s, p) for s in src])
    sg = np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8), np.zeros(L, np.uint8)])
    line = link.build(ch, sg)
    rows = []
    for n in Ns:
        w = cascade(line, n, mode=mode, sigma=sigma, seed=4)
        rb = fast.mono_decode(w, OS)
        c, s, st = link.framer(rb, NCH, **LOF)
        out = audio.reconstruct(cvsd.decode(c[0], p), RATE)
        a, b, _ = audio.align(src[0], out)
        segs = audio.seg_snr_db(a, audio.gain_match(a, b), RATE)
        ber, slips = track_ber(rb, line)
        rows.append([f'N={n}', f'{n + 1}', f'{ber:.1e}', st['lof_events'], f'{segs:.2f} dB'])
        del w
        gc.collect()
    table(rows, ['repeaters', 'spans', 'line BER', 'LOF events', 'segmental SNR'])
    return rows


def main():
    import sys
    which = sys.argv[1:] or ['cascade', 'jitter', 'edge', 'window', 'hyst',
                             'retimerc', 'next', 'impulse', 'reach', 'squelch', 'polarity', 'audio']
    if 'cascade' in which:
        exp_cascade(secs=0.5, sigmas=(0.2, 0.3, 0.4, 0.5), Ns=(0, 1, 2, 4, 8, 16, 32))
    if 'jitter' in which:
        exp_jitter(secs=0.5, sigmas=(0.0, 0.3, 0.4), Ns=(0, 1, 2, 4, 8, 16, 32))
    if 'window' in which:
        exp_window(secs=0.5, sigma=0.3, Ns=(0, 1, 2, 4, 8, 16, 32), mode='regen')
        exp_window(secs=0.5, sigma=0.4, Ns=(0, 1, 2, 4, 8, 16), mode='regen')
    if 'hyst' in which:
        exp_hyst(secs=0.5, Ns=(1, 4, 16), sigma=0.4)
    if 'edge' in which:
        exp_edge(secs=0.5)
    if 'retimerc' in which:
        exp_retime_rc()
    if 'impulse' in which:
        exp_impulse()
    if 'next' in which:
        exp_next()
    if 'reach' in which:
        exp_reach(secs=0.5, sigma=0.0, Ns=(1, 8))
        exp_reach(secs=0.5, sigma=0.05, Ns=(1, 8))
    if 'squelch' in which:
        exp_squelch()
    if 'polarity' in which:
        exp_polarity()
    if 'audio' in which:
        exp_audio()



def exp_edge(secs=0.5, Ns=(0, 1, 2, 4, 8, 16, 32), mode='regen',
             sigmas=(0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65), procs=8):
    """
    Per-span noise the chain tolerates, versus N.  Regeneration makes errors
    ADD along the chain instead of letting noise add, so the price of N spans is
    only the SNR needed to divide the per-span error rate by N -- and because
    the error curve is steep, that price is small.  This measures how small.
    """
    print(f'\n== NOISE EDGE: per-span sd at which the chain breaks ({mode}) ==')
    key = (secs, True)
    jobs, idx = [], []
    for n in Ns:
        for sg in sigmas:
            jobs.append(('cascade', key, dict(n_rep=n, mode=mode, sigma=sg, seed=1)))
            idx.append((n, sg))
    got = dict(zip(idx, _pool_map(jobs, procs)))
    rows = []
    for n in Ns:
        best = {}
        for tgt in (1e-4, 1e-3, 1e-2):
            ok = [sg for sg in sigmas
                  if got[(n, sg)]['locked'] and got[(n, sg)]['ber'] < tgt]
            best[tgt] = max(ok) if ok else None
        rows.append([f'N={n}', f'{n + 1}'] +
                    [f'{best[t]:.2f}' if best[t] else '-' for t in (1e-4, 1e-3, 1e-2)] +
                    [' '.join(f'{got[(n, sg)]["ber"]:.0e}' for sg in sigmas)])
    table(rows, ['repeaters', 'spans', 'sd @1e-4', 'sd @1e-3', 'sd @1e-2',
                 'BER at sd ' + ','.join(f'{s:.2f}' for s in sigmas)])
    return got


def exp_next(secs=0.5, xts=(0.0, 0.10, 0.20, 0.30, 0.40, 0.50), Ns=(0, 1, 4, 8),
             sigmas=(0.0, 0.2), procs=8):
    """
    Near-end crosstalk at the repeater: the outgoing driver of one direction into
    the incoming receiver of the other.  At a repeater the aggressor is at full
    launch level and the victim is a whole span down, so this is the impairment
    that is WORSE at a repeater than at a terminal.
    """
    print('\n== NEAR-END CROSSTALK at the repeater '
          '(rms relative to the wanted launched peak, as for sigma) ==')
    key = (secs, True)
    jobs, idx = [], []
    for sg in sigmas:
        for x in xts:
            for n in Ns:
                jobs.append(('cascade', key, dict(n_rep=n, mode='regen', sigma=sg,
                                                  xt=x, seed=1)))
                idx.append((sg, x, n))
    got = dict(zip(idx, _pool_map(jobs, procs)))
    for sg in sigmas:
        rows = []
        for x in xts:
            cells = ['no lock' if not got[(sg, x, n)]['locked']
                     else f'{got[(sg, x, n)]["ber"]:.1e}' for n in Ns]
            rows.append([f'{x:.2f}',
                         '-' if x == 0 else f'{20 * np.log10(1 / x):.0f} dB'] + cells)
        print(f'per-span noise sd = {sg}')
        table(rows, ['NEXT/signal', 'rejection'] + [f'N={n}' for n in Ns])
    return got


def exp_impulse(secs=0.5, rates=(0, 5, 20, 50), Ns=(0, 1, 2, 4, 8),
                modes=('amplify', 'regen'), sigma=0.1, procs=8):
    """
    Plant impulse noise -- switching transients, relay operation, induction --
    at every span.  Spec 5.3 found the monostable receiver confines impulse
    damage where a PLL smears it; a regenerated chain has no loop either, so
    errors should ADD across spans rather than grow.  Measured here.
    """
    print('\n== PLANT IMPULSE NOISE, one independent burst train per span ==')
    key = (secs, True)
    jobs, idx = [], []
    for mode in modes:
        for r in rates:
            for n in Ns:
                jobs.append(('cascade', key, dict(n_rep=n, mode=mode, sigma=sigma,
                                                  impulse=r or None, seed=1)))
                idx.append((mode, r, n))
    got = dict(zip(idx, _pool_map(jobs, procs)))
    for mode in modes:
        rows = []
        for r in rates:
            cells = ['no lock' if not got[(mode, r, n)]['locked']
                     else f'{got[(mode, r, n)]["ber"]:.1e} ({got[(mode, r, n)]["lof"]})'
                     for n in Ns]
            rows.append([f'{r}/s'] + cells)
        print(f'{mode}')
        table(rows, ['impulse rate'] + [f'N={n}' for n in Ns])
    return got


def exp_retime_rc(secs=0.5, mids=(0.42, 0.46, 0.50, 0.54, 0.58), Ns=(4, 16),
                  sigma=0.4, procs=8):
    """Tolerance of the retiming one-shot's RC, if retiming is ever populated."""
    print(f'\n== RETIMING ONE-SHOT RC (sd={sigma}) ==')
    key = (secs, True)
    jobs, idx = [], []
    for m in mids:
        for n in Ns:
            jobs.append(('cascade', key, dict(n_rep=n, mode='retime', sigma=sigma,
                                              seed=1, mid=m)))
            idx.append((m, n))
    got = dict(zip(idx, _pool_map(jobs, procs)))
    rows = []
    for m in mids:
        rows.append([f'{m:.2f}', f'{(m / 0.5 - 1) * 100:+.0f}%'] +
                    ['no lock' if not got[(m, n)]['locked'] else f'{got[(m, n)]["ber"]:.1e}'
                     for n in Ns])
    table(rows, ['one-shot width', 'error'] + [f'N={n}' for n in Ns])
    return got


if __name__ == '__main__':
    main()
