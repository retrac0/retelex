"""
Feasibility track: repeater front-end filter, transmitter edge rate, transformer droop.

Nothing here modifies repeater.py; the cascade below is a copy of its regen
chain (span -> front_end -> re-drive), generalised so the repeater's filter,
the terminal's filter, the driver edge and the line transformers are
independent arguments.

  a    REPEATER FILTER, absolute margin (strap.py section 31 method):
       every line rate simulated at one 32.768 MHz grid, so a noise sd is the
       same PSD at every rate; one fixed cable (1.0 MHz first order); the
       repeater front end is the variable.  Two receiver arrangements are
       scored at every span count, from ONE chain:
         A  every receiver, repeaters AND terminal, uses filter X
            (1 span of A = a single terminal with filter X)
         B  repeaters use X, the terminal uses its rate plug (symbol rate)
            (1 span of B = the plugged terminal, independent of X)
  b1   TX EDGE RATE in the spec's sd convention (sd 0.4 at 32 samples per line
       bit, cable scaled with the symbol rate = a short, good cable, where the
       edge is the dominant band limit): BER and classifier window, all five
       line rates, edges ideal / 75 / 150 / 300 ns, 1 and 3 spans at sd 0.4,
       9 spans at sd 0.25.
  b2   TX EDGE RATE, absolute margin (1 MHz cable, fixed PSD): largest sd with
       BER <= 1e-4, 256 / 512 / 1024 kbps, 1 and 4 spans.
  c    TRANSFORMER DROOP at 64 kbps: two first-order high-passes per span
       (TX and RX transformer), corner R/(2 pi L); BER at sd 0.4, noise limit,
       classifier window, baseline wander, pulse-width distortion.
  c2   droop cross-check in the absolute frame (32.768 MHz, 1 MHz cable).

Edge model: the line-transmitter's "series R, shunt C" slew network, a
first-order RC.  "X ns edge" = 10-90% rise time = 2.197 tau.

Usage:  python3 feas_rptx.py pilot|a|b1|b2|c|c2
"""
import sys, time, gc
import numpy as np
from scipy import signal
import fast, framing_review as fr, s4_simple as ss
from repeater import track_ber            # block-tracked line BER, slip-proof

FSC = 32.768e6            # common grid, as strap.py section 31
CABLE = 1.0e6             # one physical cable, section 31
H = 0.05                  # comparator hysteresis, fraction of received peak
DEAD = 0.20               # spec dead time, cells
THR = 0.75                # classifier threshold, cells
THRS = (0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95)
MODE = {64000: (1, 16000), 128000: (1, 32000), 256000: (3, 32000),
        512000: (7, 32000), 1024000: (7, 64000)}
NBITS = 48000             # line bits per run; track_ber scores 40 000 of them
S4 = fr.SCHEMES['S4 T=1110 period 4']
GRID = [2 ** (k / 6) for k in range(-30, 16)]   # 1.003 dB steps, 0.031 .. 6.35

_CV = None
_COEF = {}


def cvsd_bits():
    global _CV
    if _CV is None:
        _CV = fr.load(4.0)          # (speech, silence) at 32 kHz, 128 000 bits each
    return _CV


def line_for(lr, nbits=NBITS, payload='speech'):
    """S4 line bit stream for the mode at line rate `lr`."""
    n, rate = MODE[lr]
    flen = 2 + 2 * n
    L = nbits // flen + 1
    cv, sil = cvsd_bits()
    if payload == 'speech':
        C = np.array([np.roll(cv, 977 * j)[:L] for j in range(n)])
        A = np.array([np.full(L, j % 2, np.uint8) for j in range(n)])
    elif payload == 'data1':               # data card idling 1, A strapped 1
        C = np.ones((n, L), np.uint8)
        A = np.ones((n, L), np.uint8)
    elif payload == 'data0':               # data card idling 0
        C = np.zeros((n, L), np.uint8)
        A = np.ones((n, L), np.uint8)
    else:
        raise ValueError(payload)
    return fr.gbuild(C, A, S4), n


