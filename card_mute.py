"""
How should the voice card mute, so that loss of lock is silent and relock does
not click?

The receive card asserts MUTE as a level while it is not locked or has no
carrier (line-receiver.md §6-7, spec §10).  The A demux is cleared while muted;
the C demux is not, so a voice card's decoder keeps receiving whatever the line
delivers.  squelch.py measured a noise-only line driving an unmuted decoder to
+20..+24 dB rms and +47.7 dB peak re speech, and line-receiver.md §6 leaves the
relock click unmeasured.  This measures the burst, the mute and the relock for
the ways the card could obey MUTE.

Method
  Decoder  card_fast.c's decoder loop, re-implemented below with mute hooks and
           compiled on first use.  With MUTE never asserted it is bit-identical
           to card.decode (section 1).  Hooks, active only while MUTE:
             coincidence forced to 0      syllabic RC decays with tau_syl
             step current forced to 0     Iabc off; integrator decays via R_int
             idle fed back                data input = NOT Q0, so it sees 1010
             integrator held at bias      a switch across C_int
             data input cleared           the C demux cleared (rejected in §6)
           plus an output gate (decoder output forced to 0 ahead of the
           reconstruction filter) whose release can be delayed, an optional
           integrator rail, and a per-bit clock enable: when the RX frame clock
           does not tick, the flip-flops hold and the OTA current keeps flowing
           (step = I t / C), which is what a stalled strobe does to the card.
  Stream   7 talkers, 30 s.  CVSD speech; hash replaces the bits for D = 1 s at
           4, 11, 18 and 25 s; the good stream then resumes as the far encoder's
           continuing output: SPEECH, or IDLE (the far talker silent from hash
           onset: source zeroed from onset to release + 600 ms and re-encoded).
  Hash     random   i.i.d. bits, p(1) = 0.5, clocked at the nominal rate
           ones     runs of 1s, geometric lengths with mean 320 bits, each ended
                    by a single 0, clocked at the nominal rate: the channel C
                    stream the monostable emits on a quiet noise-only line
                    (section 2 measures it through the repository's receive
                    chain; decoding the emitted bits at the nominal rate is the
                    convention squelch.py uses)
           section 5 adds measured chain bits at sd 1.0, the same chain at
           sd 0.05 with its real strobe timing (the clock stalls), and a dead
           line (no strobes at all).
  MUTE     asserts LOF frames after hash onset (16 or 40; tables use 40) and
           releases 32 frames after the good stream resumes.  One frame = one
           channel bit.
  Output   F = audio.reconstruct (8th-order Butterworth, zero phase), or
           F = causal 4th-order 3.4 kHz Butterworth then first-order 300 Hz
           high-pass (the output transformer) -- 'tx chain' below.
  Metrics  peak and loudest 10 ms rms, dB re the rms of the same talker's
           uninterrupted decoded speech through the same F:
             burst    F(y on [onset, MUTE)), window [onset-20 ms, MUTE+50 ms):
                      the part no strategy can remove; equals a perfect gate
             assert   F(output on [MUTE, release)), [MUTE-5 ms, release-20 ms)
             mute     loudest 10 ms rms in [MUTE+50 ms, release-20 ms)
             release, good stream IDLE: F(output from the moment it opens),
                      [open-20 ms, open+100 ms): the click itself
             release, good stream SPEECH:
                  err     F((output - uninterrupted decode) from the opening),
                          same window: slam, wind-up and mis-start
                  excess  peak of F(output) in [open-5 ms, open+50 ms) over
                          the larger of the uninterrupted decode's peak there
                          and the speech rms: louder than the speech that
                          belongs there? (err alone would charge a decoder that
                          starts quietly from rest, and not a gate that snaps
                          open onto speech; the floor is needed because idle
                          CVSD is a Nyquist tone the filters null to ~1e-33)
           Per talker the worst of its four outages; tables give mean/worst
           over the seven talkers.  '-' means below -99 dB (gated: exactly zero).

Usage:  python3 card_mute.py          (about 6 minutes, 2 worker processes)
"""
import ctypes, hashlib, math, os, subprocess, sys, tempfile, time
import numpy as np
from multiprocessing import Pool
from scipy import signal
import audio, card, fast

SECS = 30.0
ONSETS = (4.0, 11.0, 18.0, 25.0)       # hash onsets, s
RELOCK = 32                             # good frames before MUTE releases
RUN_MEAN = 320                          # 'ones' model: mean run of 1s, channel bits
N_CH, OS = 3, 32                        # receive-chain model: N = 3, 32 samples per cell
WORKERS = 2

