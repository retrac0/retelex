"""
The channel card's audio filters, as causal analog filters that can be built.

QUESTION
  Every audio number in the repository is scored through zero-phase, high-order
  digital filters that cannot be built: audio.bandlimit (6th-order Butterworth
  band-pass 300-3400 Hz, sosfiltfilt at the source rate) before the encoder, and
  audio.reconstruct (8th-order Butterworth low-pass 3400 Hz, sosfiltfilt at the
  bit rate) after the decoder.  channel-card.md §3 says only 'build it at 3rd or
  4th order'.  What input band-limiting and what reconstruction filter does the
  card need, and how many op-amp sections is that?

METHOD
  Analog filters.  Every analog filter is applied as its exact s-plane transfer
  function H(j2pi f), evaluated from its poles and zeros (on a 0.5 Hz grid and
  interpolated onto the FFT grid of the whole clip; §0 prints the interpolation
  error).  At least 0.25 s of silence is appended so the causal tails do not
  wrap round.  No bilinear transform is used anywhere, so no stopband is warped;
  §0 shows what a bilinear design would have claimed.

  Encoder input.  The comparator and its D flip-flop sample the filtered analog
  input at the bit instants, with nothing else in the way.  Talker content ends
  at 8 kHz <= R/2, so the source is band-limited-interpolated to the bit rate,
  filtered on that grid, and those samples go to card.encode.

  Decoder output.  The integrator is a constant +/- current into C_int for a
  whole bit, so its voltage ramps from one bit-edge value to the next.  The
  decoder's per-bit values are joined by straight lines at FA = 192 kHz (12, 6
  and 3 points per bit at 16, 32 and 64 kbps).  This keeps what a real integrator
  emits: the sinc^2 droop in band and the images of the quantisation noise above
  R/2.  Scores and band powers are computed on this 192 kHz waveform.

  Alignment.  Delay is removed to a fraction of a 192 kHz sample: the integer
  cross-correlation peak, a parabolic refinement, then a linear-interpolation
  fractional shift.  Integer-sample alignment is not good enough: one 192 kHz
  sample (5 us) moves a causal filter's conventional score by 1-4 dB, and §0
  shows that card.score's whole-bit alignment costs about 4 dB at 64 kbps.

  Scores.  Segmental SNR as audio.seg_snr_db computes it (20 ms frames, -45 dB
  silence gate, clipped to -10..35 dB), least-squares gain:
    conventional  decoded-through-H against the source, as card.score does.
                  H's phase and passband shape count as error.
    matched       decoded-through-H against source-through-the-same-H.  H is
                  common to both, so only the codec error H lets through remains:
                  quantisation-noise leakage.  Phase is inaudible; this is the
                  number to choose a filter on.
    ceiling       source-through-H against the source: the conventional score of
                  a perfect codec, i.e. what H's phase and shape cost on their own.
    BP window     (§3, §5) matched, with a zero-phase 300-3400 Hz window
                  (audio.bandlimit's shape) on both sides as well, so every input
                  filter is judged on the same telephone band.  Without it a
                  high-pass looks worse only because it removes low-frequency
                  speech energy from the reference, which segSNR rewards.
  'ideal' is audio.reconstruct's shape, |8th-order Butterworth 3.4 kHz|^2 at zero
  phase, in the same 192 kHz chain.  Its -3 dB point is 3.22 kHz, not 3.4, so
  'ideal@fc' moves that shape to put -3 dB at fc: comparing against it separates
  a candidate's bandwidth from its stopband.

SECTIONS
  0  model checks: source content, bilinear warping, integrator droop, the metric
  1  reconstruction low-pass: Butterworth 1-6 at 3.0 / 3.4 / 4.0 kHz, Chebyshev
     0.5 dB orders 3 and 4 at 3.4 kHz; the minimum order within 0.5 and 1 dB
  2  out-of-band residual at the card output, speech and idle channel
  3  input filter: causal high-pass x causal low-pass, including no low-pass
  4  50 and 60 Hz hum at the card input, with and without the high-pass
  5  the recommended card end to end, and what it takes to build

  §1, §2 and §4 feed the encoder the repository's standard talker
  (card.load_talker: zero-phase band-limited, nominal 0.15 rms FS), so only the
  filter under test differs.  §3 and §5 start from the raw 16 kHz file with its
  gain set so that the 300-3400 Hz band is at nominal, as load_talker sets it.
  Card as designed: card.CardParams(rate), slew 12000 at every rate.
  7 talkers x 16/32/64 kbps.  §0, §1, §2, §5 on 30 s clips; §3, §4 on 15 s.
  At most 2 worker processes.

Usage:  python3 card_filters.py [0 1 2 3 4 5] [--secs S]
        (all sections: 20-40 minutes on a shared machine.  --secs shortens every
        clip, for checking the script only.)
"""
import os
for _v in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ.setdefault(_v, '1')
import sys, time
import numpy as np
from multiprocessing import Pool
from scipy import signal, fft as sfft
import audio, card, run

FA = 192000                  # analog model rate
MAXLAG = 4096                # alignment search, samples at FA (21 ms)
LAG_DEC = 8                  # delay search on the lowest 12 kHz, then refined
WORKERS = 2
NOM = run.NOMINAL_RMS
SECS_HEAD, SECS_SWEEP = 30.0, 15.0
INBAND = (300.0, 3400.0)
BANDS = ((3400.0, 4000.0), (4000.0, 8000.0), (8000.0, FA / 2.0))
BAND_NAMES = ('3.4-4k', '4-8k', '>8k')
SIL_DB = -45.0               # audio.seg_snr_db's silence gate
F32, C32 = np.float32, np.complex64


# ------------------------------------------------------------------ filters
# spec = (kind, order, corner Hz, btype[, ripple dB]);  None = no filter
def BW(n, fc, bt='lowpass'):
    return ('butter', n, float(fc), bt)


