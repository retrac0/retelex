"""
Which errors in the step generator are tolerance-critical when the encoder and
the decoder are on different cards?

channel-card.md 2.4 and tolerance.py perturbed three things: I_max and I_min
together (the slew, which is gain), and the syllabic and integrator RCs.  A
pilot found that I_min on its own matters much more than that picture
suggests.  A discrete step generator -- an LM13700 whose Iabc pin sits about
1.2 V above V-, fed from the syllabic node and a bias rail through resistors --
also makes errors those sweeps never tried: an additive offset on the syllabic
path (a dead zone when negative), a syllabic-path gain error, and an up/down
current mismatch.

Method.  card.py's circuit-level engine (card_fast.c), seven talkers, 30 s
each at nominal level (0.15 rms FS), at 16, 32 and 64 kbps, slew 12000 at
every rate.  Unless a section says otherwise the ENCODER is nominal and the
DECODER carries the error: the mismatch between two cards.  The reference for
every sweep is the matched pair at the same settings, talker by talker, and
two criteria are applied to the per-talker segSNR losses:

    mean    the mean over talkers of the per-talker loss (= loss of the mean)
    worst   the largest per-talker loss

A tolerance is the interval around nominal inside which the loss stays within
1 dB (or 0.5 dB), walking out from nominal and interpolating linearly at the
first crossing.  '<' or '>' means the grid ended first.

Two metrics, side by side, throughout:

    card.score   exactly as card.py computes it: reconstruction filter,
                 integer lag from the cross-correlation of the first 200 000
                 samples, least-squares gain, segmental SNR.
    best lag     the same pipeline and the same segSNR, taken at whichever of
                 lags -1, 0, +1 scores highest.

Section 0 shows why both are needed: the card engine has no delay (a
fractional-delay search peaks at exactly 0), but card.score's correlation
picks lag +1 or +2 for several talkers, costing them 3-6 dB, and the choice
flips under perturbations far too small to matter.  card.score is reported
because it is the repository's metric; tolerances are judged on best lag.

Sections
   0  matched nominal, every talker, both metrics, fractional-delay check
   1  slew_scale 0.6..1.4       decoder side (exactness), and encoder side
   2  i_min_scale alone         decoder and encoder side; the pilot repeated
   3  off, syllabic offset      decoder and encoder side; vs the I_min error it mimics
   4  ks, syllabic-path gain
   5  asym, up/down mismatch    matched / decoder only / encoder only / opposite,
                                in-band (200 Hz high-pass) and low-frequency wander
   6  tau_syl, tau_int          re-checks tolerance.py's +-20% / +-30%
   7  companding 20..40 dB      matched optimum; I_min and offset tolerance at each depth
   8  BOM corners               each card independently at the corners of
                                tau_syl, tau_int +-6%, slew +-8%, I_min +-X%, off +-0.005;
                                all 1536 pairs on 10 s clips, worst pairs re-run at 30 s
   9  summary, and how often card.score's lag disagreed with the best lag

Two worker processes (other simulations share the machine).  Results are
memoised in-process, so a trial two sections share is run once.  The full
run takes roughly an hour, most of it section 8.

Usage:  python3 card_tolerance.py [0 1 2 3 4 5 6 7 8 9 | all] [--secs S]
"""
import sys, time, itertools, dataclasses
import multiprocessing as mp
import numpy as np
from scipy import signal, fft
import audio, card, run

SECS = 30.0                     # headline clip length
CORNER_SECS = 10.0              # section 8's enumeration stage
PROCS = 2
RATES = card.RATES
TALKERS = card.TALKERS
NT = len(TALKERS)
COMP = run.BASE['companding_db']                 # 30 dB
RATIO = 10.0 ** (COMP / 20.0)                    # 31.6
I_MAX_UA = 120.0                                 # channel-card.md 2.3, slew * C_int
I_MIN_UA = I_MAX_UA / RATIO                      # 3.8 uA
OFF_PER_IMIN = RATIO - 1.0                       # one syllabic unit = 30.6 x I_min
METRICS = (('best', 'best lag'), ('score', 'card.score'))


def hdr(t):
    print('\n' + '=' * 100 + f'\n{t}\n' + '=' * 100, flush=True)


# ================================================================ measurement engine
_CLIPS, _HPREF = {}, {}


def clip(talker, rate, secs):
    k = (talker, rate, secs)
    if k not in _CLIPS:
        _CLIPS[k] = card.load_talker(talker, rate, secs)
    return _CLIPS[k]


def highpass(x, rate):
    """2nd-order 200 Hz high-pass, zero phase: a stand-in for an output
    transformer, applied to source and output alike."""
    return signal.sosfiltfilt(signal.butter(2, 200.0, btype='high', fs=rate, output='sos'), x)


def at_lag(ref, test, lag):
    """audio.align's trimming for a given lag."""
    n = min(len(ref), len(test))
    ref, test = ref[:n], test[:n]
    if lag > 0:
        test = test[lag:]; ref = ref[:len(test)]
    elif lag < 0:
        ref = ref[-lag:]; test = test[:len(ref)]
    n = min(len(ref), len(test))
    return ref[:n], test[:n]