# ---------------------------------------------------------------------------
# 1. The decoder with mute hooks
# ---------------------------------------------------------------------------
C_SRC = r'''
#include <stdint.h>
#include <math.h>
/* card_fast.c's step law and decoder loop, term for term, plus mute hooks.
 * ctl[i]: bit 0 = MUTE, bit 1 = the frame clock ticks at this bit.
 * h[]: 0 coincidence->0, 1 step current->0, 2 feed NOT Q0, 3 hold integrator at
 *      bias, 4 clear data input (each only while MUTE), 5 rail (FS, 0 = none),
 *      6 hold residual: the OTA current times the switch resistance, FS at I_max. */
static double step_of(const double *p, double syl) {
    double g = p[6] * syl + p[7];
    if (g < 0) g = 0;
    double s = p[5] + g * (p[4] - p[5]);
    return s < 0 ? 0 : s;
}
void dec_mute(const uint8_t *bits, const uint8_t *ctl, long n, const double *p,
              const double *h, double *yout, double *sylout) {
    double dt = 1.0 / p[0];
    int run = (int)p[1];
    unsigned mask = (1u << run) - 1u;
    double a_syl = 1.0 - exp(-dt / p[2]);
    double a_int = exp(-dt / p[3]);
    double k = dt * p[0];
    double up = k * (1.0 + p[8]), dn = k * (1.0 - p[8]);
    int f_coin = h[0] != 0, f_step = h[1] != 0, f_idle = h[2] != 0;
    int f_hold = h[3] != 0, f_clear = h[4] != 0;
    double rail = h[5], hres = h[6];
    double y = 0.0, syl = 0.0;
    unsigned hist = 0;
    for (long i = 0; i < n; i++) {
        int mute = ctl[i] & 1, clk = (ctl[i] >> 1) & 1;
        if (clk) {
            unsigned d = bits[i] ? 1u : 0u;
            if (mute && f_clear) d = 0u;
            if (mute && f_idle) d = (~hist) & 1u;
            hist = ((hist << 1) | d) & mask;
        }
        int b = (int)(hist & 1u);
        double coin = (hist == 0 || hist == mask) ? 1.0 : 0.0;
        if (mute && f_coin) coin = 0.0;
        syl += (coin - syl) * a_syl;
        double s = step_of(p, syl);
        if (mute && f_step) s = 0.0;
        y = (y + (b ? s * up : -s * dn)) * a_int;
        if (rail > 0) { if (y > rail) y = rail; else if (y < -rail) y = -rail; }
        if (mute && f_hold) y = hres * (b ? s : -s) / p[4];
        yout[i] = y;
        if (sylout) sylout[i] = syl;
    }
}
'''
MUTE, CLK = 1, 2
_lib = None


def lib():
    """Compile C_SRC with card_fast.c's flags (bit identity depends on them)."""
    global _lib
    if _lib is None:
        tag = hashlib.sha1(C_SRC.encode()).hexdigest()[:12]
        so = os.path.join(tempfile.gettempdir(), f'card_mute_{tag}.so')
        if not os.path.exists(so):
            src, tmp = f'{so}.{os.getpid()}.c', f'{so}.{os.getpid()}'
            with open(src, 'w') as f:
                f.write(C_SRC)
            subprocess.run(['gcc', '-O3', '-march=native', '-ffp-contract=off', '-shared',
                            '-fPIC', '-o', tmp, src, '-lm'], check=True)
            os.replace(tmp, so)
            os.remove(src)
        L = ctypes.CDLL(so)
        u8, dp = np.ctypeslib.ndpointer(np.uint8), np.ctypeslib.ndpointer(np.float64)
        L.dec_mute.argtypes = [u8, u8, ctypes.c_long, dp, dp, dp, ctypes.c_void_p]
        _lib = L
    return _lib


HOOKS = ('coin', 'step', 'idle', 'hold', 'clear')


def decode_mute(bits, p, ctl=None, rail=0.0, internals=False, **hooks):
    bits = np.ascontiguousarray(bits, np.uint8)
    n = len(bits)
    ctl = np.full(n, CLK, np.uint8) if ctl is None else np.ascontiguousarray(ctl, np.uint8)
    h = np.array([float(hooks.get(k, 0)) for k in HOOKS] + [rail, float(hooks.get('hres', 0.0))])
    y = np.empty(n)
    s = np.empty(n) if internals else None
    lib().dec_mute(bits, ctl, n, p.vector(), h, y, card._ptr(s))
    return (y, s) if internals else y


def decode_mute_py(bits, p, ctl, rail=0.0, **hooks):
    """The same hooks in plain Python, to check the C against."""
    v = p.vector()
    rate, run = v[0], int(v[1])
    mask = (1 << run) - 1
    dt = 1.0 / rate
    a_syl = 1.0 - math.exp(-dt / v[2])
    a_int = math.exp(-dt / v[3])
    k = dt * rate
    up, dn = k * (1.0 + v[8]), k * (1.0 - v[8])
    y = syl = 0.0
    hist = 0
    out = np.empty(len(bits))
    for i in range(len(bits)):
        mute, clk = ctl[i] & 1, ctl[i] & 2
        if clk:
            d = 1 if bits[i] else 0
            if mute and hooks.get('clear'): d = 0
            if mute and hooks.get('idle'): d = (~hist) & 1
            hist = ((hist << 1) | d) & mask
        b = hist & 1
        coin = 1.0 if (hist == 0 or hist == mask) else 0.0
        if mute and hooks.get('coin'): coin = 0.0
        syl += (coin - syl) * a_syl
        g = max(0.0, v[6] * syl + v[7])
        s = v[5] + g * (v[4] - v[5])
        s = 0.0 if s < 0 else s
        if mute and hooks.get('step'): s = 0.0
        y = (y + (s * up if b else -s * dn)) * a_int
        if rail > 0: y = min(rail, max(-rail, y))
        if mute and hooks.get('hold'): y = hooks.get('hres', 0.0) * (s if b else -s) / v[4]
        out[i] = y
    return out