def filt(x, fs, spec):
    """spec: None | ('lp2', fc) Butterworth | ('rcrc', fc) | ('lp1', fc) | ('hp1', fc)."""
    if spec is None:
        return x
    kind, fc = spec
    key = (kind, float(fc), float(fs))
    if key not in _COEF:
        wn = 2.0 * fc / fs
        assert wn < 0.99, f'{spec} not representable at fs={fs}'
        if kind == 'hp1':
            _COEF[key] = signal.butter(1, wn, btype='high')
        elif kind == 'lp2':
            _COEF[key] = signal.butter(2, wn)
        else:
            _COEF[key] = signal.butter(1, wn)
    b, a = _COEF[key]
    y = signal.lfilter(b, a, x)
    if kind == 'rcrc':
        y = signal.lfilter(b, a, y)
    return y


def fname(spec):
    if spec is None:
        return 'none'
    k, fc = spec
    return f'{k} {fc/1e6:g}M' if fc >= 1e6 else f'{k} {fc/1e3:g}k'


def score(w, spb, line, n, windows=False, framer=False):
    rb = fast.mono_decode(w, spb, thr=THR, dead=DEAD)
    r = dict(ber=track_ber(rb, line)[0] if len(rb) > 8000 else 1.0)
    if framer:
        st = ss.framer_single(rb, n)
        r['lock'] = st['lock_bit'] is not None
        r['lof'] = st['lof_events']
    if windows:
        win = {}
        for t in THRS:
            if t == THR:
                win[t] = r['ber']
                continue
            rbt = fast.mono_decode(w, spb, thr=t, dead=DEAD)
            win[t] = track_ber(rbt, line)[0] if len(rbt) > 8000 else 1.0
        r['win'] = win
    return r


def run_chain(line, n, lr, fs, sigma, n_spans, taps, rep_f, term_f, cable_fc,
              edge_tau=0.0, xfmr_fc=None, seed=1, abort=1e-2, windows=False,
              framer=True, sd_scale=1.0):
    """
    Regenerating chain (repeater.py 'regen' mode): launch -> [TX xfmr] -> edge RC
    -> cable -> peak normalise -> + noise -> [RX xfmr] -> front end.  The
    repeater re-drives its comparator output; at each tap the same noisy
    waveform is also scored through the terminal's filter.  Stops early once
    the terminal-filter BER at a tap exceeds `abort` (every later tap then
    fails a fortiori: regeneration never removes an error that the best
    filter could not avoid).
    """
    spb = fs / lr
    assert abs(spb - round(spb)) < 1e-9 and int(round(spb)) % 2 == 0, spb
    spb = int(round(spb))
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2.0 - 1.0, spb // 2)
    out = {}
    for k in range(1, n_spans + 1):
        y = x
        if xfmr_fc:
            y = filt(y, fs, ('hp1', xfmr_fc))
        if edge_tau:
            y = filt(y, fs, ('lp1', 1.0 / (2 * np.pi * edge_tau)))
        y = filt(y, fs, ('lp1', cable_fc))
        del x
        y /= np.abs(y).max()
        if sigma:
            nz = np.random.default_rng(seed * 1000 + k).standard_normal(len(y))
            nz *= sigma * sd_scale
            y += nz
            del nz
        if xfmr_fc:
            y = filt(y, fs, ('hp1', xfmr_fc))
        wr = fast.slice_hyst(filt(y, fs, rep_f), H)
        if k in taps:
            wt = wr if term_f == rep_f else fast.slice_hyst(filt(y, fs, term_f), H)
            rA = score(wr, spb, line, n, windows=windows and term_f != rep_f, framer=False)
            rB = rA if term_f == rep_f and not framer else \
                score(wt, spb, line, n, windows=windows, framer=framer)
            out[k] = dict(A=rA, B=rB)
            del wt
            if rB['ber'] > abort and k < n_spans:
                del y, wr
                gc.collect()
                break
        del y
        if k == n_spans:
            del wr
            break
        x = wr.astype(np.float64) * 2.0 - 1.0
        del wr
        gc.collect()
    gc.collect()
    return out


def fmt_ber(e):
    return '0' if e == 0 else f'{e:.0e}'


def flush(*a):
    print(*a, flush=True)


# ----------------------------------------------------------------------- pilot
def do_pilot():
    for lr in (64000, 256000, 1024000):
        line, n = line_for(lr)
        sym = 2 * lr
        for sg in (0.8, 1.0, 1.26, 2.0):
            t = time.time()
            r = run_chain(line, n, lr, FSC, sg, 1, (1,), ('lp2', sym), ('lp2', sym), CABLE)
            flush(f'{lr//1000}k sd {sg}: {r[1]["B"]}  {time.time()-t:.1f}s')


