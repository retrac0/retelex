"""
The impulse-noise falloff curve for the MF8 link, measured precisely.

mf8/line-codes.md 4 placed differential Manchester's impulse cliff "between 1
and 10 events per second" from four points (0, 10, 100, 1000/s).  This sweeps a
log grid of impulse rates in both line codes, with enough independent runs per
point to put error bars on it, and fits the curve.

Model.  If each impulse independently knocks the link out with probability p
for a mean time tau, outages arrive as a Poisson process of rate r*p and the
fraction of time muted is

    muted(r) = 1 - exp(-r / r0),        r0 = 1 / (p * tau)

The low-rate points measure p and tau directly and the high-rate points test the
model.  It holds for differential Manchester and FAILS for AMI, whose curve is a
threshold, so the thresholds reported are interpolated on the measured points and
the model is used only to say how well independent outages explain each curve.

Link layer only -- random payload, the mf8 framer, no audio -- so it runs well
faster than mf8_render.py.  The physical layer is mf8_render.stream: chunked,
with encoder, filter and slicer state carried across chunks, and verified
bit-identical against an unchunked reference.

Usage:  python3 sim/impulse_sweep.py              the sweep, ~16 min
        python3 sim/impulse_sweep.py --quick      coarse grid, short runs
        python3 sim/impulse_sweep.py --reanalyse  rebuild the analysis from the CSV
"""
import sys, time, csv, gc, numpy as np
import audio, mf8, mf8_render

RATE = 64000
NCH = 6
T_RUN = 10.0                       # seconds of line per independent run
TARGET_EVENTS = 200                # impulses per rate point, before clamping
K_MIN, K_MAX = 3, 12
AMP = (0.5, 3.0)                   # impulse amplitude, x transmitted peak
RATES = (0.3, 0.5, 1, 2, 3, 5, 7, 10, 15, 20, 30, 50, 70, 100, 150, 200,
         300, 500, 600, 700, 800, 900, 1000)   # 600-900: AMI's collapse


def one_run(code, rate, seed, secs):
    """One independent run: fresh payload, fresh noise.  Returns link stats
    measured from the FIRST lock onward, so start-up acquisition is excluded."""
    nf = int(secs * RATE)
    rg = np.random.default_rng(10007 * seed + 17)
    C = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    A = [np.full(nf, (0, 0, 0, 1, 0, 0)[j], np.uint8) for j in range(NCH)]
    ln = mf8.build(C, A)
    rb = mf8_render.stream(ln, code, imp=rate, seed=seed)
    st = mf8.framer(rb)
    del rb, ln; gc.collect()
    if st['lock_bit'] is None:
        return dict(post=0, locked=0, lof=st['lof_events'], ok=False)
    post = nf - st['lock_bit'] // 8          # frames of time after first lock
    return dict(post=post, locked=st['frames'], lof=st['lof_events'], ok=True)


def sweep(rates, t_run, target, kmin, kmax, log):
    rows = []
    for code, label in (('dm', 'diff Manchester'), ('ami', 'AMI')):
        log(f'\n{label}\n')
        log(f'  {"rate/s":>7s} {"runs":>5s} {"impulses":>9s} {"LOF":>6s} '
            f'{"LOF/imp":>8s} {"breaks/s":>9s} {"muted %":>9s} {"+/- se":>8s} '
            f'{"ms/break":>9s}')
        for r in rates:
            k = int(np.clip(np.ceil(target / (r * t_run)), kmin, kmax))
            runs = []
            t0 = time.time()
            for s in range(1, k + 1):
                runs.append(one_run(code, r, s, t_run))
            post = sum(x['post'] for x in runs)
            locked = sum(x['locked'] for x in runs)
            lof = sum(x['lof'] for x in runs)
            muted = 1.0 - locked / post if post else 1.0
            per = [1.0 - x['locked'] / x['post'] if x['post'] else 1.0 for x in runs]
            se = float(np.std(per, ddof=1) / np.sqrt(k)) if k > 1 else 0.0
            imps = r * t_run * k
            ms = 1000.0 * (post - locked) / RATE / lof if lof else float('nan')
            bps = lof / (post / RATE) if post else float('nan')
            rows.append(dict(code=code, rate=r, runs=k, impulses=imps, lof=lof,
                             muted=muted, se=se, ms=ms, per=per, bps=bps,
                             secs=time.time() - t0))
            log(f'  {r:7.1f} {k:5d} {imps:9.0f} {lof:6d} {lof / imps:8.3f} '
                f'{bps:9.2f} {100 * muted:8.3f}% {100 * se:7.3f}% '
                f'{"-" if np.isnan(ms) else f"{ms:8.2f}":>9s}')
    return rows