def measure(ref, y, rate, hp=False, score=True):
    """-> (segSNR card.score, segSNR best lag, gain, lag card.score, lag best).
    With hp=False the first value is card.score(ref, y, rate) exactly; with
    score=False it is NaN and the cross-correlation is not run.
    gain is decoder output level / source level at the best lag."""
    out = audio.reconstruct(y, rate)
    if hp:
        out = highpass(out, rate)
    if score:
        r, t, lag = audio.align(ref, out)
        s_score = audio.seg_snr_db(r, audio.gain_match(r, t), rate)
    else:                                   # best lag only: skips the correlation
        lag, s_score = None, np.nan
    best = (-np.inf, 1.0, 0)
    for L in (-1, 0, 1):
        if L == lag:
            s, rr, tt = s_score, r, t
        else:
            rr, tt = at_lag(ref, out, L)
            s = audio.seg_snr_db(rr, audio.gain_match(rr, tt), rate)
        if s > best[0]:
            g = np.dot(rr, tt) / max(np.dot(tt, tt), 1e-20)
            best = (s, float(1.0 / g), L)
    return s_score, best[0], best[1], lag, best[2]


def _task(job):
    idx, (rate, ti, secs, mode, pairs) = job
    x = clip(TALKERS[ti], rate, secs)
    if mode == 'hp':
        k = (TALKERS[ti], rate, secs)
        if k not in _HPREF:
            _HPREF[k] = highpass(x, rate)
        ref = _HPREF[k]
    else:
        ref = x
    bits, out = {}, []
    for enc, dec in pairs:
        if enc not in bits:
            bits[enc] = card.encode(x, card.CardParams(rate, **dict(enc)))
        y = card.decode(bits[enc], card.CardParams(rate, **dict(dec)))
        out.append(measure(ref, y, rate, hp=(mode == 'hp'), score=(mode != 'fast')))
    return idx, out


_POOL = None
_MEMO = {}          # (rate, talker, secs, mode, enc, dec) -> measure()
_DEFAULT = {f.name: f.default for f in dataclasses.fields(card.CardParams)
            if f.default is not dataclasses.MISSING}


def pool():
    global _POOL
    if _POOL is None:
        _POOL = mp.get_context('fork').Pool(PROCS)
    return _POOL


def kw(d):
    """Canonical key: fields at the design value are dropped, so one card
    reached from two sections is one trial."""
    return tuple(sorted((k, v) for k, v in d.items() if _DEFAULT.get(k) != v))


def trials(pairs, mode='std', secs=None, rates=RATES, chunk=48):
    """pairs: [(encoder kwargs, decoder kwargs)], each run on every talker at
    every rate.  mode: 'std' both metrics, 'hp' both after the 200 Hz high-pass,
    'fast' best lag only (card.score entries NaN).  A 'std' result serves a
    'fast' request.  Returns {'best'|'score'|'gain'|'lag'|'lagbest': {rate: (len(pairs), NT)}}."""
    secs = secs or SECS
    keyed = [(kw(e), kw(d)) for e, d in pairs]
    jobs = []
    for rate in rates:
        for ti in range(NT):
            todo = sorted({p for p in keyed if (rate, ti, secs, mode) + p not in _MEMO
                           and not (mode == 'fast' and (rate, ti, secs, 'std') + p in _MEMO)})
            for c in range(0, len(todo), chunk):
                jobs.append((rate, ti, secs, mode, todo[c:c + chunk]))
    if jobs:
        t0 = time.time()
        for i, out in pool().imap_unordered(_task, list(enumerate(jobs))):
            rate, ti, _, _, todo = jobs[i]
            for p, v in zip(todo, out):
                _MEMO[(rate, ti, secs, mode) + p] = v
        print(f'  [{sum(len(j[4]) for j in jobs)} trials, {time.time() - t0:.0f} s]', flush=True)
    def get(r, ti, p):
        k = (r, ti, secs, mode) + p
        return _MEMO[k] if k in _MEMO else _MEMO[(r, ti, secs, 'std') + p]
    res = {}
    for name, col in (('score', 0), ('best', 1), ('gain', 2), ('lag', 3), ('lagbest', 4)):
        res[name] = {r: np.array([[get(r, ti, p)[col] for ti in range(NT)]
                                  for p in keyed], dtype=float) for r in rates}
    return res


def nominal(mode='std', secs=None, **common):
    """The matched pair at `common` (e.g. companding_db): {metric: {rate: (NT,)}}"""
    res = trials([(common, common)], mode=mode, secs=secs)
    return {m: {r: v[r][0] for r in RATES} for m, v in res.items()}


# ================================================================ reduction
def losses(S, S0):
    """S (n, NT), S0 (NT,) -> mean segSNR, worst-talker segSNR, loss of mean, worst per-talker loss"""
    d = S0[None, :] - S
    return S.mean(1), S.min(1), d.mean(1), d.max(1)


def edge(vals, drop, v0, crit):
    """(lo, hi): where the loss first exceeds `crit` walking out from v0; None
    where the grid ends first."""
    o = np.argsort(vals)
    v, d = np.asarray(vals, float)[o], np.asarray(drop, float)[o]
    i0 = int(np.argmin(np.abs(v - v0)))
    assert abs(v[i0] - v0) < 1e-12
    out = []
    for step in (-1, 1):
        j, x = i0 + step, None
        while 0 <= j < len(v):
            if d[j] > crit:
                a = j - step
                x = v[a] + (crit - d[a]) * (v[j] - v[a]) / (d[j] - d[a])
                break
            j += step
        out.append(x)
    return tuple(out)


