"""
Feasibility: ANALOG, JUMPER-CONFIGURED clockless receiver.

The receiver of docs/line-receiver.md (RC-RC input filter, comparator with
hysteresis, interval classifier with dead time, spec §7 framer), with its
rate-dependent parts chosen by jumpers.  How many positions does each part
really need, and what does a half-changed configuration do?

All runs use the ABSOLUTE margin method of strap.py §31: every line rate
simulated at one common 32.768 MHz sample rate (so one noise sd is one noise
power spectral density), one fixed first-order 1.0 MHz cable, and the receiver
filter as specified by the variant under test.  Hysteresis 0.05 of the
normalised amplitude, as strap.py §31.  Classifier 0.75 cell and dead time
0.2 cell (the spec values) unless a section varies them.

Speed trick (exact, not an approximation): everything up to the comparator is
linear, so for one receiver filter the filtered signal and the filtered unit
noise are computed once, and each noise level is  slice(sig_f + sd * noise_f).
The noise path is the same seed scaled, so error-freeness is monotone in sd
to within sampling luck; section a checks that.

Usage:  python3 feas_analog_rx.py SECTION
    check      harness self-checks (framer_trace == framer_single, py_mono == mono_decode)
    a [seed]   error-free sd vs RC-RC corner at all five line rates (one noise seed)
    arep       report over all saved seeds: dB per corner, best groupings, fixed 2.048 MHz
    b          classifier and dead-time windows at 64 / 256 / 1024 kbps; retrigger lockout
    cd         carrier detect: dead fraction vs a timeout in microseconds, signal and noise only
    d          half-changed configurations (global alignment scoring)
    d2         the half-changed cases that lock, re-scored with local alignment; band-crossed cases
    dead       dead-time window edges (can it be one fixed value?)
    dead128    128 kbps error-free vs sd for five dead times (why one fixed dead time fails)
    e          proposed designs end to end (3- and 2-position filter, 2-position dead time)
    e2         fixed dead time 250 ns + fixed carrier detect 31.25 us (rejected: see 128 kbps)
"""
import sys, gc, time
import numpy as np
from scipy import signal
import audio, cvsd, run, fast, framing_review as fr, s4_simple as ss, rx_review as rr

FSC = 32.768e6            # common sample rate
FCC = 1.0e6               # the one cable, first-order 3 dB
HYS = 0.05
S4 = fr.SCHEMES['S4 T=1110 period 4']
RATES = (64000, 128000, 256000, 512000, 1024000)
MODE = {64000: (1, 16000), 128000: (3, 16000), 256000: (3, 32000),
        512000: (7, 32000), 1024000: (7, 64000)}
SECS = {64000: 1.5, 128000: 1.0, 256000: 0.6, 512000: 0.4, 1024000: 0.3}
CH = 1 << 22              # processing chunk, samples


def T0():
    return time.time()


# ------------------------------------------------------------------ line
def build(lr, secs=None):
    n, rate = MODE[lr]
    secs = secs or SECS[lr]
    src, fs = audio.read_wav('speech30.wav', seconds=secs + 0.2)
    bl = audio.bandlimit(src, fs)
    x = audio.resample_to(bl * run.NOMINAL_RMS / np.std(bl), fs, rate)
    b = cvsd.encode(x, run.params(rate))
    L = int(secs * rate)
    C = np.array([np.roll(b, 977 * j)[:L] for j in range(n)])
    A = np.array([np.full(L, j % 2, np.uint8) for j in range(n)])
    line = fr.gbuild(C, A, S4)
    return dict(lr=lr, n=n, rate=rate, flen=2 + 2 * n, line=line, C=C, A=A,
                spb=FSC / lr, sym=2 * lr, L=L)


def lfilt(b, a, src_chunks, total, dtype=np.float32):
    out = np.empty(total, dtype)
    zi = np.zeros(max(len(a), len(b)) - 1)
    k = 0
    for x in src_chunks:
        y, zi = signal.lfilter(b, a, np.asarray(x, np.float64), zi=zi)
        out[k:k + len(y)] = y
        k += len(y)
    assert k == total
    return out


def chunks(arr):
    for s in range(0, len(arr), CH):
        yield arr[s:s + CH]


def cable_wave(B):
    hc = int(round(B['spb'] / 2))
    dm = fast.dm_encode(B['line'])
    total = len(dm) * hc
    per = CH // hc
    def gen():
        for s in range(0, len(dm), per):
            yield np.repeat(dm[s:s + per].astype(np.float64) * 2 - 1, hc)
    b, a = signal.butter(1, 2 * FCC / FSC)
    y = lfilt(b, a, gen(), total)
    y /= np.abs(y).max()
    return y


def rcrc(x, fc):
    b, a = signal.butter(1, min(0.99, 2 * fc / FSC))
    y = lfilt(b, a, chunks(x), len(x))
    return lfilt(b, a, chunks(y), len(y))


def noise(total, seed=1):
    rng = np.random.default_rng(seed)
    out = np.empty(total, np.float32)
    for s in range(0, total, CH):
        m = min(CH, total - s)
        out[s:s + m] = rng.standard_normal(m, dtype=np.float32)
    return out


def slicer(sf, nf, sd, h=HYS):
    w = np.empty(len(sf), np.uint8)
    state = 0
    for s in range(0, len(sf), CH):
        m = min(CH, len(sf) - s)
        x = np.empty(m + 1)
        x[0] = 2 * h if state else -2 * h
        x[1:] = sf[s:s + m]
        if nf is not None and sd:
            x[1:] += sd * nf[s:s + m]
        o = fast.slice_hyst(x, h)
        w[s:s + m] = o[1:]
        state = int(o[-1])
    return w


