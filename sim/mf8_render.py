"""
Render recovered audio from the MF8 link, for listening.

Six independent talkers, 15 s each, through the whole chain in both line codes
under a range of line and noise conditions, written to out/ as 8 kHz wavs.

15 s of line at OS = 32 is 246 M samples -- 2.0 GB as float64 -- so the physical
layer is STREAMED in chunks and only the cheap intermediate is accumulated:
the sliced uint8 waveform for differential Manchester, the decimated float32 for
AMI.  Filter state carries across chunks; the hysteretic slicer's does not, which
costs at most one sample per chunk boundary out of 16 M and self-heals.

Usage:  python3 sim/mf8_render.py           everything, ~20 min
        python3 sim/mf8_render.py --secs 5  a shorter pass
"""
import os, sys, gc, time, numpy as np
from scipy import signal
import audio, cvsd, fast, phy, mf8

RATE = 64000
LINE = 8 * RATE
NCH = 6
OSB = 32
FS = LINE * OSB
CABLE = 1.8e6
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
WAV_FS = 8000                      # the chain band-limits to 300-3400 Hz
CHUNK_FRAMES = 64000               # 1 s of line per chunk

CONDITIONS = [
    ('clean',      dict()),
    ('sd0.40',     dict(sd=0.40)),
    ('sd0.50',     dict(sd=0.50)),
    ('sd0.60',     dict(sd=0.60)),
    ('sd0.70',     dict(sd=0.70)),
    ('imp10',      dict(imp=10.0)),
    ('imp100',     dict(imp=100.0)),
    ('atten0.25',  dict(atten=0.25, sd=0.10)),
    ('atten0.12',  dict(atten=0.12, sd=0.10)),
]


def sources(secs):
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


def _sos(fc, order):
    return signal.butter(order, min(0.99, 2 * fc / FS), btype='low')