def fmt_pct(lim, v, side):
    if lim is None:
        e = v.min() if side < 0 else v.max()
        return f'{"<" if side < 0 else ">"}{(e - 1) * 100:+.0f}%'
    return f'{(lim - 1) * 100:+.1f}%'


def fmt_abs(lim, v, side):
    if lim is None:
        e = v.min() if side < 0 else v.max()
        return ('<' if side < 0 else '>') + f'{e:+.3f}'
    return f'{lim:+.4f}'


CRITS = ((1.0, 'mean'), (1.0, 'worst'), (0.5, 'mean'), (0.5, 'worst'))


def tol_cells(vals, S, S0, v0, fmt):
    _, _, dm, dw = losses(S, S0)
    v = np.asarray(vals, float)
    out = []
    for crit, which in CRITS:
        lo, hi = edge(v, dm if which == 'mean' else dw, v0, crit)
        out.append(f'{fmt(lo, v, -1)}..{fmt(hi, v, +1)}')
    return out


def sweep_table(label, vals, R, R0, extra=None, vfmt='{:.3f}'):
    """For each metric, one row per value; per rate: mean, loss of mean, worst talker, worst loss."""
    for m, mname in METRICS:
        print(f'\n  [{mname}]')
        print(f'  {label:>9s}' + (f' {extra[0]:>17s}' if extra else '') + ''.join(
            f' | {r // 1000:2d}k  mean  dMean worst dWorst' for r in RATES))
        for k, v in enumerate(vals):
            line = f'  {vfmt.format(v):>9s}' + (f' {extra[1](v):>17s}' if extra else '')
            for r in RATES:
                mean, w, dm, dw = (a[k] for a in losses(R[m][r], R0[m][r]))
                line += f' | {mean:6.2f} {-dm:+6.2f} {w:5.2f} {-dw:+6.2f}'
            print(line)


def tol_table(title, vals, R, R0, v0, fmt):
    print(f'\n  {title}')
    print(f'  {"":10s} {"rate":>5s} ' + ' '.join(f'{f"{c:g} dB {w}":>19s}' for c, w in CRITS))
    for m, mname in METRICS:
        for r in RATES:
            cells = tol_cells(vals, R[m][r], R0[m][r], v0, fmt)
            print(f'  {mname:10s} {r // 1000:4d}k ' + ' '.join(f'{x:>19s}' for x in cells))


SUMMARY = []


def summarize(name, vals, R, R0, v0, fmt, note=''):
    """Tightest limits over the three rates, for the summary table."""
    v = np.asarray(vals, float)
    row = [name]
    for m, crits in (('best', CRITS), ('score', ((1.0, 'worst'),))):
        for crit, which in crits:
            los, his = [], []
            for r in RATES:
                _, _, dm, dw = losses(R[m][r], R0[m][r])
                lo, hi = edge(v, dm if which == 'mean' else dw, v0, crit)
                los.append(lo); his.append(hi)
            lo = None if all(x is None for x in los) else max(x for x in los if x is not None)
            hi = None if all(x is None for x in his) else min(x for x in his if x is not None)
            row.append(f'{fmt(lo, v, -1)}..{fmt(hi, v, +1)}')
    SUMMARY.append(row + [note])


# ================================================================ 0. nominal
def sec0():
    hdr('0. MATCHED NOMINAL  (slew 12000, 30 dB, run 3, tau_syl 6 ms, tau_int 3 ms, 0.15 rms FS, 30 s)')
    N = nominal()
    for r in RATES:
        x = clip(TALKERS[0], r, SECS)
        p = card.CardParams(r)
        y = card.decode(card.encode(x, p), p)
        assert measure(x, y, r)[0] == card.score(x, y, r)
    print('  measure()[card.score] == card.score() bit for bit: checked at every rate (talker1)')
    print(f'\n  {"":6s} {"":12s}' + ' '.join(f'{t[:-4]:>8s}' for t in TALKERS) + f' {"mean":>7s} {"worst":>7s}')
    for r in RATES:
        for m, mname in METRICS:
            print(f'  {r // 1000:4d}k  {mname:12s}' + ' '.join(f'{v:8.2f}' for v in N[m][r])
                  + f' {N[m][r].mean():7.2f} {N[m][r].min():7.2f}')
        print(f'  {"":6s}{"card.score lag":12s}' + ' '.join(f'{int(v):+8d}' for v in N['lag'][r]))
        print(f'  {"":6s}{"best lag":12s}' + ' '.join(f'{int(v):+8d}' for v in N['lagbest'][r]))
    print('\n  spec 11.1 / family.md 3 (seven.py, slews 7000/12000/16000): mean (worst) '
          '10.80 (9.02), 17.40 (14.91), 23.28 (19.69)')

    print('\n  fractional-delay check: segSNR with the output advanced by d samples (FFT phase shift,')
    print('  2000 samples trimmed each end), same gain match.  Does the engine have any delay?')
    ds = np.arange(-0.5, 1.01, 0.25)
    print(f'  {"":5s} {"talker":8s}' + ''.join(f' {d:+6.2f}' for d in ds) + '   best d')
    for r in RATES:
        for ti, t in enumerate(TALKERS):
            x = clip(t, r, SECS)
            p = card.CardParams(r)
            out = audio.reconstruct(card.decode(card.encode(x, p), p), r)
            n = len(out)
            F, f = fft.rfft(out), fft.rfftfreq(n)
            vals = []
            for d in ds:
                o = fft.irfft(F * np.exp(2j * np.pi * f * d), n)[2000:n - 2000]
                rr = x[2000:n - 2000]
                vals.append(audio.seg_snr_db(rr, audio.gain_match(rr, o), r))
            print(f'  {r // 1000:4d}k {t[:-4]:8s}' + ''.join(f' {v:6.2f}' for v in vals)
                  + f'   {ds[int(np.argmax(vals))]:+.2f}')


