"""
Validation of the 3-channel build against the claims in docs/spec.md.

    frame   [A1][C1][A2][C2][A3][C3][S][T]   8 bits @ 32 kHz
            256 kbps line, 512 kbaud biphase, 8.192 MHz master

Runs the whole chain -- CVSD, frame, differential Manchester, cable, noise,
monostable receiver, framer, demux -- and checks each spec claim with an
explicit pass criterion.  Simulation sample rate is 8.192 MHz, i.e. exactly the
hardware master clock, so OS=32 samples per line bit.
"""
import numpy as np, gc, sys
from scipy import signal
import audio, cvsd, link, run, fast

RATE, NCH, FLEN = 32000, 3, 8
LINE = RATE * FLEN            # 256 kbps
SYM = 2 * LINE                # 512 kbaud
OS = 32
FS = LINE * OS                # 8.192 MHz
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1)
p = run.params(RATE)
SRC = ('speech30.wav', 'spk_300.wav', 'spk_600.wav')

results = []


def check(name, ok, detail):
    results.append((name, ok, detail))
    print(f'  [{"PASS" if ok else "FAIL"}] {name:38s} {detail}')


def lp(x, fc, order):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def load(secs):
    out = []
    for f in SRC:
        a, fs = audio.read_wav(f, seconds=secs)
        a = audio.bandlimit(a, fs)
        out.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, RATE))
    L = min(map(len, out))
    return [s[:L] for s in out]


def line_wave(line, sigma=0.0, fc=900_000, seed=0):
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    x = lp(x, fc, 1)
    x /= np.abs(x).max()
    if sigma:
        x += rng.normal(0, sigma, len(x))
    w = fast.slice_hyst(lp(x, SYM, 2), 0.05)
    del x
    gc.collect()
    return w


def chan_ber(c, ref, pos=None, hi=2000):
    """BER with an explicit offset search.  The recovered stream's alignment to
    the transmitted one is unknown, so it must be found, not assumed."""
    # find the offset on a short probe, then score on the full length
    probe = 50_000
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


# ---------------------------------------------------------------- 1. framing
print('\n1. FRAMING  (spec 2.1, 6)')
src = load(6.0)
L = len(src[0])
ch = np.array([cvsd.encode(s, p) for s in src])
sg = np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8), np.zeros(L, np.uint8)])
line = link.build(ch, sg)

phases_ok, exact_ok = True, True
for k in range(FLEN):
    c, s, st = link.framer(line, NCH, skew=k, **LOF)
    true = (FLEN - k % FLEN) % FLEN
    phases_ok &= (st['lock_phase'] == true and not st['false_lock'])
    best = 1.0
    for o in range(0, 400):
        n = min(len(ch[0]) - o, len(c[0]))
        if n < 20000:
            break
        e = float((c[0][:n] != ch[0][o:o + n]).mean())
        best = min(best, e)
        if best == 0.0:
            break
    exact_ok &= (best == 0.0)
check('lock to true phase, all 8 skews', phases_ok, 'ideal stream')
check('bit-exact channel recovery', exact_ok, 'BER = 0 at every skew')

# adjacency rule: no wrong alignment may see two static bits
names = ['A1', 'C1', 'A2', 'C2', 'A3', 'C3', 'S', 'T']
static = {'A1', 'A2', 'A3'}      # S/T are the mechanism, not violations
bad = [k for k in range(1, FLEN)
       if names[(FLEN - 2 + k) % FLEN] in static and names[(FLEN - 1 + k) % FLEN] in static]
check('adjacency rule holds', not bad, 'every wrong alignment gated by a CVSD bit')

# grouped ordering must fail -- proves the test has teeth
gl = link.build(ch, sg, order='grouped')
gbad = sum(1 for k in range(FLEN)
           if link.framer(gl, NCH, skew=k, order='grouped', **LOF)[2]['false_lock'])
check('grouped ordering false-locks', gbad > 0, f'{gbad}/8 skews false-lock (control)')

# ---------------------------------------------------------------- 2. loss of frame
print('\n2. LOSS OF FRAME  (spec 6.1)')
line2 = link.build(ch, np.zeros((NCH, L), np.uint8))
at = (L // 2) * FLEN
det = []
for k in range(1, FLEN):
    st = link.framer(link.slip(line2, at, n=k), NCH, **LOF)[2]
    pos = st['pos']
    tp = np.where(pos < at, pos % FLEN, (pos + k) % FLEN)
    det.append(1000 * int((tp != tp[0]).sum()) / RATE)
check('every slip size detected', max(det) < 2.0, f'worst {max(det):.2f} ms over slips 1-7')
fr = [link.framer(link.impair(line2, ber=b, seed=5), NCH, **LOF)[2]['lof_events']
      for b in (1e-3, 1e-2)]
check('no false reframes', sum(fr) == 0, f'{fr[0]} at 1e-3, {fr[1]} at 1e-2 BER')

# ---------------------------------------------------------------- 3. line
print('\n3. LINE AND RECEIVER  (spec 4, 5)')
w = line_wave(line)
rb = fast.mono_decode(w, OS)
c, s, st = link.framer(rb, NCH, skew=3, **LOF)
b0 = chan_ber(c[0], ch[0], st['pos'])
check('monostable, clean line', b0 == 0.0, f'BER {b0:.1e}, locked at phase {st["lock_phase"]}')

wi = line_wave(line, fc=900_000, seed=0)
inv = fast.slice_hyst(-lp(np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2),
                          SYM, 2), 0.05)