def stream(ln, code, sd=0.0, imp=0.0, atten=1.0, seed=1, hyst=0.05):
    """Chunked physical layer.  Returns the recovered bit stream."""
    b_c, a_c = _sos(CABLE, 1)
    zi_c = signal.lfilter_zi(b_c, a_c) * 0.0
    rx_fc = 2 * LINE if code == 'dm' else LINE
    b_r, a_r = _sos(rx_fc, 2)
    zi_r = signal.lfilter_zi(b_r, a_r) * 0.0
    acc = []
    scale = None
    last_state = 0
    # Encode the WHOLE line first: dm_encode carries a running level and
    # ami_encode a running polarity, so encoding chunk by chunk restarts them
    # and corrupts the bit at every boundary.  The encoded form is cheap (one
    # byte per half-cell); it is the upsampled float that has to be streamed.
    sym = (fast.dm_encode(ln).astype(np.float64) * 2 - 1) if code == 'dm' \
        else fast.ami_encode(ln)
    up = OSB // 2 if code == 'dm' else OSB
    step = CHUNK_FRAMES * 8 * (2 if code == 'dm' else 1)
    for ci, s0 in enumerate(range(0, len(sym), step)):
        x = np.repeat(sym[s0:s0 + step], up)
        x, zi_c = signal.lfilter(b_c, a_c, x, zi=zi_c)
        if scale is None:                       # fixed driver level, set once
            scale = 1.0 / max(np.abs(x).max(), 1e-12)
        x *= scale
        if atten != 1.0:
            x *= atten
        rng = np.random.default_rng(seed * 100003 + ci)
        if sd:
            x += rng.normal(0, sd, len(x))
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0),
                                 seed=seed * 7919 + ci)
        x, zi_r = signal.lfilter(b_r, a_r, x, zi=zi_r)
        if code == 'dm':
            pad = np.array([2.0 * hyst if last_state else -2.0 * hyst])
            sl = fast.slice_hyst(np.concatenate([pad, x]), hyst)
            last_state = int(sl[-1])
            acc.append(sl[1:]); del sl
        else:
            acc.append(x[::4].astype(np.float32))
        del x; gc.collect()
    del sym; gc.collect()
    w = np.concatenate(acc)
    del acc; gc.collect()
    if code == 'dm':
        rb = fast.mono_decode(w, OSB, thr=0.75, dead=0.25)
    else:
        rb = fast.ami_decode(w.astype(np.float64), OSB // 4, thresh=0.5)
    del w; gc.collect()
    return rb


def longest_run(pos, flen=8):
    if len(pos) == 0:
        return None
    return max(np.split(pos, np.flatnonzero(np.diff(pos) != flen) + 1), key=len)


def render(tag, ln, code, src, bits, p, **kw):
    """Assemble what the link actually DELIVERS: the full duration, with the
    output muted wherever the framer is not locked (mf8-spec.md 13).  Each
    locked run is placed at its own source offset, because a slip re-phases the
    stream and a single global offset would smear everything after the first."""
    t0 = time.time()
    rb = stream(ln, code, **kw)
    st = mf8.framer(rb)
    nfr = len(ln) // 8
    down = 100.0 * (1.0 - st['frames'] / nfr)
    pos = st['pos']
    # Gaps are filled with 1010 -- the codec's own idle pattern, and the
    # empty-slot fill mf8-spec.md 12.3 specifies because it decodes as silence.
    # A card's decoder runs continuously; what the mute gates is its OUTPUT.
    idle = (np.arange(nfr) & 1).astype(np.uint8)
    out = [idle.copy() for _ in range(NCH)]
    live = np.zeros(nfr, bool)
    segs = [] if len(pos) == 0 else np.split(
        pos, np.flatnonzero(np.diff(pos) != 8) + 1)
    placed = 0
    shift = None                                # source minus recovered, frames
    for g in segs:
        if len(g) < 66:                         # under ~1 ms: not a run
            continue
        g = g[:len(g) - 2]
        c0 = int(g[0]) // 8
        if shift is None:
            # First run: wide forward search.  Bits are only ever LOST, so the
            # source index runs AHEAD of the recovered index.  All six lanes,
            # over the run's first 4096 frames: one lane is not enough, because
            # a talker's leading silence is CVSD idle, period 2, and an idle
            # lane matches at every even offset -- the run is then placed up
            # to 64 frames off, the shift it pins is one the narrow window
            # below never recovers from, and the rest of the clip is muted.
            cand = range(max(0, c0 - 64), min(c0 + 6000, nfr))
            lanes = np.stack([rb[g[:4096] + mf8.CBIT[j]] for j in range(NCH)])
            ref_of = lambda d, n: np.stack([bits[j][d:d + n] for j in range(NCH)])
        else:
            # Later runs: a slip loses only a few bits, so the offset sits just
            # past the previous run's.  A narrow window over ALL six lanes aligns
            # even a 64-frame run -- the old 2000-frame minimum discarded most of
            # the LOCKED time at high impulse rates and reported it as muted.
            cand = range(max(0, c0 + shift - 4), min(c0 + shift + 64, nfr))
            lanes = np.stack([rb[g + mf8.CBIT[j]] for j in range(NCH)])
            ref_of = lambda d, n: np.stack([bits[j][d:d + n] for j in range(NCH)])
        best = (1.0, None)
        for d in cand:
            n = min(lanes.shape[1], nfr - d)
            if n < 32:
                break
            e = float((lanes[:, :n] != ref_of(d, n)).mean())
            if e < best[0]:
                best = (e, d)
            if e == 0.0:
                break
        # only place a run whose offset the search is CONFIDENT about.  A run
        # we cannot align is a run we cannot honestly render, so it is muted
        # rather than placed somewhere plausible-looking.
        if best[1] is None or best[0] > 0.10:
            continue
        d = best[1]; n = min(len(g), nfr - d)
        shift = d - c0
        for j in range(NCH):
            out[j][d:d + n] = rb[g[:n] + mf8.CBIT[j]]
        live[d:d + n] = True
        placed += 1
    del rb; gc.collect()
    if not placed:
        return dict(tag=tag, code=code, lof=st['lof_events'], down=down,
                    seg=[float('nan')] * NCH, mute=100.0, runs=0,
                    secs=time.time() - t0, wrote=0)
    mute = 100.0 * (1.0 - live.mean())
    segsnr = []
    for j in range(NCH):
        # One continuous decode, gaps idling on 1010, then the OUTPUT is muted
        # in the gaps.  Feeding the gaps zeros instead slams the integrator to
        # the rail -- the +47.7 dB failure mf8-spec.md 13 requires squelch for.
        dec = cvsd.decode(out[j], p)
        dec[~live[:len(dec)]] = 0.0
        y = audio.reconstruct(dec, RATE)
        # The assembled output is already in the SOURCE time base -- each run was
        # placed at its own offset -- so no global align, which would shift the
        # arrays out from under the `live` mask.  Score only where the link was
        # up; the mutes are counted separately by `mute`.
        n = min(len(y), len(src[j]), len(live))
        m = live[:n]
        aa = src[j][:n][m]
        bb = audio.gain_match(src[j][:n], y[:n])[m]
        segsnr.append(audio.seg_snr_db(aa, bb, RATE) if m.sum() > RATE // 4
                      else float('nan'))
        yy = audio.resample_to(y, RATE, WAV_FS)
        audio.write_wav(os.path.join(OUT, f'{code}_{tag}_ch{j + 1}.wav'),
                        yy * (0.9 / max(np.abs(yy).max(), 1e-9)), WAV_FS)
    return dict(tag=tag, code=code, lof=st['lof_events'], down=down,
                seg=segsnr, mute=mute, runs=placed, secs=time.time() - t0,
                wrote=NCH)


def main(secs=15.0):
    os.makedirs(OUT, exist_ok=True)
    old = [f for f in os.listdir(OUT) if os.path.isfile(os.path.join(OUT, f))]
    for f in old:
        os.remove(os.path.join(OUT, f))
    print(f'out/: removed {len(old)} files from previous runs\n')

    print(f'Encoding {secs:.0f} s x {NCH} talkers at {RATE // 1000} kbps CVSD...')
    src, bits, p = sources(secs)
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf8.build(bits, A)
    print(f'  line: {len(ln)} bits, {len(ln) // 8} frames, '
          f'{len(ln) / LINE:.1f} s at {LINE // 1000} kbps\n')

    for j in range(NCH):
        y = audio.resample_to(src[j], RATE, WAV_FS)
        audio.write_wav(os.path.join(OUT, f'source_ch{j + 1}.wav'),
                        y * (0.9 / max(np.abs(y).max(), 1e-9)), WAV_FS)
    print(f'wrote {NCH} source references\n')

    hdr = (f'  {"condition":12s} {"code":6s} {"LOF":>5s} {"muted":>7s} '
           f'{"runs":>5s} ' + ' '.join(f'ch{j + 1:<5d}' for j in range(NCH)))
    print(hdr)
    rows = []
    for tag, kw in CONDITIONS:
        for code, label in (('dm', 'DM'), ('ami', 'AMI')):
            r = render(tag, ln, code, src, bits, p, **kw)
            rows.append(r)
            segs = ' '.join(('  --  ' if np.isnan(v) else f'{v:6.2f}')
                            for v in r['seg'])
            print(f'  {tag:12s} {label:6s} {r["lof"]:>5d} {r["mute"]:6.2f}% '
                  f'{r["runs"]:>5d} {segs}', flush=True)
    n = len([f for f in os.listdir(OUT) if f.endswith('.wav')])
    print(f'\nout/: {n} wavs at {WAV_FS // 1000} kHz — {NCH} sources, plus one per '
          f'channel for every condition and code that held lock long enough to place audio.')
    print('Each wav is the FULL duration: what the link delivers, with the output')
    print('muted wherever the framer was not locked, so the outages are audible in')
    print('place rather than edited out.  "muted" is the fraction of the clip lost')
    print('that way and "runs" the number of locked stretches stitched together.')
    print('segSNR is scored only where the link was up, so it measures fidelity')
    print('and the mute column measures continuity -- they fail independently.')
    print('A "--" row never held lock long enough to place any audio.')


if __name__ == '__main__':
    a = sys.argv[1:]
    secs = float(a[a.index('--secs') + 1]) if '--secs' in a else 15.0
    main(secs)