# ================================================================ 1. slew
SLEW_GRID = [0.6, 0.7, 0.8, 0.9, 0.92, 1.0, 1.08, 1.1, 1.2, 1.3, 1.4]


def sec1():
    hdr('1. SLEW_SCALE  (I_max and I_min together)')
    N = nominal()
    R = trials([({}, {'slew_scale': s}) for s in SLEW_GRID])
    print('  decoder carries the error.  gain = decoder output level re the nominal decoder, mean over')
    print('  talkers (best-lag fit).  |dseg| = largest per-talker segSNR change, dB, in each metric')
    print(f'  {"slew":>6s}' + ''.join(f' | {r // 1000:2d}k  gain  |dseg| best  |dseg| score' for r in RATES))
    for k, s in enumerate(SLEW_GRID):
        line = f'  {s:6.2f}'
        for r in RATES:
            g = (R['gain'][r][k] / N['gain'][r]).mean()
            line += (f' | {g:8.4f} {np.abs(R["best"][r][k] - N["best"][r]).max():11.1e}'
                     f' {np.abs(R["score"][r][k] - N["score"][r]).max():12.1e}')
        print(line)
    print('\n  exactness: decode(bits, slew x1.4) against 1.4 x decode(bits, nominal), talker1')
    for r in RATES:
        x = clip(TALKERS[0], r, SECS)
        p = card.CardParams(r)
        b = card.encode(x, p)
        y0, y1 = card.decode(b, p), card.decode(b, p.perturb(slew_scale=1.4))
        print(f'  {r // 1000:4d}k  max|y1 - 1.4 y0| / max|y0| = {np.abs(y1 - 1.4 * y0).max() / np.abs(y0).max():.1e}')

    R = trials([({'slew_scale': s}, {}) for s in SLEW_GRID])
    print('\n  encoder carries the error: identical to an input level change of -20 log10(slew) dB')
    sweep_table('slew', SLEW_GRID, R, N)
    tol_table('encoder-side slew tolerance', SLEW_GRID, R, N, 1.0, fmt_pct)
    SUMMARY.append(['slew, decoder'] + ['exact gain'] * 5 + ['no segSNR change at any value'])
    summarize('slew, encoder', SLEW_GRID, R, N, 1.0, fmt_pct, 'a level shift into the encoder')


# ================================================================ 2. I_min
IMIN_GRID = [0.5, 0.562, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0,
             1.02, 1.05, 1.1, 1.15, 1.2, 1.25, 1.5, 1.778, 2.0]


def imin_note(v):
    return f'{30 - 20 * np.log10(v):4.1f}dB {v * I_MIN_UA:5.2f}uA'


def sec2():
    hdr('2. I_MIN_SCALE ALONE  (I_max unchanged, so the companding ratio moves)')
    N = nominal()
    R = trials([({}, {'i_min_scale': v}) for v in IMIN_GRID])
    print('  decoder carries the error.  Note: the decoder\'s effective companding, and I_min at I_max = 120 uA')
    sweep_table('i_min', IMIN_GRID, R, N, extra=('comp   I_min', imin_note))
    tol_table('decoder-side I_min tolerance (change in I_min)', IMIN_GRID, R, N, 1.0, fmt_pct)
    summarize('I_min, decoder', IMIN_GRID, R, N, 1.0, fmt_pct, 'I_min alone')

    print('\n  the pilot repeated: decoder at 25 dB (x1.778) and 35 dB (x0.562), 32 kbps, loss per talker')
    for m, mname in METRICS:
        for v in (1.778, 0.562):
            k = IMIN_GRID.index(v)
            d = N[m][32000] - R[m][32000][k]
            print(f'  {mname:10s} x{v:5.3f}: ' + ' '.join(f'{x:5.2f}' for x in d)
                  + f'   mean {d.mean():.2f}  worst {d.max():.2f}')

    R = trials([({'i_min_scale': v}, {}) for v in IMIN_GRID])
    print('\n  encoder carries the error')
    sweep_table('i_min', IMIN_GRID, R, N, extra=('comp   I_min', imin_note))
    tol_table('encoder-side I_min tolerance (change in I_min)', IMIN_GRID, R, N, 1.0, fmt_pct)
    summarize('I_min, encoder', IMIN_GRID, R, N, 1.0, fmt_pct, 'I_min alone')


