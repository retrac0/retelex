"""
The CVSD law: MIL-STD-188-113, the DNVT's, carried to 64 kbps.

mf8-spec.md 12.1 specifies the voice card's codec as the military CVSD law of
the DNVT family (TA-954, TA-1042) run at the frame's 64 kbps.  This measures
what that decision rests on:

  spec    The law, read from the standard.  188-113 quotes its compression
          ratio as the step at 30 % run-of-threes over the step at 0 %;
          cvsd.py's companding_db is FULL SCALE, 100 % over 0 %.  The
          standard's own decoder test patterns calibrate the mapping -- and
          show that the standard contradicts itself by about 6 dB.
  laws    Against the law it replaced, at 64 kbps: speech level, bit errors,
          and where the slew sits.
  rates   Is the law bit-rate specific?  One parameter at a time around it at
          16, 32 and 64 kbps: does any optimum move with the rate?
  dnvt    Can a 16 or 32 kbps DNVT be put on a 64 kbps channel in the bit
          domain?  Decimating, repeating, re-modulating, transcoding, and
          clocking the card's own codec at the DNVT's rate.

The standard's text is IRIG 106-15 Appendix F, which reproduces 188-113:
3-bit shift register with the run-of-threes algorithm; syllabic filter
5 ms +-1; reconstruction integrator 1 ms +-0.25; compression ratio 16:1,
12:1 to 21:1 (5.5); decoder reference patterns DB492 and FB412 at 16 kbps,
DB54924AB6 and FDAA10255E at 32 kbps, 0 % and 30 % run-of-threes, 800 Hz,
-24 +-1 and 0 +-1 dBm0 (Table F-1).

Scoring is mf8_line.py's: reconstruction filter, alignment, one gain match,
segSNR against the band-limited source.  Talkers 1-3, 6 s each; levels are
relative to mf8.NOMINAL_RMS; bit errors are random, at nominal level.

Usage:  python3 cvsd_law.py            everything, ~20 min on 8 cores  (cvsd_law.log is the run)
        python3 cvsd_law.py spec       the standard's patterns, and the two readings of it
        python3 cvsd_law.py laws       against the previous law at 64 kbps; the slew
        python3 cvsd_law.py rates      one parameter at a time at 16, 32 and 64 kbps
        python3 cvsd_law.py dnvt       a DNVT on a 64 kbps channel
"""
import sys, numpy as np
from multiprocessing import Pool
import audio, cvsd, mf8

TALKERS = (1, 2, 3)
SECS = 6.0
LEVELS = (-30, -20, -10, 0, 6)
BERS = (1e-3, 1e-2)
TRUNK = 64000
PREVIOUS = dict(run_length=3, tau_syl=0.006, tau_int=0.003, companding_db=30.0)
PATTERNS = {16000: {0: 'DB492', 30: 'FB412'}, 32000: {0: 'DB54924AB6', 30: 'FDAA10255E'}}


def full_scale_db(ratio, duty=0.30):
    """188-113's compression ratio (30 % over 0 % run-of-threes) as companding_db."""
    return float(20 * np.log10(1 + (ratio - 1) / duty))


def spec_ratio(companding_db, duty=0.30):
    """The inverse: cvsd.py's full-scale companding_db as 188-113's ratio."""
    return float(1 + duty * (10 ** (companding_db / 20) - 1))


def law(rate, **kw):
    """mf8.BASE at a rate, with any parameter overridden."""
    return cvsd.CVSDParams(rate=rate, slew=kw.pop('slew', mf8.SLEW[rate]), **{**mf8.BASE, **kw})


# ----------------------------------------------------------------- sources

_src = {}

def source(j, rate):
    """mf8_line.py's source: band-limited, level-normalised, at the codec rate."""
    if (j, rate) not in _src:
        x, fs = audio.read_wav(f'talker{j}.wav', seconds=SECS + 0.5)
        x = audio.bandlimit(x, fs)
        x = x * (mf8.NOMINAL_RMS / max(x.std(), 1e-9))
        _src[j, rate] = audio.resample_to(x, fs, rate)[:int(SECS * rate)]
    return _src[j, rate]


def heard(bits, p):
    """A decoder and its reconstruction filter, delivered at the trunk rate."""
    y = audio.reconstruct(cvsd.decode(bits, p), p.rate)
    return y if p.rate == TRUNK else audio.resample_to(y, p.rate, TRUNK)