# Strategies: hooks while MUTE, output gate, gate release delay (ms)
STRATS = {
    'none':  (dict(), False, 0, 'MUTE ignored'),
    'a':     (dict(), True, 0, 'output gate'),
    'b':     (dict(coin=1, step=1), False, 0, 'coin 0 + step current 0'),
    'c':     (dict(coin=1, step=1), True, 0, '(b) + output gate'),
    'd':     (dict(coin=1), False, 0, 'coin 0'),
    'e':     (dict(coin=1), True, 0, '(d) + output gate'),
    'f':     (dict(step=1), True, 0, 'step 0 + gate, coin free'),
    'g':     (dict(idle=1), True, 0, 'fed NOT Q0 + gate'),
    'h':     (dict(coin=1, hold=1), False, 0, 'C_int shorted + coin 0'),
    'h100':  (dict(coin=1, hold=1, hres=0.012), False, 0, '(h), switch 100 ohm'),
    'h1k':   (dict(coin=1, hold=1, hres=0.12), False, 0, '(h), switch 1 kohm'),
    'a0':    (dict(clear=1), True, 0, 'C demux cleared + gate'),
    'a+10':  (dict(), True, 10, 'gate, release +10 ms'),
    'a+20':  (dict(), True, 20, 'gate, release +20 ms'),
    'a+30':  (dict(), True, 30, 'gate, release +30 ms'),
    'a+50':  (dict(), True, 50, 'gate, release +50 ms'),
}
BRIEF = ['none', 'a', 'b', 'c', 'd']
MAIN = ['none', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'a+10', 'a+20', 'a+30', 'a+50']
OTHER_RATES = BRIEF + ['e', 'g', 'h', 'a+20', 'a+30', 'a+50']


# ---------------------------------------------------------------------------
# Filters and metrics
# ---------------------------------------------------------------------------
_TX = {}


def f_tx(x, rate):
    if rate not in _TX:
        _TX[rate] = (signal.butter(4, 3400.0, fs=rate, output='sos'),
                     signal.butter(1, 300.0, btype='high', fs=rate, output='sos'))
    lo, hi = _TX[rate]
    return signal.sosfilt(hi, signal.sosfilt(lo, x))


FILTERS = (('reconstruct', audio.reconstruct), ('tx chain', f_tx))


def db(v, ref):
    return 20.0 * np.log10(max(v, 1e-12 * ref) / ref)


def pk_r10(x, rate, lo, hi, ref, overall=False):
    seg = x[max(0, lo):hi]
    w = int(round(0.010 * rate))
    pk = float(np.abs(seg).max())
    if overall:
        r = float(np.sqrt(np.mean(seg * seg)))
    else:
        c = np.concatenate([[0.0], np.cumsum(seg * seg)])
        r = float(np.sqrt(max(0.0, np.max(c[w:] - c[:-w])) / w))
    return db(pk, ref), db(r, ref)


def ms(rate, t):
    return int(round(t * rate / 1000.0))


# ---------------------------------------------------------------------------
# Hash models
# ---------------------------------------------------------------------------
def hash_bits(kind, n, seed):
    rng = np.random.default_rng(seed)
    if kind == 'random':
        return rng.integers(0, 2, n, dtype=np.uint8)
    out = np.ones(n, np.uint8)                       # 'ones'
    i = int(rng.integers(0, RUN_MEAN))
    while i < n:
        out[i] = 0
        i += 1 + int(rng.geometric(1.0 / RUN_MEAN))
    return out


def noise_slicer(sd, cells, seed):
    """Noise-only line through the repository's receive front end, as
    s4_simple.py spec runs it: 2nd-order low-pass at the symbol rate, slicer
    with 0.05 hysteresis.  Returns the slicer output at OS samples per cell."""
    rng = np.random.default_rng(seed)
    b, a = signal.butter(2, 2.0 * 2.0 / OS)          # corner = 2 x line rate = symbol rate
    return fast.slice_hyst(signal.lfilter(b, a, rng.normal(0.0, sd, int(cells * OS))), 0.05)