class Front:
    """Filtered signal and filtered unit noise for one receiver filter corner."""
    def __init__(self, B, cab, fc, seed=1):
        self.B, self.fc = B, fc
        self.sf = rcrc(cab, fc)
        nz = noise(len(cab), seed)
        self.nf = rcrc(nz, fc)
        del nz
        gc.collect()

    def w(self, sd):
        return slicer(self.sf, self.nf, sd)


# ------------------------------------------------------------------ scoring
def align(rb, line, probe=3000, lo=-16, hi=48):
    best, bo = 2.0, None
    for o in range(lo, hi):
        a0 = max(64, -o + 64)
        if a0 + probe > len(rb) or a0 + o + probe > len(line):
            continue
        e = float((rb[a0:a0 + probe] != line[a0 + o:a0 + o + probe]).mean())
        if e < best:
            best, bo = e, o
            if e == 0:
                break
    return bo


def score(rb, B, framer=True):
    """Line-bit errors (all bits, framing included) and the spec §7 framer."""
    line, flen, n = B['line'], B['flen'], B['n']
    o = align(rb, line)
    r = dict(bits=0, errs=None, lock=False, false_lock=False, lof=0, pay_err=None,
             nb=len(rb), expect=len(line))
    if o is not None:
        a0 = max(64, -o + 64)
        m = min(len(rb) - a0, len(line) - a0 - o) - 64
        if m > 0:
            r['bits'] = m
            r['errs'] = int((rb[a0:a0 + m] != line[a0 + o:a0 + o + m]).sum())
    if framer:
        st = ss.framer_single(rb, n)
        r['lof'] = st['lof_events']
        pos = st['pos']
        if st['lock_bit'] is not None:
            r['lock'] = True
            r['lock_frames'] = st['lock_bit'] / flen
            if o is None or ((st['lock_bit'] + o) % flen) != 0:
                r['false_lock'] = True
            if o is not None and len(pos):
                ok = (pos + o >= 0) & (pos + o + flen <= len(line)) & (pos + flen <= len(rb))
                p = pos[ok]
                got = rb[p[:, None] + np.arange(2 * n)[None, :]]
                ref = line[(p + o)[:, None] + np.arange(2 * n)[None, :]]
                r['pay_err'] = int((got != ref).sum())
                r['pay_bits'] = int(got.size)
    return r


def good(r):
    return (r['errs'] == 0 and r['bits'] > 0.95 * (r['expect'] - 200) and r['lock']
            and not r['false_lock'] and r['lof'] == 0 and r['pay_err'] == 0)


def decode(w, B, thr=0.75, dead=0.2, spb=None):
    return fast.mono_decode(w, spb or B['spb'], thr=thr, dead=dead)


def threshold(ev, g, step=1.41, res_db=0.25):
    lo = hi = None
    s = g
    cache = {}
    def E(x):
        if x not in cache:
            cache[x] = ev(x)
        return cache[x]
    if E(s):
        lo = s
        while hi is None:
            s *= step
            if s > 20: return s, None, cache
            if E(s): lo = s
            else: hi = s
    else:
        hi = s
        while lo is None:
            s /= step
            if s < 1e-3: return 0.0, hi, cache
            if E(s): lo = s
            else: hi = s
    while 20 * np.log10(hi / lo) > res_db:
        m = np.sqrt(lo * hi)
        if E(m): lo = m
        else: hi = m
    return lo, hi, cache


# ------------------------------------------------------------------ cal
def do_cal():
    for lr in (256000, 1024000):
        t = T0()
        B = build(lr)
        cab = cable_wave(B)
        F = Front(B, cab, B['sym'])
        for sd in (0.0, 0.5, 1.0, 1.5, 2.0):
            r = score(decode(F.w(sd), B), B)
            print(f'  {lr//1000}k sd {sd}: {r}', flush=True)
        print(f'  {time.time()-t:.1f}s')
        del F, cab
        gc.collect()


# ------------------------------------------------------------------ a
GRID = [128000 * 2 ** (m / 2) for m in range(-2, 11)]      # 90.5 kHz ... 4.096 MHz, sqrt2 steps


SCR = '/tmp/claude-1000/-home-joel-telco/ae7de41b-ce55-4205-b770-dad64b2d68bb/scratchpad/feas_analog'


def do_a(seed=1):
    print('=' * 88)
    print('(a) ERROR-FREE NOISE sd vs RC-RC CORNER, absolute method (32.768 MHz, 1 MHz cable)')
    print('    corner grid in sqrt(2) steps; entry = largest error-free sd found, bisection to 0.25 dB')
    print('    error-free = zero line-bit errors over the clip AND framer locked, true alignment, 0 LOF,')
    print(f'    zero payload errors.  thr 0.75, dead 0.2 cell, hysteresis 0.05.  noise seed {seed}')
    print('=' * 88, flush=True)
    res = {}
    guess = {64000: 3.0, 128000: 2.0, 256000: 1.5, 512000: 1.0, 1024000: 0.5}
    for lr in RATES:
        t = T0()
        B = build(lr)
        cab = cable_wave(B)
        print(f'\n  {lr//1000} kbps line, N={B["n"]} @ {B["rate"]//1000}k, symbol {B["sym"]/1e3:.0f} kbaud, '
              f'{SECS[lr]} s clip, {len(B["line"])} line bits', flush=True)
        g = guess[lr]
        for fc in GRID:
            ratio = fc / B['sym']
            if ratio < 0.35 or ratio > 16.1:
                continue
            F = Front(B, cab, fc, seed)
            ev = lambda sd: good(score(decode(F.w(sd), B), B))
            if not ev(1e-3):
                res[(lr, fc)] = 0.0
                print(f'    corner {fc/1e3:7.1f} kHz ({ratio:5.2f}x sym): NOT error-free even with no noise', flush=True)
                del F; gc.collect(); continue
            lo, hi, cache = threshold(ev, g)
            # monotonicity spot check 1 and 2 dB below
            mono = all(ev(lo * 10 ** (-d / 20)) for d in (1.0, 2.0))
            res[(lr, fc)] = lo
            if ratio > 0.9 and ratio < 1.1:
                g = lo
            print(f'    corner {fc/1e3:7.1f} kHz ({ratio:5.2f}x sym): error-free to sd {lo:.3f} '
                  f'(fails {hi:.3f}), evals {len(cache)+2}, monotone-check {"ok" if mono else "FAIL"}', flush=True)
            del F; gc.collect()
        del cab, B; gc.collect()
        print(f'    [{time.time()-t:.0f} s]', flush=True)
    np.save(f'{SCR}/feas_a_s{seed}.npy',
            np.array([[lr, fc, v] for (lr, fc), v in res.items()]))
    report_a(res)
    return res