def score(ref, y, fs):
    """(segSNR, output level re the source in dB) after alignment and one gain match."""
    a, b, _ = audio.align(ref, y)
    g = np.dot(a, b) / max(np.dot(b, b), 1e-20)
    return audio.seg_snr_db(a, b * g, fs), float(-20 * np.log10(abs(g) + 1e-20))


def hits(bits, ber, seed):
    if ber:
        bits = bits ^ (np.random.default_rng(seed).random(bits.size) < ber).astype(np.uint8)
    return bits


def trial(kw, rate, lv, ber):
    """Mean segSNR over the talkers for one law at one rate, level and BER."""
    p = law(rate, **dict(kw))
    s = []
    for j in TALKERS:
        x = source(j, rate) * 10 ** (lv / 20)
        y = audio.reconstruct(cvsd.decode(hits(cvsd.encode(x, p), ber, j), p), rate)
        s.append(score(x, y, rate)[0])
    return float(np.mean(s))


def grid(cells):
    """Evaluate (kw, rate, level, ber) cells in parallel; return a lookup."""
    keys = list(dict.fromkeys((tuple(sorted(kw.items())), r, lv, ber) for kw, r, lv, ber in cells))
    with Pool() as pool:
        vals = pool.starmap(trial, keys)
    table = dict(zip(keys, vals))
    return lambda kw, r, lv=0, ber=0.0: table[tuple(sorted(kw.items())), r, lv, ber]


def conditions(kw, rate):
    return [(kw, rate, lv, 0.0) for lv in LEVELS] + [(kw, rate, 0, b) for b in BERS]


def row(get, kw, rate):
    v = [get(kw, rate, lv) for lv in LEVELS]
    return v + [float(np.mean(v))] + [get(kw, rate, 0, b) for b in BERS]


HEAD = ' '.join(f'{lv:+5d}' for lv in LEVELS) + '   mean  BER 1e-3 1e-2'

def fmt(v):
    return ' '.join(f'{x:5.1f}' for x in v[:5]) + f'  {v[5]:5.1f}     {v[6]:5.1f} {v[7]:5.1f}'


# -------------------------------------------------------------------- spec