# ================================================================ 3. offset
OFF_GRID = [-0.1, -0.05, -0.02, -0.01, -0.0075, -0.005, -0.003, -0.002, 0.0,
            0.002, 0.003, 0.005, 0.0075, 0.01, 0.02, 0.05, 0.1]


def off_note(o):
    return f'{o * OFF_PER_IMIN * 100:+5.0f}% {o * (I_MAX_UA - I_MIN_UA):+6.2f}uA'


def sec3():
    hdr('3. OFF: ADDITIVE SYLLABIC-PATH OFFSET  (syllabic units; negative = dead zone)')
    print('  step = step_min + (step_max - step_min) * max(0, ks*syl + off).  One syllabic unit is')
    print(f'  I_max - I_min = {I_MAX_UA - I_MIN_UA:.1f} uA = {OFF_PER_IMIN:.1f} x I_min.  A positive off adds off x 30.6 of')
    print('  I_min at every syllabic level.  A negative off holds I_min until syl > |off|, then lowers every')
    print('  step by the same current; the I_min% column is that shortfall.')
    N = nominal()
    R = trials([({}, {'off': o}) for o in OFF_GRID])
    print('\n  decoder carries the error')
    sweep_table('off', OFF_GRID, R, N, extra=('I_min%      uA', off_note), vfmt='{:+.4f}')
    tol_table('decoder-side offset tolerance (syllabic units)', OFF_GRID, R, N, 0.0, fmt_abs)
    summarize('off, decoder', OFF_GRID, R, N, 0.0, fmt_abs, 'x30.6 = fraction of I_min')
    Rd = R

    R = trials([({'off': o}, {}) for o in OFF_GRID])
    print('\n  encoder carries the error')
    sweep_table('off', OFF_GRID, R, N, extra=('I_min%      uA', off_note), vfmt='{:+.4f}')
    tol_table('encoder-side offset tolerance (syllabic units)', OFF_GRID, R, N, 0.0, fmt_abs)
    summarize('off, encoder', OFF_GRID, R, N, 0.0, fmt_abs, 'x30.6 = fraction of I_min')

    pos = [0.002, 0.005, 0.01, 0.02]
    Ri = trials([({}, {'i_min_scale': 1 + OFF_PER_IMIN * o}) for o in pos])
    print('\n  is a positive offset just an I_min error?  decoder, best lag: loss of mean (worst per-talker loss)')
    print(f'  {"off":>7s} {"=I_min x":>9s}' + ''.join(f' | {r // 1000:2d}k    off          I_min    ' for r in RATES))
    for k, o in enumerate(pos):
        j = OFF_GRID.index(o)
        line = f'  {o:+7.3f} {1 + OFF_PER_IMIN * o:9.3f}'
        for r in RATES:
            a = losses(Rd['best'][r][j:j + 1], N['best'][r]); b = losses(Ri['best'][r][k:k + 1], N['best'][r])
            line += f' | {a[2][0]:5.2f} ({a[3][0]:5.2f})  {b[2][0]:5.2f} ({b[3][0]:5.2f})'
        print(line)


# ================================================================ 4. ks
KS_GRID = [0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2]


def sec4():
    hdr('4. KS: SYLLABIC-PATH GAIN  (scales the I_max - I_min span; I_min unchanged)')
    N = nominal()
    R = trials([({}, {'ks': v}) for v in KS_GRID])
    print('  decoder carries the error')
    sweep_table('ks', KS_GRID, R, N)
    tol_table('decoder-side ks tolerance', KS_GRID, R, N, 1.0, fmt_pct)
    summarize('ks, decoder', KS_GRID, R, N, 1.0, fmt_pct)


# ================================================================ 5. asym
ASYM_GRID = [0.0, 0.005, 0.01, 0.02, 0.05, 0.1]
ASYM_MODES = (('matched', lambda a: ({'asym': a}, {'asym': a})),
              ('dec only', lambda a: ({}, {'asym': a})),
              ('enc only', lambda a: ({'asym': a}, {})),
              ('opposite', lambda a: ({'asym': a}, {'asym': -a})))


def lf_wander(a_enc, a_dec, rate):
    """Largest |decoder output below 100 Hz| and largest |output|, FS, over the talkers."""
    sos = signal.butter(4, 100.0, btype='low', fs=rate, output='sos')
    lf = pk = 0.0
    for t in TALKERS:
        x = clip(t, rate, SECS)
        y = card.decode(card.encode(x, card.CardParams(rate, asym=a_enc)), card.CardParams(rate, asym=a_dec))
        lf = max(lf, np.abs(signal.sosfiltfilt(sos, y)).max())
        pk = max(pk, np.abs(y).max())
    return lf, pk


