"""
The channel card as built: one slew trim at every rate, and the swings and
levels its analog circuit has to handle.

QUESTION
  1  Are the published per-rate figures (spec 2.1 / 11.1, family.md 3) -- mean
     10.80 / 17.40 / 23.28 dB, worst talker 9.02 / 14.91 / 19.69 dB -- reproducible,
     and why does card.score give less at the same per-rate slews?
  2  What does leaving the one trim (slew = I_abc / C_int) fixed cost across
     16 / 32 / 64 kbps?  Which single trim is best, and is a rate strap justified?
     Who is the worst talker at each rate, and why?
  3  segSNR against input level, -30 .. +12 dB relative to nominal (0.15 rms FS).
  4  Integrator and syllabic-node swings at nominal, +6 and +10 dB.
  5  Largest sine encoded without slope overload; idle-channel noise.

METHOD
  The card's engine at circuit level (card.py, zero imperfections, which is
  bit-identical to cvsd.py -- checked in section 1 at the per-rate slews), seven
  independent LibriSpeech talkers prepared exactly as card.load_talker does.
  Every speech figure is 30 s per talker, mean over seven AND worst talker.

  Three scorings are carried side by side, because section 1 finds they disagree:
    card    card.score exactly: reconstruct, integer-lag align at the CVSD rate,
            gain match, segSNR at the CVSD rate.
    lagfix  card.score with the lag re-chosen for best segSNR within +-2 samples
            of the one audio.align picks, and of zero.  Section 1 shows audio.align's
            cross-correlation peak lands one sample late on some talkers.
    8k      the published pipeline: reconstructed output and reference both
            resampled to 8 kHz, then align / gain match / segSNR at 8 kHz.

Usage:  python3 card_levels.py [1 2 3 4 5]      (default: all; sections 3-5 use
        the trim section 2 recommends, or TRIM below when run on their own)
Uses at most 2 worker processes.
"""
import sys, time
import numpy as np
from multiprocessing import Pool
from scipy import signal
import audio, card, cvsd, run

WORKERS = 2
SECS = 30.0
RATES = card.RATES
TALKERS = card.TALKERS
NOM = run.NOMINAL_RMS
SLEWS = (5000, 6000, 7000, 8500, 10000, 12000, 14000, 16000, 19000, 22000, 26000)
EXTRA = (13000, 15000, 17000, 30000, 36000)     # finer near the optimum, and past 26000
TRIM = 16000.0          # section 2's recommendation; recomputed when section 2 runs
PUBLISHED = {16000: (10.80, 9.02), 32000: (17.40, 14.91), 64000: (23.28, 19.69)}


def hdr(t):
    print('\n' + '=' * 78 + f'\n{t}\n' + '=' * 78, flush=True)


def sub(t):
    print(f'\n--- {t}', flush=True)


# ------------------------------------------------------------------ scoring
def shift(ref, test, lag):
    """audio.align's trimming for a given integer lag."""
    if lag > 0:
        test = test[lag:]; ref = ref[:len(test)]
    elif lag < 0:
        ref = ref[-lag:]; test = test[:len(ref)]
    n = min(len(ref), len(test))
    return ref[:n], test[:n]


def seg_at(ref, test, fs, lag, silence_db=-45.0):
    r, t = shift(ref, test, lag)
    return audio.seg_snr_db(r, audio.gain_match(r, t), fs, silence_db=silence_db)


def scores(x, y, rate, silence_db=-45.0, eight=True):
    """x: CVSD input at `rate`; y: decoder integrator.  Returns the three
    scorings (see module docstring) plus the lags they used."""
    yr = audio.reconstruct(y, rate)
    _, _, lag = audio.align(x, yr)
    out = dict(lag=lag)
    out['card'] = seg_at(x, yr, rate, lag, silence_db)
    lags = sorted(set(range(lag - 2, lag + 3)) | set(range(-2, 3)))
    cand = {L: (out['card'] if L == lag else seg_at(x, yr, rate, L, silence_db)) for L in lags}
    out['lagbest'] = max(cand, key=cand.get)
    out['lagfix'] = cand[out['lagbest']]
    if eight:
        x8 = audio.resample_to(x, rate, 8000)
        y8 = audio.resample_to(yr, rate, 8000)
        r8, t8, lag8 = audio.align(x8, y8)
        out['8k'] = audio.seg_snr_db(r8, audio.gain_match(r8, t8), 8000, silence_db=silence_db)
        out['lag8'] = lag8
    return out


def codec(x, p):
    return card.decode(card.encode(x, p), p)


def pmap(fn, jobs):
    with Pool(WORKERS) as P:
        return P.map(fn, jobs, chunksize=1)


def mw(vals):
    v = np.asarray(vals, float)
    return v.mean(), v.min(), int(np.argmin(v))