def pattern(hexs, n):
    b = np.array([int(c) for h in hexs for c in f'{int(h, 16):04b}'], dtype=np.uint8)
    return np.tile(b, n // len(b) + 1)[:n]


def tone(bits, p, f=800.0):
    """RMS of the decoder's output at f, steady state."""
    y = cvsd.decode(bits, p)[len(bits) // 2:]
    t = np.arange(len(y)) / p.rate
    return float(np.hypot(y @ np.sin(2 * np.pi * f * t), y @ np.cos(2 * np.pi * f * t))
                 * np.sqrt(2) / len(y))


def run_of_threes(bits, run=3):
    w = np.lib.stride_tricks.sliding_window_view(bits, run)
    return float((w.min(1) == w.max(1)).mean())


def pattern_db(p):
    """Table F-1's measurement: 30 % pattern output over 0 % pattern output."""
    r = p.rate
    return 20 * np.log10(tone(pattern(PATTERNS[r][30], r), p) / tone(pattern(PATTERNS[r][0], r), p))


def spec():
    print('THE STANDARD -- MIL-STD-188-113 as IRIG 106-15 App. F reproduces it')
    print('  5.5 quotes the compression ratio between the syllabic filter outputs at')
    print('  30 % and 0 % run-of-threes.  cvsd.py steps linearly in the filtered')
    print('  run-of-threes duty, so a ratio R quoted that way is 1 + (R - 1)/0.30 full')
    print('  scale:\n')
    for r in (12, 16, 21):
        print(f'    {r:2d}:1 at 30 %  =  {full_scale_db(r):4.1f} dB full scale')
    print(f'    the previous mf8 law, {PREVIOUS["companding_db"]:.0f} dB full scale  =  '
          f'{spec_ratio(PREVIOUS["companding_db"]):.1f}:1 at 30 %  (below the 12:1 minimum)')
    print(f'    mf8.BASE, {mf8.BASE["companding_db"]:.1f} dB full scale  =  '
          f'{spec_ratio(mf8.BASE["companding_db"]):.1f}:1 at 30 %\n')

    print('  Table F-1: the decoder reference patterns, decoded (800 Hz, repeating).')
    for rate, pats in PATTERNS.items():
        for k, h in pats.items():
            print(f'    {rate // 1000}k  {h:10s}  specified {k:2d} % run-of-threes, '
                  f'measured {100 * run_of_threes(pattern(h, 4000)):4.1f} %')
    print()
    print('  At one fixed step the two patterns do not give one output: the 30 %')
    print('  pattern has longer runs, so it swings further per step.')
    for rate in PATTERNS:
        for ti in (0.001, 0.003):
            d = pattern_db(law(rate, companding_db=0.0, tau_int=ti))
            print(f'    {rate // 1000}k, integrator {ti * 1e3:.0f} ms: 30 % pattern / 0 % pattern '
                  f'= {10 ** (d / 20):.2f} ({d:.1f} dB)')
    print('    3.9 of the standard implies the same thing: 16:1 in step and a 0.48')
    print('    amplitude for the 30 % step on the 0 % pattern, so 2.08 (6.4 dB).\n')

    print('  So the standard contradicts itself.  Table F-1 wants the two outputs')
    print('  24 +-2 dB apart; 5.5 wants the steps 12:1 to 21:1 apart, which with the')
    print('  pattern factor above puts the outputs about 27-32 dB apart.  No decoder')
    print('  meets both.  The two readings, as cvsd.py laws with 188-113 timing:\n')
    f1 = {}
    for rate in PATTERNS:
        lo, hi = 10.0, 45.0
        for _ in range(40):
            c = (lo + hi) / 2
            lo, hi = (c, hi) if pattern_db(law(rate, companding_db=c)) < 24.0 else (lo, c)
        f1[rate] = c
    print(f'    {"":30s} {"full scale":>10s} {"5.5 ratio":>10s} {"F-1 16k":>8s} {"F-1 32k":>8s}')
    rows = [('5.5 reading (mf8.BASE)', mf8.BASE['companding_db'])]
    rows += [(f'Table F-1 reading, {r // 1000}k', f1[r]) for r in PATTERNS]
    rows += [('previous mf8 law', PREVIOUS['companding_db'])]
    for name, c in rows:
        o = [pattern_db(law(r, companding_db=c)) for r in PATTERNS]
        print(f'    {name:30s} {c:7.1f} dB {spec_ratio(c):8.1f}:1 {o[0]:6.1f} dB {o[1]:6.1f} dB')
    print('    Table F-1 passes at 22-26 dB; 5.5 passes at 12:1 to 21:1.\n')

    print('  The reference level.  0 dBm0 is the 30 % pattern\'s output, which is set')
    print('  by the slew.  Per 1000 units of slew, mf8.BASE:')
    for rate in PATTERNS:
        p = law(rate)
        print(f'    {rate // 1000}k: 0 dBm0 = {1000 * tone(pattern(PATTERNS[rate][30], rate), p) / p.slew:.4f} '
              f'full scale; mf8.SLEW {p.slew:.0f} puts nominal speech at '
              f'{20 * np.log10(mf8.NOMINAL_RMS / tone(pattern(PATTERNS[rate][30], rate), p)):+.1f} dBm0')
    print('  Equal within a fraction of a dB: the standard holds the slew, not the step,')
    print('  across its two rates.  mf8.SLEW raises it with rate instead, which is a')
    print('  level alignment -- scaling the slew is scaling the input.')


# -------------------------------------------------------------------- laws

def laws():
    ls = [('previous: 30 dB, 6 ms, 3 ms', PREVIOUS),
          ('previous, 1 ms integrator', {**PREVIOUS, 'tau_int': 0.001}),
          ('188-113, 5.5 reading (mf8.BASE)', {}),
          ('188-113, Table F-1 reading', {'companding_db': 28.3})]
    slews = (10000.0, 12000.0, 16000.0, 20000.0, 24000.0)
    cells = [c for _, kw in ls for c in conditions(kw, TRUNK)]
    cells += [c for s in slews for c in conditions({'slew': s}, TRUNK)]
    get = grid(cells)
    print(f'THE LAW AGAINST THE PREVIOUS ONE -- {TRUNK // 1000} kbps, talkers {TALKERS}, '
          f'{SECS:.0f} s, segSNR dB')
    print('  level re nominal speech; bit errors random, at nominal level\n')
    print(f'  {"":34s} {HEAD}')
    for name, kw in ls:
        print(f'  {name:34s} {fmt(row(get, kw, TRUNK))}')
    print('\n  The integrator buys the bit-error columns and costs nothing clean; the')
    print('  ratio buys the quiet columns and costs nothing loud.\n')
    print(f'  {"slew, mf8.BASE otherwise":34s} {HEAD}')
    for s in slews:
        tag = '  <- mf8.SLEW' if s == mf8.SLEW[TRUNK] else ''
        print(f'  {f"{s:.0f} full scale/s":34s} {fmt(row(get, {"slew": s}, TRUNK))}{tag}')
    print('  Slew and input level are one knob: raising the slew moves every column')
    print('  toward the loud end.')


# ------------------------------------------------------------------- rates

SWEEPS = [('companding_db', (26.0, 28.3, 30.0, 32.0, 34.2, 36.6, 39.0, 42.0), '{:.1f} dB', 1),
          ('run_length', (3, 4, 6, 12), '{} bits', 1),
          ('tau_syl', (0.0025, 0.0035, 0.005, 0.007, 0.010), '{:.2f} ms', 1e3),
          ('tau_int', (0.0005, 0.00075, 0.001, 0.0015, 0.003), '{:.2f} ms', 1e3)]
RATES = (16000, 32000, 64000)


def rates():
    cells = [c for r in RATES for f, vals, _, _ in SWEEPS for v in vals for c in conditions({f: v}, r)]
    get = grid(cells)
    print('IS THE LAW BIT-RATE SPECIFIC? -- one parameter at a time around mf8.BASE')
    print(f'  talkers {TALKERS}, {SECS:.0f} s, segSNR dB; slew per mf8.SLEW\n')
    best = {}
    for r in RATES:
        print(f'  === {r // 1000} kbps')
        for f, vals, spec_fmt, k in SWEEPS:
            print(f'  {f:14s} {HEAD}')
            for v in vals:
                tag = '  <- mf8.BASE' if v == mf8.BASE[f] else ''
                print(f'  {spec_fmt.format(v * k):>14s} {fmt(row(get, {f: v}, r))}{tag}')
            m = [row(get, {f: v}, r) for v in vals]
            best[f, r] = (vals[int(np.argmax([x[5] for x in m]))], vals[int(np.argmax([x[7] for x in m]))])
        print()
    print('  Best value of each parameter at each rate (level mean / BER 1e-2):')
    print(f'  {"":14s} ' + ' '.join(f'{r // 1000:>19d}k' for r in RATES))
    for f, vals, spec_fmt, k in SWEEPS:
        cell = lambda v: spec_fmt.format(v * k) + (' (edge)' if v in (vals[0], vals[-1]) else '')
        print(f'  {f:14s} ' + ' '.join(f'{cell(best[f, r][0]):>20s}' for r in RATES))
        print(f'  {"":14s} ' + ' '.join(f'{cell(best[f, r][1]):>20s}' for r in RATES))


# -------------------------------------------------------------------- dnvt

def remod(bits, m):
    """m:1 first-order re-modulator: the running sum of +-1 per group, emit its sign."""
    s = (bits[:len(bits) // m * m].astype(np.int64) * 2 - 1).reshape(-1, m).sum(1)
    out = np.zeros(len(s), dtype=np.uint8)
    acc = 0
    for i, v in enumerate(s):
        acc += v
        o = 1 if acc >= 0 else -1
        out[i] = o > 0
        acc -= m * o
    return out


def tandem(bits, p_in, p_out):
    """Decode, reconstruction filter, resample, re-encode: a transcoding card."""
    y = audio.reconstruct(cvsd.decode(bits, p_in), p_in.rate)
    return cvsd.encode(audio.resample_to(y, p_in.rate, p_out.rate), p_out)


def dnvt_path(name, low, j):
    m = TRUNK // low
    pt, pl = law(TRUNK), law(low)
    ref = source(j, TRUNK)
    if name == 'the DNVT alone':
        y = heard(cvsd.encode(source(j, low), pl), pl)
    elif name.startswith('up'):
        bl = cvsd.encode(source(j, low), pl)
        if 'repeat' in name and 'window' in name:
            y = heard(np.repeat(bl, m), law(TRUNK, run_length=3 * m))
        elif 'repeat' in name:
            y = heard(np.repeat(bl, m), pt)
        else:
            y = heard(tandem(bl, pl, pt), pt)
    elif name.startswith('down'):
        b64 = cvsd.encode(ref, pt)
        if 'every' in name:
            y = heard(b64[::m], pl)
        elif 'remod' in name:
            y = heard(remod(b64, m), pl)
        else:
            y = heard(tandem(b64, pt, pl), pl)
    else:                                  # DNVT to DNVT through two transcoding cards
        bl = cvsd.encode(source(j, low), pl)
        y = heard(tandem(tandem(bl, pl, pt), pt, pl), pl)
    return score(ref, y, TRUNK)


DNVT_PATHS = [
    ('the DNVT alone', 'reference: its own codec, end to end'),
    ('up: repeat each bit', 'DNVT -> trunk, into the 64k card as specified'),
    ('up: repeat, window x m', '... into a 64k decoder whose window is 3m bits'),
    ('up: tandem', '... decoded and re-encoded on the card'),
    ('down: every m-th bit', 'trunk -> DNVT, decimated'),
    ('down: remod', '... summed per group, re-modulated to one bit'),
    ('down: tandem', '... decoded and re-encoded on the card'),
    ('DNVT - 64k - DNVT, 2 tandems', 'two DNVTs through two transcoding cards'),
]


def dnvt():
    lows = (32000, 16000)
    jobs = [(n, low, j) for low in lows for n, _ in DNVT_PATHS for j in TALKERS]
    with Pool() as pool:
        out = dict(zip(jobs, pool.starmap(dnvt_path, jobs)))
    print('A DNVT ON A 64 kbps CHANNEL -- both ends on mf8.BASE, the DNVT at its own rate')
    print(f'  talkers {TALKERS}, {SECS:.0f} s; segSNR dB against the source, and the output')
    print('  level re the source in dB, both heard at 64 kHz; m = 64k / DNVT rate\n')
    print(f'  {"":30s} ' + ' '.join(f'{low // 1000:>9d}k  level' for low in lows))
    for n, what in DNVT_PATHS:
        cells = []
        for low in lows:
            s = np.array([out[n, low, j] for j in TALKERS])
            cells.append(f'{s[:, 0].mean():10.1f} {s[:, 1].mean():+6.1f}')
        print(f'  {n:30s} ' + ' '.join(cells) + f'    {what}')

    print('\n  Why decimation cannot work: the 64k encoder\'s bits in one 16k period')
    b = cvsd.encode(source(1, TRUNK), law(TRUNK))
    g = (b[:len(b) // 4 * 4].astype(int) * 2 - 1).reshape(-1, 4)
    net = g.sum(1)
    print('    net step  ' + '  '.join(f'{v:+d}: {100 * (net == v).mean():4.1f} %' for v in (-4, -2, 0, 2, 4)))
    print(f'    the kept bit reports +-4 for every group; {100 * (net == 0).mean():.0f} % of groups moved 0.')
    idle = cvsd.encode(np.zeros(TRUNK), law(TRUNK))
    print(f'    silence, {"".join(map(str, idle[:12]))}..., decimated 2:1 or 4:1 is '
          f'{"".join(map(str, idle[::2][:12]))}...: the far integrator goes to the rail.')
    print('  Why repetition fails into the card as specified: the integrator is exact')
    print('  (the same current for the same time), but a 3-bit window at 64k fires on')
    print('  the DNVT\'s runs of 2 at 32k and of 1 at 16k -- the step runs high.')
    print('  Repetition IS exact as transport: a card whose codec is clocked at the')
    print('  DNVT\'s rate, carrying each bit m times in the DS0, takes any one of each m')
    bl = cvsd.encode(source(1, 16000), law(16000))
    ok = all(np.array_equal(np.repeat(bl, 4)[ph::4], bl) for ph in range(4))
    print(f'  back: bit-exact at every one of the 4 phases at 16k: {ok}.')


TARGETS = {'spec': spec, 'laws': laws, 'rates': rates, 'dnvt': dnvt}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
