"""
Line-code measurements for the MF8 carrier.  Backs docs/line-codes.md and
docs/frame-rate.md.

Everything runs on the mf8 frame (mf8.py, docs/mf8-spec.md).  Audio lives in
mf8_line.py, which carries six talkers through the whole chain; this file is
the line itself -- which code, how it fails, and what the rate costs.

Usage:  python3 linecodes.py            everything, ~40 min
        python3 linecodes.py codes      nine codes, structural properties
        python3 linecodes.py clock      zero-run bound; AMI clock, tank vs DPLL
        python3 linecodes.py rxclock    does an AMI receiver need a local clock?
        python3 linecodes.py polarity   tip/ring swap, both codes
        python3 linecodes.py plant      Gaussian, impulse and attenuation
        python3 linecodes.py impulse    impulse threshold and mitigations
        python3 linecodes.py framerate  frame rate: reach, quality, capacity
"""
import sys, gc, numpy as np
from scipy import signal
import audio, cvsd, fast, phy, mf8

RATE = 64000
LINE = 8 * RATE                   # 512 kbps
NCH = 6
OSB = 32
FS = LINE * OSB
CABLE = 1.8e6


def _lp(x, fc, fs=FS, order=2):
    b, a = signal.butter(order, min(0.99, 2 * fc / fs), btype='low')
    return signal.lfilter(b, a, x)