def sec5():
    hdr('5. ASYM: UP/DOWN STEP CURRENT MISMATCH  (up x(1+a), down x(1-a))')
    print('  "full" is the card.score pipeline.  "in-band" high-passes source and output alike at 200 Hz')
    print('  (2nd order, zero phase: a stand-in for the output transformer), each against its own nominal.')
    print('  LF = largest decoder output below 100 Hz, peak = largest |output|, FS, over talkers (no clipping')
    print('  is modelled; the nominal speech peak is the a = 0 row).')
    res = {}
    for name, f in ASYM_MODES:
        res[name] = (trials([f(a) for a in ASYM_GRID]), trials([f(a) for a in ASYM_GRID], mode='hp'))
    lim = {}
    for r in RATES:
        print(f'\n  {r // 1000}k   loss of mean (worst per-talker loss), dB')
        print(f'  {"mode":>9s} {"a":>6s} | {"full, card.score":>17s} | {"full, best lag":>17s} | '
              f'{"in-band, best lag":>17s} | {"LF":>6s} {"peak":>6s}')
        for name, f in ASYM_MODES:
            Rs, Rh = res[name]
            for k, a in enumerate(ASYM_GRID):
                if k == 0 and name != 'matched':
                    continue
                cells = []
                for R, m in ((Rs, 'score'), (Rs, 'best'), (Rh, 'best')):
                    _, _, dm, dw = losses(R[m][r][k:k + 1], R[m][r][0])
                    cells.append(f'{dm[0]:6.2f} ({dw[0]:6.2f})')
                e, d = f(a)
                lf, pk = lf_wander(e.get('asym', 0.0), d.get('asym', 0.0), r)
                print(f'  {name:>9s} {a:6.3f} | ' + ' | '.join(cells) + f' | {lf:6.3f} {pk:6.3f}')
    print('\n  largest a inside tolerance, tightest of the three rates, best lag')
    print(f'  {"mode":>9s} {"":8s} ' + ' '.join(f'{f"{c:g} dB {w}":>13s}' for c, w in CRITS))
    for name, _ in ASYM_MODES:
        for R, tag in ((res[name][0], 'full'), (res[name][1], 'in-band')):
            cells = []
            for crit, which in CRITS:
                his = []
                for r in RATES:
                    _, _, dm, dw = losses(R['best'][r], R['best'][r][0])
                    hi = edge(ASYM_GRID, dm if which == 'mean' else dw, 0.0, crit)[1]
                    his.append(np.inf if hi is None else hi)
                h = min(his)
                cells.append(f'>{ASYM_GRID[-1]:.1%}' if np.isinf(h) else f'{h:.2%}')
            print(f'  {name:>9s} {tag:8s} ' + ' '.join(f'{c:>13s}' for c in cells))
            if name in ('dec only', 'opposite'):
                SUMMARY.append([f'asym {name}, {tag}', f'0..{cells[0]}', f'0..{cells[1]}',
                                f'0..{cells[2]}', f'0..{cells[3]}', '', 'best lag only'])


# ================================================================ 6. tau
TAU_GRID = [0.7, 0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.3]


def sec6():
    hdr('6. TAU_SYL AND TAU_INT  (decoder carries the error; re-checks tolerance.py)')
    N = nominal()
    for field, claim in (('tau_syl_scale', 'tolerance.py: +-20%'), ('tau_int_scale', 'tolerance.py: +-30%')):
        R = trials([({}, {field: v}) for v in TAU_GRID])
        print(f'\n  {field}  ({claim})')
        sweep_table(field[:7], TAU_GRID, R, N)
        tol_table(f'decoder-side {field} tolerance', TAU_GRID, R, N, 1.0, fmt_pct)
        summarize(f'{field[:7]}, decoder', TAU_GRID, R, N, 1.0, fmt_pct, claim)


# ================================================================ 7. companding
COMP_GRID = [20.0, 22.5, 25.0, 27.5, 30.0, 32.5, 35.0, 37.5, 40.0]
COMP_IMIN = [0.5, 0.7, 0.8, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.25, 1.5, 2.0]
COMP_OFF_AT = [20.0, 25.0, 30.0, 35.0, 40.0]
COMP_OFF = [-0.05, -0.02, -0.01, -0.005, -0.002, 0.0, 0.002, 0.005, 0.01, 0.02, 0.05]