def do_arep():
    import glob
    files = sorted(glob.glob(f'{SCR}/feas_a_s*.npy'))
    per = []
    for f in files:
        d = np.load(f); per.append({(int(r[0]), float(r[1])): float(r[2]) for r in d})
    keys = set.intersection(*[set(p) for p in per])
    print(f'  seeds: {[f.split("_s")[-1][:-4] for f in files]}')
    for i, p in enumerate(per):
        own = {lr: p[min((k for k in p if k[0] == lr), key=lambda k: abs(np.log2(k[1] / (2 * lr))))] for lr in RATES}
        print(f'  seed file {i}: own-corner limits ' + ', '.join(f'{lr//1000}k sd {own[lr]:.3f}' for lr in RATES))
    # spread between seeds, in dB, per cell
    spread = [20 * np.log10(max(p[k] for p in per) / min(p[k] for p in per)) for k in keys if min(p[k] for p in per) > 0]
    print(f'  seed-to-seed spread per cell: median {np.median(spread):.2f} dB, max {max(spread):.2f} dB over {len(spread)} cells')
    mean = {k: float(10 ** np.mean([np.log10(p[k]) for p in per])) for k in keys}
    print('  REPORT ON THE GEOMETRIC MEAN OVER SEEDS')
    report_a(mean)


def report_a(res):
    def get(lr, fc):
        k = min((abs(np.log2(f / fc)), f) for (l, f) in res if l == lr)
        if k[0] > 0.01:
            return None
        return res[(lr, k[1])]
    own = {lr: get(lr, 2 * lr) for lr in RATES}
    print('\n  dB relative to each rate\'s own-symbol-rate corner (positive = better):')
    print('    corner kHz ' + ' '.join(f'{lr//1000:>7d}k' for lr in RATES))
    for fc in GRID:
        row = []
        for lr in RATES:
            v = get(lr, fc) if any(l == lr and abs(f - fc) < 1 for (l, f) in res) else None
            row.append('       -' if v is None else ('    dead' if v == 0 else f'{20*np.log10(v/own[lr]):+8.1f}'))
        print(f'    {fc/1e3:9.1f}  ' + ' '.join(row))
    print('\n  absolute, dB relative to 256 kbps own corner:  ' +
          ',  '.join(f'{lr//1000}k {20*np.log10(own[lr]/own[256000]):+.1f}' for lr in RATES))

    def loss(lr, fc):
        v = get(lr, fc) if any(l == lr and abs(f - fc) < 1 for (l, f) in res) else None
        if v is None: return None
        if v == 0: return 99.0
        return 20 * np.log10(own[lr] / v)

    # best contiguous partitions
    import itertools
    idx = list(range(5))
    print('\n  best contiguous groupings (corner chosen on the sqrt2 grid to minimise the worst loss in each group)')
    for k in (1, 2, 3, 5):
        best = None
        for cuts in itertools.combinations(range(1, 5), k - 1):
            bounds = [0, *cuts, 5]
            groups = [idx[bounds[i]:bounds[i + 1]] for i in range(k)]
            plan = []; worst = 0; tot = 0
            for gp in groups:
                cand = []
                for fc in GRID:
                    ls = [loss(RATES[i], fc) for i in gp]
                    if any(l is None for l in ls): continue
                    cand.append((max(ls), sum(ls), fc, ls))
                if not cand: plan = None; break
                c = min(cand)
                plan.append((gp, c[2], c[3])); worst = max(worst, c[0]); tot += c[1]
            if plan is None: continue
            if best is None or (worst, tot) < (best[0], best[1]):
                best = (worst, tot, plan)
        print(f'    {k} position(s): worst loss {best[0]:.1f} dB')
        for gp, fc, ls in best[2]:
            print(f'       corner {fc/1e3:7.1f} kHz for ' + ', '.join(
                f'{RATES[i]//1000}k ({fc/(2*RATES[i]):.2f}x, -{l:.1f} dB)' for i, l in zip(gp, ls)))
    print('    fixed at the 1024 kbps symbol rate (2.048 MHz): ' + ', '.join(
        f'{lr//1000}k -{loss(lr, 2048000):.1f} dB' for lr in RATES))



# ------------------------------------------------------------------ shared for b, cd, d
def own_threshold(B, cab, fc=None, seed=1):
    F = Front(B, cab, fc or B['sym'], seed)
    ev = lambda sd: good(score(decode(F.w(sd), B), B))
    lo, hi, _ = threshold(ev, 1.0)
    return F, lo


def py_mono(w, spb, thr=0.75, dead=0.2, lockout=0.0):
    """Reference classifier, identical to fast.mono_decode when lockout=0 (checked).
    lockout > 0 models a retriggerable timer's minimum retrigger time: an accepted
    edge closer than `lockout` cells to the previous one does not restart the timer."""
    e = np.flatnonzero(np.diff(w.view(np.int8)) != 0) + 1
    thr_s, dead_s, lo = thr * spb, dead * spb, lockout * spb
    last = trig = 0; at_mid = 0; out = []
    for i in e.tolist():
        gap = i - last
        if gap < dead_s:
            continue
        long_ = (i - trig) > thr_s
        if gap >= lo:
            trig = i
        last = i
        if long_:
            out.append(1); at_mid = 0
        elif at_mid:
            out.append(0); at_mid = 0
        else:
            at_mid = 1
    return np.array(out, np.uint8)