# ------------------------------------------------------------------- (a) filter
def walk(line, n, lr, fs, n_spans, taps, rep_f, term_f, cable_fc, top, floor=0.12,
         target=1e-4, need_A=(1,), **kw):
    """
    Walk the 1 dB sd grid down from `top` until every terminal-plugged metric
    (B at every tap) and the A metrics in `need_A` are <= target, or the floor
    is reached.  While every unresolved metric is far from target (> 3e-3 or
    aborted) the walk takes 2 dB steps; afterwards any metric whose first pass
    sits just below a skipped grid point has that point evaluated too, so each
    reported limit is a 1 dB grid limit.  Once every B tap has passed, lower
    sds only run the spans still needed.  Returns {sd: chain result}.
    """
    grid = [g for g in GRID if floor <= g <= top][::-1]
    res = {}

    def ev(i, spans_needed):
        sg = grid[i]
        t = time.time()
        tp = tuple(k for k in taps if k <= spans_needed)
        r = run_chain(line, n, lr, fs, sg, spans_needed, tp, rep_f, term_f, cable_fc, **kw)
        res[sg] = r
        cells = []
        for k in taps:
            if k in r:
                cells.append(f'{k}:A {fmt_ber(r[k]["A"]["ber"])} B {fmt_ber(r[k]["B"]["ber"])}'
                             + ('' if r[k]['B'].get('lock', True) else ' nolock'))
            else:
                cells.append(f'{k}:--')
        flush(f'    sd {sg:5.3f}  ' + '  |  '.join(cells) + f'   ({time.time()-t:.1f}s)')
        return r

    def ok(r, arr, k):
        return k in r and r[k][arr]['ber'] <= target

    metrics = [('B', k) for k in taps] + [('A', k) for k in need_A]
    passed = set()
    i = 0
    while i < len(grid):
        spans = n_spans if any(m[0] == 'B' and m not in passed for m in metrics) else max(need_A)
        r = ev(i, spans)
        if i == 0 and any(ok(r, a, k) for a, k in metrics):
            flush('    WARNING: a metric passes at the top of the walk; its limit is >= top')
        for m in metrics:
            if ok(r, *m):
                passed.add(m)
        if all(m in passed for m in metrics):
            break
        far = all((not ok(r, *m)) and (m[1] not in r or r[m[1]][m[0]]['ber'] > 3e-3)
                  for m in metrics if m not in passed)
        i += 2 if far else 1
    # refinement: first pass directly below an unevaluated grid point
    for a, k in metrics:
        idx = [j for j, g in enumerate(grid) if g in res and ok(res[g], a, k)]
        if idx:
            j = min(idx)
            g = grid[j - 1] if j > 0 else None
            if g is not None and (g not in res or k not in res[g]):
                prev = res.get(g, {})
                r = ev(j - 1, k)
                for kk, v in prev.items():
                    r.setdefault(kk, v)
    return res


def limits(res, taps, target=1e-4):
    """Largest grid sd with BER <= target for each (arrangement, tap), requiring
    every larger sd walked to have failed or been aborted (monotone reading)."""
    out = {}
    sds = sorted(res, reverse=True)
    for arr in 'AB':
        for k in taps:
            lim = None
            for sg in sds:                     # descending: first pass is the limit
                r = res[sg]
                if k in r and r[k][arr]['ber'] <= target:
                    lim = sg
                    break
            out[(arr, k)] = lim
    return out