ri = fast.mono_decode(inv, OS)
ci, _, sti = link.framer(ri, NCH, skew=0, **LOF)
check('polarity-blind', chan_ber(ci[0], ch[0], sti['pos']) == 0.0, 'tip/ring swapped, BER 0')
del w, wi, inv
gc.collect()

noise_rows = []
for sg_ in (0.2, 0.4, 0.5, 0.6):
    ww = line_wave(line, sigma=sg_, seed=1)
    cc, _, ss = link.framer(fast.mono_decode(ww, OS), NCH, skew=3, **LOF)
    noise_rows.append((sg_, chan_ber(cc[0], ch[0], ss['pos']) if ss['frames'] > 300 else 1.0))
    del ww
    gc.collect()
clean_to = max(s_ for s_, b in noise_rows if b == 0.0)
check('error-free margin', clean_to >= 0.4,
      'clean to sd=' + f'{clean_to} ({20*np.log10(1/clean_to):.1f} dB peak SNR)')

# monostable RC window
win = []
w = line_wave(line, sigma=0.4, seed=1)      # design limit; link is clean to 0.6
for thr in (0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90):
    cc, _, ss = link.framer(fast.mono_decode(w, OS, thr=thr), NCH, skew=3, **LOF)
    if ss['frames'] > 300 and chan_ber(cc[0], ch[0], ss['pos']) < 1e-3:
        win.append(thr)
del w
gc.collect()
margin = min(abs(min(win) - 0.75), abs(max(win) - 0.75)) / 0.75 if win else 0
check('monostable RC window', margin >= 0.13,
      f'{min(win):.2f}-{max(win):.2f} of a cell, +-{margin:.0%} at sd=0.4')

# ---------------------------------------------------------------- 4. audio
print('\n4. AUDIO  (spec 9)')
w = line_wave(line)
c, s, st = link.framer(fast.mono_decode(w, OS), NCH, skew=3, **LOF)
del w
gc.collect()
outs = [audio.reconstruct(cvsd.decode(c[i], p), RATE) for i in range(NCH)]
a, b, _ = audio.align(src[0], outs[0])
segs = audio.seg_snr_db(a, audio.gain_match(a, b), RATE)
check('segmental SNR', segs >= 17.0, f'{segs:.2f} dB, 32 kbps CVSD over the link')

cm = np.zeros((NCH, NCH))
for i in range(NCH):
    for j in range(NCH):
        aa, bb, _ = audio.align(src[j][:len(outs[i])], outs[i])
        cm[i, j] = np.corrcoef(aa, bb)[0, 1]
off = max(abs(cm[i, j]) for i in range(NCH) for j in range(NCH) if i != j)
diag = min(cm[i, i] for i in range(NCH))
check('channel isolation', diag > 0.95 and off < 0.05,
      f'diagonal >= {diag:.3f}, off-diagonal <= {off:.3f}')

# ---------------------------------------------------------------- 5. signalling
print('\n5. SIGNALLING  (spec 7)')
sg2 = np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8), np.zeros(L, np.uint8)])
l3 = link.build(ch, sg2)
worst = 0
for ber in (1e-3, 1e-2, 3e-2):
    cc, ss_, stt = link.framer(link.impair(l3, ber=ber, seed=13), NCH, **LOF)
    filt = link.rc_schmitt(ss_[0], RATE, tau=2e-3)      # channel 1 is idle
    worst = max(worst, len(link.runs_of(filt)))
check('no spurious ring assertions', worst == 0, f'{worst} assertions to 3e-2 BER, ch1 idle')

pulse = np.zeros(L, np.uint8)
for k_ in range(int(L / RATE * 10) - 2):
    a0 = int((k_ * 0.100 + 0.20) * RATE)
    a1 = a0 + int(0.060 * RATE)
    if a1 < L:
        pulse[a0:a1] = 1
l4 = link.build(ch, np.array([pulse, np.zeros(L, np.uint8), np.zeros(L, np.uint8)]))
tx_n = len(link.runs_of(pulse))
cc, ss_, _ = link.framer(link.impair(l4, ber=1e-2, seed=21), NCH, **LOF)
rx = link.runs_of(link.rc_schmitt(ss_[0], RATE, tau=2e-3)) / RATE * 1000.0
rx = rx[rx > 5]
check('dial pulse fidelity', len(rx) == tx_n and abs(rx.mean() - 60) / 60 < 0.02,
      f'{len(rx)}/{tx_n} pulses at 1e-2 BER, make {rx.mean():.2f} ms vs 60 nominal')

# ---------------------------------------------------------------- 6. squelch
print('\n6. SQUELCH  (spec 8.1)')
locked = []
for sg_ in (0.05, 0.2, 0.5):
    rng = np.random.default_rng(1)
    nw = fast.slice_hyst(lp(rng.normal(0, sg_, len(line) * OS // 2), SYM, 2), 0.05)
    rr = fast.mono_decode(nw, OS)
    stt = link.framer(rr, NCH, **LOF)[2] if len(rr) > 100 else dict(lock_bit=None)
    locked.append(stt['lock_bit'] is not None)
    del nw
    gc.collect()
check('never locks on noise', not any(locked), 'not-locked is a valid mute trigger')

# ---------------------------------------------------------------- summary
print(f'\n{"="*64}')
n_fail = sum(1 for _, ok, _ in results if not ok)
print(f'{len(results) - n_fail}/{len(results)} checks passed')
for name, ok, detail in results:
    if not ok:
        print(f'  FAILED: {name} -- {detail}')
sys.exit(1 if n_fail else 0)