def window(F, B, sd, grid, dead=0.2, lockout=0.0):
    ok = []
    for t in grid:
        rb = decode(F.w(sd), B, thr=t, dead=dead) if not lockout else py_mono(F.w(sd), B['spb'], t, dead, lockout)
        ok.append(good(score(rb, B)))
    # contiguous run containing the nominal (or the longest run)
    runs, cur = [], []
    for t, g in zip(grid, ok):
        if g: cur.append(t)
        elif cur: runs.append(cur); cur = []
    if cur: runs.append(cur)
    if not runs:
        return None, ok
    r = max(runs, key=len)
    return (r[0], r[-1]), ok


# ------------------------------------------------------------------ b
def do_b(extra_mult=()):
    print('=' * 88)
    print('(b) CLASSIFIER AND DEAD-TIME WINDOWS AT THE EXTREME LINE RATES')
    print('    absolute method; design point = 3.5 dB below each rate\'s own error-free sd')
    print('    (the spec\'s sd 0.4 against the relative limit sd 0.6).  Window = contiguous')
    print('    error-free threshold range; step 0.025 cell.')
    print('=' * 88, flush=True)
    TG = [round(0.45 + 0.025 * k, 3) for k in range(25)]      # 0.45 .. 1.05
    DG = [0.025, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45]
    for lr in (64000, 256000, 1024000):
        B = build(lr); cab = cable_wave(B)
        F, lim = own_threshold(B, cab)
        print(f'\n  {lr//1000} kbps, own corner, error-free to sd {lim:.3f}', flush=True)
        for label, sd in (('clean', 0.0), ('design sd (-3.5 dB)', lim * 0.4 / 0.6), ('-1.9 dB (spec sd 0.5 equiv.)', lim * 0.5 / 0.6)):
            win, ok = window(F, B, sd, TG)
            s = ''.join('o' if g else '.' for g in ok)
            if win:
                lo, hi = win; c = (lo + hi) / 2
                print(f'    classifier {label:30s} sd {sd:.3f}: {lo:.3f}-{hi:.3f}  about 0.75: '
                      f'-{(0.75-lo)/0.75:.0%}/+{(hi-0.75)/0.75:.0%}  (min +-{min(0.75-lo, hi-0.75)/0.75:.0%}); '
                      f'centre {c:.3f} +-{(hi-lo)/2/c:.0%}   [{s}]', flush=True)
            else:
                print(f'    classifier {label:30s} sd {sd:.3f}: NONE [{s}]', flush=True)
        sd = lim * 0.4 / 0.6
        dok = [good(score(decode(F.w(sd), B, dead=d), B)) for d in DG]
        print('    dead time at design sd:  ' + ' '.join(f'{d:.3f}:{"ok" if g else "--"}' for d, g in zip(DG, dok)), flush=True)
        # retrigger lockout of a 74HC123 at 1024k (datasheet formula, R=2k and 5k)
        if lr == 1024000:
            for lock in (0.22, 0.28):
                win, ok = window(F, B, sd, TG[4:17], lockout=lock)
                print(f'    classifier with retrigger lockout {lock:.2f} cell (dead 0.2), design sd: '
                      f'{win}  [{"".join("o" if g else "." for g in ok)}]', flush=True)
            win, ok = window(F, B, sd, TG[4:17], dead=0.3, lockout=0.28)
            print(f'    same, lockout 0.28 with dead time raised to 0.30: {win}  [{"".join("o" if g else "." for g in ok)}]', flush=True)
        for m in extra_mult:
            F2 = Front(B, cab, m * B['sym'])
            for label, sd in (('design sd (-3.5 dB)', lim * 0.4 / 0.6),):
                win, ok = window(F2, B, sd, TG)
                s = ''.join('o' if g else '.' for g in ok)
                print(f'    corner {m:.2f}x sym, classifier {label}: {win}  [{s}]', flush=True)
            del F2; gc.collect()
        # relative convention, as spec §6.2 measured it (OS 32, cable 1.7578 x sym, sd 0.4)
        for kind in ('butter2', 'rcrc'):
            w = rr.wave(B['line'], lr, 0.4, rx_kind=kind)
            okr = [good(score(fast.mono_decode(w, 32, thr=t, dead=0.2), B)) for t in TG]
            runs = [t for t, g in zip(TG, okr) if g]
            print(f'    relative convention sd 0.4, {kind:7s}: {min(runs) if runs else None}-{max(runs) if runs else None} '
                  f'[{"".join("o" if g else "." for g in okr)}]', flush=True)
            del w; gc.collect()
        del F, cab, B; gc.collect()


# ------------------------------------------------------------------ cd
def gaps_cells(w, spb):
    e = np.flatnonzero(np.diff(w.view(np.int8)) != 0)
    if len(e) < 2:
        return np.array([len(w) / spb])
    return np.diff(np.concatenate([[0], e, [len(w) - 1]])) / spb


