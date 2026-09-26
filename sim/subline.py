"""
The subscriber line of common/subscriber-line.md, and the register of exchange/register.md.

One phone on two pairs, 64 kbps CVSD each way in differential Manchester at
128 kBaud.  Hook and ring are held bit patterns; a dial pulse is the on-hook
pattern keyed by the dial contact.  This promotes the scratch measurements
behind subscriber-line.md §§2-5 into a tool, and adds the register that reads
the dial.

Chain, upstream:

    hook switch + dial contact -> 1100 while the loop is open, else the CVSD encoder
      -> differential Manchester -> cable -> impairment -> mf8-spec §9.4 receiver
      -> hook detector: G = Q^Q[n-2] + violation hold + /carrier
         -> RC 4 ms -> comparator 0.85 / 0.70 -> ON_HOOK            (the line card)
      -> register: a 1 kHz tick, a two-stage synchronizer, one timer, one counter

The receiver is modelled in real time at 32 samples per bit: the latch holds
between strobes, carrier detect and the violation hold run in samples, and the
RC integrates the gated level cell by cell.  The register is modelled tick by
tick, as the logic would run.

Usage:  python3 sim/subline.py            everything, ~7 min       (subline.log is the run)
        python3 sim/subline.py density    §2: how near CVSD traffic comes to either pattern
        python3 sim/subline.py hook       §3: the hook and ring detectors, and a dead pair
        python3 sim/subline.py dial       §5: dial pulses as the line card sees them
        python3 sim/subline.py register   register.md: dialled digits into the register
        python3 sim/subline.py dtmf       §5: DTMF through the codec
        python3 sim/subline.py xfmr       mf8-spec §9.3: the line transformer's inductance
"""
import sys, time, numpy as np
from multiprocessing import Pool
from scipy import signal
import audio, cvsd, phy, mf8

RATE = 64000                      # line bit rate, and the CVSD rate
OS = 32                           # samples per bit
FS = RATE * OS                    # 2.048 MHz
CABLE = 1.8e6                     # as mf8_line.py
CHUNK = 1 << 21                   # samples per block through the line model
P = mf8.params(RATE)

THR, DEAD = 0.75, 0.20            # classifier and dead time, cells (mf8-spec §9.4, §9.7)
CD = 2.0                          # carrier-detect timeout, cells (§9.6)
VLONG, HOLD = 1.25, 16            # violation: a gap over 1.25 cells; held 16 cells
TAU, HI, LO = 0.004, 0.85, 0.70   # hook detector: RC and comparator

TICK = 1000                       # register tick, Hz: TX_OCT / 8
T_HIT, T_ID, T_CLR = 8, 128, 256  # ticks: the '4040's Q4, Q8, Q9

TALKERS = {}


# ------------------------------------------------------------------ the line

def _filt(fc, order):
    return signal.butter(order, min(0.99, 2 * fc / FS), btype='low')


def _slice(x, h, state):
    """Hysteretic comparator with its state carried in from the previous block."""
    ev = np.where(x > h, 1, np.where(x < -h, 0, -1)).astype(np.int8)
    idx = np.maximum.accumulate(np.where(ev >= 0, np.arange(len(x)), -1))
    out = np.where(idx >= 0, ev[np.maximum(idx, 0)], state).astype(np.uint8)
    return out, int(out[-1])


def _xf(L, lk, R):
    """One line transformer, its state carried across blocks: high-pass L/R, low-pass Lleak/2R."""
    fs = [signal.butter(1, R / (2 * np.pi * L), btype='high', fs=FS)]
    fc = 2 * R / (2 * np.pi * lk)
    if fc < 0.45 * FS:
        fs.append(signal.butter(1, fc, btype='low', fs=FS))
    zs = [np.zeros(1) for _ in fs]

    def run(x):
        for i, (b, a) in enumerate(fs):
            x, zs[i] = signal.lfilter(b, a, x, zi=zs[i])
        return x
    return run