def CH(n, fc, rp=0.5):
    return ('cheby1', n, float(fc), 'lowpass', rp)


IDEAL_3DB = (np.sqrt(2.0) - 1.0) ** (1.0 / 16.0)      # |BW8|^2 is -3 dB at 0.9464 fc
IDEAL = ('ideal', 8, 3400.0, 'lowpass')                 # audio.reconstruct's shape
IDEAL_BP = ('ideal', 6, (300.0, 3400.0), 'bandpass')    # audio.bandlimit's shape


def ideal_at(f3):
    return ('ideal', 8, f3 / IDEAL_3DB, 'lowpass')


RECON = ([BW(n, 3400) for n in range(1, 7)] + [BW(n, 3000) for n in range(2, 7)] +
         [BW(n, 4000) for n in range(2, 7)] + [CH(3, 3400), CH(4, 3400)])
IDEALS_AT = [ideal_at(3000), ideal_at(3400), ideal_at(4000)]
HPFS = [None, BW(1, 200, 'highpass'), BW(2, 200, 'highpass'),
        BW(1, 300, 'highpass'), BW(2, 300, 'highpass')]
LPFS = [None, BW(1, 3400), BW(2, 3400), BW(3, 3400), BW(4, 3400)]
HUM = [(50, -30), (50, -20), (60, -30), (60, -20), (50, -10), (60, -10), (50, 0), (60, 0)]

# The recommendation, chosen from §1-§4; §5 measures it.
REC_HPF = BW(1, 200, 'highpass')
REC_LPF = BW(2, 3400)
REC_RECON = BW(3, 3400)


def name(spec):
    if spec is None:
        return 'none'
    kind, n, fc, bt = spec[:4]
    if kind == 'ideal':
        if bt == 'bandpass':
            return 'ideal BP (audio.bandlimit)'
        if abs(fc - 3400.0) < 1e-6:
            return 'ideal (audio.reconstruct)'
        return f'ideal@{fc * IDEAL_3DB / 1000:.1f}k'
    if bt == 'highpass':
        return f'HP{n} {fc:.0f}'
    return f'{ {"butter": "BW", "cheby1": "Ch"}[kind]}{n} {fc / 1000:.1f}k'


def zpk(spec):
    kind, n, fc, bt = spec[:4]
    w = 2 * np.pi * np.asarray(fc, float)
    if kind == 'cheby1':
        return signal.cheby1(n, spec[4], w, bt, analog=True, output='zpk')
    return signal.butter(n, w, bt, analog=True, output='zpk')


def resp_exact(spec, f):
    z, p, k = zpk(spec)
    s = 2j * np.pi * np.asarray(f, float)
    h = np.full(np.shape(s), k, complex)
    for q in z:
        h *= s - q
    for q in p:
        h /= s - q
    return (h * h.conj()).real if spec[0] == 'ideal' else h


def resp(spec, f):
    """Analog response at f (Hz).  'ideal' is |H|^2, zero phase, as filtfilt gives.
    Large grids: exact on a 0.5 Hz grid, linearly interpolated, single precision."""
    if spec is None:
        return 1.0
    f = np.asarray(f, float)
    if f.size <= 400000:
        return resp_exact(spec, f)
    fg = np.arange(0.0, f[-1] + 1.0, 0.5)
    hg = resp_exact(spec, fg)
    if np.iscomplexobj(hg):
        h = np.empty(f.size, C32)
        h.real = np.interp(f, fg, hg.real)
        h.imag = np.interp(f, fg, hg.imag)
        return h
    return np.interp(f, fg, hg).astype(F32)


def props(spec, points=(50.0, 60.0, 300.0, 3000.0, 3400.0)):
    """Gain re 1 kHz at the given points, -3 dB frequency above 1 kHz, group-delay spread 300-3400 Hz."""
    f = np.arange(20.0, 20000.0, 0.5)
    h = resp_exact(spec, f)
    mag = 20 * np.log10(np.abs(h) + 1e-300)
    g1k = mag[np.searchsorted(f, 1000.0)]
    hi = f > 1000.0
    out = {pt: mag[np.searchsorted(f, pt)] - g1k for pt in points}
    out['f3'] = f[hi][np.argmax(mag[hi] < g1k - 3.0)] if (mag[hi] < g1k - 3.0).any() else np.nan
    if spec[0] == 'ideal':
        out['gd'] = 0.0
    else:
        tg = -np.diff(np.unwrap(np.angle(h))) / np.diff(2 * np.pi * f)
        m = (f[:-1] >= 300.0) & (f[:-1] <= 3400.0)
        out['gd'] = 1000 * (tg[m].max() - tg[m].min())
    return out


# ------------------------------------------------------------------ chain
def grid16(secs):
    """Clip length at 16 kHz: >= 0.25 s of padding, even, and 5-smooth for the FFT."""
    return 2 * sfft.next_fast_len(int(np.ceil((secs + 0.25) * 8000)), True)


def geometry(secs, rate):
    """(samples at 16 kHz, at the bit rate, points per bit at FA, at FA, scored at FA)"""
    n16 = grid16(secs)
    nR = n16 * rate // 16000
    k = FA // rate
    return n16, nR, k, nR * k, int(round(secs * FA))


def pad_to(x, n):
    out = np.zeros(n)
    m = min(n, len(x))
    out[:m] = x[:m]
    return out