def do_cd():
    print('=' * 88)
    print('(cd) CARRIER DETECT: can the timeout be fixed, or grouped?')
    print('    fraction of time with no comparator transition for longer than T; T in')
    print('    MICROSECONDS so one timer value can be read across rates.  Filter at own corner.')
    print('=' * 88, flush=True)
    TU = (0.98, 1.95, 3.9, 7.8, 15.6, 31.25, 62.5)                 # 2 cells at 1024k ... 2 cells at 64k, x2
    print('    T (us)                        ' + ' '.join(f'{t:>7.2f}' for t in TU))
    for lr in RATES:
        secs = min(SECS[lr], 0.3)
        B = build(lr, secs); cab = cable_wave(B)
        F, lim = own_threshold(B, cab)
        for label, sd in (('signal clean', 0.0), ('signal at limit', lim), ('signal 2x limit', 2 * lim)):
            g = gaps_cells(F.w(sd), FSC * 1e-6)          # gaps in microseconds
            tot = g.sum()
            print(f'    {lr//1000:5d}k {label:22s} ' + ' '.join(f'{np.clip(g - t, 0, None).sum()/tot:7.3f}' for t in TU)
                  + f'   (max gap {g[5:-5].max() if len(g) > 10 else g.max():.2f} us)', flush=True)
        nf = F.nf
        for sd in (0.01, 0.03, 0.1, 0.3, 1.0):
            w = slicer(np.zeros_like(nf), nf, sd)
            g = gaps_cells(w, FSC * 1e-6); tot = g.sum()
            print(f'    {lr//1000:5d}k noise only sd {sd:<5.2f}      ' + ' '.join(f'{np.clip(g - t, 0, None).sum()/tot:7.3f}' for t in TU), flush=True)
        del F, cab, B; gc.collect()


# ------------------------------------------------------------------ d
def framer_trace(line, n, skew=0, confirm=32, up=1, dn=1, trip=16):
    """s4_simple.framer_single, recording EVERY lock (bit index) instead of the last."""
    flen = 2 + 2 * n
    if skew:
        line = np.roll(line, -skew)
    i = cc = err = 0; locked = False; hist = []; locks = []; lof = 0; pos = []
    N = line.size
    while i + flen <= N:
        s, t = int(line[i + flen - 2]), int(line[i + flen - 1])
        good_ = (s == 0) and (len(hist) < 3 or (hist[-3:] + [t]).count(0) == 1)
        hist = (hist + [t])[-3:]
        if not locked:
            if good_:
                cc += 1
                if cc >= confirm:
                    locked = True; locks.append(i)
                i += flen
            else:
                cc = 0; hist = []; i += 1
            continue
        err = max(0, err - dn) if good_ else err + up
        if err >= trip:
            locked = False; cc = err = 0; hist = []; lof += 1; i += 1
            continue
        pos.append(i); i += flen
    return dict(locks=locks, lof=lof, pos=np.array(pos, np.int64), locked_end=locked)


def judge(rb, B):
    """lock events, how many at a true alignment, locked fraction, payload errors while locked."""
    n, flen, line = B['n'], B['flen'], B['line']
    st = framer_trace(rb, n)
    o = align(rb, line)
    r = dict(nlocks=len(st['locks']), lof=st['lof'], nb=len(rb), expect=len(line))
    r['first'] = (st['locks'][0] / flen) if st['locks'] else None
    if o is None:
        r['true'] = 0; r['false'] = len(st['locks']); r['line_ber'] = None
    else:
        r['true'] = sum(1 for L in st['locks'] if (L + o) % flen == 0)
        r['false'] = len(st['locks']) - r['true']
        a0 = max(64, -o + 64); m = min(len(rb) - a0, len(line) - a0 - o) - 64
        r['line_ber'] = float((rb[a0:a0 + m] != line[a0 + o:a0 + o + m]).mean()) if m > 1000 else None
    pos = st['pos']
    r['locked_frac'] = len(pos) * flen / max(len(rb), 1)
    if len(pos) and o is not None:
        ok = (pos + o >= 0) & (pos + o + flen <= len(line)) & (pos + flen <= len(rb))
        p = pos[ok]
        got = rb[p[:, None] + np.arange(2 * n)[None, :]]
        ref = line[(p + o)[:, None] + np.arange(2 * n)[None, :]]
        r['pay_ber'] = float((got != ref).mean()) if got.size else None
    else:
        r['pay_ber'] = None
    return r


def fmt_j(r):
    lb = '   -   ' if r['line_ber'] is None else ('   0   ' if r['line_ber'] == 0 else f'{r["line_ber"]:7.1e}')
    pb = '   -   ' if r['pay_ber'] is None else ('   0   ' if r['pay_ber'] == 0 else f'{r["pay_ber"]:7.1e}')
    fl = '  -  ' if r['first'] is None else f'{r["first"]:5.0f}'
    return (f'{r["nlocks"]:>3d} {r["true"]:>3d} {r["false"]:>3d} {r["lof"]:>4d} {fl} {100*r["locked_frac"]:5.1f}% '
            f'{lb} {pb} {r["nb"]/r["expect"]:5.2f}')