# ============================================================ 1. reproduction
def _job_repro(args):
    f, rate = args
    x = card.load_talker(f, rate, SECS)
    p = card.CardParams(rate, slew=run.SLEW[rate])
    y = codec(x, p)
    s = scores(x, y, rate)
    yr = audio.reconstruct(y, rate)
    # the published pipeline as bond.py / strap.py 32 write it: the 8 kHz
    # reference is taken straight from the 16 kHz source, not from x
    a, fs = audio.read_wav(f, seconds=SECS)
    a = audio.bandlimit(a, fs)
    x8 = audio.resample_to(a * (NOM / a.std()), fs, 8000)
    r8, t8, _ = audio.align(x8, audio.resample_to(yr, rate, 8000))
    s['8k_src'] = audio.seg_snr_db(r8, audio.gain_match(r8, t8), 8000)
    # same, but the CVSD input is itself upsampled from that 8 kHz reference
    xu = audio.resample_to(x8, 8000, rate)
    yu = audio.reconstruct(codec(xu, p), rate)
    r8, t8, _ = audio.align(x8, audio.resample_to(yu, rate, 8000))
    s['8k_up'] = audio.seg_snr_db(r8, audio.gain_match(r8, t8), 8000)
    # segSNR at the CVSD rate at fixed lags, and the correlation peak, sub-sample
    s['at'] = {L: seg_at(x, yr, rate, L) for L in (-1, 0, 1, 2)}
    n = min(len(x), 200000)
    c = signal.correlate(yr[:n] - yr[:n].mean(), x[:n] - x[:n].mean(), mode='full')
    lags = signal.correlation_lags(n, n, mode='full')
    k = int(np.argmax(np.where(np.abs(lags) <= 8, c, -np.inf)))
    y0, y1, y2 = c[k - 1], c[k], c[k + 1]
    s['frac'] = lags[k] + 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2)
    s['card_check'] = card.score(x, y, rate)
    return f, rate, s


def do_repro():
    hdr('1. REPRODUCING THE PUBLISHED PER-RATE FIGURES  (run.SLEW 7000/12000/16000)')
    sub('card.py against cvsd.py at the per-rate slews (talker5, 30 s)')
    for rate in RATES:
        x = card.load_talker('talker5.wav', rate, SECS)
        rp = run.params(rate)
        cp = card.CardParams(rate, slew=run.SLEW[rate])
        rb, cb = cvsd.encode(x, rp), card.encode(x, cp)
        same = np.array_equal(rb, cb) and np.array_equal(cvsd.decode(rb, rp), card.decode(cb, cp))
        print(f'  {rate // 1000:2d}k  slew {run.SLEW[rate]:5.0f}: bits and decoder output identical: {same}')

    res = pmap(_job_repro, [(f, r) for r in RATES for f in TALKERS])
    R = {(f, r): s for f, r, s in res}
    assert all(abs(s['card'] - s['card_check']) < 1e-12 for s in R.values())

    sub('seven talkers, 30 s: mean / worst talker, dB')
    pipes = [('card', 'card.score (reconstruct, align, segSNR at CVSD rate)'),
             ('8k_src', 'published: recon -> 8 kHz vs source -> 8 kHz'),
             ('8k', 'recon -> 8 kHz vs CVSD input -> 8 kHz'),
             ('8k_up', 'CVSD input upsampled from the 8 kHz reference'),
             ('lagfix', 'card.score, lag re-chosen (+-2 of align and of 0)')]
    print(f'  {"pipeline":52s}' + ''.join(f'{r // 1000:>9d}k mean/worst' for r in RATES))
    print(f'  {"published (spec 11.1, family.md 3)":52s}' +
          ''.join(f'{PUBLISHED[r][0]:>12.2f} / {PUBLISHED[r][1]:5.2f}' for r in RATES))
    for key, name in pipes:
        row = ''
        for r in RATES:
            m, w, _ = mw([R[(f, r)][key] for f in TALKERS])
            row += f'{m:>12.2f} / {w:5.2f}'
        print(f'  {name:52s}{row}')

    sub('per talker: the lag audio.align picks at the CVSD rate, and segSNR at fixed lags')
    print(f'  {"":6s} {"talker":7s} {"align lag":>9s} {"corr peak":>9s} '
          f'{"lag -1":>7s} {"lag 0":>7s} {"lag +1":>7s} {"lag +2":>7s} {"card":>7s} {"8k":>7s}')
    for r in RATES:
        for i, f in enumerate(TALKERS):
            s = R[(f, r)]
            print(f'  {r // 1000:4d}k  t{i + 1:<6d} {s["lag"]:9d} {s["frac"]:9.2f} ' +
                  ' '.join(f'{s["at"][L]:7.2f}' for L in (-1, 0, 1, 2)) +
                  f' {s["card"]:7.2f} {s["8k"]:7.2f}')
    n1 = sum(1 for s in R.values() if s['lag'] != 0)
    print(f'\n  audio.align chose a lag other than 0 in {n1} of {len(R)} cases; '
          f'lag 0 is the best segSNR lag in '
          f'{sum(1 for s in R.values() if max(s["at"], key=s["at"].get) == 0)} of {len(R)}.')
    d = np.array([s['8k'] - s['lagfix'] for s in R.values()])
    print(f'  8 kHz scoring minus lag-fixed scoring at the CVSD rate: '
          f'mean {d.mean():+.2f} dB, range {d.min():+.2f} .. {d.max():+.2f} dB')


# ============================================================== 2. trim sweep
def _job_sweep(args):
    f, rate, slews = args
    x = card.load_talker(f, rate, SECS)
    out = {}
    for slew in slews:
        y = codec(x, card.CardParams(rate, slew=float(slew)))
        s = scores(x, y, rate)
        out[slew] = {k: s[k] for k in ('card', 'lagfix', '8k', 'lag', 'lagbest')}
    return f, rate, out