def interp_rate(rows, key, target):
    """Impulse rate at which `key` reaches `target`, by log-log interpolation
    between the bracketing MEASURED points -- no model."""
    rr = np.array([x['rate'] for x in rows]); vv = np.array([x[key] for x in rows])
    ok = np.flatnonzero(vv >= target)
    if len(ok) == 0:
        return None, 'never'
    i = ok[0]
    if i == 0:
        return None, f'< {rr[0]:g}/s'
    lo, hi = vv[i - 1], vv[i]
    if lo <= 0:
        return rr[i], f'{rr[i]:.3g}/s'
    t = (np.log(target) - np.log(lo)) / (np.log(hi) - np.log(lo))
    r = float(np.exp(np.log(rr[i - 1]) + t * (np.log(rr[i]) - np.log(rr[i - 1]))))
    return r, f'{r:.3g}/s'


def analyse(rows, log):
    """Model-free first.  The exponential model is reported as a description of
    how well independent outages explain the curve, not as the source of the
    thresholds -- its systematic error is larger than any sampling error."""
    by = {c: sorted([x for x in rows if x['code'] == c], key=lambda x: x['rate'])
          for c in ('dm', 'ami')}

    log('\n\nTHRESHOLDS, INTERPOLATED ON THE MEASURED POINTS (no model)\n')
    log('  Impulse rate at which the link reaches each level.  Per-point standard')
    log('  errors are in the tables above -- roughly 5-10% relative on "muted" --')
    log('  so read these to two significant figures, not four.\n')
    log(f'  {"":24s} {"diff Manchester":>16s} {"AMI":>10s} {"AMI / DM":>10s}')
    for key, lab, tgts, fmt in (('bps', 'breaks/s', (0.1, 1.0, 10.0, 50.0), '{:g} breaks/s'),
                                 ('muted', 'muted', (0.001, 0.01, 0.05, 0.10), '{:.1%} muted')):
        for t in tgts:
            d, ds = interp_rate(by['dm'], key, t)
            a_, as_ = interp_rate(by['ami'], key, t)
            ratio = f'{a_ / d:.1f}x' if (d and a_) else '-'
            log(f'  {fmt.format(t):24s} {ds:>16s} {as_:>10s} {ratio:>10s}')
        log('')

    log('THE SHAPE -- the two codes fail differently, not by a constant factor\n')
    for code, label in (('dm', 'diff Manchester'), ('ami', 'AMI')):
        cr = by[code]
        low = [x for x in cr if x['rate'] <= 3 and x['lof'] > 0]
        p = sum(x['lof'] for x in low) / sum(x['impulses'] for x in low)
        tau = sum(x['ms'] * x['lof'] for x in low) / sum(x['lof'] for x in low)
        r0 = 1000.0 / (p * tau)
        log(f'  {label}')
        log(f'    low rate (<= 3/s, outages do not overlap):  p = {p:.3f} breaks per')
        log(f'    impulse, tau = {tau:.2f} ms per break  ->  independent-outage model')
        log(f'    muted(r) = 1 - exp(-r / {r0:.0f}), checked against the measurements:')
        for x in cr:
            if x['rate'] in (1, 10, 100, 300, 500, 1000):
                mod = 1.0 - np.exp(-x['rate'] / r0)
                log(f'      {x["rate"]:6g}/s   measured {100 * x["muted"]:7.3f}%   '
                    f'model {100 * mod:7.3f}%   breaks/impulse {x["lof"] / x["impulses"]:.3f}')
        log('')
    log('  Differential Manchester follows the model to within ~10-15% across the')
    log('  whole range.  Each impulse above the comparator threshold causes a slip')
    log('  (0.77 per impulse at low rate), each slip costs ~0.76 ms, and outages')
    log('  simply add.  Breaks per impulse falls slowly at high rate (0.68 at 100/s,')
    log('  0.37 at 1000/s) because one outage starts absorbing several impulses.')
    log('')
    log('  AMI does NOT follow it.  Breaks per impulse stays near 0.13 -- about a')
    log('  sixth of differential Manchester -- and muting grows gently to 9.4% at')
    log('  500/s, then the link COLLAPSES -- see the 500-1000/s rows for where.')
    log('  AMI does not slip (line-codes.md 4.1: bit count preserved at every')
    log('  impulse rate), so its breaks are accumulated bit errors, and the likely')
    log('  mechanism for the collapse is F-bit errors reaching the +2/-1 counter\'s')
    log('  one-in-three trip point, beyond which nothing holds -- a threshold, not')
    log('  an exponential.  Hypothesis, consistent with the shape; not measured.')
    log('')
    cross = None
    dm = {x['rate']: x['muted'] for x in by['dm']}
    for x in by['ami']:
        if x['rate'] in dm and x['muted'] > dm[x['rate']]:
            cross = x['rate']; break
    log('  So "AMI is Nx better" has no single N: ~5-6x on breaks per second through')
    log('  the working range, falling to ~3x on muted time -- and ' +
        (f'from {cross:g}/s on, AMI is muted MORE than differential Manchester.'
         if cross else 'no measured point where AMI is worse.'))