def mono_timed(w, thr=0.75, dead=0.25):
    """fast.mono_decode with the time of each emitted bit (in cells)."""
    e = np.flatnonzero(w[1:] != w[:-1]) + 1
    thr, dead = thr * OS, dead * OS
    last, mid, bits, t = 0, False, [], []
    for i in e.tolist():
        gap = i - last
        if gap < dead:
            continue
        last = i
        if gap > thr:
            bits.append(1); t.append(i); mid = False
        elif mid:
            bits.append(0); t.append(i); mid = False
        else:
            mid = True
    return np.array(bits, np.uint8), np.array(t, np.float64) / OS, e / OS


def frame_walk(bits, times, locked, trip=16):
    """The spec §7 framer in hardware form over the strobe sequence: a frame is
    the next 2N+2 strobes; the RX frame clock ticks at the frame's last strobe;
    channel 1's C latch takes strobe 1.  Hunting, a bad frame withholds one
    strobe.  Locked, the +1/-1 counter trips at 16.  Returns tick times (cells),
    C bits, and the loss-of-frame time if locked."""
    flen = 2 + 2 * N_CH
    j, hist, err = 0, [], 0
    if locked:
        hist = [1, 1, 0]
    ticks, cb = [], []
    while j + flen <= len(bits):
        f = bits[j:j + flen]
        s_, t_ = int(f[flen - 2]), int(f[flen - 1])
        good = s_ == 0 and (len(hist) < 3 or (hist[-3:] + [t_]).count(0) == 1)
        hist = (hist + [t_])[-3:]
        ticks.append(times[j + flen - 1]); cb.append(int(f[1]))
        if locked:
            err = max(0, err - 1) if good else err + 1
            if err >= trip:
                return np.array(ticks), np.array(cb, np.uint8), times[j + flen - 1]
            j += flen
        elif good:
            j += flen
        else:
            hist = []
            j += flen + 1
    return np.array(ticks), np.array(cb, np.uint8), None