def sweep_table(S, key, slews):
    print(f'  {"slew":>6s} ' + ''.join(f'{r // 1000:>9d}k mean  worst' for r in RATES))
    for slew in slews:
        row = f'  {slew:6d}' + ('*' if slew in EXTRA else ' ')
        for r in RATES:
            m, w, _ = mw([S[(f, r)][slew][key] for f in TALKERS])
            row += f'{m:>16.2f} {w:6.2f}'
        print(row)
    for stat in ('mean', 'worst'):
        row = f'  {"best " + stat:>11s}'
        for r in RATES:
            v = {s: mw([S[(f, r)][s][key] for f in TALKERS])[0 if stat == 'mean' else 1] for s in slews}
            b = max(v, key=v.get)
            row += f'  {v[b]:6.2f} @ {b:<5d}    '
        print(row)


def regret(S, key, slews):
    """For each slew: loss against each rate's own best, on mean and on worst."""
    best = {}
    for r in RATES:
        for j, stat in enumerate(('mean', 'worst')):
            best[(r, stat)] = max(mw([S[(f, r)][s][key] for f in TALKERS])[j] for s in slews)
    rows = {}
    for s in slews:
        L = {}
        for r in RATES:
            m, w, _ = mw([S[(f, r)][s][key] for f in TALKERS])
            L[(r, 'mean')] = best[(r, 'mean')] - m
            L[(r, 'worst')] = best[(r, 'worst')] - w
        rows[s] = L
    return rows