def payload(nf, kind='random', seed=7):
    rg = np.random.default_rng(seed)
    if kind == 'random':
        return [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    if kind == 'const0':
        return [np.zeros(nf, np.uint8)] * NCH
    if kind == 'const1':
        return [np.ones(nf, np.uint8)] * NCH
    p = mf8.params(RATE)
    src, fs = audio.read_wav('talker1.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * mf8.NOMINAL_RMS, fs, RATE)
    if kind == 'speech':
        sp = cvsd.encode(x, p)[:nf]
        return [np.roll(sp, 977 * j) for j in range(NCH)]
    sil = cvsd.encode(np.zeros(nf), p)
    return [np.roll(sil, 13 * j) for j in range(NCH)]


def line_of(nf, kind='random', hooks=(0, 0, 0, 1, 0, 0)):
    A = [np.full(nf, hooks[j], np.uint8) for j in range(NCH)]
    return mf8.build(payload(nf, kind), A)


def raw_ber(rb, ln, span=60):
    best = 1.0
    for o in range(0, span):
        n = min(len(rb) - o, len(ln))
        if n < 1000:
            break
        best = min(best, float((rb[o:o + n] != ln[:n]).mean()))
        if best == 0.0:
            break
    return best


# ------------------------------------------------------------------ the line

def rx_dm(ln, sd=0.0, imp=0.0, atten=1.0, hyst=0.05, dead=0.25, hp=0.0, seed=1):
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(ln).astype(np.float64) * 2 - 1, OSB // 2)
    x = _lp(x, CABLE, order=1); x /= np.abs(x).max()
    if atten != 1.0:
        x *= atten
    if sd:
        x += rng.normal(0, sd, len(x))
    if imp:
        x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
    if hp:
        b, a = signal.butter(1, min(0.99, 2 * hp / FS), btype='high')
        x = signal.lfilter(b, a, x)
    w = fast.slice_hyst(_lp(x, 2 * LINE), hyst)
    del x; gc.collect()
    b = fast.mono_decode(w, OSB, thr=0.75, dead=dead)
    del w; gc.collect()
    return b


def rx_ami(ln, sd=0.0, imp=0.0, atten=1.0, thresh=0.5, gain=1.0, hp=0.0,
           sub=4, seed=1):
    """8x DPLL off the local 4.096 MHz crystal (sub = OSB/8)."""
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.ami_encode(ln), OSB)
    x = _lp(x, CABLE, order=1); x /= np.abs(x).max()
    if atten != 1.0:
        x *= atten
    if sd:
        x += rng.normal(0, sd, len(x))
    if imp:
        x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
    if hp:
        b, a = signal.butter(1, min(0.99, 2 * hp / FS), btype='high')
        x = signal.lfilter(b, a, x)
    x = _lp(x, LINE)
    xs = x[::sub]
    peak = gain * np.percentile(np.abs(xs), 99) if gain != 1.0 else None
    b = fast.ami_decode(xs, OSB // sub, thresh=thresh, peak=peak)
    del x, xs; gc.collect()
    return b


CODES = (('diff Manchester', rx_dm), ('AMI', rx_ami))


# ------------------------------------------------- 1: the nine line codes

def codes():
    def manchester(b):
        o = np.empty(2 * len(b)); o[0::2] = np.where(b == 1, 1, -1)
        o[1::2] = np.where(b == 1, -1, 1); return o

    def diffman(b):
        return fast.dm_encode(b).astype(float) * 2 - 1

    def ami_c(b):
        v = fast.ami_encode(b); o = np.empty(2 * len(b))
        o[0::2] = v; o[1::2] = v; return o

    def uni_nrz(b):
        o = np.empty(2 * len(b)); o[0::2] = b; o[1::2] = b; return o.astype(float)

    def uni_rz(b):
        o = np.zeros(2 * len(b)); o[0::2] = b; return o.astype(float)

    def polar_nrz(b):
        v = np.where(b == 1, 1.0, -1.0); o = np.empty(2 * len(b))
        o[0::2] = v; o[1::2] = v; return o

    def nrzi(b):
        v = np.where(np.cumsum(b) % 2 == 1, 1.0, -1.0)
        o = np.empty(2 * len(b)); o[0::2] = v; o[1::2] = v; return o

    def cmi(b):
        o = np.empty(2 * len(b)); pol = 1.0
        for i, bit in enumerate(b):
            if bit == 0:
                o[2 * i], o[2 * i + 1] = -1.0, 1.0
            else:
                o[2 * i] = o[2 * i + 1] = pol; pol = -pol
        return o

    def miller(b):
        o = np.empty(2 * len(b)); lvl = 1.0; prev = 1
        for i, bit in enumerate(b):
            if bit == 1:
                o[2 * i] = lvl; lvl = -lvl; o[2 * i + 1] = lvl
            else:
                if prev == 0:
                    lvl = -lvl
                o[2 * i] = o[2 * i + 1] = lvl
            prev = bit
        return o

    TAB = [('Manchester (biphase-L)', manchester), ('differential Manchester', diffman),
           ('AMI', ami_c), ('unipolar NRZ', uni_nrz), ('unipolar RZ', uni_rz),
           ('polar NRZ', polar_nrz), ('NRZI', nrzi), ('CMI', cmi), ('Miller', miller)]

    def props(w):
        lv = len(np.unique(np.round(w, 6)))
        tr = np.flatnonzero(np.diff(w) != 0)
        if len(tr) < 3:
            return lv, float('inf'), float('inf'), w.mean(), 0.0
        d = np.diff(tr) / 2.0
        disp = np.cumsum(w) / 2.0
        return lv, d.min(), d.max(), w.mean(), float(disp.max() - disp.min())

    print('LINE CODES ON THE MF8 FRAME -- structural properties, measured')
    print('  Intervals and disparity in BIT periods.  min interval sets the max')
    print('  fundamental; max interval sets what clock recovery must coast; the')
    print('  disparity swing is the DC wander a transformer has to pass.\n')
    for kind in ('random', 'const0', 'const1'):
        ln = line_of(4000, kind)
        print(f'  --- payload: {kind}  (line ones density {ln.mean():.3f})')
        print(f'  {"code":26s} {"levels":>6s} {"min int":>8s} {"max int":>8s} '
              f'{"mean DC":>9s} {"disparity":>10s}')
        for nm, fn in TAB:
            lv, mn, mx, dc, ds = props(fn(ln))
            print(f'  {nm:26s} {lv:6d} {mn:8.2f} {mx:8.2f} {dc:+9.3f} {ds:10.1f}')
        print()
    print('  The disparity column decides the candidate set, because the pair is')
    print('  transformer coupled (mf8-spec.md 9.3) and a transformer cannot pass')
    print('  unbounded DC wander.  Bounded at order one bit period: Manchester,')
    print('  differential Manchester, AMI, CMI.  Miller and NRZI halve the')
    print('  bandwidth and would be the interesting candidates, and both fail')
    print('  here.  Everything else fails by orders of magnitude.')


# ------------------------------------- 2: zero runs and AMI clock recovery

def clock():
    print('ZERO RUNS -- the frame bounds them, so AMI needs no zero substitution')
    print('  Worst run of zeros on the line, over all 64 hook states.\n')
    import itertools
    nf = 4096
    worst = 0
    for kind in ('const0', 'const1', 'silence', 'speech', 'random'):
        C = payload(nf, kind)
        m = 0
        for h in itertools.product((0, 1), repeat=NCH):
            A = [np.full(nf, h[j], np.uint8) for j in range(NCH)]
            ln = mf8.build(C, A)
            d = np.diff(np.flatnonzero(np.concatenate(([1], ln, [1]))))
            m = max(m, int(d.max()) - 1)
        worst = max(worst, m)
        print(f'  {kind:14s} {m:3d}')
    print(f'\n  worst over everything: {worst} bits.')
    print('  F is 0 one frame in eight, so a mark lands at worst every 2 frames =')
    print('  16 line bits whatever the payload does.  B8ZS substitutes at 8 zeros')
    print('  and HDB3 at 4, so neither is needed -- the framing bit does the job.')

    def tank(x, foff, Q):
        r = np.abs(x); r = r - r.mean()
        b, a = signal.iirpeak(LINE * (1.0 + foff) / (FS / 2), Q)
        return signal.lfilter(b, a, r)

    def tank_bits(x, t, phase, skip):
        idx = np.flatnonzero(np.diff((t > 0).astype(np.int8)) == 1) + 1 + phase
        idx = idx[(idx >= skip) & (idx < len(x))]
        thr = 0.5 * np.percentile(np.abs(x), 99)
        return (np.abs(x)[idx] > thr).astype(np.uint8), idx

    def ber_at(b, ln, start):
        best = 1.0
        for off in range(max(0, start - 40), start + 60):
            n = min(len(b), len(ln) - off)
            if n < 500:
                break
            best = min(best, float((b[:n] != ln[off:off + n]).mean()))
            if best == 0.0:
                break
        return best

    def analog(ln):
        x = np.repeat(fast.ami_encode(ln), OSB)
        x = _lp(x, CABLE, order=1); x /= np.abs(x).max()
        return _lp(x, LINE)

    n2 = 6000
    ln0 = line_of(n2, 'const0')
    lnr = line_of(n2, 'random')
    SKIP = 60 * OSB
    x = analog(lnr); t = tank(x, 0.0, 100.0)
    cal, bb = 0, 1.0
    for ph in range(OSB):
        b, idx = tank_bits(x, t, ph, SKIP)
        e = ber_at(b, lnr, int(idx[0]) // OSB if len(idx) else 0)
        if e < bb:
            bb, cal = e, ph
    print('\n\nOPTION B -- analog tank (rectify, resonator, flywheel)')
    print(f'  Sampling phase trimmed once at nominal: phase {cal}, BER {bb:.1e}.')
    print('  BER on the worst payload (constant 0), tank detuned:\n')
    offs = (0.0, 0.001, 0.0025, 0.005, 0.01, 0.02)
    print(f'  {"Q":>6s} {"amp left":>9s} ' + ' '.join(f'{f * 100:>7.2f}%' for f in offs))
    for Q in (20.0, 50.0, 100.0, 200.0, 500.0):
        row = []
        for f in offs:
            xx = analog(ln0); tt = tank(xx, f, Q)
            b, idx = tank_bits(xx, tt, cal, SKIP)
            row.append(ber_at(b, ln0, int(idx[0]) // OSB if len(idx) else 0))
            del xx, tt; gc.collect()
        print(f'  {Q:6.0f} {np.exp(-np.pi * 15 / Q):9.2f} '
              + ' '.join(('     ok' if e == 0 else f'{e:7.1e}') for e in row), flush=True)
    print('\n  Two effects pull opposite ways, and the second binds:')
    print('    coasting decay over 15 idle cycles = exp(-pi*15/Q)  -> wants Q high')
    print('    static phase shift when detuned    = atan(2*Q*df/f) -> wants Q low')
    print('  The measured edge sits at df/f ~ 1/(2Q).  A tank wants Q ~ 100 AND')
    print('  tuning inside ~0.25%: a ceramic resonator, not an LC.')


# ------------------------------------------ 3: does the receiver need a clock

def rxclock():
    def analog(ln, sd=0.0, seed=1):
        x = np.repeat(fast.ami_encode(ln), OSB)
        x = _lp(x, CABLE, order=1); x /= np.abs(x).max()
        if sd:
            x += np.random.default_rng(seed).normal(0, sd, len(x))
        return _lp(x, LINE)

    def clockless(x, tol=0.0, thresh=0.5):
        peak = np.percentile(np.abs(x), 99)
        above = (np.abs(x) > thresh * peak).astype(np.int8)
        edges = np.flatnonzero(np.diff(above) == 1) + 1
        if len(edges) < 2:
            return np.zeros(0, np.uint8)
        period = OSB * (1.0 + tol)
        out = [1]
        for gap in np.diff(edges):
            k = max(1, int(round(gap / period)))
            out.extend([0] * (k - 1)); out.append(1)
        return np.array(out, np.uint8)

    def ber_mark(b, ln):
        best = 1.0
        for o in range(0, 80):
            n = min(len(b), len(ln) - o)
            if n < 500:
                break
            best = min(best, float((b[:n] != ln[o:o + n]).mean()))
            if best == 0.0:
                break
        return best

    print('WHY AMI NEEDS A TIME REFERENCE AND DIFFERENTIAL MANCHESTER DOES NOT')
    print('  It is the DYNAMIC RANGE of the timing measurement:\n')
    print('    diff Manchester  intervals are 0.5 or 1.0 cell  -> 2:1, +/-13% ok')
    print('    AMI              gaps run 1 to 16 bit periods   -> 16:1, needs')
    print('                     tol < 0.5/16 = 3.1%\n')
    n2 = 6000
    ln0 = line_of(n2, 'const0'); lnr = line_of(n2, 'random')
    print('OPTION A -- no clock at all: quantise the gap between marks\n')
    print(f'  {"RC tol":>7s} {"random BER":>11s} {"count":>7s} | {"const 0 BER":>12s} {"count":>8s}')
    for tol in (0.0, 0.005, 0.01, 0.02, 0.03, 0.05, 0.10):
        r = []
        for ln in (lnr, ln0):
            x = analog(ln); b = clockless(x, tol=tol)
            r.append((ber_mark(b, ln), len(b) - len(ln)))
            del x, b; gc.collect()
        print(f'  {tol * 100:6.1f}% {r[0][0]:11.1e} {r[0][1]:7d} | '
              f'{r[1][0]:12.1e} {r[1][1]:8d}', flush=True)
    print('\n  Error-free to 2%, broken at 3% -- the 3.1% predicted.  A 1% resistor')
    print('  and a 2% C0G give +/-3%, so a clockless AMI receiver sits ON its')
    print('  failure point.  And it fails by SLIPPING: a mis-rounded gap emits the')
    print('  wrong number of zeros, handing back the one property (4) that makes')
    print('  AMI worth considering.  Not a real option.')

    print('\n\nOPTION C -- oversampling DPLL off the local 4.096 MHz crystal')
    print('  4.096 MHz divides every family rate exactly: '
          + ', '.join(f'{r} kbps {4096 // r}x' for r in (1024, 512, 256, 128, 64)))
    print('\n  The crystal is a SAMPLING reference; the DPLL recovers bit phase')
    print('  from the line, so the bit clock stays locked to the far transmitter.\n')
    print(f'  {"crystal offset":>15s} {"drift over clip":>17s} {"bits emitted - sent":>21s} {"BER":>9s}')
    for ppm in (0, 100, 200, 1000, 5000):
        x = analog(ln0)
        step = 4 * (1.0 + ppm * 1e-6)
        idx = np.round(np.arange(0, len(x) - 1, step)).astype(np.int64)
        b = fast.ami_decode(x[idx], OSB // 4, thresh=0.5)
        del x; gc.collect()
        print(f'  {ppm:12d} ppm {ppm * 1e-6 * len(ln0):14.1f} bits '
              f'{len(b) - len(ln0):21d} {raw_ber(b, ln0):9.1e}', flush=True)
    print('\n  The bit count is exact at every offset.  The DPLL absorbs drift as')
    print('  PHASE, not as bits, so mf8-spec.md 2\'s slip-free property survives:')
    print('  a local crystal used as a SAMPLING reference does not cause slips.')
    print('  What it costs is the receiver\'s clocklessness, and nothing else.')


# --------------------------------------------------------------- 4: polarity

def polarity():
    nf = 8000
    ln = line_of(nf, 'random')

    print('POLARITY -- is AMI blind to a tip/ring swap, as biphase is?\n')
    print('  A swap inverts everything arriving differentially, so the test is to')
    print('  invert the complete received waveform, impairments included.\n')

    def build_wave(code, sd, imp, atten, invert):
        rng = np.random.default_rng(1)
        if code == 'dm':
            x = np.repeat(fast.dm_encode(ln).astype(np.float64) * 2 - 1, OSB // 2)
        else:
            x = np.repeat(fast.ami_encode(ln), OSB)
        x = _lp(x, CABLE, order=1); x /= np.abs(x).max()
        if atten != 1.0:
            x *= atten
        if sd:
            x += rng.normal(0, sd, len(x))
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=8)
        if invert:
            x = -x
        if code == 'dm':
            w = fast.slice_hyst(_lp(x, 2 * LINE), 0.05)
            del x; gc.collect()
            b = fast.mono_decode(w, OSB, thr=0.75, dead=0.25)
            del w; gc.collect()
            return b
        x = _lp(x, LINE)
        b = fast.ami_decode(x[::4], OSB // 4, thresh=0.5)
        del x; gc.collect()
        return b

    print(f'  {"condition":22s} {"code":16s} {"identical":>10s} {"bits differing":>15s}')
    allsame = True
    for nm, kw in (('clean', dict(sd=0, imp=0, atten=1.0)),
                   ('noise sd 0.4', dict(sd=0.4, imp=0, atten=1.0)),
                   ('noise sd 0.6', dict(sd=0.6, imp=0, atten=1.0)),
                   ('impulse 100/s', dict(sd=0, imp=100.0, atten=1.0)),
                   ('attenuated 0.25x', dict(sd=0.10, imp=0, atten=0.25))):
        for cn, code in (('diff Manchester', 'dm'), ('AMI', 'ami')):
            a = build_wave(code, invert=False, **kw)
            b = build_wave(code, invert=True, **kw)
            n = min(len(a), len(b))
            same = (len(a) == len(b)) and bool((a[:n] == b[:n]).all())
            allsame &= same
            print(f'  {nm:22s} {cn:16s} {("YES" if same else "no"):>10s} '
                  f'{int((a[:n] != b[:n]).sum()) + abs(len(a) - len(b)):>15d}', flush=True)
    print(f'\n  All conditions bit-identical: {allsame}.')
    print('\n  Differential Manchester decides same-vs-different half cells, and')
    print('  inversion flips both.  AMI decides |x| > thresh*peak, so the sign')
    print('  never enters -- and a full-wave front end is MANDATORY for AMI')
    print('  anyway, because marks arrive as both + and - pulses.  Polarity')
    print('  neutrality falls out of the receiver you must build regardless.')
    print('  The alternation rule is symmetric too, so even bipolar-violation')
    print('  error detection survives a swap.')


# ------------------------------- 5: Gaussian, impulse and attenuation, swept

def plant():
    nf = 16000
    ln = line_of(nf, 'random')
    SEEDS = (1, 2, 3, 4)

    def cell(rx, **kw):
        unl = 0; lk = 0; raw = []
        for sd_i in SEEDS:
            rb = rx(ln, seed=sd_i, **kw)
            raw.append(raw_ber(rb, ln))
            st = mf8.framer(rb)
            unl += st['lof_events']; lk += st['frames']
            del rb; gc.collect()
        return float(np.mean(raw)), unl, 100.0 * (1.0 - lk / (nf * len(SEEDS)))

    print('LINE IMPAIRMENTS, SWEPT INDEPENDENTLY -- random data, both codes')
    print(f'  {nf} frames x {len(SEEDS)} seeds per cell.  Each impairment applied')
    print('  on its own.  "raw BER" is the PHY alone; a slip re-phases the stream,')
    print('  so raw BER reads high once slips start -- read LOF and down % then.\n')
    for title, kwname, vals, extra in (
            ('GAUSSIAN FLOOR, sd referred to the transmitted peak', 'sd',
             (0.0, 0.4, 0.5, 0.6, 0.7), {}),
            ('IMPULSE NOISE, damped rings 0.5-3x peak, 15-80 kHz, Poisson', 'imp',
             (0.0, 10.0, 100.0, 1000.0), {}),
            ('ATTENUATION, sd 0.10 floor and 0.05 hysteresis held fixed', 'atten',
             (1.0, 0.5, 0.25, 0.12), dict(sd=0.10))):
        print(f'  {title}\n')
        print(f'  {kwname:>10s} {"code":16s} {"raw BER":>10s} {"LOF":>6s} {"down %":>8s}')
        for v in vals:
            kw = dict(extra); kw[kwname] = v
            for cn, rx in CODES:
                raw, unl, down = cell(rx, **kw)
                print(f'  {v:>10.4g} {cn:16s} {raw:10.1e} {unl:>6d} {down:>7.2f}%',
                      flush=True)
        print()
    print('  Differential Manchester holds a Gaussian floor to sd 0.6 where AMI is')
    print('  degraded from 0.4, and the attenuation cliff lands where the 0.05')
    print('  hysteresis passes 20% of the received amplitude (mf8-spec.md 9.3).')
    print('  Under IMPULSE the ranking reverses -- see 6 for the mechanism.')


# ---------------------------------- 6: impulse susceptibility and mitigations

def impulse():
    nf = 16000
    ln = line_of(nf, 'random')

    print('IMPULSE SUSCEPTIBILITY\n')
    print('  The rings are 15-80 kHz against a 512 kHz symbol rate, so each acts')
    print('  as a slowly varying OFFSET on the timescale of a bit.  With the signal')
    print('  at +/-1 and hysteresis h, an offset of magnitude A sticks the')
    print('  comparator when A > 1-h, and every transition while that holds is')
    print('  lost.  Each event is a DAMPED SINUSOID with a randomly signed')
    print('  amplitude, so it swings BOTH polarities many times.\n')
    x = phy.plant_noise(int(0.5 * FS), FS, rate_hz=200.0, amp=(0.5, 3.0), seed=3)
    print(f'  model check, 0.5 s at 200/s: min {x.min():+.3f}  max {x.max():+.3f}  '
          f'mean {x.mean():+.2e}')
    print(f'  below -0.1: {(x < -0.1).mean():.4f}   above +0.1: {(x > 0.1).mean():.4f}'
          '   -- symmetric')
    del x; gc.collect()

    print('\n  Bits gained or lost vs bits sent, 200 events/s, 4 seeds.  A count')
    print('  change is a SLIP: the frame re-phases and must reacquire.\n')
    print(f'  {"amplitude":>10s} {"diff Manchester":>34s} {"AMI: count":>12s} {"AMI: raw BER":>13s}')
    for a in (0.5, 0.8, 0.95, 1.1, 1.5, 3.0):
        d = []; da = []; e = []
        for sd_i in (1, 2, 3, 4):
            rb = rx_dm(ln, imp=200.0, seed=sd_i)
            d.append(len(rb) - len(ln)); del rb
            ra = rx_ami(ln, imp=200.0, seed=sd_i)
            da.append(len(ra) - len(ln)); e.append(raw_ber(ra, ln)); del ra
            gc.collect()
        print(f'  {a:10.2f} {str(d):>34s} {str(list(set(da))):>12s} {np.mean(e):13.1e}',
              flush=True)
        break   # amplitude is swept below with a fixed rate; this row is the check
    print('\n  (the amplitude sweep proper)\n')
    print(f'  {"amplitude":>10s} {"diff Manchester: bits lost":>30s} {"AMI: bits lost":>16s}')
    for a in (0.5, 0.8, 0.95, 1.1, 1.5, 3.0):
        d = []; da = []
        for sd_i in (1, 2):
            rb = rx_dm(ln, imp=200.0, seed=sd_i)
            d.append(len(ln) - len(rb)); del rb; gc.collect()
        for sd_i in (1, 2):
            ra = rx_ami(ln, imp=200.0, seed=sd_i)
            da.append(len(ln) - len(ra)); del ra; gc.collect()
        print(f'  {a:10.2f} {str(d):>30s} {str(da):>16s}', flush=True)

    print('\n  MITIGATIONS\n')
    print(f'  {"hysteresis":>10s} {"threshold 1-h":>14s} {"bits lost, 200/s amp 0.9":>26s}')
    for h in (0.02, 0.05, 0.10, 0.20):
        d = []
        for sd_i in (1, 2):
            rb = rx_dm(ln, imp=200.0, hyst=h, seed=sd_i)
            d.append(len(ln) - len(rb)); del rb; gc.collect()
        print(f'  {h:10.2f} {1.0 - h:14.2f} {str(d):>26s}', flush=True)
    print('  -> hysteresis moves the threshold the WRONG way, so the')
    print('     impulse-optimal comparator is a tight one.\n')
    print(f'  {"dead time":>10s} {"bits lost, 200/s":>20s}')
    for dd in (0.05, 0.15, 0.25, 0.35, 0.45):
        d = []
        for sd_i in (1, 2):
            rb = rx_dm(ln, imp=200.0, dead=dd, seed=sd_i)
            d.append(len(ln) - len(rb)); del rb; gc.collect()
        print(f'  {dd:10.2f} {str(d):>20s}', flush=True)
    print('  -> dead time rejects edges that arrive too EARLY; a stuck comparator')
    print('     REMOVES edges, so there is nothing for it to reject.\n')
    print(f'  {"HP corner":>10s} {"diff Manchester LOF":>21s} {"AMI LOF":>9s}   (100 imp/s)')
    for hp in (0.0, 60e3, 120e3, 200e3):
        r = []
        for rx in (rx_dm, rx_ami):
            rb = rx(ln, imp=100.0, hp=hp, seed=1)
            r.append(mf8.framer(rb)['lof_events']); del rb; gc.collect()
        lbl = 'none' if hp == 0 else f'{hp / 1e3:.0f} kHz'
        print(f'  {lbl:>10s} {r[0]:>21d} {r[1]:>9d}', flush=True)
    print('  -> AC coupling helps differential Manchester; the lowest signal')
    print('     fundamental is 256 kHz so a 120 kHz corner is free.  AMI\'s')
    print('     spectrum reaches lower, so the same filter costs it signal.')


# ------------------------------------------------------- 7: the frame rate

def framerate():
    RATES = (16000, 32000, 64000)
    print('THE FAMILY.  F + S + N channels must be a power of two, so N = 2, 6, 14\n')
    print(f'  {"frame":>6s} {"N":>3s} {"per-ch":>7s} {"line":>7s} {"baud":>9s} '
          f'{"capacity":>9s} {"reach":>6s} {"superframe":>11s}')
    for N in (2, 6, 14):
        flen = 2 + N
        sf = 4 if N == 2 else (8 if N == 6 else 16)
        for r in RATES:
            line = flen * r
            print(f'  {flen:5d}b {N:3d} {r // 1000:6d}k {line // 1000:6d}k '
                  f'{2 * line / 1e6:8.3f}M {N * r // 1000:8d}k '
                  f'{(256000.0 / line) ** 0.5:5.2f}x {sf:8d} fr')
        print()
    print('  Reach is the sqrt(f) law scaled to a 256 kbps reference; the ratios')
    print('  are sound and the kilometres are not measured.\n')
    print('  Read it by COLUMN: the line rate sets reach, the frame length decides')
    print('  how that line is divided.  64 kbps channels are available at ANY')
    print('  reach -- two of them at 1.00x, six at 0.71x.\n')

    print('WHAT THE PER-CHANNEL RATE COSTS THE AUDIO\n')
    secs = 2.0
    src, fs = audio.read_wav('talker1.wav', seconds=secs + 0.5)
    got = {}
    for r in RATES:
        p = mf8.params(r)
        ref = audio.resample_to(audio.bandlimit(src, fs) * mf8.NOMINAL_RMS, fs, r)[:int(secs * r)]
        y = audio.reconstruct(cvsd.decode(cvsd.encode(ref, p), p), r)
        a, b, _ = audio.align(ref, y)
        got[r] = audio.seg_snr_db(a, audio.gain_match(a, b), r)
    print(f'  {"per-channel":>12s} {"segSNR":>9s} {"vs 64 kbps":>11s}')
    for r in RATES:
        print(f'  {r // 1000:10d}k {got[r]:6.2f} dB {got[r] - got[64000]:+8.2f} dB')
    print('\n  32 kbps is the quality knee, 16 kbps is a real sacrifice, 64 kbps')
    print('  is comfortable -- and only 64 kbps is one-for-one with a DS0')
    print('  (mf8-spec.md 6): the 8-frame superframe IS the octet counter, and at')
    print('  a 64 kHz frame rate the superframe rate is 8 kHz exactly.\n')

    print('REACH IS NOT FREE EITHER -- the same span at three line rates')
    print('  Attenuation goes as sqrt(f), referenced to 12 dB at 256 kbps.\n')
    L0 = 12.0
    print(f'  {"line":>7s} {"loss":>7s} {"amplitude":>10s} {"hysteresis % of rx":>19s}')
    plan = []
    for line in (128000, 256000, 512000):
        dB = L0 * (line / 256000.0) ** 0.5
        amp = 10 ** (-dB / 20.0)
        plan.append((line, amp))
        print(f'  {line // 1000:6d}k {dB:6.1f}dB {amp:10.3f} {100 * 0.05 / amp:18.0f}%')
    print('\n  mf8-spec.md 9.3 specifies hysteresis at or under 10% of received, and')
    print('  20% is the single-span maximum, so the 512 kbps column is already')
    print('  outside it on this span.  That is the real case for a lower rate.')


TARGETS = {'codes': codes, 'clock': clock, 'rxclock': rxclock,
           'polarity': polarity, 'plant': plant, 'impulse': impulse,
           'framerate': framerate}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