def sec7():
    hdr('7. COMPANDING DEPTH: MATCHED OPTIMUM AND MISMATCH SENSITIVITY  (slew 12000 throughout)')
    M = {c: nominal(companding_db=c) for c in COMP_GRID}
    for m, mname in METRICS:
        print(f'\n  [{mname}] matched pair, mean (worst talker)')
        print(f'  {"comp":>6s}' + ''.join(f' | {r // 1000:2d}k  mean  worst' for r in RATES))
        for c in COMP_GRID:
            print(f'  {c:6.1f}' + ''.join(f' | {M[c][m][r].mean():9.2f} {M[c][m][r].min():6.2f}' for r in RATES))
        for r in RATES:
            cm = max(COMP_GRID, key=lambda c: M[c][m][r].mean())
            cw = max(COMP_GRID, key=lambda c: M[c][m][r].min())
            print(f'  {r // 1000:4d}k  best mean at {cm:4.1f} dB: {M[cm][m][r].mean():.2f} (30 dB: {M[30.0][m][r].mean():.2f});'
                  f'   best worst talker at {cw:4.1f} dB: {M[cw][m][r].min():.2f} (30 dB: {M[30.0][m][r].min():.2f})')

    I = {c: trials([({'companding_db': c}, {'companding_db': c, 'i_min_scale': v}) for v in COMP_IMIN])
         for c in COMP_GRID}
    O = {c: trials([({'companding_db': c}, {'companding_db': c, 'off': o}) for o in COMP_OFF])
         for c in COMP_OFF_AT}
    for m, mname in METRICS:
        print(f'\n  [{mname}] decoder I_min tolerance at each companding depth (change in I_min).  uA: the')
        print('  1 dB worst-talker limits as absolute current at I_max = 120 uA')
        for r in RATES:
            print(f'  {r // 1000:2d}k {"comp":>5s} ' + ' '.join(f'{f"{c:g} dB {w}":>17s}' for c, w in CRITS)
                  + f' {"uA, 1 dB worst":>16s}')
            for c in COMP_GRID:
                cells = tol_cells(COMP_IMIN, I[c][m][r], M[c][m][r], 1.0, fmt_pct)
                lo, hi = edge(COMP_IMIN, losses(I[c][m][r], M[c][m][r])[3], 1.0, 1.0)
                imin = I_MAX_UA / 10 ** (c / 20)
                ua = (f'{"<" + format((COMP_IMIN[0] - 1) * imin, "+.2f") if lo is None else format((lo - 1) * imin, "+.2f")}..'
                      f'{">" + format((COMP_IMIN[-1] - 1) * imin, "+.2f") if hi is None else format((hi - 1) * imin, "+.2f")}')
                print(f'  {"":3s} {c:5.1f} ' + ' '.join(f'{x:>17s}' for x in cells) + f' {ua:>16s}')
        print(f'\n  [{mname}] decoder offset tolerance at each companding depth (syllabic units)')
        for r in RATES:
            print(f'  {r // 1000:2d}k {"comp":>5s} ' + ' '.join(f'{f"{c:g} dB {w}":>17s}' for c, w in CRITS))
            for c in COMP_OFF_AT:
                cells = tol_cells(COMP_OFF, O[c][m][r], M[c][m][r], 0.0, fmt_abs)
                print(f'  {"":3s} {c:5.1f} ' + ' '.join(f'{x:>17s}' for x in cells))


# ================================================================ 8. corners
DIMS_ENC = ('tau_syl_scale', 'tau_int_scale', 'slew_scale', 'i_min_scale', 'off')
DIMS_DEC = ('tau_syl_scale', 'tau_int_scale', 'i_min_scale', 'off')
TAU_TOL, SLEW_TOL, OFF_TOL = 0.06, 0.08, 0.005
X_GRID = (0.02, 0.05, 0.10)
SHORT = {'tau_syl_scale': 'Ts', 'tau_int_scale': 'Ti', 'slew_scale': 'Sl', 'i_min_scale': 'Im', 'off': 'Of'}
TOP = 4


def corner(dims, signs, x):
    tol = {'tau_syl_scale': TAU_TOL, 'tau_int_scale': TAU_TOL, 'slew_scale': SLEW_TOL, 'i_min_scale': x}
    return {d: (s * OFF_TOL if d == 'off' else 1.0 + s * tol[d]) for d, s in zip(dims, signs)}


def signs_str(dims, signs):
    return ''.join(f'{SHORT[d]}{"+" if s > 0 else "-"} ' for d, s in zip(dims, signs)).strip()