def stall_event(sd, D, rate, seed):
    """One outage of a noise-only line with its real strobe timing, mapped onto
    the channel-bit grid.  MUTE from the carrier detector (2-cell timeout on
    comparator transitions, a forced loss of frame, line-receiver §7)."""
    flen = 2 + 2 * N_CH
    n = int(round(D * rate))
    cells = n * flen
    if sd == 0:
        return dict(ticks=np.zeros(0, np.int64), cbits=np.zeros(0, np.uint8), tm=1,
                    lof_ms=None, strobes=0.0, collisions=0)
    w = noise_slicer(sd, cells, seed)
    b, t, e = mono_timed(w)
    del w
    g = np.diff(np.concatenate([[0.0], e]))
    k = np.flatnonzero(g > 2.0)
    ticks, cb, _ = frame_walk(b, t, locked=False)
    _, _, t_lof = frame_walk(b, t, locked=True)
    if len(k):
        t_cd = (0.0 if k[0] == 0 else e[k[0] - 1]) + 2.0
    else:
        t_cd = t_lof if t_lof is not None else cells
    grid, bits, last, coll = [], [], -1, 0
    for tc, c in zip(ticks, cb):
        v = int(tc // flen)
        if v <= last:
            v, coll = last + 1, coll + 1
        if v >= n:
            break
        grid.append(v); bits.append(c); last = v
    return dict(ticks=np.array(grid, np.int64), cbits=np.array(bits, np.uint8),
                tm=max(1, int(math.ceil(t_cd / flen))),
                lof_ms=None if t_lof is None else 1000.0 * t_lof / flen / rate,
                strobes=len(b) / cells, collisions=coll)


# ---------------------------------------------------------------------------
# One talker, one configuration
# ---------------------------------------------------------------------------
def talker_job(args):
    ti, cfg = args
    rate, D, lof, rail = cfg['rate'], cfg['D'], cfg['lof'], cfg.get('rail', 0.0)
    kind, strats = cfg['hash'], cfg['strats']
    p = card.CardParams(rate)
    x = card.load_talker(card.TALKERS[ti], rate, SECS)
    n = len(x)
    evs = []
    for k, t in enumerate(ONSETS):
        th = int(round(t * rate))
        tg = th + int(round(D * rate))
        ev = dict(th=th, tg=tg, tr=tg + RELOCK, tm=th + lof)
        if kind in ('stall', 'dead'):
            ev['tm'] = th + cfg['stall'][k]['tm']
        evs.append(ev)

    x_idle = x.copy()
    for ev in evs:
        x_idle[ev['th']:ev['tr'] + ms(rate, 600)] = 0.0
    b_sp, b_id = card.encode(x, p), card.encode(x_idle, p)
    y_sp, y_id = card.decode(b_sp, p), card.decode(b_id, p)
    refs = {fn: float(np.sqrt(np.mean(F(y_sp, rate) ** 2))) for fn, F in FILTERS}

    ctl = np.full(n, CLK, np.uint8)
    h_sp, h_id = b_sp.copy(), b_id.copy()
    for k, ev in enumerate(evs):
        th, tg = ev['th'], ev['tg']
        if kind in ('random', 'ones'):
            h = hash_bits(kind, tg - th, seed=1000 * ti + k)
        elif kind == 'measured':
            src = cfg['measured']
            h = src[k * (tg - th): (k + 1) * (tg - th)]
        else:                                                  # stall / dead
            st = cfg['stall'][k]
            h = h_sp[th:tg].copy()
            ctl[th:tg] = 0
            ctl[th + st['ticks']] = CLK
            h[st['ticks']] = st['cbits']
        h_sp[th:tg] = h
        h_id[th:tg] = h
        ctl[ev['tm']:ev['tr']] |= MUTE

    res = dict(refs=refs, rate=rate)
    pad, tail = ms(rate, 50), ms(rate, 300)
    y_none = decode_mute(h_sp, p, ctl, rail=rail)

    # burst: strategy-independent
    for fn, F in FILTERS:
        pk, r = [], []
        for ev in evs:
            th, tm = ev['th'], ev['tm']
            lo, hi = th - pad, tm + ms(rate, 100)
            seg = np.zeros(hi - lo)
            seg[th - lo:tm - lo] = y_none[th:tm]
            a, b = pk_r10(F(seg, rate), rate, pad - ms(rate, 20), tm - lo + pad, refs[fn])
            pk.append(a); r.append(b)
        res[(fn, 'burst', 'pk')], res[(fn, 'burst', 'r10')] = pk, r

    # cold-start control for the release
    for fn, F in FILTERS:
        for post, bb, yr in (('sp', b_sp, y_sp), ('id', b_id, y_id)):
            pk, r = [], []
            for ev in evs:
                tr = ev['tr']
                seg = np.zeros(pad + tail)
                seg[pad:] = card.decode(bb[tr:tr + tail], p) - yr[tr:tr + tail]
                a, b = pk_r10(F(seg, rate), rate, pad - ms(rate, 20), pad + ms(rate, 100), refs[fn])
                pk.append(a); r.append(b)
            res[(fn, 'cold', 'r' + post + '_pk')], res[(fn, 'cold', 'r' + post + '_r10')] = pk, r
        xs = []
        for ev in evs:
            tr = ev['tr']
            yc = np.concatenate([np.zeros(pad), card.decode(b_sp[tr:tr + tail], p)])
            w0, w1 = pad - ms(rate, 5), pad + ms(rate, 50)
            xs.append(pk_r10(F(yc, rate), rate, w0, w1, refs[fn])[0]
                      - max(0.0, pk_r10(F(y_sp[tr - pad:tr + tail], rate), rate, w0, w1, refs[fn])[0]))
        res[(fn, 'cold', 'rsp_x')] = xs

    for s in strats:
        hooks, gated, delay, _ = STRATS[s]
        muted = s != 'none'
        c2 = ctl if muted else (ctl & CLK)
        outs = {}
        for post, hb, yr in (('sp', h_sp, y_sp), ('id', h_id, y_id)):
            y = y_none if (post == 'sp' and not muted) else decode_mute(hb, p, c2, rail=rail, **hooks)
            if gated:
                y = y.copy()
                for ev in evs:
                    y[ev['tm']:ev['tr'] + ms(rate, delay)] = 0.0
            outs[post] = (y, yr)
        for fn, F in FILTERS:
            m = {key: [] for key in ('as_pk', 'as_r10', 'mute_r10', 'rsp_pk', 'rsp_r10', 'rsp_x',
                                     'rid_pk', 'rid_r10', 'hash_rms', 'hash_pk')}
            for ev in evs:
                th, tm, tr = ev['th'], ev['tm'], ev['tr']
                y = outs['sp'][0]
                lo, hi = tm - pad, tr + pad
                seg = np.zeros(hi - lo)
                seg[pad:tr - lo] = y[tm:tr]
                fs_ = F(seg, rate)
                a, b = pk_r10(fs_, rate, pad - ms(rate, 5), tr - lo - ms(rate, 20), refs[fn])
                m['as_pk'].append(a); m['as_r10'].append(b)
                m['mute_r10'].append(pk_r10(fs_, rate, pad + ms(rate, 50), tr - lo - ms(rate, 20), refs[fn])[1])
                a, b = pk_r10(fs_, rate, pad + ms(rate, 50), tr - lo - ms(rate, 20), refs[fn], overall=True)
                m['hash_pk'].append(a); m['hash_rms'].append(b)
                t_open = tr + (ms(rate, delay) if gated else 0)
                for post in ('sp', 'id'):
                    y, yr = outs[post]
                    seg = np.zeros(pad + tail)
                    seg[pad:] = y[t_open:t_open + tail] - yr[t_open:t_open + tail]
                    a, b = pk_r10(F(seg, rate), rate, pad - ms(rate, 20), pad + ms(rate, 100), refs[fn])
                    m['r' + post + '_pk'].append(a); m['r' + post + '_r10'].append(b)
                y, yr = outs['sp']
                lo, hi, w0, w1 = t_open - pad, t_open + tail, pad - ms(rate, 5), pad + ms(rate, 50)
                m['rsp_x'].append(pk_r10(F(y[lo:hi], rate), rate, w0, w1, refs[fn])[0]
                                  - max(0.0, pk_r10(F(yr[lo:hi], rate), rate, w0, w1, refs[fn])[0]))
            for key, v in m.items():
                res[(fn, s, key)] = v
    return res


def run_cfg(pool, cfg):
    t0 = time.time()
    out = pool.map(talker_job, [(ti, cfg) for ti in range(len(card.TALKERS))])
    return out, time.time() - t0


def agg(results, fn, s, key):
    """Per talker the worst of its outages; then (mean, worst) over talkers."""
    v = np.array([max(r[(fn, s, key)]) for r in results])
    v = np.maximum(v, -99.0)
    return float(v.mean()), float(v.max())


def cell(mw):
    m, w = mw
    if w <= -99.0:
        return f'{"-":>12s}'
    return f'{m:+6.1f}/{w:+5.1f}'


COLS = (('as_pk', 'assert pk'), ('as_r10', 'assert r10'), ('mute_r10', 'mute r10'),
        ('rid_pk', 'idle pk'), ('rid_r10', 'idle r10'),
        ('rsp_pk', 'sp err pk'), ('rsp_r10', 'sp err r10'), ('rsp_x', 'sp excess'))
LW = 32


def table(results, fn, strats, title):
    print(f'\n  {title}  [{fn}]   dB re speech rms, mean/worst of 7 talkers')
    print('  ' + f'{"":{LW}s}' + f'{"-------- MUTE asserts --------":>36s}'
          + f'{"---------------- MUTE releases ----------------":>60s}')
    print('  ' + f'{"":{LW}s}' + ''.join(f'{c:>12s}' for _, c in COLS))
    print('  ' + f'{"burst before MUTE (all)":{LW}s}'
          + cell(agg(results, fn, 'burst', 'pk')) + cell(agg(results, fn, 'burst', 'r10')))
    print('  ' + f'{"cold start (control)":{LW}s}' + ' ' * 36
          + ''.join(cell(agg(results, fn, 'cold', k)) for k in ('rid_pk', 'rid_r10', 'rsp_pk', 'rsp_r10', 'rsp_x')))
    for s in strats:
        label = f'{s:6s}{STRATS[s][3]}'
        print('  ' + f'{label:{LW}s}' + ''.join(cell(agg(results, fn, s, k)) for k, _ in COLS))


# ---------------------------------------------------------------------------
if __name__ == '__main__':
    print(' '.join(__doc__.strip().splitlines()[:2]))
    t_start = time.time()

    print('\n=== 1. THE HOOKED DECODER IS card.decode WHEN MUTE NEVER ASSERTS ===')
    print('  30 s, speech bits and random bits, every talker and rate; bit-exact comparison')
    for rate in card.RATES:
        p = card.CardParams(rate)
        same = 0
        for f in card.TALKERS:
            bs = card.encode(card.load_talker(f, rate, SECS), p)
            rb = np.random.default_rng(7).integers(0, 2, len(bs), dtype=np.uint8)
            for bb in (bs, rb):
                y0, s0 = card.decode(bb, p, internals=True)
                y1, s1 = decode_mute(bb, p, internals=True)
                same += int(np.array_equal(y0, y1) and np.array_equal(s0, s1))
        print(f'  {rate // 1000:2d}k  identical output and syllabic node: {same}/{2 * len(card.TALKERS)}')
        assert same == 2 * len(card.TALKERS)
    print('  and with every hook set, a rail, a mute window and a stalled clock: C against plain Python')
    p = card.CardParams(32000)
    x = card.load_talker(card.TALKERS[0], 32000, 1.0)[16000:28800]
    bb = card.encode(x, p)
    bb[4000:8000] = hash_bits('ones', 4000, 3)
    ctl = np.full(len(bb), CLK, np.uint8)
    ctl[4000 + 200:8000 + 32] |= MUTE
    held = np.arange(6000, 7000)
    ctl[held[held % 7 != 0]] &= ~np.uint8(CLK)          # clock ticks one bit in seven
    agree = []
    for hk in (dict(), dict(coin=1), dict(step=1), dict(coin=1, step=1), dict(idle=1),
               dict(coin=1, hold=1), dict(coin=1, hold=1, hres=0.12), dict(clear=1)):
        for rail in (0.0, 2.0):
            agree.append(np.array_equal(decode_mute(bb, p, ctl, rail=rail, **hk),
                                        decode_mute_py(bb, p, ctl, rail=rail, **hk)))
    print(f'  identical: {sum(agree)}/{len(agree)}')
    assert all(agree)

    print('\n=== 2. HASH MODELS: WHAT THE RECEIVE CHAIN DELIVERS ON A NOISE-ONLY LINE ===')
    print('  N = 3, 32 samples per cell, 2nd-order low-pass at the symbol rate, slicer')
    print('  hysteresis 0.05, monostable 0.75 / 0.25 cell; 0.5 s of line.  Channel stream =')
    print('  every 8th emitted bit (the demux position of C1).')
    print(f'  {"noise sd":>8s} {"strobes/cell":>13s} {"ones":>6s} {"C1 ones":>8s} '
          f'{"C1 run of 1s: mean":>19s} {"max":>5s} {"run of 0s: mean":>16s}  mono_timed == fast')
    measured = None
    for sd in (0.05, 0.1, 0.2, 1.0):
        w = noise_slicer(sd, 0.5 * 256000, seed=11)
        rb = fast.mono_decode(w, OS)
        bt, _, _ = mono_timed(w)
        del w
        c = rb[1::8]
        edges = np.concatenate([[0], np.flatnonzero(np.diff(c.astype(np.int8)) != 0) + 1, [len(c)]])
        L, V = np.diff(edges), c[edges[:-1]]
        print(f'  {sd:8.2f} {len(rb) / 128000:13.3f} {rb.mean():6.3f} {c.mean():8.3f} '
              f'{L[V == 1].mean():19.1f} {L[V == 1].max():5d} {L[V == 0].mean():16.2f}  '
              f'{np.array_equal(rb, bt)}')
    print(f'  -> "ones" model: runs of 1s, geometric, mean {RUN_MEAN} bits, single 0s between.')
    print('     A quiet line also strobes at only ~4% of the nominal rate: section 5 models that.')
    w = noise_slicer(1.0, 1.0 * 256000, seed=12)
    measured = fast.mono_decode(w, OS)
    del w
    print(f'  measured sd 1.0 stream for section 5: {len(measured)} bits, ones {measured.mean():.3f}')

    with Pool(WORKERS) as pool:
        R, ALL = {}, {}
        for rate in card.RATES:
            for kind in ('random', 'ones'):
                cfg = dict(rate=rate, D=1.0, lof=40, hash=kind,
                           strats=MAIN if rate == 32000 else OTHER_RATES)
                R[(rate, kind)], dt = run_cfg(pool, cfg)
                ALL[f'{rate // 1000}k {kind}'] = R[(rate, kind)]
                print(f'  [ran {rate // 1000}k {kind}: {dt:.0f} s]', flush=True)

        print('\n  Open-loop decoder during 1 s of hash (no mute), whole-hash rms and peak, 32k:')
        for kind in ('random', 'ones'):
            for fn, _ in FILTERS:
                print(f'    {kind:7s} [{fn:11s}]  rms {cell(agg(R[(32000, kind)], fn, "none", "hash_rms"))}'
                      f'   peak {cell(agg(R[(32000, kind)], fn, "none", "hash_pk"))}')
        print('    (squelch.py, noise-only line through the old framer: +20.8..+24.1 rms, +41.0..+47.7 peak)')

        print('\n=== 3. HEADLINE: 32 kbps, 30 s, D = 1 s, MUTE 40 frames after onset, release 32 frames after ===')
        print('  assert = output after MUTE asserts; mute = loudest 10 ms late in the mute; idle = output')
        print('  after it opens onto an idle far end; sp err = output minus the uninterrupted decode after')
        print('  it opens onto speech; sp excess = its peak over the speech peak that belongs there.')
        print('  Unbounded integrator (the repository model).')
        for kind in ('random', 'ones'):
            for fn, _ in FILTERS:
                table(R[(32000, kind)], fn, MAIN, f'32k, hash = {kind}')

        print('\n  LOF delay: burst before MUTE at 16 and 40 frames, 32k (mean/worst)')
        R16 = {}
        for kind in ('random', 'ones'):
            R16[kind], dt = run_cfg(pool, dict(rate=32000, D=1.0, lof=16, hash=kind, strats=['b']))
            for fn, _ in FILTERS:
                print(f'    {kind:7s} [{fn:11s}]  16 frames: pk {cell(agg(R16[kind], fn, "burst", "pk"))} '
                      f'r10 {cell(agg(R16[kind], fn, "burst", "r10"))}   40 frames: pk '
                      f'{cell(agg(R[(32000, kind)], fn, "burst", "pk"))} r10 {cell(agg(R[(32000, kind)], fn, "burst", "r10"))}'
                      f'   (b) assert pk 16: {cell(agg(R16[kind], fn, "b", "as_pk"))}')

        print('\n=== 4. 16 AND 64 kbps (same method; 40 / 32 frames are 2.5 / 2.0 ms at 16k, 0.6 / 0.5 ms at 64k) ===')
        for rate in (16000, 64000):
            for kind in ('random', 'ones'):
                for fn, _ in FILTERS:
                    table(R[(rate, kind)], fn, OTHER_RATES, f'{rate // 1000}k, hash = {kind}')

        print('\n=== 5. HARDWARE REALISM, 32 kbps ===')
        REAL = ['none', 'a', 'a0', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'h100', 'h1k', 'a+10', 'a+20', 'a+30']
        print('\n  Section 5 adds h100 / h1k: the switch across C_int has 100 ohm / 1 kohm in circuit, so the OTA')
        print('  current leaves I x R on the integrator while MUTE (0.012 / 0.12 FS at I_max = 120 uA, 1 V FS).')
        print('\n  5.1 Integrator rail at +/-2 FS (full scale = +/-1 V about bias; the rail is an assumption)')
        for kind in ('random', 'ones'):
            rr, dt = run_cfg(pool, dict(rate=32000, D=1.0, lof=40, hash=kind, rail=2.0, strats=REAL))
            ALL[f'32k {kind}, rail 2 FS'] = rr
            for fn, _ in FILTERS:
                table(rr, fn, REAL, f'32k, hash = {kind}, rail 2 FS')

        print('\n  5.2 Hash = measured chain bits at noise sd 1.0 (ones 25%), nominal clock')
        rr, dt = run_cfg(pool, dict(rate=32000, D=1.0, lof=40, hash='measured', measured=measured, strats=REAL))
        ALL['32k measured sd 1.0'] = rr
        for fn, _ in FILTERS:
            table(rr, fn, REAL, '32k, hash = measured sd 1.0')

        print('\n  5.3 Clock stall: noise sd 0.05 through the chain with its real strobe timing.')
        print('      The RX frame clock ticks only when 8 strobes have arrived (plus slips); between')
        print('      ticks the decoder flip-flops hold and the OTA current flows.  MUTE from the carrier')
        print('      detector (2-cell timeout, forced loss of frame).  Four outages, shared by all talkers.')
        stall = []
        for k in range(len(ONSETS)):
            st = stall_event(0.05, 1.0, 32000, seed=500 + k)
            stall.append(st)
            print(f'      outage {k}: strobes/cell {st["strobes"]:.3f}, frame-clock ticks in 1 s '
                  f'{len(st["ticks"])} of 32000, C1 ones {st["cbits"].mean() if len(st["cbits"]) else float("nan"):.3f}, '
                  f'grid collisions {st["collisions"]}; MUTE after {st["tm"]} bit(s) by carrier detect, '
                  f'by the LOF counter alone after '
                  + ('never' if st['lof_ms'] is None else f'{st["lof_ms"]:.1f} ms'))
        for kind, sts, title in (('stall', stall, 'noise sd 0.05, real timing'),
                                 ('dead', [stall_event(0, 1.0, 32000, 0)] * len(ONSETS),
                                  'dead line: no strobes, clock stopped')):
            rr, dt = run_cfg(pool, dict(rate=32000, D=1.0, lof=40, hash=kind, stall=sts, strats=REAL))
            ALL[f'32k {kind}'] = rr
            for fn, _ in FILTERS:
                table(rr, fn, REAL, f'32k, {title}')

        print('\n      The same stalled line with MUTE from the loss-of-frame counter alone (no carrier detect):')
        slow = [dict(st, tm=int(math.ceil((st['lof_ms'] or 1000.0) * 32.0))) for st in stall]
        rr, dt = run_cfg(pool, dict(rate=32000, D=1.0, lof=40, hash='stall', stall=slow,
                                    strats=['none', 'a', 'c', 'h', 'a+30']))
        for fn, _ in FILTERS:
            table(rr, fn, ['a', 'c', 'h', 'a+30'], f'32k, noise sd 0.05, real timing, MUTE by LOF counter')

        print('\n  5.4 Hash for 2 s instead of 1 s (release columns are the ones that could change)')
        for kind in ('random', 'ones'):
            rr, dt = run_cfg(pool, dict(rate=32000, D=2.0, lof=40, hash=kind, strats=BRIEF + ['a+30']))
            table(rr, 'tx chain', BRIEF + ['a+30'], f'32k, hash = {kind}, D = 2 s')

        print('\n=== 6. SUMMARY: worst talker, worst condition (every table above except 5.3-LOF and 5.4) ===')
        SUM = ['a', 'b', 'c', 'd', 'h', 'h100', 'a+30']
        for fn, _ in FILTERS:
            print(f'\n  [{fn}]   dB re speech rms; condition in brackets')
            keys = (('as_pk', 'assert pk'), ('mute_r10', 'mute r10'), ('rid_pk', 'relock idle pk'),
                    ('rsp_x', 'relock sp excess'))
            print('  ' + f'{"":{LW}s}' + ''.join(f'{c:>28s}' for _, c in keys))
            for s_ in SUM:
                row = []
                for k, _ in keys:
                    v = [(agg(rr, fn, s_, k)[1], name) for name, rr in ALL.items() if (fn, s_, k) in rr[0]]
                    w, name = max(v)
                    row.append(f'{"-" if w <= -99 else f"{w:+.1f}":>7s} [{name:>18s}]')
                print('  ' + f'{s_ + "  " + STRATS[s_][3]:{LW}s}' + ''.join(row))
            w, name = max((agg(rr, fn, 'burst', 'pk')[1], nm) for nm, rr in ALL.items())
            print(f'  {"burst before MUTE, any strategy":{LW}s}{w:+7.1f} [{name:>18s}]')

    print(f'\n[total {time.time() - t_start:.0f} s]')