def pitch(f):
    """Median F0 of loud voiced frames: normalised unbiased autocorrelation of
    the RAW source (the 300 Hz band edge removes most male fundamentals),
    50 ms frames at 8 kHz, 60-450 Hz, voiced if the peak exceeds 0.6."""
    a, fs = audio.read_wav(f, seconds=SECS)
    x8 = audio.resample_to(a - a.mean(), fs, 8000)
    fw, out, rms = 400, [], x8.std()
    for k in range(0, len(x8) - fw, fw // 2):
        seg = x8[k:k + fw] - x8[k:k + fw].mean()
        if seg.std() < rms:
            continue
        ac = np.correlate(seg, seg, 'full')[fw - 1:]
        ac = ac / (ac[0] * (fw - np.arange(fw)) / fw)
        lo, hi = 8000 // 450, 8000 // 60
        m = lo + int(np.argmax(ac[lo:hi]))
        if ac[m] > 0.6:
            out.append(8000 / m)
    return float(np.median(out))


def talker_features(f, rate=32000):
    """Input statistics at nominal level, prepared as the card sees them."""
    x = card.load_talker(f, rate, SECS)
    w = int(0.02 * rate)
    n = len(x) // w * w
    fr = 10 * np.log10((x[:n].reshape(-1, w) ** 2).mean(1) + 1e-20)
    act = fr > -45.0
    active_rms = np.sqrt(np.mean(10 ** (fr[act] / 10)))
    F, P = signal.welch(x, rate, nperseg=4096)
    band = (F >= 300) & (F <= 3400)
    centroid = float((F[band] * P[band]).sum() / P[band].sum())
    hi = float(P[(F >= 1500) & (F <= 3400)].sum() / P[band].sum())
    slope = np.abs(np.diff(x)) * rate                   # FS / s
    return dict(crest=float(np.abs(x).max() / x.std()),
                act_db=20 * np.log10(active_rms / NOM), act_frac=float(act.mean()),
                p999=float(np.percentile(np.abs(x), 99.9) / NOM),
                centroid=centroid, hi=hi,
                slope_rms=float(np.sqrt(np.mean(slope ** 2))),
                slope999=float(np.percentile(slope, 99.9)),
                f0=pitch(f))


def _job_diag(args):
    """Where a talker loses: slope-overload indicators from the encoder's own
    nodes, and segSNR split into frames above / below the long-term rms."""
    f, rate, slew = args
    x = card.load_talker(f, rate, SECS)
    p = card.CardParams(rate, slew=float(slew))
    bits, ye, se = card.encode(x, p, internals=True)
    y = card.decode(bits, p)
    yr = audio.reconstruct(y, rate)
    s = scores(x, y, rate, eight=False)
    r, t = shift(x, yr, s['lagbest'])
    t = audio.gain_match(r, t)
    w = int(0.02 * rate)
    m = len(r) // w * w
    R = r[:m].reshape(-1, w); E = (r[:m] - t[:m]).reshape(-1, w)
    snr = np.clip(10 * np.log10((R ** 2).sum(1) / np.maximum((E ** 2).sum(1), 1e-20)), -10, 35)
    lvl = 10 * np.log10((R ** 2).mean(1) + 1e-20)
    loud = lvl > 20 * np.log10(NOM)                      # frames above the long-term rms
    quiet = (lvl > -45) & ~loud
    step_max = slew / rate
    behind = float((np.abs(x - ye) > step_max).mean())    # more than one full step behind
    fast = float((np.abs(np.diff(x)) * rate > slew).mean())   # input slope beyond the trim
    return f, rate, dict(behind=behind, fast=fast, loud=float(snr[loud].mean()),
                         quiet=float(snr[quiet].mean()), nloud=float(loud.mean()),
                         seg=s['lagfix'])


def do_sweep():
    global TRIM
    hdr('2. ONE TRIM AT EVERY RATE  (7 talkers, 30 s, nominal level)')
    t0 = time.time()
    grid = tuple(sorted(SLEWS + EXTRA))
    res = pmap(_job_sweep, [(f, r, grid) for r in RATES for f in TALKERS])
    S = {(f, r): o for f, r, o in res}
    print(f'  {len(grid)} slews x {len(RATES)} rates x {len(TALKERS)} talkers in {time.time() - t0:.0f} s')
    print(f'  (* = extra slews beyond the requested grid; "best" rows use the whole grid)')
    for key, name in (('card', 'card.score, as specified'),
                      ('lagfix', 'lag-fixed (card.score with the lag re-chosen)'),
                      ('8k', 'scored at 8 kHz (the published pipeline)')):
        sub(f'segSNR, dB -- {name}')
        sweep_table(S, key, grid)

    sub('talkers (of 7) where audio.align picked lag != 0, and where the best-segSNR lag != 0')
    print(f'  {"slew":>6s}' + ''.join(f'{r // 1000:>5d}k align best' for r in RATES))
    for s in grid:
        print(f'  {s:6d}' + ''.join(f'{sum(S[(f, r)][s]["lag"] != 0 for f in TALKERS):11d}'
                                    f'{sum(S[(f, r)][s]["lagbest"] != 0 for f in TALKERS):5d}' for r in RATES))

    choice = {}
    for key in ('card', 'lagfix', '8k'):
        sub(f'loss against each rate\'s own best, dB  [{key}]')
        G = regret(S, key, grid)
        print(f'  {"slew":>6s}' + ''.join(f'{r // 1000:>5d}k mean worst' for r in RATES) +
              f'{"max mean":>10s}{"max worst":>10s}')
        for s in grid:
            L = G[s]
            print(f'  {s:6d}' + ('*' if s in EXTRA else ' ') + ''.join(f'{L[(r, "mean")]:10.2f}{L[(r, "worst")]:6.2f}' for r in RATES) +
                  f'{max(L[(r, "mean")] for r in RATES):10.2f}{max(L[(r, "worst")] for r in RATES):10.2f}')
        mm = min(grid, key=lambda s: max(G[s][(r, 'mean')] for r in RATES))
        mwst = min(grid, key=lambda s: max(G[s][(r, 'worst')] for r in RATES))
        both = min(grid, key=lambda s: max(max(G[s][(r, 'mean')], G[s][(r, 'worst')]) for r in RATES))
        print(f'  minimax loss on mean: {mm}   on worst talker: {mwst}   on both: {both} '
              f'(max loss {max(max(G[both][(r, "mean")], G[both][(r, "worst")]) for r in RATES):.2f} dB)')
        choice[key] = (both, G)

    TRIM = float(choice['lagfix'][0])
    G = choice['lagfix'][1]
    sub(f'recommended single trim (lag-fixed scoring, minimax loss on mean and worst): {TRIM:.0f}')
    for r in RATES:
        v = {s: mw([S[(f, r)][s]['lagfix'] for f in TALKERS]) for s in grid}
        bm = max(grid, key=lambda s: v[s][0]); bw = max(grid, key=lambda s: v[s][1])
        m, w, iw = v[int(TRIM)]
        print(f'  {r // 1000:2d}k at {TRIM:.0f}: mean {m:5.2f}  worst {w:5.2f} (talker{iw + 1});  '
              f'own best mean {v[bm][0]:5.2f} @ {bm}, worst {v[bw][1]:5.2f} @ {bw};  '
              f'cost {G[int(TRIM)][(r, "mean")]:.2f} / {G[int(TRIM)][(r, "worst")]:.2f} dB')
    for r in RATES:
        m, w, iw = mw([S[(f, r)][12000]['lagfix'] for f in TALKERS])
        print(f'  {r // 1000:2d}k at 12000 (as built): mean {m:5.2f}  worst {w:5.2f} (talker{iw + 1});  '
              f'cost {G[12000][(r, "mean")]:.2f} / {G[12000][(r, "worst")]:.2f} dB')

    sub('per talker at the recommended trim, lag-fixed segSNR, dB')
    print(f'  {"rate":>5s} ' + ' '.join(f'{"t" + str(i + 1):>7s}' for i in range(len(TALKERS))))
    for r in RATES:
        print(f'  {r // 1000:4d}k ' + ' '.join(f'{S[(f, r)][int(TRIM)]["lagfix"]:7.2f}' for f in TALKERS))

    sub('slew range within 1 dB of each rate\'s best (lag-fixed; log-interpolated; "<"/">" = grid end)')
    for r in RATES:
        row = f'  {r // 1000:2d}k'
        for stat, j in (('mean', 0), ('worst', 1)):
            vals = [mw([S[(f, r)][s]['lagfix'] for f in TALKERS])[j] for s in grid]
            lo, hi, lo_o, hi_o, pk, pv = span(np.log10(grid), vals, 1.0)
            row += (f'   {stat}: {"<" if lo_o else ""}{10 ** lo:6.0f} .. {">" if hi_o else ""}{10 ** hi:6.0f}'
                    f' (best {pv:5.2f} @ {10 ** pk:.0f})')
        print(row)

    sub('a rate strap: the best trim for each rate on its own, and what it buys over one trim')
    print(f'  {"rate":>5s} {"strap trim":>11s} {"its loss mean/worst":>20s} '
          f'{"one trim " + str(int(TRIM)):>16s} {"12000 as built":>16s}')
    for r in RATES:
        own = min(grid, key=lambda s: max(G[s][(r, 'mean')], G[s][(r, 'worst')]))
        print(f'  {r // 1000:4d}k {own:11d} {G[own][(r, "mean")]:10.2f} / {G[own][(r, "worst")]:4.2f} '
              f'{G[int(TRIM)][(r, "mean")]:9.2f} / {G[int(TRIM)][(r, "worst")]:4.2f} '
              f'{G[12000][(r, "mean")]:9.2f} / {G[12000][(r, "worst")]:4.2f}')
    for r_tr, r_on in ((16000, 64000), (64000, 16000)):
        own = min(grid, key=lambda s: max(G[s][(r_tr, 'mean')], G[s][(r_tr, 'worst')]))
        print(f'  mis-strap: the {r_tr // 1000}k trim ({own}) at {r_on // 1000}k costs '
              f'{G[own][(r_on, "mean")]:.2f} / {G[own][(r_on, "worst")]:.2f} dB')

    sub('per talker, lag-fixed segSNR, dB')
    print(f'  {"rate":>5s} {"slew":>6s} ' + ' '.join(f'{"t" + str(i + 1):>6s}' for i in range(len(TALKERS))))
    for r in RATES:
        for sl in sorted({12000, int(TRIM)}):
            print(f'  {r // 1000:4d}k {sl:6d} ' + ' '.join(f'{S[(f, r)][sl]["lagfix"]:6.2f}' for f in TALKERS))

    sub('why: talker input statistics at nominal level (30 s, prepared at 32 kHz)')
    feats = pmap(talker_features, TALKERS)
    print(f'  {"":4s} {"crest":>6s} {"p99.9":>6s} {"active":>7s} {"act lvl":>8s} {"centroid":>9s} '
          f'{">1.5k":>6s} {"rms slope":>10s} {"p99.9 slope":>12s} {"F0":>5s}')
    print(f'  {"":4s} {"pk/rms":>6s} {"/rms":>6s} {"frames":>7s} {"re rms":>8s} {"Hz":>9s} '
          f'{"share":>6s} {"FS/s":>10s} {"FS/s":>12s} {"Hz":>5s}')
    for i, ft in enumerate(feats):
        print(f'  t{i + 1:<3d} {ft["crest"]:6.1f} {ft["p999"]:6.2f} {ft["act_frac"]:7.0%} '
              f'{ft["act_db"]:+8.2f} {ft["centroid"]:9.0f} {ft["hi"]:6.1%} '
              f'{ft["slope_rms"]:10.0f} {ft["slope999"]:12.0f} {ft["f0"]:5.0f}')
    print('  active frames: 20 ms frames above -45 dBFS; act lvl: their rms re the 0.15 long-term rms;')
    print('  centroid and >1.5k share within 300-3400 Hz; slope |dx/dt| at the CVSD input.')
    diag = pmap(_job_diag, [(f, r, int(TRIM)) for r in RATES for f in TALKERS])
    D = {(f, r): d for f, r, d in diag}
    print(f'\n  at slew {int(TRIM)}: behind = time the encoder integrator is more than one full step')
    print(f'  (slew/rate) from the input; fast = time |dx/dt| exceeds the slew; loud / quiet =')
    print(f'  lag-fixed segSNR over frames above / below the long-term rms (quiet: > -45 dBFS)')
    print(f'  {"":4s}' + ''.join(f'{r // 1000:>4d}k behind  fast  loud quiet' for r in RATES))
    for i, f in enumerate(TALKERS):
        print(f'  t{i + 1:<3d}' + ''.join(f'{D[(f, r)]["behind"]:12.2%}{D[(f, r)]["fast"]:6.2%}'
                                          f'{D[(f, r)]["loud"]:6.1f}{D[(f, r)]["quiet"]:6.1f}' for r in RATES))
    print(f'  frames above the long-term rms: ' +
          ', '.join(f't{i + 1} {D[(f, 32000)]["nloud"]:.0%}' for i, f in enumerate(TALKERS)))
    segs = {r: np.array([S[(f, r)][int(TRIM)]['lagfix'] for f in TALKERS]) for r in RATES}

    def rank_corr(a, b):
        ra = np.argsort(np.argsort(a)); rb = np.argsort(np.argsort(b))
        return float(np.corrcoef(ra, rb)[0, 1])
    print('\n  Spearman rank correlation with per-talker segSNR at this trim (7 talkers: weak evidence)')
    names = [('crest', 'crest'), ('p999', 'p99.9/rms'), ('act_db', 'active level'),
             ('centroid', 'centroid'), ('hi', '>1.5k share'), ('slope_rms', 'rms slope'),
             ('slope999', 'p99.9 slope'), ('f0', 'F0')]
    print(f'  {"":14s}' + ''.join(f'{r // 1000:>7d}k' for r in RATES))
    for k, nm in names:
        v = np.array([ft[k] for ft in feats])
        print(f'  {nm:14s}' + ''.join(f'{rank_corr(v, segs[r]):8.2f}' for r in RATES))
    for k in ('behind', 'loud', 'quiet'):
        print(f'  {k:14s}' + ''.join(
            f'{rank_corr(np.array([D[(f, r)][k] for f in TALKERS]), segs[r]):8.2f}' for r in RATES))
    return S


# ================================================================== 3. level
LEVELS = tuple(range(-30, 13)) + (14, 16, 18, 20, 24)    # past +12 only to close open ranges


def _job_level(args):
    f, rate, slew = args
    out = {}
    p = card.CardParams(rate, slew=slew)
    for L in LEVELS:
        x = card.load_talker(f, rate, SECS, level_db=float(L))
        yr = audio.reconstruct(codec(x, p), rate)
        _, _, lag = audio.align(x, yr)
        lags = sorted(set(range(lag - 2, lag + 3)) | set(range(-2, 3)))
        fixed = {k: seg_at(x, yr, rate, k) for k in lags}
        best = max(fixed, key=fixed.get)
        rel = {k: seg_at(x, yr, rate, k, silence_db=-45.0 + L) for k in lags}
        out[L] = dict(card=fixed[lag], lagfix=fixed[best], rel=max(rel.values()),
                      lag=lag, best=best)
    return f, rate, out


def span(levels, vals, drop):
    """Contiguous level range around the peak within `drop` dB, interpolated."""
    v = np.asarray(vals); lv = np.asarray(levels, float)
    k = int(np.argmax(v)); thr = v[k] - drop
    i = k
    while i > 0 and v[i - 1] >= thr:
        i -= 1
    lo = lv[i] if i == 0 else lv[i - 1] + (thr - v[i - 1]) / (v[i] - v[i - 1]) * (lv[i] - lv[i - 1])
    lo_open = i == 0 and v[0] >= thr
    j = k
    while j < len(v) - 1 and v[j + 1] >= thr:
        j += 1
    hi = lv[j] if j == len(v) - 1 else lv[j] + (v[j] - thr) / (v[j] - v[j + 1]) * (lv[j + 1] - lv[j])
    hi_open = j == len(v) - 1 and v[-1] >= thr
    return lo, hi, lo_open, hi_open, lv[k], v[k]


def do_level(slew):
    hdr(f'3. segSNR AGAINST INPUT LEVEL  (slew {slew:.0f}, 7 talkers, 30 s, 0 dB = 0.15 rms FS)')
    print('  card    card.score as specified (silence threshold fixed at -45 dBFS)')
    print('  lagfix  lag re-chosen, threshold fixed at -45 dBFS')
    print('  rel     lag checked, threshold moved with the level (-45 dB + level): the SAME')
    print('          frames are scored at every level, so this is the level sensitivity')
    sub('the trim is a level: CVSD with a leaky integrator is scale-invariant')
    print('  Scaling the input by k and every step by k scales the whole loop by k, so slew S')
    print('  at level L is the same codec as slew S*10^(-L/20) at level 0.  Checked directly:')
    for f, r, L in (('talker5.wav', 32000, 20 * np.log10(12000 / 16000)),
                    ('talker2.wav', 16000, 20 * np.log10(8500 / 16000)),
                    ('talker1.wav', 64000, 20 * np.log10(22000 / 16000))):
        k = 10 ** (L / 20)
        x = card.load_talker(f, r, SECS)
        a = card.encode(x * k, card.CardParams(r, slew=16000.0))
        b = card.encode(x, card.CardParams(r, slew=16000.0 / k))
        sa = scores(x * k, card.decode(a, card.CardParams(r, slew=16000.0)), r,
                    silence_db=-45.0 + L, eight=False)['lagfix']
        sb = scores(x, card.decode(b, card.CardParams(r, slew=16000.0 / k)), r, eight=False)['lagfix']
        print(f'  {f} {r // 1000}k: level {L:+.2f} dB at slew 16000 vs level 0 at slew '
              f'{16000 / k:.0f}: bits identical {np.mean(a == b):.4%}, segSNR {sa:.2f} vs {sb:.2f} dB')

    res = pmap(_job_level, [(f, r, slew) for r in RATES for f in TALKERS])
    V = {(f, r): o for f, r, o in res}
    nz = sum(1 for o in V.values() for L in LEVELS if o[L]['best'] != 0)
    nl = sum(1 for o in V.values() for L in LEVELS if o[L]['lag'] != 0)
    print(f'\n  over {len(V) * len(LEVELS)} runs: audio.align chose lag != 0 in {nl}; best-segSNR lag != 0 in {nz}')
    for r in RATES:
        sub(f'{r // 1000} kbps')
        print(f'  {"level":>6s} {"card mean":>10s} {"worst":>6s} {"lagfix mean":>12s} {"worst":>6s} '
              f'{"rel mean":>9s} {"worst":>6s}')
        for L in LEVELS:
            c = mw([V[(f, r)][L]['card'] for f in TALKERS])
            g = mw([V[(f, r)][L]['lagfix'] for f in TALKERS])
            e = mw([V[(f, r)][L]['rel'] for f in TALKERS])
            print(f'  {L:+6d} {c[0]:10.2f} {c[1]:6.2f} {g[0]:12.2f} {g[1]:6.2f} {e[0]:9.2f} {e[1]:6.2f}')
    sub('peak and range within 1 dB / 3 dB of peak, dB re nominal (interpolated; ">" = open end)')
    for key in ('rel', 'lagfix', 'card'):
        print(f'  [{key}]')
        for r in RATES:
            for stat, j in (('mean', 0), ('worst', 1)):
                vals = [mw([V[(f, r)][L][key] for f in TALKERS])[j] for L in LEVELS]
                row = f'    {r // 1000:2d}k {stat:5s}'
                for drop in (1.0, 3.0):
                    lo, hi, lo_o, hi_o, pk, pv = span(LEVELS, vals, drop)
                    row += (f'  within {drop:.0f} dB: {"<" if lo_o else ""}{lo:+6.1f} .. '
                            f'{">" if hi_o else ""}{hi:+5.1f} ({hi - lo:4.1f} dB)')
                print(row + f'   peak {pv:5.2f} dB at {pk:+.0f}')
    return V


# ================================================================== 4. swing
SWING_LEVELS = (0.0, 6.0, 10.0)
PCT = (99.0, 99.9, 99.99)


def _job_swing(args):
    rate, level, slew = args
    xs, ye, yd, sy, sd, cmp_in, yo = [], [], [], [], [], [], []
    ident = True
    for f in TALKERS:
        x = card.load_talker(f, rate, SECS, level_db=level)
        p = card.CardParams(rate, slew=slew)
        bits, y_enc, s_enc = card.encode(x, p, internals=True)
        y_dec, s_dec = card.decode(bits, p, internals=True)
        ident &= bool(np.array_equal(y_enc, y_dec) and np.array_equal(s_enc, s_dec))
        xs.append(np.abs(x).astype(np.float32))
        ye.append(np.abs(y_enc).astype(np.float32))
        yd.append(np.abs(y_dec).astype(np.float32))
        sy.append(s_enc.astype(np.float32))
        sd.append(s_dec.astype(np.float32))
        prev = np.concatenate(([0.0], y_enc[:-1]))           # what the comparator sees
        cmp_in.append(np.abs(x - prev).astype(np.float32))
        yo.append(np.abs(audio.reconstruct(y_dec, rate)).astype(np.float32))
    cat = lambda z: np.concatenate(z)
    out = dict(ident=ident)
    for nm, arr in (('input', xs), ('enc int', ye), ('dec int', yd), ('comparator in', cmp_in),
                    ('recon out', yo)):
        a = cat(arr)
        out[nm] = [float(np.percentile(a, q)) for q in PCT] + [float(a.max())]
    for nm, arr in (('enc syl', sy), ('dec syl', sd)):
        a = cat(arr)
        out[nm] = dict(mean=float(a.mean()), median=float(np.median(a)),
                       p90=float(np.percentile(a, 90)), p99=float(np.percentile(a, 99)),
                       p9999=float(np.percentile(a, 99.99)), max=float(a.max()),
                       lt05=float((a < 0.05).mean()), lt25=float((a < 0.25).mean()))
    return rate, level, out


def do_swing(slew):
    hdr(f'4. SWINGS  (slew {slew:.0f}; |value| percentiles in FS, 7 talkers x 30 s pooled)')
    print('  Whole clips including pauses.  "comparator in" is x[n] - y[n-1], the difference')
    print('  the encoder decides on.  "recon out" is audio.reconstruct of the decoder')
    print('  integrator before any gain; the card\'s output stage scales it.')
    res = pmap(_job_swing, [(r, L, slew) for r in RATES for L in SWING_LEVELS])
    W = {(r, L): o for r, L, o in res}
    for r in RATES:
        sub(f'{r // 1000} kbps   (step_max {slew / r:.3f} FS/bit, step_min {slew / r / 10 ** 1.5:.4f} FS/bit)')
        print(f'  {"node":14s} {"level":>6s} {"p99":>7s} {"p99.9":>7s} {"p99.99":>7s} {"max":>7s}')
        for nm in ('input', 'enc int', 'dec int', 'comparator in', 'recon out'):
            for L in SWING_LEVELS:
                v = W[(r, L)][nm]
                print(f'  {nm:14s} {L:+6.0f} ' + ' '.join(f'{z:7.3f}' for z in v))
        print(f'  encoder and decoder nodes bit-identical at every level: '
              f'{all(W[(r, L)]["ident"] for L in SWING_LEVELS)}')
        print(f'\n  {"syllabic node":14s} {"level":>6s} {"mean":>6s} {"median":>7s} {"p90":>6s} '
              f'{"p99":>6s} {"p99.99":>7s} {"max":>6s} {"<0.05":>7s} {"<0.25":>7s}')
        for L in SWING_LEVELS:
            s = W[(r, L)]['enc syl']
            print(f'  {"enc = dec":14s} {L:+6.0f} {s["mean"]:6.3f} {s["median"]:7.3f} {s["p90"]:6.3f} '
                  f'{s["p99"]:6.3f} {s["p9999"]:7.3f} {s["max"]:6.3f} {s["lt05"]:7.1%} {s["lt25"]:7.1%}')
    return W


# ================================================================== 5. tones
TONE_F = (300.0, 1004.0, 2000.0, 3400.0)
TONE_SECS = 2.0


def tone_fit(y, f, rate, secs):
    """Least-squares fundamental amplitude over the last `secs` (steady state)."""
    n = int(secs * rate)
    t = np.arange(len(y))[-n:] / rate
    A = np.stack([np.sin(2 * np.pi * f * t), np.cos(2 * np.pi * f * t), np.ones_like(t)], 1)
    c, *_ = np.linalg.lstsq(A, y[-n:], rcond=None)
    fund = A @ c
    res = y[-n:] - fund
    amp = float(np.hypot(c[0], c[1]))
    return amp, 10 * np.log10(np.mean((fund - c[2]) ** 2) / max(np.mean(res ** 2), 1e-30))


def _job_tone(args):
    rate, f, slew, amps = args
    p = card.CardParams(rate, slew=slew)
    n = int(TONE_SECS * rate)
    t = np.arange(n) / rate
    rows = []
    for a in amps:
        x = a * np.sin(2 * np.pi * f * t)
        bits, ye, se = card.encode(x, p, internals=True)
        yr = audio.reconstruct(card.decode(bits, p), rate)
        xr = audio.reconstruct(x, rate)                  # same filter on the reference
        g_out, sinad = tone_fit(yr, f, rate, 1.0)
        g_ref, _ = tone_fit(xr, f, rate, 1.0)
        m = int(1.0 * rate)
        rows.append(dict(a=a, gain=g_out / g_ref, sinad=sinad,
                         syl=float(np.percentile(se[-m:], 50)),
                         err=float(np.abs(x[-m:] - ye[-m:]).max())))
    return rate, f, rows


def do_tones(slew):
    hdr(f'5. TONES AND IDLE CHANNEL  (slew {slew:.0f})')
    print('  Each tone runs 2 s; the last 1 s is fitted by least squares at the known frequency,')
    print('  on the reconstructed decoder output and on the equally reconstructed input.')
    print('  gain = output fundamental / input fundamental.  Slope overload makes the output a')
    print('  slew-limited triangle, so above onset the gain falls exactly 1 dB per dB.')
    print('  Criterion: A_1dB is the LARGEST amplitude whose gain is within 1 dB of the')
    print('  small-signal gain g0 (median gain from A_theory -30 dB to A_theory -6 dB); every')
    print('  louder amplitude on the 0.25 dB grid is compressed by more.  spread = p10..p90 of')
    print('  gain over that small-signal range: large spread = no linear region to compress from.')
    print('  A_theory = slew / (2 pi f), the ideal bound.  half-period = rate / 2f in bits.')
    amps = 10 ** (np.arange(-40, 26.01, 0.25) / 20)       # -40 .. +26 dB FS peak, 0.25 dB
    res = pmap(_job_tone, [(r, f, slew, amps) for r in RATES for f in TONE_F])
    T = {(r, f): rows for r, f, rows in res}
    print(f'\n  {"rate":>5s} {"freq":>6s} {"half-per":>8s} {"A_theory":>9s} {"g0":>6s} {"spread":>7s} '
          f'{"A_1dB":>7s} {"re theory":>10s} {"A_3dB":>7s} {"max out":>8s} {"SINAD@1dB":>10s} {"syl@1dB":>8s}')
    summary = {}
    for r in RATES:
        for f in TONE_F:
            rows = T[(r, f)]
            at = slew / (2 * np.pi * f)
            a_arr = np.array([z['a'] for z in rows])
            gdb = 20 * np.log10(np.array([z['gain'] for z in rows]))
            small = (a_arr >= at * 10 ** (-30 / 20)) & (a_arr <= at * 10 ** (-6 / 20))
            g0 = float(np.median(gdb[small]))
            spread = float(np.percentile(gdb[small], 90) - np.percentile(gdb[small], 10))
            i1 = int(np.where(gdb >= g0 - 1.0)[0].max())
            i3 = int(np.where(gdb >= g0 - 3.0)[0].max())
            top = i1 == len(rows) - 1
            out_max = float(np.max(a_arr * 10 ** (gdb / 20)))
            summary[(r, f)] = (a_arr[i1], top)
            print(f'  {r // 1000:4d}k {f:6.0f} {r / (2 * f):8.1f} {at:9.3f} {g0:+6.1f} {spread:7.1f} '
                  f'{">" if top else " "}{a_arr[i1]:6.3f} {20 * np.log10(a_arr[i1] / at):+9.1f}dB '
                  f'{a_arr[i3]:7.3f} {out_max:8.3f} {rows[i1]["sinad"]:9.1f}dB {rows[i1]["syl"]:8.2f}')
    print('  max out = largest fitted output fundamental at any amplitude, FS (same gain basis)')
    print('\n  A_1dB in dB re nominal speech rms (0.15 FS): as a peak, and as the rms of that sine')
    print(f'  {"rate":>5s}' + ''.join(f'{f:>14.0f} Hz' for f in TONE_F))
    for r in RATES:
        print(f'  {r // 1000:4d}k' + ''.join(
            f'{20 * np.log10(summary[(r, f)][0] / NOM):+9.1f} pk {20 * np.log10(summary[(r, f)][0] / np.sqrt(2) / NOM):+5.1f} rms'
            for f in TONE_F))

    sub('idle channel: zero input, 30 s, first 0.5 s discarded')
    print(f'  {"rate":>5s} {"recon rms":>10s} {"re 0.15 rms":>12s} {"integrator p-p":>15s} '
          f'{"step_min":>9s} {"idle pattern":>14s}')
    for r in RATES:
        p = card.CardParams(r, slew=slew)
        n = int(SECS * r)
        bits, ye, se = card.encode(np.zeros(n), p, internals=True)
        yd = card.decode(bits, p)
        yr = audio.reconstruct(yd, r)[int(0.5 * r):]
        rms = float(np.sqrt(np.mean(yr ** 2)))
        pp = float(np.ptp(yd[int(0.5 * r):]))
        pat = ''.join(map(str, bits[-12:]))
        db = 20 * np.log10(max(rms, 1e-300) / NOM)
        print(f'  {r // 1000:4d}k {rms:10.2e} {db:+11.1f}dB {pp:15.2e} {slew / r / 10 ** 1.5:9.4f} {pat:>14s}')
    return T


# ==================================================================== main
if __name__ == '__main__':
    which = [a for a in sys.argv[1:] if a.isdigit()] or ['1', '2', '3', '4', '5']
    t0 = time.time()
    if '1' in which:
        do_repro()
    if '2' in which:
        do_sweep()
    if '3' in which:
        do_level(TRIM)
    if '4' in which:
        do_swing(TRIM)
    if '5' in which:
        do_tones(TRIM)
    print(f'\n[{time.time() - t0:.0f} s]')