def do_a():
    TAPS = (1, 4, 9)
    PLAN = {
        64000:   [('lp2', 128e3), ('lp2', 512e3), ('lp2', 1.024e6), ('lp2', 2.048e6), None],
        256000:  [('lp2', 128e3), ('lp2', 256e3), ('lp2', 512e3), ('lp2', 1.024e6),
                  ('lp2', 2.048e6), None],
        1024000: [('lp2', 512e3), ('lp2', 1.024e6), ('lp2', 2.048e6), None],
    }
    if 'impl' in sys.argv[2:]:               # implementable fixed filters (a2)
        PLAN = {1024000: [('lp2', 4.096e6), ('rcrc', 2.048e6), ('rcrc', 3.18e6)],
                256000: [('rcrc', 3.18e6)]}
    TOP = {64000: 3.2, 256000: 1.6, 1024000: 0.8}
    FLOOR = {64000: 0.099, 256000: 0.07, 1024000: 0.044}
    # 64 kbps at 32.768 MHz proved too slow on a shared machine: optional fs override
    # (sd stays in 32.768 MHz units via sd_scale; 'none' then means fs/2 of bandwidth)
    fs_over = [float(v[3:]) for v in sys.argv[2:] if v.startswith('fs=')]
    top_over = [float(v[4:]) for v in sys.argv[2:] if v.startswith('top=')]
    only = [int(v) for v in sys.argv[2:] if v.isdigit()]
    skip = [v[5:] for v in sys.argv[2:] if v.startswith('skip=')]
    summary = {}
    for lr in (only or list(PLAN)):
        specs = PLAN[lr]
        line, n = line_for(lr)
        term = ('lp2', 2.0 * lr)
        for rep in specs:
            if fname(rep) in skip:
                continue
            fs = fs_over[0] if fs_over else FSC
            flush(f'\n[{lr//1000} kbps line, symbol {2*lr/1e3:g} kbaud] repeater filter {fname(rep)}, '
                  f'terminal {fname(term)}; cable 1 MHz, fs {fs/1e6:g} MHz (sd in 32.768 MHz units), '
                  f'{NBITS} bits')
            res = walk(line, n, lr, fs, max(TAPS), TAPS, rep, term, CABLE,
                       top_over[0] if top_over else TOP[lr], floor=FLOOR[lr],
                       sd_scale=float(np.sqrt(fs / FSC)))
            lim = limits(res, TAPS)
            summary[(lr, fname(rep))] = (lim, res)
            flush('    limits (sd @32.768MHz, BER<=1e-4): ' +
                  '  '.join(f'{a}{k}={lim[(a, k)]:.3f}' if lim[(a, k)] else f'{a}{k}=<{min(res):.3f}'
                            for a in 'AB' for k in TAPS))
    flush('\n\nSUMMARY (a): largest per-span sd with line BER <= 1e-4, 32.768 MHz grid '
          '(divide by 2 for the spec sd at 8.192 MHz)')
    flush('A = every receiver uses the filter; B = repeaters use it, terminal plugged to symbol rate')
    flush(f'{"line":>6s} {"rep filter":>12s} {"x sym":>6s} | ' +
          ' '.join(f'{a}{k:<2d}{"":4s}' for a in 'AB' for k in TAPS) + ' | dB vs symbol-rate filter (B)')
    for (lr, nm), (lim, res) in summary.items():
        ref = summary.get((lr, fname(('lp2', 2.0 * lr))))
        spec = [s for s in PLAN[lr] if fname(s) == nm][0]
        xs = '-' if spec is None else f'{spec[1] / (2 * lr):.3g}'
        lo = min(res)
        cells = ' '.join((f'{lim[(a, k)]:6.3f}' if lim[(a, k)] else f'<{lo:5.3f}') + ' '
                         for a in 'AB' for k in TAPS)
        db = ''
        if ref:
            rl = ref[0]
            db = ' '.join((f'{20*np.log10(lim[("B", k)]/rl[("B", k)]):+5.1f}'
                           if lim[('B', k)] and rl[('B', k)] else '  n/a') for k in TAPS)
        flush(f'{lr//1000:5d}k {nm:>12s} {xs:>6s} | {cells}| {db}')