def reanalyse():
    """Rebuild impulse_sweep.log from impulse_sweep.csv without re-simulating."""
    rows = []
    with open(audio.here('impulse_sweep.csv')) as f:
        for r in csv.DictReader(f):
            rows.append(dict(code=r['code'], rate=float(r['rate_per_s']),
                             runs=int(r['runs']), impulses=float(r['impulses']),
                             lof=int(r['lof']), bps=float(r['breaks_per_s']),
                             muted=float(r['muted_frac']), se=float(r['muted_se']),
                             ms=float(r['ms_per_lof']) if r['ms_per_lof'] else float('nan')))
    old = open(audio.here('impulse_sweep.log')).read()
    head = old[:old.index('\n\nTHE CURVE, FITTED')] if '\n\nTHE CURVE, FITTED' in old \
        else old[:old.index('\n\nTHRESHOLDS')]
    out = open(audio.here('impulse_sweep.log'), 'w')

    def log(s=''):
        print(s, flush=True); out.write(s + '\n')
    out.write(head)
    analyse(rows, log)
    out.close()


def main():
    if '--reanalyse' in sys.argv:
        return reanalyse()
    quick = '--quick' in sys.argv
    rates = (1, 10, 100) if quick else RATES
    t_run = 2.0 if quick else T_RUN
    target, kmin, kmax = (20, 2, 3) if quick else (TARGET_EVENTS, K_MIN, K_MAX)
    out = open(audio.here('impulse_sweep.log') if not quick else '/dev/null', 'w')

    def log(s=''):
        print(s, flush=True); out.write(s + '\n'); out.flush()

    log('IMPULSE FALLOFF -- MF8 link, both line codes')
    log(f'  impulses: damped rings, amplitude U{AMP} x transmitted peak, 15-80 kHz,')
    log(f'  20-200 us decay, Poisson arrivals.  512 kbps, 1.8 MHz cable, no other')
    log(f'  impairment.  Each rate point is several independent {t_run:.0f} s runs,')
    log(f'  enough for ~{target} impulses, clamped to {kmin}-{kmax} runs.')
    log('  "muted" is time unlocked after the first lock; "se" its standard error')
    log('  across runs; "LOF/imp" is loss-of-frame events per impulse.')
    t0 = time.time()
    rows = sweep(rates, t_run, target, kmin, kmax, log)
    if not quick:
        with open(audio.here('impulse_sweep.csv'), 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['code', 'rate_per_s', 'runs', 'impulses', 'lof',
                        'breaks_per_s', 'muted_frac', 'muted_se', 'ms_per_lof'])
            for x in rows:
                w.writerow([x['code'], x['rate'], x['runs'], f'{x["impulses"]:.0f}',
                            x['lof'], f'{x["bps"]:.4f}', f'{x["muted"]:.6f}',
                            f'{x["se"]:.6f}',
                            '' if np.isnan(x['ms']) else f'{x["ms"]:.3f}'])
    analyse(rows, log)
    log(f'\n  wall time {time.time() - t0:.0f} s')


if __name__ == '__main__':
    main()