def upspec(X, n_in, k):
    """Spectrum of an n_in-sample signal -> spectrum of its band-limited k-fold interpolation."""
    Y = np.zeros(n_in * k // 2 + 1, C32)
    Y[:len(X)] = X * k
    if n_in % 2 == 0:
        Y[len(X) - 1] *= 0.5
    return Y


def hold(y, k, y0=0.0):
    """Integrator voltage at FA: straight lines between bit-edge values, k points per bit."""
    yp = np.concatenate(([y0], y))
    d = np.diff(yp)
    return (yp[:-1, None] + d[:, None] * (np.arange(k) / k)[None, :]).ravel().astype(F32)


def lag_frac(O, R, n, dec):
    """Delay of the signal with spectrum O behind the one with spectrum R, in samples
    of their n-sample grid, resolved to a fraction: correlation on the lowest 1/dec
    of the band (speech is band-limited, nothing is lost), parabolic refinement."""
    m = min(len(O), n // 2 // dec + 1)
    c = sfft.irfft(O[:m] * np.conj(R[:m]), n=n // dec)
    ml = MAXLAG // dec
    cc = np.concatenate((c[-ml:], c[:ml + 1])).astype(float)
    i = int(np.argmax(cc))
    lag = float(i - ml)
    if 0 < i < len(cc) - 1:
        a, b, d = cc[i - 1], cc[i], cc[i + 1]
        if a - 2 * b + d != 0:
            lag += 0.5 * (a - d) / (a - 2 * b + d)
    return lag * dec


def shift(o, tau, nk):
    """o(t + tau), t in [0, nk): remove a delay of tau samples.  o is one period of a
    periodic signal (it came out of an FFT); fraction by linear interpolation, which
    at 192 kHz is within -50 dB of exact across the speech band."""
    L = int(np.floor(tau))
    d = F32(tau - L)
    a = np.roll(o, -L)[:nk + 1]
    return (1 - d) * a[:nk] + d * a[1:]


def score(r, o, R, O, nk):
    """segSNR at FA of time-domain o against r; delay found from their spectra.
    Returns (segSNR, delay in samples, least-squares gain)."""
    tau = lag_frac(O, R, len(o), LAG_DEC)
    t = shift(o, tau, nk)
    rr = r[:nk]
    g = float(np.dot(rr, t) / max(float(np.dot(t, t)), 1e-30))
    return audio.seg_snr_db(rr, g * t, FA), tau, g


def score_rate(xp, y, nx, rate):
    """segSNR at the bit rate with the delay resolved to a fraction (exact phase shift)."""
    n = len(xp)
    X, Y = sfft.rfft(xp), sfft.rfft(y)
    tau = lag_frac(Y, X, n, 1)
    f = sfft.rfftfreq(n, 1.0 / rate)
    t = sfft.irfft(Y * np.exp(2j * np.pi * f * (tau / rate)), n=n)[:nx]
    return audio.seg_snr_db(xp[:nx], audio.gain_match(xp[:nx], t), rate), tau


def band_slices(f):
    idx = lambda fr: int(np.searchsorted(f, fr))
    return slice(idx(INBAND[0]), idx(INBAND[1])), [slice(idx(lo), idx(hi)) for lo, hi in BANDS]


def pw(S):
    return float(np.sum(np.abs(S).astype(float) ** 2))


def seg_masked(s, e, fs=FA):
    """Segmental SNR of speech s against error e, frames gated on s alone."""
    w = int(fs * 0.02)
    nf = min(len(s), len(e)) // w
    ps = (s[:nf * w].astype(float).reshape(-1, w) ** 2).sum(1)
    pe = (e[:nf * w].astype(float).reshape(-1, w) ** 2).sum(1)
    act = 10 * np.log10(ps / w + 1e-20) > SIL_DB
    v = 10 * np.log10(ps[act] / np.maximum(pe[act], 1e-20))
    return float(np.clip(v, -10, 35).mean())


def raw_at_rate(path, rate, secs):
    """Raw talker (content to 8 kHz), gain set so its 300-3400 Hz band is at nominal,
    as the spectrum of its band-limited interpolation to the bit rate (double precision)."""
    raw, fs = audio.read_wav(path, seconds=secs)
    g = NOM / audio.bandlimit(raw, fs).std()
    n16, nR, k, n, nk = geometry(secs, rate)
    X = sfft.rfft(pad_to(g * raw, n16))
    m = rate // 16000
    Y = np.zeros(n16 * m // 2 + 1, complex)
    Y[:len(X)] = X * m
    Y[len(X) - 1] *= 0.5
    return Y


def ifft(S, n):
    return sfft.irfft(S, n=n)


# ------------------------------------------------------------------ jobs
def job_recon(path, rate, secs):
    """§0d, §1, §2: standard input, every reconstruction candidate."""
    n16, nR, k, n, nk = geometry(secs, rate)
    x = card.load_talker(path, rate, secs)
    nx = len(x)
    xp = pad_to(x, nR)
    p = card.CardParams(rate)
    y = card.decode(card.encode(xp, p), p)
    res = {'card.score': card.score(x, y[:nx], rate)}
    res['card.score frac'], res['delay bits'] = score_rate(xp, audio.reconstruct(y, rate), nx, rate)
    po = card.CardParams(rate, slew=run.SLEW[rate])         # spec §11.1's per-rate slews
    yo = card.decode(card.encode(xp, po), po)
    res['run.SLEW int'] = card.score(x, yo[:nx], rate)
    res['run.SLEW frac'] = score_rate(xp, audio.reconstruct(yo, rate), nx, rate)[0]
    del yo

    f = sfft.rfftfreq(n, 1.0 / FA)
    X = upspec(sfft.rfft(xp), nR, k)
    Y = sfft.rfft(hold(y, k))
    x192 = ifft(X, n)
    ib, bs = band_slices(f)
    n8, m8 = n // 12, n // 24 + 1
    for spec in [IDEAL] + IDEALS_AT + RECON:
        H = resp(spec, f)
        O, R = Y * H, X * H
        o, r = ifft(O, n), ifft(R, n)
        d = {}
        d['matched'], tau, g = score(r, o, R, O, nk)
        if spec in IDEALS_AT:
            res[name(spec)] = d
            continue
        d['conv'] = score(x192, o, X, O, nk)[0]
        d['ceil'] = score(x192, r, X, R, nk)[0]
        # matched, scored only below 8 kHz (what a 16 kHz-sampled listener gets)
        Oa = O[:m8] * np.exp(2j * np.pi * f[:m8] * (tau / FA)).astype(C32)
        o8, r8 = ifft(Oa, n8)[:nk // 12], ifft(R[:m8], n8)[:nk // 12]
        d['m8'] = audio.seg_snr_db(r8, audio.gain_match(r8, o8), 16000)
        # band powers: whole output, and noise (output minus aligned source-through-H) below 8 kHz
        pin_o, pin_r = pw(O[ib]), pw(R[ib])
        d['out'] = [10 * np.log10(pw(O[b]) / pin_o) for b in bs]
        d['src'] = [10 * np.log10(pw(R[b]) / pin_r + 1e-30) for b in bs]
        nz = lambda b: g * O[b] * np.exp(2j * np.pi * f[b] * (tau / FA)) - R[b]
        d['noise_in'] = 10 * np.log10(pw(nz(ib)) / pin_r)
        d['noise'] = [10 * np.log10(pw(nz(b)) / pin_r) for b in bs[:2]]
        res[name(spec)] = d
    return path, rate, res


def job_idle(rate, secs=2.0):
    """§2: zero input.  Levels re nominal speech power, NOM^2, after the start-up settles."""
    n16, nR, k, n, nk = geometry(secs, rate)
    p = card.CardParams(rate)
    y = card.decode(card.encode(np.zeros(nR), p), p)
    skip = int(0.1 * rate)
    yss = y[skip:nR - skip]                      # an even number of bits: whole periods
    nn = len(yss) * k
    f = sfft.rfftfreq(nn, 1.0 / FA)
    Y = sfft.rfft(hold(yss, k, y0=y[skip - 1]).astype(float))
    ib, bs = band_slices(f)
    it = int(np.argmin(np.abs(f - rate / 2)))
    ms = lambda P: 2 * P / nn ** 2 / NOM ** 2
    res = {'repo': 20 * np.log10(audio.reconstruct(y, rate)[skip:-skip].std() / NOM + 1e-30),
           'step_min': p.vector()[5]}
    for spec in [None, IDEAL] + RECON:
        H = 1.0 if spec is None else resp_exact(spec, f)
        P = np.abs(Y * H) ** 2
        res[name(spec)] = dict(
            tone=10 * np.log10(ms(P[it - 2:it + 3].sum()) + 1e-30),
            inband=10 * np.log10(ms(P[ib].sum()) + 1e-30),
            above=10 * np.log10(ms(sum(P[b].sum() for b in bs)) + 1e-30))
    return rate, res


def job_input(path, rate, secs):
    """§3: raw source -> causal HPF x LPF -> card -> ideal reconstruction."""
    n16, nR, k, n, nk = geometry(secs, rate)
    p = card.CardParams(rate)
    XR = raw_at_rate(path, rate, secs)
    fR = sfft.rfftfreq(nR, 1.0 / rate)
    f = sfft.rfftfreq(n, 1.0 / FA)
    Hi, Hbp = resp(IDEAL, f), resp(IDEAL_BP, f)
    Xstd = upspec(XR, nR, k) * Hbp                    # repository-standard source
    xstd = ifft(Xstd, n)
    nb = int(secs * rate)
    res = {}
    for hp in HPFS:
        for lp in LPFS:
            XRin = XR * resp(hp, fR) * resp(lp, fR)
            xin = ifft(XRin, nR)
            bits, _, syl = card.encode(xin, p, internals=True)
            Y = sfft.rfft(hold(card.decode(bits, p), k))
            Xin = upspec(XRin, nR, k)
            O, R = Y * Hi, Xin * Hi
            o = ifft(O, n)
            d = dict(matched=score(ifft(R, n), o, R, O, nk)[0],
                     conv=score(xstd, o, Xstd, O, nk)[0])
            O, R = Y * Hbp, Xin * Hbp
            d['bp'] = score(ifft(R, n), ifft(O, n), R, O, nk)[0]
            d['rms'] = 20 * np.log10(xin[:nb].std() / NOM)
            d['syl'] = float(syl[:nb].mean())
            res[(name(hp), name(lp))] = d
    return path, rate, res


def job_hum(path, rate, secs):
    """§4: standard speech + hum at the card input -> HPF -> card -> ideal reconstruction."""
    n16, nR, k, n, nk = geometry(secs, rate)
    p = card.CardParams(rate)
    x = card.load_talker(path, rate, secs)
    nx = len(x)
    XR = sfft.rfft(pad_to(x, nR))
    fR = sfft.rfftfreq(nR, 1.0 / rate)
    f = sfft.rfftfreq(n, 1.0 / FA)
    Hi = resp(IDEAL, f)
    t = np.arange(nx) / rate
    wr = int(0.02 * rate)
    nfr = nx // wr
    quiet = np.repeat(10 * np.log10((x[:nfr * wr].reshape(-1, wr) ** 2).mean(1) + 1e-20) <= SIL_DB, wr)
    res = {}
    for hp in HPFS:
        HhR = resp(hp, fR)
        s = ifft(upspec(XR * HhR, nR, k) * Hi, n)[:nk]     # speech alone, through the same path
        for hum in [None] + HUM:
            hm = np.zeros(nR)
            if hum:
                hm[:nx] = NOM * 10 ** (hum[1] / 20) * np.sqrt(2) * np.sin(2 * np.pi * hum[0] * t + 0.3)
            InR = (XR + sfft.rfft(hm)) * HhR
            bits, _, syl = card.encode(ifft(InR, nR), p, internals=True)
            O = sfft.rfft(hold(card.decode(bits, p), k)) * Hi
            A = upspec(InR, nR, k) * Hi
            tau = lag_frac(O, A, n, LAG_DEC)
            o = shift(ifft(O, n), tau, nk)
            a = ifft(A, n)[:nk]
            g = float(np.dot(a, o) / np.dot(o, o))
            g2 = float(np.dot(s, o) / np.dot(o, o))
            sy = syl[:nfr * wr]
            res[(name(hp), hum)] = dict(
                codec=seg_masked(s, a - g * o),       # hum is signal: only what the codec adds
                heard=seg_masked(s, s - g2 * o),      # hum is error: what the far end hears
                syl=float(sy.mean()), syl_quiet=float(sy[quiet].mean()))
    return path, rate, res


def job_card(path, rate, secs):
    """§5: the recommended card, every filter causal, against the standard chain."""
    n16, nR, k, n, nk = geometry(secs, rate)
    p = card.CardParams(rate)
    XR = raw_at_rate(path, rate, secs)
    fR = sfft.rfftfreq(nR, 1.0 / rate)
    f = sfft.rfftfreq(n, 1.0 / FA)
    Hbp, Hi, Hr = resp(IDEAL_BP, f), resp(IDEAL, f), resp(REC_RECON, f)
    Xup = upspec(XR, nR, k)
    Xstd = Xup * Hbp
    xstd = ifft(Xstd, n)
    ib, bs = band_slices(f)
    res = {}
    for tag, HinR, Hout in (('std', resp(IDEAL_BP, fR), Hi),
                            ('card', resp(REC_HPF, fR) * resp(REC_LPF, fR), Hr)):
        XRin = XR * HinR
        Y = sfft.rfft(hold(card.decode(card.encode(ifft(XRin, nR), p), p), k))
        Xin = upspec(XRin, nR, k)
        O, R = Y * Hout, Xin * Hout
        o, r = ifft(O, n), ifft(R, n)
        res[tag + ' conv'] = score(xstd, o, Xstd, O, nk)[0]
        res[tag + ' matched'] = score(r, o, R, O, nk)[0]
        res[tag + ' ceil'] = score(xstd, r, Xstd, R, nk)[0]
        Ow, Rw = O * Hbp, R * Hbp
        res[tag + ' bp'] = score(ifft(Rw, n), ifft(Ow, n), Rw, Ow, nk)[0]
        res[tag + ' out'] = [10 * np.log10(pw(O[b]) / pw(O[ib])) for b in bs]
    return path, rate, res


JOBS = dict(recon=job_recon, idle=job_idle, input=job_input, hum=job_hum, card=job_card)


def _dispatch(job):
    kind, args = job
    return JOBS[kind](*args)


def run_jobs(kind, arglist):
    t0 = time.time()
    with Pool(WORKERS) as pool:
        out = list(pool.imap_unordered(_dispatch, [(kind, a) for a in arglist]))
    print(f'  [{len(arglist)} {kind} jobs, {time.time() - t0:.0f} s]', flush=True)
    return out


def collate(results):
    """[(path, rate, dict)] -> {rate: [dict per talker, in talker order]}"""
    by = {}
    for path, rate, d in sorted(results, key=lambda r: (r[1], r[0])):
        by.setdefault(rate, []).append(d)
    return by


# ------------------------------------------------------------------ printing
def hdr(t):
    print('\n' + '=' * 100 + '\n' + t + '\n' + '=' * 100, flush=True)


def mw(v, worst=min):
    v = np.asarray(v, float)
    return f'{v.mean():6.2f}/{worst(v):6.2f}'


def dmw(v):
    v = np.asarray(v, float)
    return f'{v.mean():+6.2f}/{v.min():+6.2f}'


def section0_static():
    hdr('0. MODEL CHECKS')
    print('\n0a. What the raw talker files contain: power re their own 300-3400 Hz band (16 kHz files, 30 s)')
    print(f'  {"talker":12s} {"< 300 Hz":>9s} {"3.4-4 kHz":>10s} {"4-8 kHz":>9s}')
    rows = []
    for tk in card.TALKERS:
        a, fs = audio.read_wav(tk, seconds=SECS_HEAD)
        P = np.abs(sfft.rfft(a - a.mean())) ** 2
        f = sfft.rfftfreq(len(a), 1.0 / fs)
        bp = lambda lo, hi: P[(f >= lo) & (f < hi)].sum()
        ib = bp(300, 3400)
        rows.append([10 * np.log10(bp(20, 300) / ib), 10 * np.log10(bp(3400, 4000) / ib),
                     10 * np.log10(bp(4000, 8000) / ib)])
        print(f'  {tk:12s} ' + ' '.join(f'{v:+9.1f}' for v in rows[-1]))
    print(f'  {"max":12s} ' + ' '.join(f'{v:+9.1f}' for v in np.max(rows, 0)))

    print('\n0b. Why no filter here is a bilinear design.  4th-order Butterworth, 3.4 kHz, gain in dB:')
    print(f'  {"at":>8s} {"analog":>9s} {"bilinear@16k":>13s} {"@32k":>9s} {"@64k":>9s} {"@192k":>9s}')
    for fr in (4000, 8000, 16000, 32000):
        row = [20 * np.log10(abs(resp_exact(BW(4, 3400), [fr])[0]))]
        for fs in (16000, 32000, 64000, 192000):
            if fr > fs / 2:
                row.append(np.nan)
                continue
            _, h = signal.sosfreqz(signal.butter(4, 3400, fs=fs, output='sos'), worN=[fr], fs=fs)
            row.append(20 * np.log10(max(abs(h[0]), 1e-15)))
        print(f'  {fr / 1000:6.0f} k ' + ' '.join('       --' if np.isnan(v) else f'{v:9.1f}' for v in row))
    print('  A bilinear design at the bit rate puts its zeros at R/2, exactly where CVSD idle')
    print('  (1010...) puts its tone, and audio.reconstruct is such a design.')
    fg = np.linspace(0, 96000, 2_000_001)
    err = max(float(np.max(np.abs(resp(s, fg) - resp_exact(s, fg)))) for s in
              [BW(1, 200, 'highpass'), BW(6, 3000), CH(4, 3400), IDEAL, IDEAL_BP])
    print(f'  Response interpolation from the 0.5 Hz grid: max |error| {err:.1e} (linear gain)')

    print('\n0c. Integrator ramp (straight lines between bit edges): sinc^2 droop, dB')
    print(f'  {"rate":>6s} {"1 kHz":>8s} {"3 kHz":>8s} {"3.4 kHz":>8s}')
    for rate in card.RATES:
        print(f'  {rate // 1000:4d}k ' + ' '.join(f'{20 * np.log10(np.sinc(fr / rate) ** 2):8.2f}'
                                                  for fr in (1000, 3000, 3400)))


def section0_metric(rec):
    print('\n0d. The metric.  Standard talker, card as designed.  segSNR dB, mean/worst talker, 7 talkers, 30 s')
    print(f'  {"rate":>5s} {"card.score":>14s} {"frac. delay":>14s} {"delay":>7s} {"ideal conv":>14s} '
          f'{"ideal matched":>14s} | {"run.SLEW: int":>14s} {"frac. delay":>14s}')
    for rate in card.RATES:
        L = rec[rate]
        g = lambda key, sub=None: [d[key] if sub is None else d[key][sub] for d in L]
        print(f'  {rate // 1000:3d}k  {mw(g("card.score"))} {mw(g("card.score frac"))} '
              f'{np.mean(g("delay bits")):6.2f}b {mw(g(name(IDEAL), "conv"))} {mw(g(name(IDEAL), "matched"))} | '
              f'{mw(g("run.SLEW int"))} {mw(g("run.SLEW frac"))}')
    print('  card.score = the repository metric: audio.reconstruct at the bit rate, whole-bit alignment.')
    print('  frac. delay = the same, with the delay resolved to a fraction of a bit.  delay = codec')
    print('  delay in bits.  ideal = audio.reconstruct\'s shape in this 192 kHz chain.  run.SLEW = the')
    print('  per-rate slews (7000/12000/16000) that spec §11.1 was measured with.')


def section1(rec):
    hdr('1. RECONSTRUCTION LOW-PASS  (standard input; decoder -> causal H -> 192 kHz output)')
    print('\n  Filter shapes (rate-independent).  gain re 1 kHz, dB; group-delay spread over 300-3400 Hz')
    print(f'  {"filter":28s} {"3.0 kHz":>8s} {"3.4 kHz":>8s} {"-3 dB":>8s} {"gd spread":>10s}')
    for spec in [IDEAL] + IDEALS_AT[::2] + RECON:
        pr = props(spec)
        print(f'  {name(spec):28s} {pr[3000.0]:8.2f} {pr[3400.0]:8.2f} {pr["f3"] / 1000:6.2f} k {pr["gd"]:7.3f} ms')
    summary = {}
    for rate in card.RATES:
        L = rec[rate]
        idl = np.array([d[name(IDEAL)]['matched'] for d in L])
        idl_c = np.array([d[name(IDEAL)]['conv'] for d in L])
        print(f'\n  {rate // 1000} kbps, 30 s.  segSNR dB, mean/worst talker.  Δ = candidate minus reference, '
              f'per talker, mean/worst')
        print(f'  {"filter":28s} {"ceiling":>7s} {"conventional":>13s} {"matched":>13s} '
              f'{"Δm vs ideal":>13s} {"Δm vs ideal@fc":>14s} {"Δconv vs ideal":>14s}')
        for spec in [IDEAL] + RECON:
            nm = name(spec)
            m = np.array([d[nm]['matched'] for d in L])
            cv = np.array([d[nm]['conv'] for d in L])
            ce = np.array([d[nm]['ceil'] for d in L])
            if spec[0] == 'ideal':
                dfc = np.full(len(L), np.nan)
            else:
                ref = name(ideal_at(spec[2] if spec[2] in (3000.0, 4000.0) else 3400.0))
                dfc = m - np.array([d[ref]['matched'] for d in L])
            summary[(rate, nm)] = (m - idl, dfc, cv - idl_c)
            print(f'  {nm:28s} {ce.mean():7.2f} {mw(cv)} {mw(m)} {dmw(m - idl)} '
                  f'{"" if spec[0] == "ideal" else dmw(dfc):>14s} {dmw(cv - idl_c):>14s}')
        print('  ideal@fc matched:  ' + '   '.join(
            f'{name(s)} {mw([d[name(s)]["matched"] for d in L])}' for s in IDEALS_AT))
        d8 = [abs(np.mean([d[name(s)]['m8'] - d[name(s)]['matched'] for d in L])) for s in RECON if s[1] >= 2]
        d81 = np.mean([d[name(BW(1, 3400))]['m8'] - d[name(BW(1, 3400))]['matched'] for d in L])
        print(f'  scoring below 8 kHz only moves the matched mean by at most {max(d8):.2f} dB at order >= 2 '
              f'(order 1: {d81:+.2f} dB)')

    print('\n  Minimum Butterworth order within the margin, by the mean Δ / by the worst talker\'s Δ '
          '("-" = not by order 6)')
    print(f'  {"score vs reference":30s} {"corner":>7s} {"margin":>7s} ' +
          ''.join(f'{str(r // 1000) + "k":>10s}' for r in card.RATES))
    for label, which in (('matched vs ideal', 0), ('matched vs ideal@fc', 1), ('conventional vs ideal', 2)):
        for fc in (3000.0, 3400.0, 4000.0):
            for margin in (0.5, 1.0):
                cells = []
                for rate in card.RATES:
                    orders = range(1 if fc == 3400.0 else 2, 7)
                    pick = lambda crit: next((o for o in orders
                                              if crit(summary[(rate, name(BW(o, fc)))][which]) >= -margin), '-')
                    cells.append(f'{pick(np.mean)} / {pick(np.min)}')
                print(f'  {label:30s} {fc / 1000:5.1f}k {margin:6.1f}  ' + ''.join(f'{c:>10s}' for c in cells))


def section2(rec, idle):
    hdr('2. OUT-OF-BAND RESIDUAL AT THE CARD OUTPUT  (dB re in-band 300-3400 Hz speech power)')
    for rate in card.RATES:
        L = rec[rate]
        print(f'\n  {rate // 1000} kbps, 30 s.  out = everything at the output; noise = out minus the aligned source')
        print('  through the same H (below 8 kHz).  mean/worst (highest) talker.')
        print(f'  {"filter":28s} ' + ''.join(f'{"out " + b:>14s}' for b in BAND_NAMES) +
              ''.join(f'{"noise " + b:>14s}' for b in BAND_NAMES[:2]) + f'{"noise in-band":>14s}')
        for spec in [IDEAL] + RECON:
            nm = name(spec)
            o = np.array([d[nm]['out'] for d in L])
            nz = np.array([d[nm]['noise'] for d in L])
            ni = [d[nm]['noise_in'] for d in L]
            print(f'  {nm:28s} ' + ''.join(f'{mw(o[:, j], max):>14s}' for j in range(3)) +
                  ''.join(f'{mw(nz[:, j], max):>14s}' for j in range(2)) + f'{mw(ni, max):>14s}')
        s = np.array([d[name(BW(3, 3400))]['src'] for d in L])
        print('  the source alone through BW3 3.4k: ' +
              ', '.join(f'{b} {s[:, j].mean():.1f}' for j, b in enumerate(BAND_NAMES)) + ' dB')

    print('\n  IDLE CHANNEL (zero input: 1010..., a triangle at R/2).  dB re nominal speech power (0.15 rms FS).')
    print('  tone = the R/2 line; >3.4k = everything above 3.4 kHz; in-band = 300-3400 Hz.')
    print(f'  {"filter":28s} ' + ''.join(f'{str(r // 1000) + "k tone":>10s}{">3.4k":>8s}{"in-band":>9s}  '
                                         for r in card.RATES))
    for spec in [None, IDEAL] + RECON:
        nm = name(spec)
        print(f'  {nm:28s} ' + ''.join(
            f'{idle[r][nm]["tone"]:10.1f}{idle[r][nm]["above"]:8.1f}{idle[r][nm]["inband"]:9.1f}  '
            for r in card.RATES))
    print('  audio.reconstruct at the bit rate, rms: ' +
          ', '.join(f'{r // 1000}k {idle[r]["repo"]:.0f} dB' for r in card.RATES) +
          '   (its zero at R/2 removes the tone entirely)')
    print('  step_min: ' + ', '.join(f'{r // 1000}k {idle[r]["step_min"]:.4f} FS' for r in card.RATES))


def section3(inp):
    hdr('3. INPUT FILTER  (raw talker, content to 8 kHz -> causal HPF x LPF -> card -> ideal reconstruction)')
    print('  matched = against the source through the same input filter and the ideal reconstruction.')
    print('  BP window = matched, both sides also through the zero-phase 300-3400 Hz window.')
    print('  conv = against the repository-standard source (ideal band-pass); causal phase counts.')
    print('  rms = encoder input re nominal; syl = mean syllabic node (0 = step_min, 1 = step_max).')
    print('\n  High-pass shapes: gain re 1 kHz, dB')
    print(f'  {"HPF":8s} {"50 Hz":>7s} {"60 Hz":>7s} {"300 Hz":>7s} {"gd spread 300-3400":>19s}')
    for hp in HPFS[1:]:
        pr = props(hp)
        print(f'  {name(hp):8s} {pr[50.0]:7.1f} {pr[60.0]:7.1f} {pr[300.0]:7.2f} {pr["gd"]:16.3f} ms')
    base_key = ('none', name(BW(3, 3400)))
    for rate in card.RATES:
        L = inp[rate]
        bm = np.array([d[base_key]['matched'] for d in L])
        bb = np.array([d[base_key]['bp'] for d in L])
        print(f'\n  {rate // 1000} kbps, 15 s.  mean/worst talker.  Δ = vs no HPF + BW3 3.4k, per talker, mean/worst')
        print(f'  {"HPF":8s} {"LPF":9s} {"matched":>13s} {"Δ matched":>13s} {"BP window":>13s} {"Δ BP window":>13s} '
              f'{"conv":>13s} {"rms":>6s} {"syl":>6s}')
        for hp in HPFS:
            for lp in LPFS:
                key = (name(hp), name(lp))
                m = np.array([d[key]['matched'] for d in L])
                b = np.array([d[key]['bp'] for d in L])
                print(f'  {name(hp):8s} {name(lp):9s} {mw(m)} {dmw(m - bm)} {mw(b)} {dmw(b - bb)} '
                      f'{mw([d[key]["conv"] for d in L])} {np.mean([d[key]["rms"] for d in L]):+6.2f} '
                      f'{np.mean([d[key]["syl"] for d in L]):6.3f}')


def section4(hum):
    hdr('4. HUM  (standard speech + 50/60 Hz at the card input -> HPF -> card -> ideal reconstruction)')
    print('  level = hum rms re nominal speech rms at the card input (= the encoder input with no HPF).')
    print('  codec = segSNR of only what the codec adds (hum counted as signal);  heard = hum counted as')
    print('  error, i.e. what the far end gets.  Frames gated on the speech alone.  syl / quiet = mean')
    print('  syllabic node over all bits / over speech-silent bits (0 = step_min).')
    for rate in card.RATES:
        L = hum[rate]
        print(f'\n  {rate // 1000} kbps, 15 s.  mean/worst talker.  Δ = vs no hum with the same HPF, per talker')
        print(f'  {"HPF":8s} {"hum":>10s} {"codec":>13s} {"Δ codec":>13s} {"heard":>13s} {"syl":>6s} {"quiet":>6s}')
        for hp in HPFS:
            b = np.array([d[(name(hp), None)]['codec'] for d in L])
            for h in [None] + HUM:
                if h is not None and h[1] >= -10 and hp not in (None, REC_HPF):
                    continue
                key = (name(hp), h)
                c = np.array([d[key]['codec'] for d in L])
                lab = 'none' if h is None else f'{h[0]}Hz {h[1]:+d}'
                print(f'  {name(hp):8s} {lab:>10s} {mw(c)} {dmw(c - b)} {mw([d[key]["heard"] for d in L])} '
                      f'{np.mean([d[key]["syl"] for d in L]):6.3f} {np.mean([d[key]["syl_quiet"] for d in L]):6.3f}')


def section5(cr):
    hdr('5. THE RECOMMENDED CARD, END TO END  (raw talker, every filter causal, 30 s)')
    print(f'  input: {name(REC_HPF)} Hz high-pass, then {name(REC_LPF)} low-pass.   output: {name(REC_RECON)} low-pass.')
    fr = np.array([50.0, 60.0, 200.0, 300.0, 1000.0, 3000.0, 3400.0, 4000.0, 8000.0])
    for label, h in (('input', resp_exact(REC_HPF, fr) * resp_exact(REC_LPF, fr)),
                     ('end to end', resp_exact(REC_HPF, fr) * resp_exact(REC_LPF, fr) * resp_exact(REC_RECON, fr))):
        g = 20 * np.log10(np.abs(h))
        print(f'  {label:10s} gain re 1 kHz, dB: ' + '  '.join(f'{x:.0f} Hz {v - g[4]:+.1f}' for x, v in zip(fr, g)))
    f = np.arange(100.0, 5000.0, 0.5)
    hh = resp_exact(REC_HPF, f) * resp_exact(REC_LPF, f) * resp_exact(REC_RECON, f)
    tg = -np.diff(np.unwrap(np.angle(hh))) / np.diff(2 * np.pi * f)
    for lo, hi in ((300, 3400), (500, 3000), (1000, 2600)):
        m = (f[:-1] >= lo) & (f[:-1] <= hi)
        print(f'  end-to-end group delay {lo}-{hi} Hz: {1000 * tg[m].min():.2f} to {1000 * tg[m].max():.2f} ms '
              f'(spread {1000 * (tg[m].max() - tg[m].min()):.2f} ms)')
    print('\n  std = ideal band-pass in, ideal reconstruction out (the repository chain) on the same raw talkers.')
    print('  segSNR dB, mean/worst talker;  Δ = card minus std, per talker, mean/worst')
    print(f'  {"rate":>5s} {"":5s} {"conv":>13s} {"matched":>13s} {"BP window":>13s} {"ceiling":>8s}   '
          + ''.join(f'{"out " + b:>10s}' for b in BAND_NAMES))
    for rate in card.RATES:
        L = cr[rate]
        g = lambda key: np.array([d[key] for d in L])
        for tag in ('std', 'card'):
            o = np.array([d[tag + ' out'] for d in L])
            print(f'  {rate // 1000:3d}k  {tag:5s} {mw(g(tag + " conv"))} {mw(g(tag + " matched"))} '
                  f'{mw(g(tag + " bp"))} {g(tag + " ceil").mean():8.2f}   ' +
                  ''.join(f'{o[:, j].mean():10.1f}' for j in range(3)))
        print(f'  {"":5s} {"Δ":5s} {dmw(g("card conv") - g("std conv"))} {dmw(g("card matched") - g("std matched"))} '
              f'{dmw(g("card bp") - g("std bp"))}')

    print('\n  Realisation.  Butterworth: one 2nd-order op-amp section per complex pole pair, one RC per real pole.')
    amps = 0
    for role, spec in (('input high-pass', REC_HPF), ('input low-pass', REC_LPF), ('reconstruction', REC_RECON)):
        a, rc = spec[1] // 2, spec[1] % 2
        amps += a
        print(f'    {role:16s} {name(spec):9s}: {a} op-amp section(s), {rc} passive RC pole(s)')
    print(f'    filters on one card: {amps} op-amp sections')


# ------------------------------------------------------------------ main
def main():
    global SECS_HEAD, SECS_SWEEP
    args = sys.argv[1:]
    if '--secs' in args:
        i = args.index('--secs')
        SECS_HEAD = SECS_SWEEP = float(args[i + 1])
        del args[i:i + 2]
    which = [a for a in args if a in list('012345')] or list('012345')
    t0 = time.time()
    if '0' in which:
        section0_static()
    if {'0', '1', '2'} & set(which):
        rec = collate(run_jobs('recon', [(t, r, SECS_HEAD) for r in card.RATES for t in card.TALKERS]))
        if '0' in which:
            section0_metric(rec)
        if '1' in which:
            section1(rec)
        if '2' in which:
            with Pool(WORKERS) as pool:
                idle = dict(pool.imap_unordered(_dispatch, [('idle', (r,)) for r in card.RATES]))
            section2(rec, idle)
    if '3' in which:
        section3(collate(run_jobs('input', [(t, r, SECS_SWEEP) for r in card.RATES for t in card.TALKERS])))
    if '4' in which:
        section4(collate(run_jobs('hum', [(t, r, SECS_SWEEP) for r in card.RATES for t in card.TALKERS])))
    if '5' in which:
        section5(collate(run_jobs('card', [(t, r, SECS_HEAD) for r in card.RATES for t in card.TALKERS])))
    print(f'\n[total {time.time() - t0:.0f} s]')


if __name__ == '__main__':
    main()