def do_a0():
    """Noiseless chain: does deterministic pulse-width distortion accumulate
    through regeneration when the cable, not the filter, sets the bandwidth?"""
    flush('(a0) NOISELESS regenerating chain, 1 MHz cable, 32.768 MHz: sliced intervals at the '
          'repeater/terminal comparator (cells) and terminal line BER, per span count')
    PLAN = [(1024000, [('lp2', 1.024e6), ('lp2', 2.048e6), ('lp2', 4.096e6), None]),
            (512000, [('lp2', 1.024e6), ('lp2', 2.048e6), None]),
            (256000, [('lp2', 512e3), ('lp2', 2.048e6), None]),
            (64000, [('lp2', 128e3), ('lp2', 2.048e6)])]
    for lr, specs in PLAN:
        SP = (1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 17) if lr >= 256000 else (1, 9)
        line, n = line_for(lr, 16000)
        spb = int(FSC / lr)
        sym = 2 * lr
        for rep in specs:
            flush(f'\n  {lr//1000}k, repeater filter {fname(rep)} (terminal lp2 {sym/1e3:g}k)')
            t0 = time.time()
            flush(f'  {"spans":>5s} {"short mean":>10s} {"short max":>9s} {"long mean":>9s} {"long min":>8s}'
                  f' {"term BER":>8s} {"rep-slice BER":>13s}')
            x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2.0 - 1.0, spb // 2)
            for k in range(1, max(SP) + 1):
                y = filt(x, FSC, ('lp1', CABLE))
                y /= np.abs(y).max()
                wr = fast.slice_hyst(filt(y, FSC, rep), H)
                if k in SP:
                    wt = fast.slice_hyst(filt(y, FSC, ('lp2', sym)), H)
                    e = np.flatnonzero(np.diff(wt.astype(np.int8)) != 0) + 1
                    g = np.diff(e[e > 2000 * spb]) / spb
                    sh, lo = g[g < 0.75], g[g >= 0.75]
                    bt = score(wt, spb, line, n)['ber']
                    br = score(wr, spb, line, n)['ber']
                    flush(f'  {k:5d} {sh.mean():10.4f} {sh.max():9.3f} {lo.mean():9.4f} {lo.min():8.3f}'
                          f' {fmt_ber(bt):>8s} {fmt_ber(br):>13s}')
                    del wt
                x = wr.astype(np.float64) * 2.0 - 1.0
                del y, wr
            del x
            gc.collect()


def do_a0f():
    """a0 on a fine grid.  At 32 samples per line bit a noiseless chain can only
    move an edge by whole samples (1/32 cell), so a0's 1024 kbps rows are
    quantised; here 256 samples per line bit, noiseless, few bits."""
    flush('(a0f) NOISELESS regenerating chain on a fine grid (256 samples per line bit), 1 MHz cable, '
          'hysteresis 0.05: worst sliced intervals at the terminal comparator (cells) per span count')
    PLAN = [(1024000, [('lp2', 1.024e6), ('lp2', 2.048e6), ('lp2', 4.096e6), ('rcrc', 2.048e6),
                       ('rcrc', 3.18e6), None]),
            (512000, [('lp2', 1.024e6), ('lp2', 2.048e6), None]),
            (256000, [('lp2', 512e3), ('lp2', 2.048e6), None])]
    SP = (1, 2, 3, 4, 6, 9, 12, 17)
    for lr, specs in PLAN:
        line, n = line_for(lr, 12000)
        spb = 256
        fs = spb * lr
        sym = 2 * lr
        for rep in specs:
            flush(f'\n  {lr//1000}k, repeater filter {fname(rep)} (terminal lp2 {sym/1e3:g}k), fs {fs/1e6:g} MHz')
            flush(f'  {"spans":>5s} {"short min":>9s} {"short max":>9s} {"long min":>8s} {"long max":>8s}'
                  f' {"term BER":>8s}')
            x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2.0 - 1.0, spb // 2)
            for k in range(1, max(SP) + 1):
                y = filt(x, fs, ('lp1', CABLE))
                y /= np.abs(y).max()
                wr = fast.slice_hyst(filt(y, fs, rep), H)
                if k in SP:
                    wt = fast.slice_hyst(filt(y, fs, ('lp2', sym)), H)
                    e = np.flatnonzero(np.diff(wt.astype(np.int8)) != 0) + 1
                    g = np.diff(e[e > 2000 * spb]) / spb
                    sh, lo = g[g < 0.75], g[g >= 0.75]
                    bt = score(wt, spb, line, n)['ber']
                    flush(f'  {k:5d} {sh.min():9.3f} {sh.max():9.3f} {lo.min():8.3f} {lo.max():8.3f}'
                          f' {fmt_ber(bt):>8s}')
                    del wt
                x = wr.astype(np.float64) * 2.0 - 1.0
                del y, wr
            del x
            gc.collect()


def do_seed():
    """Seed check on the (a) 64 kbps comparison, both filters on the same 16.384 MHz grid."""
    lr = 64000
    fs = FSC / 2
    line, n = line_for(lr)
    flush('(seed) 64 kbps, fs 16.384 MHz, sd in 32.768 MHz units: terminal (B) line BER at 4 and 9 '
          'spans, repeater filter at the symbol rate vs fixed 2.048 MHz, noise seeds 1 and 2')
    for rep in (('lp2', 128e3), ('lp2', 2.048e6)):
        for seed in (1, 2):
            for sg in (2.245, 1.782, 1.414, 1.122):
                t = time.time()
                r = run_chain(line, n, lr, fs, sg, 9, (4, 9), rep, ('lp2', 128e3), CABLE, seed=seed,
                              sd_scale=float(np.sqrt(fs / FSC)), abort=1e-2)
                flush(f'  {fname(rep):>10s} seed {seed} sd {sg:5.3f}: ' + '  '.join(
                    f'{k} spans {fmt_ber(r[k]["B"]["ber"])}' if k in r else f'{k} spans aborted'
                    for k in (4, 9)) + f'   ({time.time()-t:.1f}s)')


