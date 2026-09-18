"""
Feasibility: a DIGITAL line receiver clocked by a local crystal.

Every rate-dependent ANALOG part of docs/line-receiver.md (input low-pass,
classifier timer, dead-time timer, carrier-detect timer) is replaced by logic
clocked from a local crystal through 74HC4040 taps chosen by a RATE jumper, as
on the transmitter.  One FIXED wideband analog anti-alias filter stays.

Sections
  a        clock arithmetic (no simulation)
  explore  many digital-filter variants at a few noise levels, to pick a design
  b        ABSOLUTE noise margin at 64 / 256 / 1024 kbps: analog reference vs
           unswitched analog vs digital variants (strap.py section-31 method)
  c        classification by counting: quantisation, asynchronous sampling,
           threshold and dead-time windows
  d        carrier detect as a counter timeout; noise-only lines
  b2       BER curves, three seeds: dB gaps at BER 1e-4 / 1e-3 for the candidate designs
  tune     count thresholds T (classifier) and D (dead time) under stress noise
  e        end to end with s4_simple.framer_single; rate mis-configuration
  f        CVSD decode with the tick-quantised receive frame clock

ABSOLUTE method (strap.py do_noise section 31): every rate simulated at one
32.768 MHz sample rate, so a given sd is one noise power spectral density; one
1 MHz first-order cable; each receiver's filter as specified.

Usage:  python3 feas_digital_rx.py [a|explore|b|b2run1|b2|tune|c|d|e|f]   (several allowed)
"""
import sys, os, gc, time, ctypes
import numpy as np
from scipy import signal
import fast, framing_review as fr, s4_simple as ss, rx_review as rr

_L = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'feas_digital_core.so'))
_D = np.ctypeslib.ndpointer(np.float64)
_U = np.ctypeslib.ndpointer(np.uint8)
_L.fd_slice_times.restype = ctypes.c_long
_L.fd_slice_times.argtypes = [_D, ctypes.c_long, ctypes.c_double, ctypes.POINTER(ctypes.c_int),
                              ctypes.POINTER(ctypes.c_double), ctypes.c_double, _D, ctypes.c_long]
_L.fd_mono_times.restype = ctypes.c_long
_L.fd_mono_times.argtypes = [_D, ctypes.c_long, ctypes.c_double, ctypes.c_double, ctypes.c_double,
                             _U, ctypes.c_long]
_L.fd_sat.restype = None
_L.fd_sat.argtypes = [_U, ctypes.c_long, ctypes.c_int, ctypes.c_int, _U]

FSC = 32.768e6          # common simulation rate (absolute method)
FCC = 1.0e6             # the one cable, first order
F_AA = 2.048e6          # the one fixed anti-alias filter: RC-RC, = 1024 kbps symbol rate
HYS = 0.05              # comparator hysteresis, fraction of received peak
CH = 1 << 22            # chunk, samples
MODES = {64000: (1, 16000), 256000: (3, 32000), 1024000: (7, 64000)}
SECS = {64000: 0.8, 256000: 0.4, 1024000: 0.25}      # 51k / 102k / 256k line bits
F8 = 8.192e6            # fast sample clock for the M = 8 designs (= 8 x 1024 kbps)
EPS = 150e-6            # local crystal vs far-end crystal (two +-100 ppm parts, near worst)
SCR = '/tmp/claude-1000/-home-joel-telco/ae7de41b-ce55-4205-b770-dad64b2d68bb/scratchpad'


def hdr(t):
    print('\n' + '=' * 78 + f'\n{t}\n' + '=' * 78, flush=True)


def rc1(fc, FS):
    return signal.butter(1, min(0.99, 2.0 * fc / FS))


_CV = None
def speech():
    global _CV
    if _CV is None:
        p = os.path.join(SCR, 'feas_digital_cv.npy')
        if os.path.exists(p):
            _CV = np.load(p)
        else:
            _CV = fr.load(4.0)[0]
            try: np.save(p, _CV)
            except OSError: pass
    return _CV