def line(bits, n=None, sd=0.0, imp=0.0, seed=1, off=None, xf=None):
    """Comparator output, one sample per 1/FS, for a 64 kbps bit stream.

    bits=None is a dead pair: the transmitter off, noise only, for n bits.
    off=(a, b) switches the transmitter off from bit a to bit b: a cut pair.
    xf=(L, Lleak, R) puts a line transformer at each end of the pair: its
    magnetizing L as a high-pass L/R, its leakage as a low-pass Lleak/2R."""
    nbits = n if bits is None else len(bits)
    ns = nbits * OS
    rng = np.random.default_rng(seed)
    b1, a1 = _filt(CABLE, 1)
    b2, a2 = _filt(2 * RATE, 2)                       # the §9.5 input filter, at the symbol rate
    z1 = np.zeros(max(len(a1), len(b1)) - 1)
    z2 = np.zeros(max(len(a2), len(b2)) - 1)
    half = None if bits is None else phy_dm(bits)
    xs = [_xf(*xf), _xf(*xf)] if xf else None       # driver end, receiver end
    out = np.empty(ns, np.uint8)
    state, peak = 0, None
    for c0 in range(0, ns, CHUNK):
        c1 = min(ns, c0 + CHUNK)
        if half is None:
            x = np.zeros(c1 - c0)
        else:
            x = np.repeat(half[c0 // (OS // 2):c1 // (OS // 2)], OS // 2)
            if xs:
                x = xs[0](x)
            x, z1 = signal.lfilter(b1, a1, x, zi=z1)
            peak = peak or (1.0 if xs else np.abs(x).max())   # through a transformer: the undrooped +-1
            x /= peak
            if off:
                s0, s1 = max(off[0] * OS, c0), min(off[1] * OS, c1)
                if s1 > s0:
                    x[s0 - c0:s1 - c0] = 0.0
        if sd:
            x = x + rng.normal(0, sd, len(x))
        if imp:
            x = x + phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7 + c0)
        if xs:
            x = xs[1](x)
        x, z2 = signal.lfilter(b2, a2, x, zi=z2)
        out[c0:c1], state = _slice(x, 0.05, state)
    return out


def phy_dm(bits):
    """Differential Manchester, one +-1 level per half-cell."""
    import fast
    return fast.dm_encode(bits).astype(np.float64) * 2 - 1


def receiver(w, xor2):
    """The §9.4 classifier, §9.6 carrier detect and the violation hold -> G per bit cell.

    xor2: the exchange's X = Q ^ Q[n-2], which 1100 holds at 1.  Otherwise the
    phone's X = Q.  A violation -- a half-cell with no partner, or a gap over
    1.25 cells -- forces G to 1 for HOLD cells; so does no carrier."""
    n = len(w)
    edges = np.flatnonzero(w[1:] != w[:-1]) + 1
    T, D, VL = THR * OS, DEAD * OS, VLONG * OS
    st_i, st_b, viol = [], [], []
    le, mid = 0, False
    for e in edges.tolist():
        g = e - le
        if g < D:
            continue
        le = e
        if g > VL or (g > T and mid):
            viol.append(e)
        if g > T:
            st_i.append(e); st_b.append(1); mid = False
        elif mid:
            st_i.append(e); st_b.append(0); mid = False
        else:
            mid = True
    q = np.ones(n, np.uint8)                          # the data latch powers up at 1
    if st_i:
        vals = np.array(st_b, np.uint8)
        if xor2:
            vals = vals ^ np.concatenate([[0, 0], vals[:-2]]).astype(np.uint8)
        si = np.array(st_i)
        q[si[0]:] = np.repeat(vals, np.diff(np.concatenate([si, [n]])))
    # no carrier: from 2 cells after a transition until the next one; and before the first
    mark = np.zeros(n + 1, np.int32)
    ee = np.concatenate([[-CD * OS], edges, [n]]).astype(np.int64)
    lost = np.flatnonzero(np.diff(ee) > CD * OS)
    s = np.maximum(ee[lost] + int(CD * OS), 0)
    np.add.at(mark, s, 1); np.add.at(mark, ee[lost + 1], -1)
    if viol:
        v = np.array(viol)
        np.add.at(mark, v, 1); np.add.at(mark, np.minimum(v + HOLD * OS, n), -1)
    g = q | (np.cumsum(mark[:-1], dtype=np.int32) > 0).astype(np.uint8)
    nb = n // OS
    return g[:nb * OS].reshape(nb, OS).sum(1, dtype=np.int32) / OS


def rc(level, tau=TAU, y0=0.5):
    a = 1.0 / (tau * RATE)
    y, _ = signal.lfilter([a], [1, -(1 - a)], level, zi=[y0 * (1 - a)])
    return y


def comparator(y, hi, lo, init=False):
    """Asserted above hi, released below lo: one per bit cell."""
    ev = np.where(y > hi, 1, np.where(y < lo, 0, -1)).astype(np.int8)
    idx = np.maximum.accumulate(np.where(ev >= 0, np.arange(len(y)), -1))
    return np.where(idx >= 0, ev[np.maximum(idx, 0)], int(init)).astype(bool)


def detect(bits, n=None, **cond):
    """The exchange's hook detector: ON_HOOK per bit cell, and the RC's level."""
    y = rc(receiver(line(bits, n, **cond), xor2=True))
    return comparator(y, HI, LO), y


def stretch(on, cells):
    """ON_HOOK held `cells` longer after each release: a monostable on the falling edge."""
    fall = np.flatnonzero(on[:-1] & ~on[1:]) + 1
    if not len(fall):
        return on.copy()
    last = np.full(len(on), -10 ** 9, np.int64)
    last[fall] = fall
    last = np.maximum.accumulate(last)
    return on | ((np.arange(len(on)) - last) < cells)


# ------------------------------------------------------------------ the phone

def talker(j, secs, offset=0.0):
    """Talker j at nominal level, 64 kHz, band-limited."""
    key = (j, secs, offset)
    if key in TALKERS:
        return TALKERS[key]
    x, fs = audio.read_wav(f'talker{j}.wav', seconds=secs + 0.2, offset=offset)
    x = audio.bandlimit(x, fs)
    x = x * (mf8.NOMINAL_RMS / max(x.std(), 1e-9))
    x = audio.resample_to(x, fs, RATE)[:int(secs * RATE)]
    if not offset:
        TALKERS[key] = x
    return x


P1100 = lambda n: (((np.arange(n) >> 1) & 1) ^ 1).astype(np.uint8)


def phone(n, opens, make='idle', j=3, offset=0.0):
    """The phone's upstream, n bits.  `opens` are (start, end) bit intervals where the
    hook or dial contact is open: 1100 there, from a free-running bit clock / 4.
    Elsewhere the CVSD encoder, fed silence ('idle': the dial's off-normal contact
    mutes the transmitter) or talker j ('speech': it does not, and someone talks)."""
    if make == 'idle':
        src = np.zeros(n)
    else:
        src = talker(j, n / RATE + 0.1, offset)[:n]
        src = np.concatenate([src, np.zeros(n - len(src))])
    b = cvsd.encode(src, P)
    op = np.zeros(n, bool)
    for s, e in opens:
        op[max(s, 0):min(e, n)] = True
    return np.where(op, P1100(n), b).astype(np.uint8)


def dial(digits, pps, ratio, idp, rng=None, pre=0.5, jitter=0.0):
    """Break intervals, seconds, for a digit string from a dial at pps and a break ratio.
    idp is the pause from the end of one digit's last break to the next digit's first
    (ES 201 187 4.2.7): a number, or one per gap.  jitter: +- fraction of each period."""
    rng = rng or np.random.default_rng(0)
    idps = np.broadcast_to(np.asarray(idp, float), (max(len(digits) - 1, 1),))
    br, t = [], pre
    for i, d in enumerate(digits):
        if i:
            t = br[-1][1] + idps[i - 1]
        for _ in range(10 if d == 0 else d):
            per = (1.0 / pps) * (1 + jitter * rng.uniform(-1, 1))
            br.append((t, t + ratio * per))
            t += per
    return br


def cells(intervals):
    return [(int(round(s * RATE)), int(round(e * RATE))) for s, e in intervals]


def edges(on):
    d = np.diff(on.astype(np.int8))
    return np.flatnonzero(d == 1) + 1, np.flatnonzero(d == -1) + 1


# ------------------------------------------------------------------ the register

def register(on, phase=0, t_hit=T_HIT, t_id=T_ID, t_clr=T_CLR):
    """The pulse register, tick by tick.

    ON_HOOK is sampled on each 1 kHz tick by a two-stage synchronizer; the second
    stage and a third flip-flop give the edge.  One timer ('4040) counts ticks;
    three taps are latched on their first rise -- HIT at 8 ms, ID at 128 ms, CLR at
    256 ms.  Count, then clear: the counter is enabled on the edge's tick, and a
    fourth flip-flop holds the timer and its latches clear through the next, so
    the timer restarts a tick late and every width it measures is one tick short.  A break that ends after HIT and before CLR
    advances the pulse counter ('161: ten pulses read 1010, the MT8870's code for
    0, reported here as 0).  A make that reaches ID after a counted pulse strobes
    the digit into the store.  A break that reaches CLR is the caller hanging up:
    the register releases.

    Returns digits [(value, tick)], the clear tick or None, and what the timer
    measured: every break counted, every in-digit make, every inter-digit pause."""
    step = RATE // TICK
    s = on[phase::step].astype(np.int8)
    h = np.concatenate([[s[0]], s[:-1]])              # second synchronizer stage
    t, p, seen = 10 ** 6, 0, False
    digits, clear = [], None
    brk, mk, idp = [], [], []
    for k in range(1, len(h)):
        t += 1                                            # ticks since the last edge
        if h[k] != h[k - 1]:
            if h[k - 1]:                                  # a break has ended
                if t >= t_hit:
                    p += 1; seen = True; brk.append(t)
            elif seen:
                mk.append(t)                              # a make inside a digit
            elif digits:
                idp.append(t)                             # the pause before this digit
            t = -1                                        # count on this tick, clear on the next
            continue
        if not h[k] and t == t_id and seen:
            digits.append((p % 10, k)); p, seen = 0, False
        if h[k] and t == t_clr:
            clear = k
            break
    return digits, clear, dict(brk=brk, mk=mk, idp=idp)


# ------------------------------------------------------------------ targets

def density():
    """subscriber-line.md §2: the RC-filtered density of each detector's signal
    over CVSD traffic -- how near ordinary traffic comes to either held pattern."""
    print('DENSITY -- what CVSD traffic looks like to each detector, codec only, no line')
    print('  RC tau 4 ms, extremes after 50 ms.  The phone filters Q (ringing, all zeros, is 0.00);')
    print('  the exchange filters Q^Q[n-2] (on-hook, 1100, is 1.00).  7 talkers x 30 s where named.\n')

    def src(gain_db=0.0, clip=None):
        out = []
        for j in range(1, 8):
            x, fs = audio.read_wav(f'talker{j}.wav')
            x = audio.bandlimit(x, fs)
            x = x * (mf8.NOMINAL_RMS / x.std()) * 10 ** (gain_db / 20)
            if clip:
                x = np.clip(x, -clip, clip)
            out.append(audio.resample_to(x, fs, RATE))
        return out

    def tone(f, pk, secs=5.0):
        return pk * np.sin(2 * np.pi * f * np.arange(int(secs * RATE)) / RATE)

    rng = np.random.default_rng(0)
    wn = audio.bandlimit(rng.normal(0, 1, RATE * 5), RATE)
    cases = [('speech, nominal', src()), ('speech +10 dB', src(10)),
             ('speech +20 dB, clipped at full scale', src(20, clip=1.0)),
             ('silence (encoder idle)', [np.zeros(RATE * 5)]),
             ('tone 300 Hz, full scale', [tone(300, 1.0)]),
             ('tone 300 Hz, 3x full scale', [tone(300, 3.0)]),
             ('tone 1 kHz, full scale', [tone(1000, 1.0)]),
             ('tone 3.4 kHz, full scale', [tone(3400, 1.0)]),
             ('square 300 Hz, full scale', [np.sign(tone(300, 1.0))]),
             ('noise 300-3400 Hz, 0.5 rms', [wn * 0.5 / wn.std()])]
    print(f'  {"source":38s} {"Q density":>13s} {"Q^Q[n-2]":>13s} {"longest run":>12s} {"longest X=1":>12s}')
    for name, xs in cases:
        lo1 = lo2 = 1.0; hi1 = hi2 = 0.0; run = runx = 0
        for x in xs:
            b = cvsd.encode(x, P)
            X = b ^ np.concatenate([[0, 0], b[:-2]]).astype(np.uint8)
            for sig, which in ((b, 1), (X, 2)):
                y = rc(sig.astype(float))[int(0.05 * RATE):]
                if which == 1:
                    lo1, hi1 = min(lo1, y.min()), max(hi1, y.max())
                else:
                    lo2, hi2 = min(lo2, y.min()), max(hi2, y.max())
            d = np.flatnonzero(np.diff(np.concatenate([[2], b, [2]])))
            run = max(run, int(np.diff(d).max()))
            xs1 = np.concatenate([[0], X[2:], [0]])
            d = np.diff(xs1.astype(np.int8))
            if (d == 1).any():
                runx = max(runx, int((np.flatnonzero(d == -1) - np.flatnonzero(d == 1)).max()))
        print(f'  {name:38s} {f"{lo1:.3f}-{hi1:.3f}":>13s} {f"{lo2:.3f}-{hi2:.3f}":>13s} '
              f'{run:9d} b  {runx:9d} b', flush=True)


def hook():
    """subscriber-line.md §3.1: both detectors over the line, and a dead pair."""
    print(f'HOOK AND RING DETECTORS over the line -- RC {TAU * 1e3:.0f} ms, comparator {HI:.2f} / {LO:.2f}, '
          f'violation hold {HOLD} cells, 2 s per cell, one seed.')
    print('  "false events" is the number of times the detector left the correct state after 20 ms.\n')
    NB = 2 * RATE
    skip = int(0.02 * RATE)
    noise = [('clean', {}), ('sd 0.4', dict(sd=0.4)), ('sd 0.6', dict(sd=0.6)),
             ('sd 0.7', dict(sd=0.7)), ('sd 0.8', dict(sd=0.8)),
             ('impulse 10/s', dict(imp=10)), ('impulse 100/s', dict(imp=100)),
             ('impulse 1000/s', dict(imp=1000))]
    dead = [('quiet, sd 0.01', dict(sd=0.01)), ('sd 0.03', dict(sd=0.03)),
            ('sd 0.05', dict(sd=0.05)), ('sd 0.1', dict(sd=0.1)), ('sd 0.3', dict(sd=0.3)),
            ('sd 1.0', dict(sd=1.0)), ('impulse 100/s', dict(sd=0.01, imp=100)),
            ('impulse 1000/s', dict(sd=0.01, imp=1000))]
    sp1 = cvsd.encode(talker(1, 2.0), P)
    sp2 = cvsd.encode(talker(2, 2.0), P)
    idle = (np.arange(NB) & 1).astype(np.uint8)

    def run(label, bits, want, xor2, conds):
        print(f'  {label}')
        print(f'    {"condition":20s} {"mean":>7s} {"min":>7s} {"max":>7s} {"wrong %":>8s} {"false events":>13s}')
        for cname, kw in conds:
            y = rc(receiver(line(bits, NB, **kw), xor2=xor2))
            d = comparator(y, HI, LO) if xor2 else comparator(1 - y, HI, LO)
            wrong = d[skip:] != want
            ev = int(np.sum(wrong[1:] & ~wrong[:-1]) + wrong[0])
            yy = y[skip:]
            print(f'    {cname:20s} {yy.mean():7.3f} {yy.min():7.3f} {yy.max():7.3f} '
                  f'{100 * wrong.mean():8.2f} {ev:13d}', flush=True)
        print()

    print(' EXCHANGE hook detector -- density of Q^Q[n-2]; on-hook above 0.85, off below 0.70\n')
    run('phone on-hook, sending 1100 -> want on-hook', P1100(NB), True, True, noise)
    run('phone off-hook, CVSD speech -> want off-hook', sp1, False, True, noise)
    run('phone off-hook, CVSD idle 1010 -> want off-hook', idle, False, True, noise)
    run('dead pair -> want on-hook', None, True, True, dead)
    print(' PHONE ring detector -- density of Q; ringing below 0.15, released above 0.30\n')
    run('exchange sends all zeros -> want ring', np.zeros(NB, np.uint8), True, False, noise)
    run('exchange sends idle 1010 -> want no ring', idle, False, False, noise)
    run('exchange sends CVSD speech -> want no ring', sp2, False, False, noise)
    run('dead pair -> want no ring', None, False, False, dead)


COND = [('clean', {}), ('sd 0.8', dict(sd=0.8)), ('impulse 100/s', dict(imp=100)),
        ('impulse 1000/s', dict(imp=1000))]
COMP = int(round(TAU * (np.log(1 / (1 - HI)) - np.log(1 / LO)) * RATE))   # cells


def _pulses(on, t0):
    """Break and make widths, ms, of ON_HOOK after cell t0."""
    r, f = edges(on[t0:])
    f = f[f > r[0]] if len(r) else f
    n = min(len(r), len(f))
    brk = (f[:n] - r[:n]) / RATE * 1e3
    mk = (r[1:n] - f[:n - 1]) / RATE * 1e3 if n > 1 else np.array([])
    return len(r), brk, mk


def dial_target():
    """subscriber-line.md §5: digit 0 as the exchange's ON_HOOK shows it."""
    print('DIAL PULSES as the line card sees them -- digit 0, ten breaks, ON_HOOK after the 4 ms detector')
    print('  "idle": the dial\'s off-normal contact mutes the transmitter, so the makes carry the codec\'s')
    print('  1010.  "speech": it does not, and talk continues under the dial.  Widths in ms.\n')
    rows = [(7, 0.56), (7, 0.72), (10, 0.60), (10, 0.67), (12, 0.56), (12, 0.72), (20, 0.60)]
    comp = COMP
    summary = []
    print(f'  {"dial":14s} {"makes":7s} {"condition":15s} {"pulses":>7s} {"break sent -> seen":>22s} '
          f'{"make sent -> seen":>22s}   {"corrected: break":>17s} {"make":>12s}')
    for pps, ratio in rows:
        per = 1000.0 / pps
        for make in ('idle', 'speech'):
            br = dial([0], pps, ratio, 0, pre=0.2)
            n = int((br[-1][1] + 0.3) * RATE)
            bits = phone(n, cells(br), make)
            for cname, kw in COND:
                on, _ = detect(bits, seed=3, **kw)
                k, b, m = _pulses(on, int(0.1 * RATE))
                kc, bc, mc = _pulses(stretch(on, comp), int(0.1 * RATE))
                summary.append((pps, ratio, make, cname, k, b, m, kc, bc, mc))
                print(f'  {f"{pps} pps {round(ratio * 100)}/{100 - round(ratio * 100)}":14s} {make:7s} {cname:15s} '
                      f'{f"{k}/10":>7s} {f"{ratio * per:6.1f} -> {b.min():5.1f}-{b.max():5.1f}":>22s} '
                      f'{f"{(1 - ratio) * per:6.1f} -> {m.min():5.1f}-{m.max():5.1f}":>22s}   '
                      f'{f"{bc.min() - ratio * per:+5.1f} to {bc.max() - ratio * per:+5.1f}":>17s} '
                      f'{f"{mc.min() - (1 - ratio) * per:+5.1f} to {mc.max() - (1 - ratio) * per:+5.1f}":>12s}',
                      flush=True)
    print(f'\n  "corrected" holds ON_HOOK {comp / RATE * 1e3:.2f} ms after each release -- a monostable on the falling')
    print('  edge, sized to the RC\'s own asymmetry, TAU * (ln 1/(1-0.85) - ln 1/0.70) -- and gives the error')
    print('  against what was sent.\n')
    print('  Summary, all rates and conditions:')
    for make in ('idle', 'speech'):
        rows_ = [s for s in summary if s[2] == make]
        err_b = np.concatenate([s[5] - s[1] * 1000 / s[0] for s in rows_])
        err_c = np.concatenate([s[8] - s[1] * 1000 / s[0] for s in rows_])
        cnt = sum(s[4] == 10 for s in rows_)
        print(f'    {make:7s} pulses 10/10 in {cnt}/{len(rows_)} cells;  break error as seen {err_b.min():+.1f} to '
              f'{err_b.max():+.1f} ms;  corrected {err_c.min():+.1f} to {err_c.max():+.1f} ms')


# register trials -----------------------------------------------------------

def _trial(a):
    """One dialled string end to end.  Returns what was sent and what the register read."""
    seed, lo, hi, make, kw = a
    rng = np.random.default_rng(seed)
    digits = [int(d) for d in rng.integers(0, 10, 4)]
    pps = rng.uniform(lo, hi)
    ratio = rng.uniform(0.56, 0.72)
    idp = rng.uniform(0.25, 1.0, 3)
    br = dial(digits, pps, ratio, idp, rng, pre=0.5, jitter=0.02)
    n = int((br[-1][1] + 0.35) * RATE)
    bits = phone(n, cells(br), make, j=1 + seed % 7, offset=rng.uniform(0, 20))
    on, _ = detect(bits, seed=seed, **kw)
    got, clear, w = register(on, phase=int(rng.integers(0, RATE // TICK)))
    return digits, [d for d, _ in got], clear, w, (pps, ratio, idp.min())


def _register_run(br, end, make='idle', **kw):
    """One scripted dial, break intervals `br` in seconds, through to the register."""
    n = int(end * RATE)
    bits = phone(n, cells(br), make)
    on, _ = detect(bits, seed=5, **kw)
    got, clear, w = register(on, phase=17)
    return [d for d, _ in got], clear, w


def register_target():
    print('THE REGISTER -- dialled digits end to end: phone, line, hook detector, register')
    print(f'  1 kHz tick; a break counts after {T_HIT} ms, a make of {T_ID} ms ends a digit, a break of '
          f'{T_CLR} ms clears.\n')

    # 1. random strings over the dial envelope, every condition
    N = 50
    print(f'  1. Random four-digit strings, {N} per cell.  Each string draws its own dial: rate in the range')
    print('     shown, break ratio 56-72 %, +-2 % per-pulse jitter, each inter-digit pause 250-1000 ms')
    print('     (ES 201 187 asks the phone for >= 720), a random tick phase and talker.  Widths are')
    print('     as the register\'s own timer measured them, in ticks = ms.\n')
    print(f'  {"dial":10s} {"makes":7s} {"condition":15s} {"digits":>7s} {"wrong":>6s} '
          f'{"break counted":>14s} {"make in digit":>14s} {"pause":>9s}')
    jobs, keys = [], []
    for env, lo, hi in (('7-12 pps', 7, 12), ('20 pps', 18, 22)):
        for make in ('idle', 'speech'):
            for ci, (cname, kw) in enumerate(COND):
                for t in range(N):
                    jobs.append((1000 * ci + t + (500 if make == 'speech' else 0) + (5000 if hi > 12 else 0),
                                 lo, hi, make, kw))
                    keys.append((env, make, cname))
    with Pool(6) as pool:
        res = pool.map(_trial, jobs, chunksize=1)
    ext = dict(brk=[], mk=[], idp=[])
    for key in dict.fromkeys(keys):
        rs = [r for k, r in zip(keys, res) if k == key]
        sent = sum(len(r[0]) for r in rs)
        wrong = sum(sum(a != b for a, b in zip(r[0], r[1])) + abs(len(r[0]) - len(r[1])) + (r[2] is not None)
                    for r in rs)
        b = [x for r in rs for x in r[3]['brk']]
        m = [x for r in rs for x in r[3]['mk']]
        p = [x for r in rs for x in r[3]['idp']]
        for k_, v in (('brk', b), ('mk', m), ('idp', p)):
            ext[k_] += [(key[0], x) for x in v]
        print(f'  {key[0]:10s} {key[1]:7s} {key[2]:15s} {sent:7d} {wrong:6d} {f"{min(b)}-{max(b)}":>14s} '
              f'{f"{min(m)}-{max(m)}":>14s} {f"{min(p)}-":>9s}', flush=True)
    b = [x for _, x in ext['brk']]; m = [x for _, x in ext['mk']]; p = [x for _, x in ext['idp']]
    b20 = [x for e, x in ext['brk'] if e == '20 pps']
    print(f'\n     Against the windows: shortest break counted {min(b)} ms (20 pps; {min(x for e, x in ext["brk"] if e != "20 pps")} '
          f'at 7-12) vs HIT {T_HIT};')
    print(f'     longest break {max(b)} ms vs CLR {T_CLR}; longest make in a digit {max(m)} ms and shortest pause '
          f'{min(p)} ms, either side of ID {T_ID}.')

    # 2. where each window fails, clean line, idle makes
    print('\n  2. Where each window gives way -- clean line, idle makes, one run per row.\n')
    print('     a. Two digits, 2 then 3, at 10 pps 60/40, the pause between them shortened:')
    for idp in (0.100, 0.110, 0.115, 0.120, 0.125, 0.130, 0.140, 0.200):
        br = dial([2, 3], 10, 0.60, idp, pre=0.3)
        got, clear, w = _register_run(br, br[-1][1] + 0.3)
        print(f'        pause {idp * 1e3:5.0f} ms sent, {w["idp"][0] if w["idp"] else "-":>4} ticks seen  -> read {got}')
    print('     b. Digit 3 at 56 % break, the dial slowed until its makes pass for pauses:')
    for pps in (7, 5, 4, 3.8, 3.6, 3.4, 3.2):
        br = dial([3], pps, 0.56, 0, pre=0.3)
        got, clear, w = _register_run(br, br[-1][1] + 0.4)
        print(f'        {pps:4.1f} pps, make {0.44 / pps * 1e3:5.1f} ms sent, longest seen '
              f'{max(w["mk"]) if w["mk"] else "-":>4}  -> read {got}')
    print('     c. Digit 2 at 10 pps 60/40 with its second break stretched:')
    for L in (0.100, 0.200, 0.240, 0.250, 0.255, 0.260, 0.280):
        br = dial([2], 10, 0.60, 0, pre=0.3)
        br[1] = (br[1][0], br[1][0] + L)
        got, clear, w = _register_run(br, br[-1][1] + 0.4)
        print(f'        break {L * 1e3:5.0f} ms  -> read {got}{"  and CLEAR" if clear else ""}')
    print('     d. Digit 3 at 10 pps 60/40 with its second break shortened:')
    for L in (0.006, 0.008, 0.010, 0.012, 0.014, 0.016, 0.018, 0.020):
        br = dial([3], 10, 0.60, 0, pre=0.3)
        br[1] = (br[1][0], br[1][0] + L)
        got, clear, w = _register_run(br, br[-1][1] + 0.4)
        print(f'        break {L * 1e3:5.0f} ms  -> read {got}')

    # 3. clearing
    print('\n  3. Clearing mid-dial -- 4 then 2 dialled at 10 pps 60/40, then the event 500 ms later.')
    print('     Latency is from the event to the register\'s CLR.\n')
    br = dial([4, 2], 10, 0.60, 0.8, pre=0.3)
    t_ev = br[-1][1] + 0.5
    end = t_ev + 1.0
    cases = [('phone hung up', dict(extra=[(t_ev, end)])),
             ('pair cut, quiet (sd 0.01)', dict(off=True, sd=0.01)),
             ('pair cut, noise sd 0.3', dict(off=True, sd=0.3)),
             ('pair cut, impulse 100/s', dict(off=True, sd=0.01, imp=100))]
    for name, c in cases:
        opens = br + c.get('extra', [])
        n = int(end * RATE)
        bits = phone(n, cells(opens), 'idle')
        kw = {k: v for k, v in c.items() if k in ('sd', 'imp')}
        if c.get('off'):
            kw['off'] = (int(t_ev * RATE), n)
        on, _ = detect(bits, seed=11, **kw)
        got, clear, w = register(on, phase=17)
        lat = f'{clear - t_ev * TICK:.0f} ms' if clear else 'never'
        print(f'     {name:28s} read {[d for d, _ in got]}  CLEAR after {lat}')
    br = dial([5], 10, 0.60, 0, pre=0.3)
    br = br[:3] + [(br[3][0], br[3][0] + 1.0)]
    n = int((br[-1][1] + 0.1) * RATE)
    on, _ = detect(phone(n, cells(br), 'idle'), seed=11)
    got, clear, w = register(on, phase=17)
    print(f'     {"hung up on the 4th pulse of 5":28s} read {[d for d, _ in got]}  '
          f'CLEAR after {clear - br[3][0] * TICK:.0f} ms')


def dtmf():
    """subscriber-line.md §5: DTMF through the 64 kbps codec, worst of 16 digits."""
    LOWF = [697, 770, 852, 941]
    HIGHF = [1209, 1336, 1477, 1633]
    FS_A = 8000

    def goertzel_db(x, f, fs):
        n = np.arange(len(x))
        c = np.abs(np.sum(x * np.hanning(len(x)) * np.exp(-2j * np.pi * f * n / fs)))
        return 20 * np.log10(c + 1e-20)

    print('DTMF through 64 kbps CVSD -- worst of 16 digits at each level, high group +2 dB,')
    print('  60 ms tone, 40 ms window from 15 ms in.\n')
    print(f'  {"per-tone level":>22s} {"peak, FS":>9s} {"SINAD dB":>9s} {"twist change dB":>16s} {"group dominance dB":>19s}')
    for L in [-30, -25, -20, -15, -10, -5, 0, 3, 6]:
        worst = dict(sinad=99, twist=0, dom=99)
        for li in range(4):
            for hi in range(4):
                fl, fh = LOWF[li], HIGHF[hi]
                a = mf8.NOMINAL_RMS * np.sqrt(2) * 10 ** (L / 20)
                t = np.arange(int(0.060 * RATE)) / RATE
                x = a * np.sin(2 * np.pi * fl * t) + a * 10 ** (2 / 20) * np.sin(2 * np.pi * fh * t + 1.0)
                x = np.concatenate([np.zeros(int(0.02 * RATE)), x, np.zeros(int(0.02 * RATE))])
                y = audio.reconstruct(cvsd.decode(cvsd.encode(x, P), P), RATE)
                seg = audio.resample_to(y, RATE, FS_A)
                s0 = int((0.02 + 0.015) * FS_A)
                seg = seg[s0:s0 + int(0.040 * FS_A)]
                nn = np.arange(len(seg)) / FS_A
                M = np.column_stack([np.sin(2 * np.pi * fl * nn), np.cos(2 * np.pi * fl * nn),
                                     np.sin(2 * np.pi * fh * nn), np.cos(2 * np.pi * fh * nn)])
                coef, *_ = np.linalg.lstsq(M, seg, rcond=None)
                fit = M @ coef
                sinad = 10 * np.log10(np.sum(fit ** 2) / max(np.sum((seg - fit) ** 2), 1e-30))
                twist = 20 * np.log10(np.hypot(coef[2], coef[3]) / np.hypot(coef[0], coef[1])) - 2.0
                gl = [goertzel_db(seg, f, FS_A) for f in LOWF]
                gh = [goertzel_db(seg, f, FS_A) for f in HIGHF]
                dom = min(gl[li] - max(g for k, g in enumerate(gl) if k != li),
                          gh[hi] - max(g for k, g in enumerate(gh) if k != hi))
                worst['sinad'] = min(worst['sinad'], sinad)
                worst['twist'] = max(worst['twist'], twist, key=abs)
                worst['dom'] = min(worst['dom'], dom)
        pk = mf8.NOMINAL_RMS * np.sqrt(2) * 10 ** (L / 20) * (1 + 10 ** 0.1)
        print(f'  {f"{L:+d} dB re nominal":>22s} {pk:9.2f} {worst["sinad"]:9.1f} {worst["twist"]:+16.2f} '
              f'{worst["dom"]:19.1f}', flush=True)


def _bits(w):
    """The §9.4 classifier's decoded bits."""
    edges = np.flatnonzero(w[1:] != w[:-1]) + 1
    out, le, mid = [], 0, False
    for e in edges.tolist():
        g = e - le
        if g < DEAD * OS:
            continue
        le = e
        if g > THR * OS:
            out.append(1); mid = False
        elif mid:
            out.append(0); mid = False
        else:
            mid = True
    return np.array(out, np.uint8)


def _errors(sent, got, W=256):
    """Bit errors in windows of W, each realigned within +-6 of the running offset: a slip costs its window."""
    off, e_tot, n_tot = 0, 0, 0
    for s0 in range(64, len(got) - W, W):
        best = min(((int(np.sum(sent[s0 + off + d:s0 + off + d + W] != got[s0:s0 + W])), abs(d), d)
                    for d in range(-6, 7) if 0 <= s0 + off + d and s0 + off + d + W <= len(sent)), default=None)
        if best:
            off += best[2]; e_tot += best[0]; n_tot += W
    return e_tot, n_tot


def xfmr():
    """mf8-spec §9.3: the line transformer's magnetizing and leakage inductance, one at each end."""
    print('LINE TRANSFORMER -- one at each end of the pair; BER through the §9.4 classifier over 1 s of random')
    print('  bits plus 1 s of CVSD speech, and the exchange hook detector (1100, speech, idle) under the same noise.')
    print('  R is what the magnetizing L sees: ~50 ohms with both ends terminated, 100 the pessimistic case.\n')
    NB = RATE
    rnd = np.random.default_rng(3).integers(0, 2, NB).astype(np.uint8)
    sp = cvsd.encode(talker(1, 1.0), P)[:NB]
    idle = (np.arange(NB) & 1).astype(np.uint8)
    conds = [('clean', {}), ('sd 0.4', dict(sd=0.4)), ('sd 0.5', dict(sd=0.5)), ('sd 0.6', dict(sd=0.6))]
    parts = [('none', None, None), ('78615/9C 10 mH, 44.5 uH', 10e-3, 44.5e-6), ('DA103C 4 mH, 0.91 uH', 4e-3, 0.91e-6),
             ('T1/E1 1.2 mH', 1.2e-3, 1e-6), ('2 mH', 2e-3, 1e-6)]
    skip = int(0.02 * RATE)
    print(f'    {"transformer":24s} {"R":>4s} {"L/R cells":>9s}  ' + ''.join(f'{c:>10s}' for c, _ in conds) + '   hook')
    for name, L, lk in parts:
        for R in ((0,) if L is None else (50, 100)):
            xf = None if L is None else (L, lk, R)
            row, bad = [], []
            for c, kw in conds:
                e = n = 0
                for b in (rnd, sp):
                    de, dn = _errors(b, _bits(line(b, xf=xf, **kw)))
                    e += de; n += dn
                row.append(f'{e / n:10.1e}')
                for cname, b, want in (('1100', P1100(NB), True), ('speech', sp, False), ('idle', idle, False)):
                    d = comparator(rc(receiver(line(b, xf=xf, **kw), xor2=True)), HI, LO)
                    if (d[skip:] != want).any():
                        bad.append(f'{cname}/{c}')
            cells = L / R * RATE if L else 0
            print(f'    {name:24s} {R:4d} {cells:9.2f}  ' + ''.join(row) + '   ' + (', '.join(bad) or 'clean'), flush=True)


TARGETS = {'density': density, 'hook': hook, 'dial': dial_target, 'register': register_target, 'dtmf': dtmf,
           'xfmr': xfmr}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        t0 = time.time()
        TARGETS[k]()
        print(f'\n  [{k}: {time.time() - t0:.0f} s]\n', flush=True)