# ------------------------------------------------------------------ (b) edges
def tau_of(ns):
    return ns * 1e-9 / 2.197 if ns else 0.0


def window_str(win, target):
    ok = [t for t in THRS if win[t] <= target]
    if not ok:
        return 'none'
    # contiguous run containing 0.75, if any
    if win[THR] > target:
        return f'{min(ok):.2f}-{max(ok):.2f}(split)'
    lo = hi = THRS.index(THR)
    while lo - 1 >= 0 and win[THRS[lo - 1]] <= target:
        lo -= 1
    while hi + 1 < len(THRS) and win[THRS[hi + 1]] <= target:
        hi += 1
    return f'{THRS[lo]:.2f}-{THRS[hi]:.2f}'


def do_b1():
    EDGES = (0, 75, 150, 300)
    flush('(b1) TX EDGE RATE, spec sd convention: sd referred to 32 samples per line bit '
          '(scaled by sqrt(spb/32) on the 32.768 MHz grid), cable 1.7578 x symbol rate, '
          'repeater and terminal filters lp2 at the symbol rate, edge = 10-90% of a first-order RC '
          'on EVERY driver (TX and repeaters). BER is line BER; window = classifier '
          'thresholds with BER <= 1e-4 (40k bits).')
    for sd_rel, taps in ((0.4, (1, 3)), (0.25, (9,))):
        flush(f'\n  sd {sd_rel} (spec units)')
        flush(f'  {"line":>6s} {"half-cell":>9s} {"edge":>5s} {"edge/hc":>7s} | ' +
              ' | '.join(f'{k} span BER   window     ' for k in taps))
        for lr in (64000, 128000, 256000, 512000, 1024000):
            line, n = line_for(lr)
            fs = max(FSC / 2, 32.0 * lr)       # 16.384 MHz floor: a 75 ns RC is 4.7 MHz
            spb = fs / lr
            sd = sd_rel * np.sqrt(spb / 32.0)
            sym = 2 * lr
            for e in EDGES:
                t = time.time()
                r = run_chain(line, n, lr, fs, sd, max(taps), taps, ('lp2', sym), ('lp2', sym),
                              1.7578 * sym, edge_tau=tau_of(e), windows=True, abort=0.2)
                hc = 1e9 / sym
                cells = []
                for k in taps:
                    if k in r:
                        b = r[k]['B']
                        cells.append(f'{fmt_ber(b["ber"]):>6s} {window_str(b["win"], 1e-4):>16s}'
                                     + ('' if b.get('lock') else ' NOLOCK'))
                    else:
                        cells.append(f'{"aborted":>23s}')
                flush(f'  {lr//1000:5d}k {hc:7.0f}ns {e:4d}ns {e/hc:6.1%} | ' + ' | '.join(cells)
                      + f'   ({time.time()-t:.1f}s)')


def do_b2():
    EDGES = (0, 75, 150, 300)
    TAPS = (1, 4)
    TOP = {256000: 1.6, 512000: 1.26, 1024000: 0.8}
    flush('(b2) TX EDGE RATE, absolute frame: 64 samples per line bit, sd in 32.768 MHz units, '
          '1 MHz cable, filters lp2 at the symbol rate everywhere; largest sd with line BER <= 1e-4')
    summ = []
    for lr in (1024000, 512000):
        line, n = line_for(lr)
        sym = 2 * lr
        for e in EDGES:
            flush(f'\n[{lr//1000} kbps, edge {e} ns]')
            fs = 64.0 * lr                     # 65.536 MHz at 1024 kbps: sub-sample edges
            res = walk(line, n, lr, fs, max(TAPS), TAPS, ('lp2', sym), ('lp2', sym), CABLE,
                       TOP[lr], edge_tau=tau_of(e), sd_scale=float(np.sqrt(fs / FSC)))
            lim = limits(res, TAPS)
            summ.append((lr, e, lim))
    flush('\nSUMMARY (b2)')
    base = {(lr, k): lim[('B', k)] for lr, e, lim in summ if e == 0 for k in TAPS}
    for lr, e, lim in summ:
        flush(f'  {lr//1000:5d}k edge {e:3d} ns: ' + '  '.join(
            f'{k} span sd {lim[("B", k)]:.3f} ({20*np.log10(lim[("B", k)]/base[(lr, k)]):+.1f} dB)'
            if lim[('B', k)] and base[(lr, k)] else f'{k} span <floor' for k in TAPS))