def do_d(rates=(64000, 128000, 256000, 1024000)):
    print('=' * 88)
    print('(d) HALF-CHANGED CONFIGURATION: RX parts set for different rate positions')
    print('    offsets in positions (x2 per step); + = RX part set for a FASTER rate than the TX.')
    print('    F filter corner, C classifier (0.75 cell), D dead time (0.2 cell), all relative to the TX rate.')
    print('    columns: locks = lock events, true/false = at the true / a wrong alignment, LOF,')
    print('    first = frames to first lock, locked = fraction of the clip in lock, line BER, payload BER')
    print('    while locked, bits out / line bits.  design sd = 3.5 dB below the correct receiver\'s limit.')
    print('=' * 88, flush=True)
    for lr in rates:
        p = RATES.index(lr)
        B = build(lr); cab = cable_wave(B)
        Fown, lim = own_threshold(B, cab)
        fronts = {0: Fown}
        def front(k):
            if k not in fronts:
                fronts[k] = Front(B, cab, B['sym'] * 2.0 ** k)
            return fronts[k]
        reach = [k for k in range(-4, 5) if 0 <= p + k < 5]
        cases = [(0, 0, 0)]
        cases += [(k, 0, 0) for k in reach if k]
        cases += [(0, k, 0) for k in reach if k and abs(k) <= 2]
        cases += [(0, 0, k) for k in reach if k and abs(k) <= 2]
        cases += [(0, k, k) for k in reach if k and abs(k) <= 2]
        cases += [(k, k, k) for k in reach if k and abs(k) <= 2]
        cases += [(k, 0, 0) for k in ()]
        print(f'\n  TX {lr//1000} kbps (N={B["n"]}), correct receiver error-free to sd {lim:.3f}; '
              f'design sd {lim*0.4/0.6:.3f}', flush=True)
        print(f'    {"F  C  D":>9s}  {"sd":>6s}  {"lk":>3s} {"tru":>3s} {"fal":>3s} {"LOF":>4s} {"first":>5s} {"locked":>6s} '
              f'{"lineBER":>7s} {"payBER":>7s} {"out":>5s}')
        for f, c, d in cases:
            for sd in (0.0, lim * 0.4 / 0.6):
                F = front(f)
                rb = decode(F.w(sd), B, thr=0.75 * 2.0 ** -c, dead=0.2 * 2.0 ** -d)
                r = judge(rb, B)
                print(f'    {f:+d} {c:+d} {d:+d}  {sd:6.3f}  ' + fmt_j(r), flush=True)
        # carrier detect set for another position, on signal at the design sd
        w = Fown.w(lim * 0.4 / 0.6); g = gaps_cells(w, B['spb'])[5:-5]; tot = g.sum()
        print('    carrier detect (2 cells nominal) set k positions off, signal at design sd: '
              'trips per second / fraction of time tripped')
        print('      ' + '  '.join(f'k={k:+d} T={2*2.0**-k:.2f} cells: {int((g > 2*2.0**-k).sum())/SECS[lr]:.0f}/s {np.clip(g-2*2.0**-k,0,None).sum()/tot:.3f}'
                                 for k in reach if abs(k) <= 2))
        # noise-only line: does any RX configuration lock?
        print('    noise-only line: lock events summed over 8 start skews, per RX configuration')
        nz_cfg = [(0, 0, 0)] + [(0, k, k) for k in reach if k and abs(k) <= 1] + [(k, 0, 0) for k in reach if k and abs(k) <= 2]
        for f, c, d in nz_cfg:
            nf = front(f).nf
            row = []
            for sd in (0.01, 0.1, 1.0):
                n_ = min(len(nf), int(FSC * min(0.3, 100000 / lr)))
                w = slicer(np.zeros(n_, np.float32), nf[:n_], sd)
                rb = decode(w, B, thr=0.75 * 2.0 ** -c, dead=0.2 * 2.0 ** -d)
                locks = sum(len(framer_trace(rb, B['n'], skew=k)['locks']) for k in range(0, B['flen'], max(1, B['flen'] // 8)))
                row.append(f'sd {sd}: {locks} locks ({len(rb)} bits)')
            print(f'      {f:+d} {c:+d} {d:+d}  ' + ';  '.join(row), flush=True)
        del fronts, Fown, cab, B; gc.collect()


def check():
    """Harness self-checks: framer_trace == s4_simple.framer_single; py_mono == fast.mono_decode."""
    B = build(256000, 0.3); cab = cable_wave(B); F = Front(B, cab, B['sym'])
    for sd in (0.0, 1.2, 2.0):
        w = F.w(sd); rb = decode(w, B)
        a = ss.framer_single(rb, B['n']); b = framer_trace(rb, B['n'])
        same = (a['lof_events'] == b['lof'] and np.array_equal(a['pos'], b['pos'])
                and (a['lock_bit'] == (b['locks'][-1] if b['locks'] else None)))
        pm = py_mono(w, B['spb'], 0.75, 0.2)
        print(f'  sd {sd}: framer_trace matches framer_single: {same} ({len(b["locks"])} locks); '
              f'py_mono matches mono_decode: {np.array_equal(pm, rb)} ({len(rb)} bits)', flush=True)


# ------------------------------------------------------------------ e: the proposed jumper design, end to end
# band A = 64/128/256 kbps, band B = 512/1024 kbps
DESIGNS = {
    '3-filter': dict(fc={64000: 128e3, 128000: 362.04e3, 256000: 362.04e3, 512000: 1448.15e3, 1024000: 1448.15e3}),
    '2-filter': dict(fc={64000: 256e3, 128000: 256e3, 256000: 256e3, 512000: 1448.15e3, 1024000: 1448.15e3}),
}
DEAD_NS = {64000: 977.0, 128000: 977.0, 256000: 977.0, 512000: 195.0, 1024000: 195.0}   # 2-position dead time
CD_US = {64000: 31.25, 128000: 31.25, 256000: 31.25, 512000: 3.906, 1024000: 3.906}      # 2-position carrier detect


def do_e(seeds=(1, 2)):
    print('=' * 88)
    print('(e) PROPOSED JUMPER DESIGN, END TO END: classifier per rate (5 positions); filter 3 or 2')
    print('    positions; dead time 2 positions (977 ns band A, 195 ns band B); carrier detect 2 positions')
    print('    (31.25 us band A, 3.9 us band B).  Error-free sd by bisection, per noise seed.')
    print('=' * 88, flush=True)
    for lr in RATES:
        B = build(lr); cab = cable_wave(B)
        cell_ns = 1e9 / lr
        dead = DEAD_NS[lr] / cell_ns
        print(f'\n  {lr//1000} kbps: dead time {DEAD_NS[lr]:.0f} ns = {dead:.3f} cell; carrier detect {CD_US[lr]} us = '
              f'{CD_US[lr]*1e3/cell_ns:.1f} cells', flush=True)
        for name, D in DESIGNS.items():
            fc = D['fc'][lr]
            lims = []
            for seed in seeds:
                F = Front(B, cab, fc, seed)
                ev = lambda sd: good(score(decode(F.w(sd), B, dead=dead), B))
                lo, hi, _ = threshold(ev, 1.0)
                lims.append(lo)
                if seed == seeds[0]:
                    sd = lo * 0.4 / 0.6
                    TG = [round(0.45 + 0.025 * k, 3) for k in range(25)]
                    win, ok = window(F, B, sd, TG, dead=dead)
                    g = gaps_cells(F.w(lo), FSC * 1e-6)[5:-5]
                    trips = int((g > CD_US[lr]).sum())
                    wtxt = (f'{win[0]:.3f}-{win[1]:.3f} (-{(0.75-win[0])/0.75:.0%}/+{(win[1]-0.75)/0.75:.0%})' if win else 'NONE')
                del F; gc.collect()
            print(f'    {name}: corner {fc/1e3:7.1f} kHz ({fc/B["sym"]:.2f}x sym): error-free sd per seed '
                  + ', '.join(f'{v:.3f}' for v in lims)
                  + f';  classifier window at design sd {wtxt};  carrier-detect trips on signal at the limit: {trips}', flush=True)
        del cab, B; gc.collect()


def do_dead():
    """Could the dead time be ONE fixed value?  Lower end of the dead-time window at the slow
    rates, at two comparator hysteresis ratios; upper end at the fast rate.  Design sd."""
    print('=' * 88)
    print('(dead) DEAD-TIME WINDOW EDGES, design sd (3.5 dB below own limit), own corner, thr 0.75')
    print('=' * 88, flush=True)
    for lr, DG in ((64000, (0.002, 0.004, 0.008, 0.016, 0.025)), (128000, (0.004, 0.008, 0.016, 0.032)),
                   (1024000, (0.25, 0.275, 0.30, 0.325))):
        B = build(lr); cab = cable_wave(B)
        F, lim = own_threshold(B, cab)
        sd = lim * 0.4 / 0.6
        for h in (0.05, 0.02):
            w = slicer(F.sf, F.nf, sd, h)
            row = [good(score(decode(w, B, dead=d), B)) for d in DG]
            print(f'  {lr//1000:5d}k h {h:.2f} sd {sd:.3f}: ' + '  '.join(
                f'{d:.3f} cell ({d*1e9/lr:5.0f} ns) {"ok" if g else "--"}' for d, g in zip(DG, row)), flush=True)
            del w; gc.collect()
        del F, cab, B; gc.collect()


def judge_local(rb, B, span=300, probe=256):
    """Like judge(), but every lock event is aligned LOCALLY (bit slips move the true
    alignment), and delivered frames are scored against the alignment found at their lock."""
    n, flen, line = B['n'], B['flen'], B['line']
    st = framer_trace(rb, n)
    scale = len(line) / max(len(rb), 1)
    out = dict(nlocks=len(st['locks']), lof=st['lof'], true=0, false=0, garbage=0)
    offs = []
    for L in st['locks']:
        c = int(round(L * scale)) - L
        best, bo = 2.0, None
        for o in range(c - span, c + span + 1):
            if L + o < 0 or L + o + probe > len(line) or L + probe > len(rb):
                continue
            e = np.count_nonzero(rb[L:L + probe] != line[L + o:L + o + probe]) / probe
            if e < best:
                best, bo = e, o
        offs.append((L, bo, best))
        if bo is None or best > 0.1:
            out['garbage'] += 1
        elif (L + bo) % flen == 0:
            out['true'] += 1
        else:
            out['false'] += 1
    pos = st['pos']; errs = bits = 0; bad_frames = 0
    if len(pos):
        locks = np.array([L for L, _, _ in offs]); oo = [o for _, o, _ in offs]
        k = np.searchsorted(locks, pos, side='right') - 1
        for j in np.unique(k):
            o = oo[j]
            p = pos[k == j]
            if o is None:
                errs += p.size * n; bits += p.size * 2 * n; bad_frames += p.size; continue
            ok = (p + o >= 0) & (p + o + flen <= len(line)) & (p + flen <= len(rb))
            p = p[ok]
            got = rb[p[:, None] + np.arange(2 * n)[None, :]]
            ref = line[(p + o)[:, None] + np.arange(2 * n)[None, :]]
            d = (got != ref)
            errs += int(d.sum()); bits += d.size; bad_frames += int(d.any(axis=1).sum())
    out['locked_frac'] = len(pos) * flen / max(len(rb), 1)
    out['pay_ber'] = errs / bits if bits else None
    out['bad_frame_frac'] = bad_frames / len(pos) if len(pos) else None
    return out


def do_d2():
    print('=' * 88)
    print('(d2) HALF-CHANGED CASES THAT LOCK WITH ERRORS, re-scored with LOCAL alignment per lock event;')
    print('     plus the band-crossed cases of the proposed 2-band design.  design sd = own limit x 2/3.')
    print('     cols: lock events (true / false / on garbage), LOF, fraction of clip locked, payload BER')
    print('     delivered while locked, fraction of delivered frames with any error')
    print('=' * 88, flush=True)
    CASES = {
        64000: [('filter 4x (256 kHz), timers right', 256e3, 0.75, 0.2),
                ('filter 8x (1.024 MHz), timers right', 1024e3, 0.75, 0.2),
                ('band B filter 11.3x (1.448 MHz), timers right', 1448.15e3, 0.75, 0.2),
                ('band B dead time 195 ns = 0.0125 cell', None, 0.75, 0.0125)],
        128000: [('filter 8x (2.048 MHz), timers right', 2048e3, 0.75, 0.2),
                 ('band B filter 5.66x (1.448 MHz)', 1448.15e3, 0.75, 0.2),
                 ('dead time 0.4 cell (one step long)', None, 0.75, 0.4)],
        256000: [('band B filter 2.83x (1.448 MHz)', 1448.15e3, 0.75, 0.2),
                 ('dead time 0.4 cell (one step long)', None, 0.75, 0.4)],
        512000: [('band A filter 0.25x (256 kHz)', 256e3, 0.75, 0.2),
                 ('band A dead time 977 ns = 0.5 cell', None, 0.75, 0.5)],
        1024000: [('band A filter 0.125x (256 kHz)', 256e3, 0.75, 0.2),
                  ('dead time 0.4 cell (one step long)', None, 0.75, 0.4),
                  ('band A dead time 977 ns = 1.0 cell', None, 0.75, 1.0)],
    }
    for lr, cases in CASES.items():
        secs = SECS[lr] * (0.5 if lr <= 128000 else 1.0)
        B = build(lr, secs); cab = cable_wave(B)
        Fown, lim = own_threshold(B, cab)
        sdd = lim * 0.4 / 0.6
        print(f'\n  TX {lr//1000} kbps N={B["n"]}, {secs} s: correct receiver error-free to sd {lim:.3f}, design sd {sdd:.3f}', flush=True)
        r = judge_local(decode(Fown.w(sdd), B), B)
        print(f'    {"correct receiver":46s} sd {sdd:.3f}: {r["nlocks"]} ({r["true"]}/{r["false"]}/{r["garbage"]}) LOF {r["lof"]} '
              f'locked {100*r["locked_frac"]:.0f}% payBER {r["pay_ber"]} bad frames {r["bad_frame_frac"]}', flush=True)
        fr_ = {}
        for name, fc, thr, dead in cases:
            if fc is None:
                F = Fown
            else:
                if fc not in fr_:
                    fr_[fc] = Front(B, cab, fc)
                F = fr_[fc]
            for sd in (0.0, sdd, lim):
                r = judge_local(decode(F.w(sd), B, thr=thr, dead=dead), B)
                pb = '-' if r['pay_ber'] is None else ('0' if r['pay_ber'] == 0 else f'{r["pay_ber"]:.1e}')
                bf = '-' if r['bad_frame_frac'] is None else f'{r["bad_frame_frac"]:.3f}'
                print(f'    {name:46s} sd {sd:.3f}: {r["nlocks"]:3d} ({r["true"]}/{r["false"]}/{r["garbage"]}) LOF {r["lof"]:3d} '
                      f'locked {100*r["locked_frac"]:5.1f}% payBER {pb:>7s} bad frames {bf}', flush=True)
        del fr_, Fown, cab, B; gc.collect()


def do_e2():
    """Final recommended set: 3-position filter, classifier per rate, ONE fixed 250 ns dead
    time, ONE fixed 31.25 us carrier-detect timeout.  Seed 1 (compare feas_a_s1 own corners)."""
    print('=' * 88)
    print('(e2) RECOMMENDED SET: 3-position filter, 5-position classifier, fixed dead time 250 ns,')
    print('     fixed carrier detect 31.25 us.  Error-free sd, noise seed 1.')
    print('=' * 88, flush=True)
    own1 = {64000: 2.526, 128000: 1.649, 256000: 1.111, 512000: 0.860, 1024000: 0.440}   # section a, seed 1
    for lr in RATES:
        B = build(lr); cab = cable_wave(B)
        fc = DESIGNS['3-filter']['fc'][lr]; dead = 250.0 / (1e9 / lr)
        F = Front(B, cab, fc, 1)
        ev = lambda sd: good(score(decode(F.w(sd), B, dead=dead), B))
        lo, hi, _ = threshold(ev, own1[lr])
        g = gaps_cells(F.w(lo), FSC * 1e-6)[5:-5]
        line = (f'  {lr//1000:5d}k corner {fc/1e3:7.1f} kHz, dead {dead:.3f} cell, CD {31.25e3/(1e9/lr):.0f} cells: '
                f'error-free to sd {lo:.3f} ({20*np.log10(lo/own1[lr]):+.1f} dB vs 5-position, dead 0.2); '
                f'CD trips on signal at that sd: {int((g > 31.25).sum())}; longest gap {g.max():.2f} us')
        if lr == 1024000:
            TG = [round(0.60 + 0.025 * k, 3) for k in range(12)]
            win, ok = window(F, B, lo * 0.4 / 0.6, TG, dead=dead)
            line += f'; classifier window at design sd {win} [{"".join("o" if x else "." for x in ok)}]'
        print(line, flush=True)
        del F, cab, B; gc.collect()


def do_dead128():
    """128 kbps, 362 kHz corner (3-position design), seed 1: error-free vs sd for five dead times.
    Shows why a single fixed dead time was rejected.  (First run inline with identical code.)"""
    B = build(128000); cab = cable_wave(B); F = Front(B, cab, 362.04e3, 1)
    print('128k, corner 362 kHz, seed 1, 1.0 s: error-free (o) / not (.) vs sd, per dead time (cells)')
    SDS = (1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7)
    for dead in (0.016, 0.032, 0.0625, 0.125, 0.2):
        row = []
        for sd in SDS:
            r = score(decode(F.w(sd), B, dead=dead), B)
            row.append('o' if good(r) else ('.' if r['errs'] else 'L'))
        print(f'  dead {dead:.4f} ({dead*1e9/128000:5.0f} ns): ' + '  '.join(f'{s}:{c}' for s, c in zip(SDS, row)), flush=True)

if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    t = T0()
    if what == 'cal': do_cal()
    if what in ('a', 'all'): do_a(int(sys.argv[2]) if len(sys.argv) > 2 and what == 'a' else 1)
    if what == 'arep': do_arep()
    if what in ('b', 'all'): do_b(tuple(float(x) for x in sys.argv[2:]) if what == 'b' else ())
    if what in ('cd', 'all'): do_cd()
    if what in ('d', 'all'): do_d()
    if what == 'check': check()
    if what == 'dead': do_dead()
    if what == 'd2': do_d2()
    if what == 'e2': do_e2()
    if what == 'dead128': do_dead128()
    if what in ('e', 'all'): do_e()
    print(f'[total {time.time()-t:.0f} s]')