# ------------------------------------------------------------------ the line
class Link:
    """TX line bits -> differential Manchester -> one cable, sampled at FS.
    Receivers are applied per noise level by front()."""

    def __init__(self, line_rate, secs=None, FS=FSC, cable_fc=FCC, n=None, rate=None):
        n0, r0 = MODES.get(line_rate, (None, None))
        self.n = n or n0; self.rate = rate or r0
        assert self.n * 0 + (2 + 2 * self.n) * self.rate == line_rate
        self.secs = secs or SECS[line_rate]; self.lr = line_rate; self.FS = FS
        self.line, self.C = rr.link_line(self.n, self.rate, self.secs, speech())
        H = FS / (2 * line_rate); assert abs(H - round(H)) < 1e-9; H = int(round(H))
        self.spb = 2 * H
        hc = fast.dm_encode(self.line)
        self.ns = len(hc) * H
        y = np.empty(self.ns, np.float32)
        b, a = rc1(cable_fc, FS); zi = np.zeros(1)
        for s0 in range(0, self.ns, CH):
            s1 = min(self.ns, s0 + CH)
            xin = hc[np.arange(s0, s1) // H].astype(np.float64) * 2 - 1
            out, zi = signal.lfilter(b, a, xin, zi=zi); y[s0:s1] = out
        y /= np.abs(y).max()
        self.y = y

    def front(self, sd, fcs, seed=1, h=HYS, signal_on=True):
        """Noise at the common rate, then per receiver filter fc (two first-order
        RC sections) and a hysteretic comparator.  Returns, per fc, the comparator
        transition times in simulation samples (interpolated)."""
        rng = np.random.default_rng(seed)
        st = []
        for fc in fcs:
            b, a = rc1(fc, self.FS)
            st.append([b, a, np.zeros(1), np.zeros(1), ctypes.c_int(0), ctypes.c_double(0.0), []])
        buf = np.empty(CH, np.float64)
        for s0 in range(0, self.ns, CH):
            s1 = min(self.ns, s0 + CH)
            x = self.y[s0:s1].astype(np.float64) if signal_on else np.zeros(s1 - s0)
            if sd:
                x += rng.normal(0.0, sd, s1 - s0)
            for S in st:
                z, S[2] = signal.lfilter(S[0], S[1], x, zi=S[2])
                z, S[3] = signal.lfilter(S[0], S[1], z, zi=S[3])
                nt = _L.fd_slice_times(np.ascontiguousarray(z), s1 - s0, h, ctypes.byref(S[4]),
                                       ctypes.byref(S[5]), float(s0), buf, CH)
                assert nt >= 0
                S[6].append(buf[:nt].copy())
            del x; gc.collect()
        return [np.concatenate(S[6]) if S[6] else np.zeros(0) for S in st]


# ----------------------------------------------------------- receiver pieces
def mono_times(t, spb, thr=0.75, dead=0.2):
    """The analog interval classifier (monostables), continuous time."""
    t = np.ascontiguousarray(t, np.float64)
    out = np.empty(len(t) + 64, np.uint8)
    nb = _L.fd_mono_times(t, len(t), float(spb), thr, dead, out, len(out))
    return out[:nb]


def sample(t, ns, fclk, eps=EPS, phi=0.37, FS=FSC):
    """Comparator output sampled by a flip-flop clocked at fclk*(1+eps), an
    asynchronous local crystal; phi = initial phase in clock periods."""
    Ts = FS / (fclk * (1.0 + eps))
    K = int((ns - 1 - phi * Ts) / Ts)
    q = np.empty(K, np.uint8)
    for k0 in range(0, K, CH):
        k1 = min(K, k0 + CH)
        q[k0:k1] = np.searchsorted(t, phi * Ts + np.arange(k0, k1) * Ts, 'right') & 1
    return q


def iad(q, B, tie='one', skip_first=False):
    """Integrate-and-dump of hard samples: sign of an up/down count over each
    block of B fast samples.  skip_first: the dump tick loads 0 instead of
    counting, so B-1 samples (odd) and no ties."""
    if B == 1:
        return q.copy()
    nb = len(q) // B
    g = q[:nb * B].reshape(nb, B)
    if skip_first:
        g = g[:, 1:]
    m = g.shape[1]
    s = g.sum(1, dtype=np.int32)
    out = (2 * s > m).astype(np.int8)
    tie_m = (2 * s == m)
    if tie == 'one':
        out[tie_m] = 1
    elif tie == 'hold':
        v = np.where(tie_m, -1, out)
        idx = np.where(v >= 0, np.arange(nb), 0)
        np.maximum.accumulate(idx, out=idx)
        out = v[idx]; out[out < 0] = 0
    return out.astype(np.uint8)


def iad2(q, B):
    """Soft sliding window of two blocks: (count of this block + count of the
    previous block) against B, tie holds.  Costs a block-count register and an
    adder over plain integrate-and-dump."""
    nb = len(q) // B
    c = q[:nb * B].reshape(nb, B).sum(1, dtype=np.int32)
    s2 = c.copy(); s2[1:] += c[:-1]
    out = np.where(s2 > B, 1, np.where(s2 < B, 0, -1)).astype(np.int8)
    idx = np.where(out >= 0, np.arange(nb), 0)
    np.maximum.accumulate(idx, out=idx)
    out = out[idx]; out[out < 0] = 0
    return out.astype(np.uint8)


def maj(q, W):
    """Sliding majority of W (odd) samples: W-1 flip-flops and a majority gate."""
    if W == 1:
        return q
    c = np.concatenate([[0], np.cumsum(q, dtype=np.int64)])
    return (2 * (c[W:] - c[:-W]) > W).astype(np.uint8)


def sat(q, K, mode=0):
    q = np.ascontiguousarray(q, np.uint8); out = np.empty(len(q), np.uint8)
    _L.fd_sat(q, len(q), int(K), int(mode), out)
    return out


def count_classify(s, M, T=None, D=None):
    """Interval classifier as a counter of sample ticks: long if the count since
    the last accepted edge is >= T, edges with count < D ignored.
    fast.mono_decode with one sample per 'bit' and half-integer thresholds is
    exactly this integer comparison."""
    T = int(round(0.75 * M)) if T is None else T
    D = max(1, int(round(0.2 * M))) if D is None else D
    return fast.mono_decode(s, 1.0, thr=T - 0.5, dead=max(D, 1) - 0.5)


def digital(t, ns, lr, v, eps=EPS, phi=0.37, cache=None):
    """Run one digital receiver variant on comparator transition times.
    Returns (recovered bits, decimated filtered stream at M per line bit)."""
    M = v['M']
    if v['kind'] == 'samp':
        key = ('samp', M * lr, eps, phi)
        if cache is not None and key in cache: q = cache[key]
        else:
            q = sample(t, ns, M * lr, eps, phi)
            if cache is not None: cache[key] = q
        s = q
    else:
        F0 = v['F0']; B = F0 / (M * lr); assert abs(B - round(B)) < 1e-9; B = int(round(B))
        key = ('fast', F0, eps, phi)
        if cache is not None and key in cache: q = cache[key]
        else:
            q = sample(t, ns, F0, eps, phi)
            if cache is not None: cache[key] = q
        if v['kind'] == 'iad':
            s = iad(q, B, v.get('tie', 'one'), v.get('skip', False))
        elif v['kind'] == 'iad2':
            s = iad2(q, B)
        else:  # sat
            K = max(1, int(round(v['kf'] * B)))
            s = sat(q, K, v.get('mode', 0))[B - 1::B]
    s = maj(s, v.get('W', 1))
    return count_classify(s, M, v.get('T'), v.get('D')), s


# ------------------------------------------------------------------- scoring
def line_errors(rb, ref, win=4096, search=12, skip=64):
    """Errors in recovered line bits against the transmitted line bits, realigning
    window by window so an inserted/deleted bit costs its window, not the clip.
    Returns (errors, bits compared)."""
    rb = np.asarray(rb, np.uint8)
    if len(rb) < skip + 2 * win:
        return None, 0
    a = rb[skip:skip + 2048]; best = None
    for o in range(-32, 96):
        if skip + o < 0 or skip + o + 2048 > len(ref): continue
        e = int(np.count_nonzero(a != ref[skip + o:skip + o + 2048]))
        if best is None or e < best[0]: best = (e, o)
    o = best[1]; errs = 0; nb = 0
    for s0 in range(skip, len(rb) - win, win):
        seg = rb[s0:s0 + win]; be = None
        for d in range(-search, search + 1):
            oo = o + d
            if s0 + oo < 0 or s0 + oo + win > len(ref): continue
            e = int(np.count_nonzero(seg != ref[s0 + oo:s0 + oo + win]))
            if be is None or e < be[0]: be = (e, oo)
        if be is None: break
        errs += be[0]; nb += win; o = be[1]
    return errs, nb


def ok_of(link, rb):
    e, nb = line_errors(rb, link.line)
    full = len(link.line) - 64 - 2 * 4096
    return (e is not None and e == 0 and nb >= 0.9 * full), e, nb


def fmt_e(e, nb, full):
    if e is None or nb < 0.9 * full:
        return '  slip'
    return '    ok' if e == 0 else f'{e / nb:6.0e}'


# ---------------------------------------------------------------- variants
def V(name, **kw):
    kw['name'] = name; return kw

EXPLORE = [
    V('S8 samp M8', kind='samp', M=8),
    V('S8 samp M8 maj3', kind='samp', M=8, W=3),
    V('S16 samp M16', kind='samp', M=16),
    V('S16 samp M16 maj3', kind='samp', M=16, W=3),
    V('S32 samp M32', kind='samp', M=32),
    V('S32 samp M32 maj5', kind='samp', M=32, W=5),
    V('I8 iad F8 tie1', kind='iad', F0=F8, M=8, tie='one'),
    V('I8h iad F8 hold', kind='iad', F0=F8, M=8, tie='hold'),
    V('I8h3 iad F8 hold maj3', kind='iad', F0=F8, M=8, tie='hold', W=3),
    V('I8o3 iad F8 tie1 maj3', kind='iad', F0=F8, M=8, tie='one', W=3),
    V('I16s iad F16 B-1 M8', kind='iad', F0=2 * F8, M=8, skip=True),
    V('I16s3 iad F16 B-1 M8 maj3', kind='iad', F0=2 * F8, M=8, skip=True, W=3),
    V('J16h iad F16 hold M16', kind='iad', F0=2 * F8, M=16, tie='hold'),
    V('J16h3 iad F16 hold M16 maj3', kind='iad', F0=2 * F8, M=16, tie='hold', W=3),
    V('A8m sat F8 K=2B mid', kind='sat', F0=F8, M=8, kf=2, mode=0),
    V('A8r sat F8 K=2B rail', kind='sat', F0=F8, M=8, kf=2, mode=1),
    V('A8m4 sat F8 K=4B mid', kind='sat', F0=F8, M=8, kf=4, mode=0),
]


def run_level(link, sd, variants, eps=EPS, seed=1):
    """One noise level: analog reference, unswitched analog, every digital variant.
    Returns {name: (ok, errors, bits)}."""
    t_ref, t_wb = link.front(sd, [2 * link.lr, F_AA], seed=seed)
    R = {}
    rb = mono_times(t_ref, link.spb); R['REF analog RC-RC @ own SYM'] = ok_of(link, rb)
    rb = mono_times(t_wb, link.spb); R['WB  analog RC-RC @ 2.048M only'] = ok_of(link, rb)
    del t_ref; gc.collect()
    cache = {}
    for v in variants:
        rb, _ = digital(t_wb, link.ns, link.lr, v, eps=eps, cache=cache)
        R[v['name']] = ok_of(link, rb)
    del cache, t_wb; gc.collect()
    return R


# ================================================================ section a
def do_a():
    hdr('(a) SAMPLING CLOCK ARITHMETIC  (M ticks per line bit, 74HC4040 taps)')
    rates = [1024000, 512000, 256000, 128000, 64000]
    print(f'  {"M":>3s} {"clock @1024k":>13s} {"period":>8s} {"clock @64k":>11s}  crystal (clock = Q1 of a 4040, 50% duty) / tap per rate')
    for M in (8, 16, 32):
        f = M * 1024000
        taps = ', '.join(f'{r // 1000}k=Q{1 + i}' for i, r in enumerate(rates))
        print(f'  {M:>3d} {f / 1e6:10.3f} MHz {1e9 / f:6.1f}ns {M * 64000 / 1e3:8.0f} kHz  '
              f'{2 * f / 1e6:.3f} MHz crystal; {taps}')
    print('\n  Timing budget of the fastest synchronous path (sample FF -> one gate level -> counter')
    print('  enable / D input), against the clock period.  74HC figures are ASSUMPTIONS, typical')
    print('  datasheet class at 4.5 V, 15-50 pF, not checked against a specific datasheet:')
    typ = dict(tpd_ff=17, tpd_gate=10, tsu=15)      # ns, typical, 25 C
    wc = dict(tpd_ff=40, tpd_gate=25, tsu=25)       # ns, worst case -40..+85 C, 50 pF
    for nm, d in (('typical', typ), ('worst case', wc)):
        need = d['tpd_ff'] + d['tpd_gate'] + d['tsu']
        row = []
        for M in (8, 16, 32):
            per = 1e9 / (M * 1024000)
            row.append(f'M={M}: {per:5.1f} ns period, slack {per - need:+6.1f} ns')
        print(f'  {nm:10s} path {need:3d} ns   ' + ';  '.join(row))
    print('  Assumed guaranteed fmax of 74HC flip-flops/sync counters over temperature: ~20-25 MHz;')
    print('  typical at 25 C: ~50-90 MHz.  (Assumption, see risks.)')


# =========================================================== explore section
def do_explore():
    hdr('EXPLORE: digital filter variants, line-bit errors at a few absolute noise levels')
    plan = {64000: (1.0, 1.4, 2.0), 256000: (0.6, 0.8, 1.0), 1024000: (0.3, 0.4, 0.5)}
    for lr, sds in plan.items():
        t0 = time.time()
        link = Link(lr, secs={64000: 0.5, 256000: 0.3, 1024000: 0.2}[lr])
        full = len(link.line) - 64 - 2 * 4096
        res = {sd: run_level(link, sd, EXPLORE) for sd in sds}
        print(f'\n  {lr // 1000} kbps line ({len(link.line)} bits), sd = ' + ' '.join(f'{s:>6.2f}' for s in sds))
        for name in res[sds[0]]:
            print(f'    {name:34s} ' + ' '.join(fmt_e(res[s][name][1], res[s][name][2], full) for s in sds))
        print(f'    ({time.time() - t0:.0f} s)', flush=True)
        del link; gc.collect()


# ================================================================ section b
SDGRID = [round(0.3 * 10 ** (k / 20), 3) for k in range(0, 24)]      # 1 dB steps, 0.30 .. 4.2

B_VARIANTS = [
    V('S8 samp M8 maj3', kind='samp', M=8, W=3),
    V('S16 samp M16 maj3', kind='samp', M=16, W=3),
    V('S32 samp M32 maj5', kind='samp', M=32, W=5),
    V('I8 iad F8 tie1', kind='iad', F0=F8, M=8, tie='one'),
    V('I8h iad F8 hold', kind='iad', F0=F8, M=8, tie='hold'),
    V('I8h3 iad F8 hold maj3', kind='iad', F0=F8, M=8, tie='hold', W=3),
    V('J16h iad F16 hold M16', kind='iad', F0=2 * F8, M=16, tie='hold'),
    V('J16h3 iad F16 hold M16 maj3', kind='iad', F0=2 * F8, M=16, tie='hold', W=3),
    V('K16 iad2 F16 soft2 M16', kind='iad2', F0=2 * F8, M=16),
    V('A8m sat F8 K=2B mid', kind='sat', F0=F8, M=8, kf=2, mode=0),
]


def do_b(rates=(64000, 256000, 1024000)):
    hdr('(b) ABSOLUTE NOISE MARGIN: one cable (1 MHz), one noise floor, 32.768 MHz common rate')
    print(f'  fixed anti-alias for every digital variant: two RC sections at {F_AA / 1e6:.3f} MHz;')
    print(f'  comparator hysteresis {HYS}; local crystal offset {EPS * 1e6:.0f} ppm; sd grid 1 dB steps.')
    print('  Entry: largest sd with every grid level up to it error-free on all line bits.')
    limits = {}
    for lr in rates:
        t0 = time.time()
        link = Link(lr)
        full = len(link.line) - 64 - 2 * 4096
        names = None; lim = {}; fails = {}; rows = {}
        for sd in SDGRID:
            alive = [v for v in B_VARIANTS if fails.get(v['name'], 0) < 2]
            if names is not None and all(fails.get(nm, 0) >= 2 for nm in names):
                break
            R = run_level(link, sd, alive)
            if names is None: names = list(R.keys())
            if fails.get('REF analog RC-RC @ own SYM', 0) >= 2 and fails.get('WB  analog RC-RC @ 2.048M only', 0) >= 2:
                pass
            for nm in names:
                if nm not in R:
                    rows.setdefault(nm, []).append('     -'); continue
                ok, e, nb = R[nm]
                rows.setdefault(nm, []).append(fmt_e(e, nb, full))
                if ok and fails.get(nm, 0) == 0: lim[nm] = sd
                if not ok: fails[nm] = fails.get(nm, 0) + 1
            print(f'    {lr // 1000}k sd {sd:.3f} done ({time.time() - t0:.0f} s)', flush=True)
        nsd = len(next(iter(rows.values())))
        print(f'\n  {lr // 1000} kbps line, {len(link.line)} line bits, sd:  ' + ' '.join(f'{s:6.2f}' for s in SDGRID[:nsd]))
        for nm in names:
            l = lim.get(nm, 0.0)
            print(f'    {nm:32s} ' + ' '.join(rows[nm]) + f'   error-free to sd {l:.3f}')
        limits[lr] = lim
        del link; gc.collect()
    ref256 = limits.get(256000, {}).get('REF analog RC-RC @ own SYM')
    if ref256:
        hdr('(b) SUMMARY, dB relative to the analog reference at 256 kbps')
        names = list(next(iter(limits.values())).keys())
        allnames = []
        for lim in limits.values():
            for nm in lim:
                if nm not in allnames: allnames.append(nm)
        print(f'  {"receiver":32s} ' + ' '.join(f'{lr // 1000:>8d}k' for lr in limits))
        for nm in allnames:
            cells = []
            for lr, lim in limits.items():
                v = lim.get(nm)
                cells.append(f'{20 * np.log10(v / ref256):+8.1f} ' if v else '    fail ')
            print(f'  {nm:32s} ' + ' '.join(cells))
    return limits


# =============================================================== section b2
F12 = 12.288e6
B2_RUN1 = [   # first run (log feas_digital_b2 run 1): default T=round(0.75M), D=round(0.2M)
    V('I8h  M8  iad F8.192 hold', kind='iad', F0=F8, M=8, tie='hold'),
    V('I12h M12 iad F12.288 hold', kind='iad', F0=F12, M=12, tie='hold'),
    V('J16h3 M16 iad F16.384 hold maj3', kind='iad', F0=2 * F8, M=16, tie='hold', W=3),
    V('K16 M16 iad2 F16.384 soft2', kind='iad2', F0=2 * F8, M=16),
]
B2_VARIANTS = [  # second run: buildable no-tie variants, and M=16 with D=4 from `tune`
    V('I8s  M8  iad F8.192 B-1 T6 D2', kind='iad', F0=F8, M=8, skip=True, T=6, D=2),
    V('J16h3 M16 hold maj3 T12 D4', kind='iad', F0=2 * F8, M=16, tie='hold', W=3, T=12, D=4),
    V('J16s3 M16 B-1 maj3 T12 D4', kind='iad', F0=2 * F8, M=16, skip=True, W=3, T=12, D=4),
]
B2_SD = {64000: (1.5, 1.69, 1.89, 2.12, 2.38, 2.67, 3.0),
         256000: (0.67, 0.75, 0.85, 0.95, 1.06, 1.19, 1.34),
         1024000: (0.27, 0.30, 0.34, 0.38, 0.42, 0.47, 0.53)}


def sd_at(sds, bers, target):
    """log-log interpolation of the sd where BER first reaches target."""
    prev = None
    for sd, b in zip(sds, bers):
        if b >= target:
            if prev is None or prev[1] <= 0:
                return sd if prev is None else prev[0] + (sd - prev[0]) * 0.5
            f = (np.log(target) - np.log(prev[1])) / (np.log(b) - np.log(prev[1]))
            return float(np.exp(np.log(prev[0]) + f * (np.log(sd) - np.log(prev[0]))))
        prev = (sd, b)
    return None


def do_b2(seeds=(1, 2, 3), variants=None):
    variants = B2_VARIANTS if variants is None else variants
    hdr('(b2) BER CURVES, three noise seeds pooled: sd at which line BER reaches 1e-4 and 1e-3')
    print('  Same absolute method as (b).  Pooled bits per point: 3 x the (b) clip.')
    cross = {}
    for lr in (64000, 256000, 1024000):
        t0 = time.time()
        link = Link(lr)
        names = ['REF analog RC-RC @ own SYM'] + [v['name'] for v in variants]
        E = {nm: [] for nm in names}
        for sd in B2_SD[lr]:
            tot = {nm: [0, 0] for nm in names}
            for seed in seeds:
                t_ref, t_wb = link.front(sd, [2 * lr, F_AA], seed=seed)
                rb = mono_times(t_ref, link.spb); e, nb = line_errors(rb, link.line)
                tot[names[0]][0] += e if e is not None else nb; tot[names[0]][1] += nb
                cache = {}
                for v in variants:
                    rb, _ = digital(t_wb, link.ns, lr, v, cache=cache)
                    e, nb = line_errors(rb, link.line)
                    tot[v['name']][0] += e if e is not None else 0; tot[v['name']][1] += nb
                del t_ref, t_wb, cache; gc.collect()
            for nm in names:
                e, nb = tot[nm]; E[nm].append(e / nb if nb else 1.0)
        print(f'\n  {lr // 1000} kbps, {3 * len(link.line)} line bits per point  ({time.time() - t0:.0f} s)')
        print(f'    {"receiver":34s} ' + ' '.join(f'{s:>7.2f}' for s in B2_SD[lr]) + '   sd@1e-4  sd@1e-3')
        for nm in names:
            a = sd_at(B2_SD[lr], E[nm], 1e-4); b = sd_at(B2_SD[lr], E[nm], 1e-3)
            cross[(lr, nm)] = (a, b)
            print(f'    {nm:34s} ' + ' '.join(('      0' if x == 0 else f'{x:7.0e}') for x in E[nm])
                  + f'   {a if a else float("nan"):6.3f}  {b if b else float("nan"):6.3f}', flush=True)
        del link; gc.collect()
    ref = cross.get((256000, 'REF analog RC-RC @ own SYM'), (None, None))
    hdr('(b2) SUMMARY: dB of tolerable noise at BER 1e-4 (1e-3), vs the analog reference at 256 kbps')
    names = ['REF analog RC-RC @ own SYM'] + [v['name'] for v in variants]
    for nm in names:
        cells = []
        for lr in (64000, 256000, 1024000):
            a, b = cross.get((lr, nm), (None, None))
            ca = f'{20 * np.log10(a / ref[0]):+5.1f}' if a and ref[0] else '  n/a'
            cb = f'{20 * np.log10(b / ref[1]):+5.1f}' if b and ref[1] else '  n/a'
            cells.append(f'{ca} ({cb})')
        print(f'  {nm:34s} ' + '   '.join(f'{lr // 1000:>4d}k {c}' for lr, c in zip((64000, 256000, 1024000), cells)))


# ============================================================= section tune
def do_tune(seeds=(1, 2)):
    hdr('(tune) COUNT THRESHOLDS UNDER STRESS: line-bit errors (two seeds pooled) vs T and D')
    print('  Noise levels at or beyond each candidate\'s error-free limit, so the counts discriminate.')
    plan = {64000: (2.12, 2.38), 256000: (0.95, 1.06), 1024000: (0.34, 0.38)}
    cands = [('M8 iad hold', V('x', kind='iad', F0=F8, M=8, tie='hold'), (5, 6, 7), (1, 2, 3, 4)),
             ('M12 iad hold', V('x', kind='iad', F0=F12, M=12, tie='hold'), (8, 9, 10), (2, 3, 4, 5)),
             ('M16 iad hold maj3', V('x', kind='iad', F0=2 * F8, M=16, tie='hold', W=3), (11, 12, 13), (2, 3, 4, 6))]
    for lr, sds in plan.items():
        link = Link(lr)
        for sd in sds:
            acc = {}
            for seed in seeds:
                t = link.front(sd, [F_AA], seed=seed)[0]
                cache = {}
                for nm, v, Ts, Ds in cands:
                    for T in Ts:
                        for D in Ds:
                            rb, _ = digital(t, link.ns, lr, dict(v, T=T, D=D), cache=cache)
                            e, nb = line_errors(rb, link.line)
                            a = acc.setdefault((nm, T, D), [0, 0]); a[0] += (e if e is not None else nb); a[1] += nb
                del t, cache; gc.collect()
            print(f'\n  {lr // 1000}k sd {sd}  (errors / {acc[(cands[0][0], 6, 2)][1]} bits)')
            for nm, v, Ts, Ds in cands:
                print(f'    {nm:18s} ' + '  '.join(f'T{T}:' + ','.join(f'D{D}={acc[(nm, T, D)][0]}' for D in Ds)
                                                   for T in Ts), flush=True)
        del link; gc.collect()


# ================================================================ section c
def do_c():
    hdr('(c1) QUANTISATION ALONE: the specified analog front end (RC-RC at SYM), relative setup,')
    print('     256 kbps, OS 32 (8.192 MHz), cable 1.7578 x SYM.  Continuous monostable vs counting')
    print('     classifier on the comparator sampled at M per bit.  Entry: error-free thresholds.')
    lr = 256000; FS = lr * 32
    link = Link(lr, secs=0.4, FS=FS, cable_fc=1.7578 * 2 * lr)
    full = len(link.line) - 64 - 2 * 4096
    THR = [round(0.45 + 0.05 * k, 2) for k in range(13)]
    for sd in (0.0, 0.4):
        t = link.front(sd, [2 * lr], seed=1)[0]
        okc = [x for x in THR if ok_of(link, mono_times(t, 32, thr=x, dead=0.2))[0]]
        print(f'\n  sd {sd:.1f}  continuous  thr (cell): ' + (f'{min(okc):.2f}-{max(okc):.2f}' if okc else 'none')
              + f'   ok at {okc}', flush=True)
        for M in (8, 16):
            D = max(1, int(round(0.2 * M)))
            for lab, eps, phis in (('+150 ppm', EPS, (0.37,)), ('-150 ppm', -EPS, (0.37,)),
                                   ('sync, 4 phases', 0.0, (0.0, 0.25, 0.5, 0.75)), ('+1% stress', 0.01, (0.37,))):
                good = []
                qs = [sample(t, link.ns, M * lr, eps, ph, FS=FS) for ph in phis]
                for T in range(int(0.4 * M), int(1.2 * M) + 1):
                    if all(ok_of(link, count_classify(q, M, T, D))[0] for q in qs):
                        good.append(T)
                del qs
                w = (f'T = {min(good)}..{max(good)} counts = {min(good) / M:.3f}-{max(good) / M:.3f} cell'
                     if good else 'none')
                print(f'         M={M:2d} D={D} {lab:15s} {w}', flush=True)
            if sd == 0.4:
                q = sample(t, link.ns, M * lr, EPS, 0.37, FS=FS)
                okd = [D2 for D2 in range(1, M) if ok_of(link, count_classify(q, M, None, D2))[0]]
                okd_c = [x for x in (0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45)
                         if ok_of(link, mono_times(t, 32, thr=0.75, dead=x))[0]] if M == 8 else None
                print(f'         M={M:2d} dead-time counts error-free (T={int(round(0.75 * M))}, +150 ppm): {okd}'
                      + (f';  continuous dead (cell): {okd_c}' if okd_c is not None else ''), flush=True)
        del t; gc.collect()
    del link; gc.collect()

    hdr('(c2) THE DIGITAL RECEIVER (design below), absolute setup: threshold and dead-time windows')
    print(f'  Design: {DESIGN["name"]} (M=16 alternative {ALT16["name"]} at 1024k).  Defaults T=round(0.75M),')
    print('  D=round(0.2M); one is swept with the other at default.')
    for lr, D_, sds in ((64000, DESIGN, (1.6,)), (256000, DESIGN, (0.0, 0.8)),
                        (1024000, DESIGN, (0.24,)), (1024000, ALT16, (0.4,))):
        link = Link(lr, secs={64000: 0.5, 256000: 0.3, 1024000: 0.2}[lr])
        for sd in sds:
            t = link.front(sd, [F_AA], seed=1)[0]
            M = D_['M']
            for lab, eps, phis in (('+150 ppm', EPS, (0.37,)), ('-150 ppm', -EPS, (0.61,)),
                                   ('sync, 4 phases', 0.0, (0.0, 0.25, 0.5, 0.75))):
                goodT = []; goodD = []
                cache = [{} for _ in phis]
                for T in range(M // 2, M + 1):
                    if all(ok_of(link, digital(t, link.ns, lr, dict(D_, T=T), eps, ph, cache[i])[0])[0]
                           for i, ph in enumerate(phis)):
                        goodT.append(T)
                for D in range(1, M // 2 + 1):
                    if all(ok_of(link, digital(t, link.ns, lr, dict(D_, D=D), eps, ph, cache[i])[0])[0]
                           for i, ph in enumerate(phis)):
                        goodD.append(D)
                wt = f'T {min(goodT)}..{max(goodT)} ({min(goodT) / M:.2f}-{max(goodT) / M:.2f} cell)' if goodT else 'T none'
                wd = f'D {min(goodD)}..{max(goodD)}' if goodD else 'D none'
                print(f'  M={M:2d} {lr // 1000:5d}k sd {sd:4.2f} {lab:15s} {wt:34s} {wd}', flush=True)
                del cache; gc.collect()
            del t; gc.collect()
        del link; gc.collect()


# ================================================================ section d
def gaps_frac(s, C):
    """Fraction of ticks at which a counter cleared by every edge of s has reached C."""
    e = np.flatnonzero(np.diff(s.astype(np.int8)) != 0)
    if len(e) < 2:
        return 1.0
    g = np.diff(np.concatenate([[0], e, [len(s) - 1]]))
    return float(np.clip(g - C, 0, None).sum() / len(s))


def do_d():
    hdr('(d) CARRIER DETECT AS A COUNTER: fraction of time "no carrier" (counter of ticks since the')
    print('    last edge of the filtered, decimated stream has reached C), design receiver')
    M = DESIGN['M']; CS = (M, 2 * M, 4 * M)
    print(f'  C in cells: ' + ', '.join(f'{c / M:.0f} ({c} ticks)' for c in CS))
    for lr in (64000, 256000, 1024000):
        link = Link(lr, secs={64000: 0.3, 256000: 0.2, 1024000: 0.1}[lr])
        print(f'\n  {lr // 1000} kbps line         ' + ' '.join(f'C={c / M:.0f} cell' for c in CS))
        cases = [('signal, clean', 0.0, True), (f'signal, sd {DESIGN_SD[lr]:.2f}', DESIGN_SD[lr], True),
                 (f'signal, sd {2 * DESIGN_SD[lr]:.2f} (x2)', 2 * DESIGN_SD[lr], True)]
        cases += [(f'noise only, sd {s:.2f}', s, False) for s in (0.05, 0.2, 1.0, 2.0)]
        for lab, sd, on in cases:
            t = link.front(sd, [F_AA], seed=1, signal_on=on)[0]
            _, s = digital(t, link.ns, lr, DESIGN)
            print(f'    {lab:26s} ' + ' '.join(f'{gaps_frac(s, c):9.4f}' for c in CS), flush=True)
            del t, s; gc.collect()
        del link; gc.collect()


# ================================================================ section e
def chan_errors(rb, n, C, hi=800, probe=3000):
    st = ss.framer_single(rb, n)
    pos = st['pos']
    out = dict(first_lock=(int(pos[0]) if len(pos) else None), lof=st['lof_events'], frames=len(pos))
    if len(pos) < 200:
        out['errs'] = None; return out
    te = tb = 0
    for j in range(n):
        c = rb[pos + 2 * j + 1]; ref = C[j]; pr = min(probe, len(c) // 2); best = None
        for o in range(hi):
            if o + pr > len(ref): break
            e = int(np.count_nonzero(c[:pr] != ref[o:o + pr]))
            if best is None or e < best[0]: best = (e, o)
            if e == 0: break
        o = best[1]; m = min(len(ref) - o, len(c))
        te += int(np.count_nonzero(c[:m] != ref[o:o + m])); tb += m
        a = rb[pos + 2 * j]
        te += int(np.count_nonzero(a != (j % 2))); tb += len(a)
    out['errs'] = te; out['bits'] = tb
    return out


def do_e():
    hdr('(e) END TO END: recovered bits -> s4_simple.framer_single -> A and C bits of every channel')
    print('  sd 0.4 absolute (all rates), and each rate\'s relative-equivalent design noise: the spec\'s')
    print('  sd 0.4 at 32 samples per line bit has the PSD of sd 0.4*sqrt(32.768M/(32*line)) here.')
    for lr in (64000, 256000, 1024000):
        link = Link(lr, secs={64000: 0.6, 256000: 0.4, 1024000: 0.25}[lr])
        flen = 2 + 2 * link.n
        for sd in sorted({0.4, DESIGN_SD[lr]}):
            t_ref, t_wb = link.front(sd, [2 * lr, F_AA], seed=2)
            for lab, rb in (('analog ref ', mono_times(t_ref, link.spb)),
                            ('digital M=8 ', digital(t_wb, link.ns, lr, DESIGN)[0]),
                            ('digital M=16', digital(t_wb, link.ns, lr, ALT16)[0])):
                r = chan_errors(rb, link.n, link.C)
                fl = f'{r["first_lock"] / flen:.0f} fr' if r['first_lock'] is not None else 'never'
                ber = (f'{r["errs"]} errors / {r["bits"]} A+C bits' if r['errs'] is not None else 'no lock')
                print(f'  N={link.n} {lr // 1000:5d}k sd {sd:4.2f} {lab} first lock {fl:>7s}, LOF {r["lof"]}, '
                      f'locked frames {r["frames"]}, {ber}', flush=True)
            del t_ref, t_wb; gc.collect()
        del link; gc.collect()

    hdr('(e2) NOISE-ONLY LINE: does the framer lock on the digital receiver\'s output? (skews)')
    for lr in (64000, 256000, 1024000):
        link = Link(lr, secs={64000: 0.3, 256000: 0.15, 1024000: 0.08}[lr])
        flen = 2 + 2 * link.n; sk = range(min(flen, 4))
        row = []
        for sd in (0.05, 0.2, 1.0):
            t = link.front(sd, [F_AA], seed=3, signal_on=False)[0]
            rb, _ = digital(t, link.ns, lr, DESIGN)
            nl = sum(1 for k in sk if ss.framer_single(rb, link.n, skew=k)['lock_bit'] is not None)
            row.append(f'sd {sd}: {nl}/{len(sk)} ({len(rb)} bits, {rb.mean() if len(rb) else 0:.2f} ones)')
            del t, rb; gc.collect()
        print(f'  N={link.n} {lr // 1000:5d}k  ' + ';  '.join(row), flush=True)
        del link; gc.collect()

    hdr('(e3) RATE MIS-CONFIGURATION: TX at 256 kbps (N=3), RX rate jumper set to each rate')
    link = Link(256000, secs=0.2)
    for sd in (0.0, 0.8):
        t = link.front(sd, [F_AA], seed=4)[0]
        for rx_lr in (1024000, 512000, 256000, 128000, 64000):
            v = dict(DESIGN)
            rb, s = digital(t, link.ns, rx_lr, v)       # RX clocking as if the line were rx_lr
            locks = sum(1 for k in range(4) if ss.framer_single(rb, 3, skew=k)['lock_bit'] is not None)
            nc = gaps_frac(s, 2 * v['M'])
            print(f'  sd {sd:.1f} RX set {rx_lr // 1000:5d}k: {len(rb):7d} bits out '
                  f'({len(rb) / len(link.line):.2f} x), ones {rb.mean() if len(rb) else 0:.2f}, '
                  f'framer locks {locks}/4 skews, no-carrier {nc:.3f}', flush=True)
        del t; gc.collect()


# ================================================================ section f
def do_f(secs=6.0):
    import audio, cvsd, run
    hdr('(f) WHAT THE LOCAL CLOCK COSTS THE CODEC: frame-clock jitter from tick-quantised strobes')
    print('  The RX frame clock is a frame-counter stage clocked by the bit strobe, and the strobe now')
    print('  lands on a local tick: each frame interval is T + u_i - u_(i-1), u in [0, tick).')
    print('  CVSD decode with that dt (cvsd.decode models an analog integrator: step ~ interval).')
    src, fs = audio.read_wav('speech30.wav', seconds=secs)
    bl = audio.bandlimit(src, fs)
    for n, rate, lr in ((1, 16000, 64000), (3, 32000, 256000), (7, 64000, 1024000)):
        p = run.params(rate)
        x = audio.resample_to(bl * (run.NOMINAL_RMS / np.std(bl)), fs, rate)
        bits = cvsd.encode(x, p); N = len(bits); T = 1.0 / rate
        rng = np.random.default_rng(7)
        def score(dt):
            y = audio.reconstruct(cvsd.decode(bits, p, dt=dt), rate)
            r, t, _ = audio.align(x, y)
            g = np.dot(r, t) / max(np.dot(t, t), 1e-20)
            return audio.seg_snr_db(r, t * g, rate)
        base = score(np.full(N, T))
        row = [f'perfect {base:5.2f} dB']
        for M in (8, 16):
            tick = 1.0 / (M * lr)
            tk = tick / (1 + EPS)
            det = np.ceil((np.arange(N + 1) * T - 0.37 * tk) / tk) * tk      # boundary -> next tick
            d1 = score(np.diff(det))
            u = rng.uniform(0, tick, N + 1)                                   # fully dithered by noise
            d2 = score(T + np.diff(u))
            row.append(f'M={M} tick/frame {tick / T * 100:4.2f}%: drift {d1 - base:+5.2f}, dithered {d2 - base:+5.2f} dB')
        print(f'  N={n} @ {rate // 1000}k ({lr // 1000}k line): ' + ';  '.join(row), flush=True)


# ------------------------------------------------------------------ design
# Chosen after `explore` and `b` (see the study notes returned with this file).
DESIGN = V('I8h iad F8 hold T6 D2', kind='iad', F0=F8, M=8, tie='hold', T=6, D=2)
ALT16 = V('J16h3 iad F16 hold M16 maj3 T12 D4', kind='iad', F0=2 * F8, M=16, tie='hold', W=3, T=12, D=4)
DESIGN_SD = {64000: 1.6, 256000: 0.8, 1024000: 0.4}     # relative sd 0.4, per rate, in absolute terms


if __name__ == '__main__':
    what = sys.argv[1:] or ['a']
    T0 = time.time()
    for w in what:
        {'a': do_a, 'explore': do_explore, 'b': do_b, 'b2': do_b2, 'b2run1': lambda: do_b2(variants=B2_RUN1), 'tune': do_tune, 'c': do_c, 'd': do_d, 'e': do_e,
         'f': do_f}[w]()
    print(f'\n[total {time.time() - T0:.0f} s]')