# -------------------------------------------------------------- (c) transformer
def wander_metrics(line, lr, fs, xfmr_fc, cable_fc, sym):
    """Noiseless single span: baseline wander at the comparator input (difference
    from the no-transformer waveform), vertical eye at half-cell centres, and
    pulse-width distortion of the sliced waveform."""
    spb = int(round(fs / lr))
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2.0 - 1.0, spb // 2)

    def rx(hp):
        y = x
        if hp:
            y = filt(y, fs, ('hp1', hp))
        y = filt(y, fs, ('lp1', cable_fc))
        y = y / np.abs(filt(filt(x, fs, ('lp1', cable_fc)), fs, None)).max()
        if hp:
            y = filt(y, fs, ('hp1', hp))
        return filt(y, fs, ('lp2', sym))
    y0 = rx(None)
    y1 = rx(xfmr_fc) if xfmr_fc else y0
    skip = 4000 * spb                      # past the start transient
    d = (y1 - y0)[skip:]
    # half-cell centres, delayed by the filter group delay (align on y0)
    hc = spb // 2
    lags = range(0, 2 * spb)
    ref = x[skip:skip + 200 * spb]
    lag = max(lags, key=lambda L: float(np.dot(ref, y0[skip + L:skip + L + 200 * spb])))
    centres = np.arange(skip + hc // 2 + lag, len(y1) - spb, hc)
    sgn = x[centres - lag]
    eye1 = float((y1[centres] * sgn).min())
    eye0 = float((y0[centres] * sgn).min())
    w = fast.slice_hyst(y1, H)
    e = np.flatnonzero(np.diff(w.astype(np.int8)) != 0) + 1
    g = np.diff(e[e > skip]) / spb
    sh, lo = g[g < 0.75], g[g >= 0.75]
    return dict(wander_pk=float(np.abs(d).max()), wander_rms=float(d.std()),
                eye=eye1, eye0=eye0,
                pwd_short=float(np.abs(sh - 0.5).max()) if len(sh) else np.nan,
                pwd_long=float(np.abs(lo - 1.0).max()) if len(lo) else np.nan)


def do_c():
    lr = 64000
    sym = 2 * lr
    fs = lr * 32                             # 2.048 MHz: spec convention, 32 samples/bit
    cable = 1.7578 * sym
    R = 100.0
    XF = [('none', None), ('33 mH', 33e-3), ('10 mH', 10e-3), ('4.7 mH', 4.7e-3), ('2.2 mH', 2.2e-3)]
    nb = 96000
    flush(f'(c) TRANSFORMER DROOP at the 64 kbps line rate. Spec sd convention (fs = 2.048 MHz, '
          f'32 samples/bit), cable {cable/1e3:.0f} kHz, filters lp2 {sym/1e3:.0f} kHz. Two first-order '
          f'high-passes per span (TX + RX transformer), corner R/(2 pi L), R = {R:.0f} ohm. '
          f'{nb} line bits.')
    for payload in ('speech', 'data1', 'data0'):
        line, n = line_for(lr, nb, payload)
        flush(f'\n  payload {payload}: noiseless single span (wander = deviation from the '
              f'no-transformer waveform at the comparator input, fraction of launched peak; eye = '
              f'min signed level at half-cell centres; PWD = worst sliced interval error, cells)')
        flush(f'  {"xfmr":>7s} {"corner":>7s} {"droop/cell":>10s} | {"wander pk":>9s} {"wander rms":>10s} '
              f'{"eye":>6s} {"eye0":>6s} {"PWD short":>9s} {"PWD long":>8s}')
        for nm, L in XF:
            fc = R / (2 * np.pi * L) if L else None
            droop = 1 - np.exp(-(1 / lr) / (L / R)) if L else 0.0
            m = wander_metrics(line, lr, fs, fc, cable, sym)
            flush(f'  {nm:>7s} {(f"{fc:.0f}Hz" if fc else "-"):>7s} {droop:10.1%} | {m["wander_pk"]:9.3f} '
                  f'{m["wander_rms"]:10.4f} {m["eye"]:6.3f} {m["eye0"]:6.3f} {m["pwd_short"]:9.4f} '
                  f'{m["pwd_long"]:8.4f}')
    for payload in ('speech', 'data1'):
        line, n = line_for(lr, nb, payload)
        for sd, taps in ((0.4, (1, 3)), (0.25, (9,))):
            flush(f'\n  payload {payload}, sd {sd}: line BER, framer lock, classifier window (BER<=1e-4)')
            for nm, L in XF:
                fc = R / (2 * np.pi * L) if L else None
                r = run_chain(line, n, lr, fs, sd, max(taps), taps, ('lp2', sym), ('lp2', sym), cable,
                              xfmr_fc=fc, windows=True, abort=0.2)
                flush(f'  {nm:>7s}: ' + ' | '.join(
                    f'{k} span BER {fmt_ber(r[k]["B"]["ber"])} lock {r[k]["B"]["lock"]} '
                    f'LOF {r[k]["B"]["lof"]} window {window_str(r[k]["B"]["win"], 1e-4)}'
                    if k in r else f'{k} span aborted' for k in taps))
        flush(f'\n  payload {payload}: largest sd (spec units) with BER <= 1e-4')
        for nm, L in XF:
            fc = R / (2 * np.pi * L) if L else None
            res = walk(line, n, lr, fs, 9, (1, 4, 9), ('lp2', sym), ('lp2', sym), cable, 0.9,
                       floor=0.1, xfmr_fc=fc)
            lim = limits(res, (1, 4, 9))
            flush(f'  {nm:>7s}: ' + '  '.join(f'{k} span {lim[("B", k)]:.3f}' if lim[('B', k)] else
                                             f'{k} span <floor' for k in (1, 4, 9)))
    # R = 50 ohm sensitivity (source || load across the magnetising inductance)
    line, n = line_for(lr, nb, 'speech')
    flush('\n  R = 50 ohm (both ends terminated), speech, droop metrics')
    for nm, L in XF[1:]:
        fc = 50.0 / (2 * np.pi * L)
        m = wander_metrics(line, lr, fs, fc, cable, sym)
        flush(f'  {nm:>7s} {fc:6.0f}Hz droop/cell {1-np.exp(-(1/lr)/(L/50.0)):5.1%} wander pk '
              f'{m["wander_pk"]:.3f} eye {m["eye"]:.3f} PWD short {m["pwd_short"]:.4f} long {m["pwd_long"]:.4f}')


def do_c2():
    lr = 64000
    sym = 2 * lr
    line, n = line_for(lr)
    R = 100.0
    fs = FSC / 4                             # 8.192 MHz: every filter here is <= 1 MHz
    flush('(c2) droop, absolute frame: 1 MHz cable, lp2 at 128 kHz everywhere, R = 100 ohm, two '
          'transformers per span; run at 8.192 MHz with sd x 1/2 so the PSD equals the 32.768 MHz '
          'frame; largest sd (32.768 MHz units) with BER <= 1e-4')
    for nm, L in (('none', None), ('33 mH', 33e-3), ('10 mH', 10e-3)):
        fc = R / (2 * np.pi * L) if L else None
        flush(f'\n[{nm}]  (sd printed below is at 8.192 MHz; x2 for 32.768 MHz units)')
        res = walk(line, n, lr, fs, 4, (1, 4), ('lp2', sym), ('lp2', sym), CABLE, 1.6, floor=0.3,
                   xfmr_fc=fc)
        lim = limits(res, (1, 4))
        flush(f'  {nm}: ' + '  '.join(f'{k} span {2*lim[("B", k)]:.3f}' if lim[('B', k)] else
                                     f'{k} span <floor' for k in (1, 4)))


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'pilot'
    t0 = time.time()
    dict(pilot=do_pilot, a=do_a, a0=do_a0, a0f=do_a0f, seed=do_seed, b1=do_b1, b2=do_b2, c=do_c, c2=do_c2)[cmd]()
    flush(f'\n[{cmd} done in {time.time()-t0:.0f}s]')