def sec8():
    hdr('8. BOM CORNERS: EACH CARD INDEPENDENTLY AT tau_syl, tau_int +-6%, slew +-8%, I_min +-X%, off +-0.005')
    print('  Encoder 2^5 = 32 corners.  Decoder 2^4 = 16: its slew is left out because section 1 shows a')
    print('  decoder slew error is an exact output gain (the loop is linear in the step currents) and both')
    print('  metrics remove gain.  512 pairs per X, 1536 in all, x 7 talkers x 3 rates.')
    print(f'  Stage 1 runs every pair on {CORNER_SECS:g} s clips, best lag only (card.score\'s correlation is the')
    print(f'  slowest step and section 0 shows it misaligns); stage 2 re-runs the worst pairs on {SECS:g} s clips')
    print('  in both metrics.')
    print('  Ts tau_syl, Ti tau_int, Sl slew, Im I_min, Of offset.  Losses are against the matched nominal pair.')
    enc_s = list(itertools.product((-1, 1), repeat=len(DIMS_ENC)))
    dec_s = list(itertools.product((-1, 1), repeat=len(DIMS_DEC)))
    prs = [(e, d) for e in enc_s for d in dec_s]
    same = np.array([e[:2] + e[3:] == d for e, d in prs])
    N1 = nominal(secs=CORNER_SECS, mode='fast')
    N30 = nominal()
    for x in X_GRID:
        pairs = [(corner(DIMS_ENC, e, x), corner(DIMS_DEC, d, x)) for e, d in prs]
        R = trials(pairs, secs=CORNER_SECS, mode='fast')
        print(f'\n  ---------------- I_min +-{x:.0%} ----------------')
        for r in RATES:
            print(f'\n  {r // 1000}k  stage 1 ({CORNER_SECS:g} s, best lag only).  nominal mean (worst talker): '
                  f'{N1["best"][r].mean():.2f} ({N1["best"][r].min():.2f})')
            for m, mname in METRICS[:1]:
                _, _, dm, dw = losses(R[m][r], N1[m][r])
                print(f'    [{mname:10s}] loss of mean: median {np.median(dm):5.2f}  90% {np.percentile(dm, 90):5.2f}'
                      f'  max {dm.max():5.2f} | worst per-talker loss: median {np.median(dw):5.2f}  max {dw.max():5.2f}'
                      f' | pairs >0.5/>1 dB: mean {np.mean(dm > 0.5):4.0%}/{np.mean(dm > 1):4.0%},'
                      f' worst {np.mean(dw > 0.5):4.0%}/{np.mean(dw > 1):4.0%}'
                      f' | same corner: max {dm[same].max():.2f} ({dw[same].max():.2f})')
            _, _, dm, dw = losses(R['best'][r], N1['best'][r])
            eff = []
            for i, dname in enumerate(DIMS_DEC):
                ei = DIMS_ENC.index(dname)
                diff = np.array([e[ei] != d[i] for e, d in prs])
                eff.append(f'{SHORT[dname]} {dm[diff].mean() - dm[~diff].mean():+.2f}')
            up = np.array([e[2] > 0 for e, d in prs])
            eff.append(f'Sl(enc + vs -) {dm[up].mean() - dm[~up].mean():+.2f}')
            hi_dec = np.array([d[2] > 0 and e[3] < 0 for e, d in prs])
            lo_dec = np.array([d[2] < 0 and e[3] > 0 for e, d in prs])
            print(f'    [best lag  ] cost of disagreeing, per dimension (loss of mean, differ - agree): '
                  + ', '.join(eff))
            print(f'    [best lag  ] I_min disagreement: decoder high/encoder low {dm[hi_dec].mean():.2f},'
                  f' decoder low/encoder high {dm[lo_dec].mean():.2f}, agree {dm[~(hi_dec | lo_dec)].mean():.2f}')

            pick = []
            for key in (dm, dw):
                for k in np.argsort(-key)[:TOP]:
                    if k not in pick:
                        pick.append(int(k))
            R30 = trials([pairs[k] for k in pick], secs=SECS, rates=(r,))
            print(f'    stage 2 ({SECS:g} s): the {TOP} worst pairs by loss of mean and by worst-talker loss (best lag).'
                  f'  nominal: best lag {N30["best"][r].mean():.2f} ({N30["best"][r].min():.2f})'
                  f', card.score {N30["score"][r].mean():.2f} ({N30["score"][r].min():.2f})')
            print(f'    {"encoder":24s} {"decoder":20s} | {"best lag: mean (worst talker)  loss (worst loss)":>50s}'
                  f' | {"card.score: mean (worst)  loss (worst loss)":>44s}')
            for j, k in enumerate(pick):
                e, d = prs[k]
                cells = []
                for m in ('best', 'score'):
                    mean, w, lm, lw = (a[j] for a in losses(R30[m][r], N30[m][r]))
                    cells.append(f'{mean:6.2f} ({w:5.2f})  {lm:5.2f} ({lw:5.2f})')
                print(f'    {signs_str(DIMS_ENC, e):24s} {signs_str(DIMS_DEC, d):20s} | {cells[0]:>50s} | {cells[1]:>44s}')
            SUMMARY.append([f'corners X={x:.0%} {r // 1000}k', '', '', '', '', '',
                            f'worst pair (30 s) best lag loss of mean '
                            f'{max(losses(R30["best"][r], N30["best"][r])[2]):.2f}, worst talker '
                            f'{max(losses(R30["best"][r], N30["best"][r])[3]):.2f}'])


# ================================================================ 9. summary
def sec9():
    hdr('9. SUMMARY  (decoder-side mismatch unless noted; tightest limit over 16/32/64 kbps)')
    print(f'  {"error":24s} {"best: 1 dB mean":>18s} {"1 dB worst":>18s} {"0.5 dB mean":>18s} {"0.5 dB worst":>18s}'
          f' {"score: 1 dB worst":>18s}   note')
    for row in SUMMARY:
        print(f'  {row[0]:24s} ' + ' '.join(f'{c:>18s}' for c in row[1:6]) + f'   {row[6]}')

    print('\n  how often did card.score align at a different lag from the best lag?  (all trials run, std pipeline)')
    for secs in sorted({k[2] for k in _MEMO}):
        line = f'  {secs:4.0f} s clips:'
        for r in RATES:
            v = [(val[3], val[4], val[1] - val[0]) for k, val in _MEMO.items() if k[0] == r and k[2] == secs and k[3] == 'std']
            if v:
                bad = [dd for a, b, dd in v if a != b]
                line += (f'   {r // 1000}k {len(bad)}/{len(v)} ({len(bad) / len(v):.0%}), costing '
                         f'{np.mean(bad) if bad else 0:.2f} dB on average')
        print(line)


SECTIONS = {'0': sec0, '1': sec1, '2': sec2, '3': sec3, '4': sec4, '5': sec5,
            '6': sec6, '7': sec7, '8': sec8, '9': sec9}

if __name__ == '__main__':
    sys.stdout.reconfigure(line_buffering=True)
    args = sys.argv[1:]
    if '--secs' in args:
        i = args.index('--secs')
        SECS = CORNER_SECS = float(args[i + 1])
        del args[i:i + 2]
        print(f'*** --secs {SECS:g}: a development run, not the reported figures ***')
    want = args or ['all']
    if 'all' in want:
        want = list(SECTIONS)
    t0 = time.time()
    for s in want:
        SECTIONS[s]()
    print(f'\ntotal {time.time() - t0:.0f} s')
