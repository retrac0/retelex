"""
Framing battery for the 10-bit eight-channel header of exchange/analysis/eight-channel-mf8.md §4.1.

Frame, 10 bits at a 64 kHz frame rate:

    [ F ][ C0 ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ][ C7 ]

Superframe, 10 frames; S at bit 5 (half a frame from F).  Default F word
0x3FE = 1111111110, one zero at state 9.  Default guard 0,5 = 0,1 — the
analogue of today's 0,4; the battery measures whether that analogue holds,
because 5 is odd and a period-2 lane then sees *different* values at the two
pads.

The 8-bit spec model in mf8.py is not touched.  Acquisition, tracking and
the two counters are the same rules (32 good frames, +2/-1 trip 12, F and
guard counted separately).  The hunt looks for the word's unique zero and
loads that superframe state, then counts.

**Measured (`python3 sim/mf8_10.py`, sim/mf8_10.log):** 0x3FE is the word.
The 0,5 analogue of today's 0,4 pads admits a one-data-card false lock
(period-2 idle satisfies 0,5 = 0,1).  Guard 0,6 = 0,1 is clean.  Slot rule:
PCM octets safe in every pair; period-10 lanes not (1,5)(2,6)(3,7)(4,8).

Usage:  python3 sim/mf8_10.py            the whole battery
        python3 sim/mf8_10.py word       choose the F word
        python3 sim/mf8_10.py sfphase    superframe phase, exhaustive
        python3 sim/mf8_10.py skew       which lanes a wrong alignment reads
        python3 sim/mf8_10.py guard      pad seats, including 0,5 vs same-parity
        python3 sim/mf8_10.py locks      false locks over payload classes
        python3 sim/mf8_10.py seats      the slot rule
        python3 sim/mf8_10.py errors     line errors and resync
"""
import os, sys, itertools
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio, cvsd

RATE = 64000
NCH = 8
FLEN = 10
SF = 10
SBIT = 5
WORD = 0x3FE                                # 1111111110, zero at state 9
FIXED = {0: 0, 5: 1}
NOMINAL_RMS = 0.15
SLEW = {16000: 7000.0, 32000: 12000.0, 64000: 16000.0}
BASE = dict(run_length=3, tau_syl=0.005, tau_int=0.001, companding_db=34.2)
CONFIRM = 32
TRIP = 12


def params(rate=RATE):
    return cvsd.CVSDParams(rate=rate, slew=SLEW[rate], **BASE)


def fbits(word=WORD, sf=SF):
    return np.array([(word >> (sf - 1 - k)) & 1 for k in range(sf)], np.uint8)


def zero_at(word=WORD):
    z = np.flatnonzero(fbits(word) == 0)
    return int(z[0]) if len(z) == 1 else None


def cbit(sbit=SBIT):
    return [b for b in range(FLEN) if b not in (0, sbit)]


def slot_map(fixed=None):
    """A_n sits at the superframe state equal to C_n's frame bit, skipping
    guard states.  With the default 0,5 pads that *is* the C seats."""
    fixed = FIXED if fixed is None else fixed
    free = [s for s in range(SF) if s not in fixed]
    return {s: i for i, s in enumerate(free)}


def impair(line, ber=0.0, seed=1):
    out = line.copy()
    if ber > 0:
        out[np.random.default_rng(seed).random(out.size) < ber] ^= 1
    return out


def slip(line, at, n=1):
    return np.concatenate([line[:at], line[at + n:]])


def pattern(bits, nf):
    bits = np.asarray(bits, np.uint8)
    return np.tile(bits, nf // len(bits) + 1)[:nf]


def octet(b, nf):
    """A data card carrying the 8-bit byte b in every octet, MSB first.
    Period 8 against a 10-frame superframe: lcm 40."""
    return pattern([(b >> (7 - k)) & 1 for k in range(8)], nf)


def wordlane(word, nf, nbits=SF):
    """A lane carrying the n-bit word in every superframe, MSB = state 0."""
    return pattern(fbits(word, nbits), nf)


def guard_lane(fixed, nf):
    bits = np.zeros(SF, np.uint8)
    for st, v in fixed.items():
        bits[st] = v
    return pattern(bits, nf)


def talker(n, seed=1):
    """Band-limited synthetic speech at nominal RMS.  speech30.wav is not in
    the tree; this is the same 300–3400 Hz band and 0.15 rms the 8-bit
    battery uses, not a LibriSpeech clip."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / RATE
    f0 = 120.0 + 18.0 * np.sin(2 * np.pi * 2.7 * t)
    ph = 2 * np.pi * np.cumsum(f0) / RATE
    x = 0.45 * np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.10 * np.sin(3 * ph)
    x += 0.20 * rng.normal(size=n)
    x = audio.bandlimit(x, RATE)
    x *= NOMINAL_RMS / max(x.std(), 1e-9)
    return x


def cvsd_lane(nf, kind='speech', seed=1, roll=0):
    p = params()
    if kind == 'silence':
        x = np.zeros(nf + 64)
    else:
        x = talker(nf + 64, seed)
    b = cvsd.encode(x, p)[:nf]
    return np.roll(b, roll) if roll else b


# --------------------------------------------------------------- transmitter

def build(C, A, word=WORD, sbit=SBIT, fixed=None, slot=None):
    fixed = FIXED if fixed is None else fixed
    slot = slot_map(fixed) if slot is None else slot
    cb = cbit(sbit)
    nf = min(len(c) for c in C)
    sfc = np.arange(nf) % SF
    line = np.zeros((nf, FLEN), np.uint8)
    line[:, 0] = fbits(word)[sfc]
    s = np.zeros(nf, np.uint8)
    for st, ch in slot.items():
        s[sfc == st] = A[ch][sfc == st]
    for st, v in fixed.items():
        s[sfc == st] = v
    line[:, sbit] = s
    for j in range(NCH):
        line[:, cb[j]] = C[j][:nf]
    return line.reshape(-1)


# ------------------------------------------------------------------ receiver

def framer(line, skew=0, confirm=CONFIRM, up=2, dn=1, trip=TRIP, gtrip=TRIP,
           word=WORD, sbit=SBIT, fixed=None):
    """Same predictive check as mf8.py, on a 10-bit / 10-state frame.

    good := F == word[sfc] AND (sfc not a guard OR S == FIXED[sfc]).
    Hunt: the word's unique zero is the phase marker.  Ten frames with no
    zero: slip one line bit.  Track: +2/-1 floor 0 trip 12, and a second
    counter on the two guard checks.
    """
    fixed = FIXED if fixed is None else fixed
    Z = zero_at(word)
    if Z is None:
        raise ValueError('framer wants a word with exactly one zero')
    if skew:
        line = np.roll(line, -skew)
    true = (FLEN - skew % FLEN) % FLEN
    exp = fbits(word)
    i = cc = wait = err = gerr = sfc = 0
    locked = False
    st = dict(lock_bit=None, false_lock=False, sf_offset=None,
              lof_events=0, guard_lof=0, frames=0, off_phase=0, release=None)
    pos = []
    N = line.size
    while i + FLEN <= N:
        f_bit = int(line[i])
        s_bit = int(line[i + sbit]) if i + sbit < N else 0

        if not locked and cc == 0:
            if f_bit == 0:
                sfc = (Z + 1) % SF
                cc = 1
                wait = 0
                i += FLEN
            else:
                wait += 1
                if wait >= SF:
                    wait = 0
                    i += 1
                else:
                    i += FLEN
            continue

        good_f = (f_bit == exp[sfc])
        good_g = (sfc not in fixed) or (s_bit == fixed[sfc])
        good = good_f and good_g

        if not locked:
            if good:
                cc += 1
                if cc >= confirm:
                    locked = True
                    gerr = 0
                    if st['lock_bit'] is None:
                        st['lock_bit'] = i
                        st['false_lock'] = (i % FLEN) != true
                        st['sf_offset'] = (sfc - ((i + skew) // FLEN)) % SF
                i += FLEN
                sfc = (sfc + 1) % SF
            else:
                cc = wait = 0
                i += 1
            continue

        err = max(0, err - dn) if good else err + up
        if gtrip and sfc in fixed:
            gerr = max(0, gerr - dn) if good_g else gerr + up
        if err >= trip or (gtrip and gerr >= gtrip):
            if gtrip and gerr >= gtrip:
                st['guard_lof'] += 1
            if st['false_lock'] and st['release'] is None and (i % FLEN) != true:
                st['release'] = (i - st['lock_bit']) // FLEN
            locked = False
            cc = err = gerr = wait = 0
            st['lof_events'] += 1
            i += 1
            continue
        st['frames'] += 1
        if (i % FLEN) != true:
            st['off_phase'] += 1
        pos.append(i)
        i += FLEN
        sfc = (sfc + 1) % SF
    st['pos'] = np.array(pos, np.int64)
    return st


def longest_run(lane, word):
    exp = fbits(word)
    best = 0
    for ph in range(SF):
        e = exp[(np.arange(len(lane)) + ph) % SF]
        m = (lane == e)
        run = mx = 0
        for v in m:
            run = run + 1 if v else 0
            mx = max(mx, run)
        best = max(best, mx)
    return best


def hooks():
    return itertools.product((0, 1), repeat=NCH)


# ------------------------------------------------------------ 1: the F word

def word():
    print('THE F WORD — 10-bit superframe\n')
    print('  F carries a 10-bit word over the superframe, so one check pins bit')
    print('  alignment and superframe phase.  Acquisition still wants 32')
    print('  consecutive matches.  A payload lane whose longest run is under 32')
    print('  is rejected deterministically.\n')
    nf = 8192
    p = params()
    sp = cvsd.encode(talker(nf + 64, 1), p)[:nf]
    sil = cvsd.encode(np.zeros(nf + 64), p)[:nf]
    lanes = {
        'CVSD speech':   sp,
        'CVSD silence':  sil,
        'constant 1':    np.ones(nf, np.uint8),
        'constant 0':    np.zeros(nf, np.uint8),
        'random':        (np.random.default_rng(3).random(nf) < 0.5).astype(np.uint8),
        'octet 0xFE':    octet(0xFE, nf),
        'octet 0xAA':    octet(0xAA, nf),
        'period-2 10b':  pattern([1, 0] * (SF // 2), nf),
    }
    CANDS = [
        (0x2AA, '1010101010  period 2'),
        (0x155, '0101010101  period 2, other'),
        (0x1FF, '0111111111  one zero at 0'),
        (0x3FE, '1111111110  one zero at 9  (lean)'),
        (0x3FB, '1111111011  one zero at 7'),
        (0x3FD, '1111111101  one zero at 8'),
        (0x3FC, '1111111100  two zeros'),
        (0x3F8, '1111111000  three zeros'),
        (0x2AA ^ 0x001, '1010101011'),
    ]
    print('  Longest run of consecutive frames a payload lane matches the word,')
    print('  over every superframe phase.\n')
    names = list(lanes)
    print(f'  {"word":40s} ' + ' '.join(f'{n:>13s}' for n in names))
    for w, lbl in CANDS:
        row = [longest_run(lanes[n], w) for n in names]
        print(f'  {lbl:40s} ' + ' '.join(f'{v:13d}' for v in row), flush=True)
    print('\n  0x2AA / 0x155 *are* period-2, which CVSD silence and FILL are.')
    print('  0x3FE is the analogue of 0xFE: one zero, at the last state, so the')
    print('  decade counter\'s wrap (load at 9) is the F generator.  0x3FB keeps')
    print('  today\'s NAND(q2,q1,q0) and adds ~q3.  The table says which of them')
    print('  a payload can hold for 32 frames.')


# ------------------------------------------- 2: superframe phase, exact

def sfphase():
    print('SUPERFRAME PHASE — 10-bit word against itself\n')
    print('  At offset d the receiver expects the word and sees it rotated by d.')
    print('  Acquisition needs 32 in a row.\n')
    for w, lbl in ((WORD, '0x3FE 1111111110  lean'),
                   (0x3FB, '0x3FB 1111111011  zero at 7'),
                   (0x1FF, '0x1FF 0111111111  zero at 0')):
        exp = fbits(w)
        print(f'  {lbl}')
        print(f'    {"offset":>7s} {"match of 10":>12s} {"longest good run":>18s}')
        for d in range(SF):
            rot = np.roll(exp, -d)
            m = (rot == exp)
            seq = np.tile(m, 8)
            run = mx = 0
            for v in seq:
                run = run + 1 if v else 0
                mx = max(mx, run)
            print(f'    {d:>7d} {int(m.sum()):>12d} {mx:>18d}')
        print()
    # exhaustive: can a wrong phase pass F and the default guard for every frame
    # of a superframe, under any hook state?
    exp = fbits(WORD)
    slot = slot_map(FIXED)
    bad = 0
    for h in hooks():
        A = [0] * SF
        for st, ch in slot.items():
            A[st] = h[ch]
        for st, v in FIXED.items():
            A[st] = v
        for d in range(1, SF):
            ok = True
            for k in range(SF):
                if exp[k] != exp[(k + d) % SF]:
                    ok = False
                    break
                if k in FIXED and A[(k + d) % SF] != FIXED[k]:
                    ok = False
                    break
            bad += ok
    print(f'  wrong superframe phases admissible over all {2 ** NCH} hook states,')
    print(f'  0x3FE and guard 0,5 = 0,1: {bad}')


# ----------------------------------------------- 3: which lanes a skew reads

def skew():
    print('SKEW — which two lanes the check reads at a wrong bit alignment\n')
    print('  The check reads bit 0 as F and bit 5 as S.  At skew d it reads')
    print('  bit d as F and bit (d+5) mod 10 as S.\n')
    names = {0: 'F', SBIT: 'S'}
    for i, b in enumerate(cbit()):
        names[b] = f'C{i}'
    print(f'  {"skew":>5s}  {"as F":>6s}  {"as S":>6s}  what')
    for d in range(FLEN):
        f_l = names[d]
        s_l = names[(d + SBIT) % FLEN]
        if d == 0:
            what = 'true alignment'
        elif d == SBIT:
            what = 'header on itself'
        else:
            what = 'two payload lanes, five seats apart on the wire'
        print(f'  {d:>5d}  {f_l:>6s}  {s_l:>6s}  {what}')
    print('\n  Header-on-itself is skew 5, the analogue of today\'s skew 4.')
    print('  Every other wrong skew is a C pair five wire-bits apart:')
    print('  (C0,C4) (C1,C5) (C2,C6) (C3,C7) and the swaps.  That is the slot')
    print('  rule to measure: not those four pairs.')
    print('\n  0x3FE starts with 1; G0 = 0, so S never matches the word and')
    print('  header-on-itself fails the F check for every hook state.  The')
    print('  F lane as guard is 1,1 at states 0 and 5; the pads want 0,1.')


# ------------------------------------------------- 4: guard pad seats

def guard():
    print('GUARD POSITION — 10-state superframe\n')
    print('  0 and 5 are half a superframe apart, the analogue of 0 and 4.')
    print('  5 is odd, so they have *different* parity: a period-2 lane')
    print('  (CVSD silence, FILL) gives 0 at evens and 1 at odds, which *is*')
    print('  0,5 = 0,1.  Same-parity pads (0,2 / 0,4 / 0,6 / 0,8) are the')
    print('  ones a period-2 lane fails.  False locks over all 256 hook')
    print('  states x 10 skews (2560 per cell).\n')
    nf = 1200
    sil = cvsd_lane(nf, 'silence')
    W = wordlane(WORD, nf)
    p2 = pattern([1, 0] * (nf // 2 + 1), nf)
    LAYOUTS = [
        ('0,5 = 0,1  (lean analogue)', {0: 0, 5: 1}),
        ('0,5 = 1,0',                  {0: 1, 5: 0}),
        ('0,6 = 0,1  (same parity, 6)', {0: 0, 6: 1}),
        ('0,4 = 0,1  (same parity, 4)', {0: 0, 4: 1}),
        ('0,2 = 0,1  (same parity, 2)', {0: 0, 2: 1}),
        ('0,8 = 0,1  (same parity, 8)', {0: 0, 8: 1}),
        ('0,5 = F word there',         {0: int(fbits()[0]), 5: int(fbits()[5])}),
    ]

    def scan(C, fixed):
        """(hook, wrong-skew) pairs whose check passes for two superframes.
        The framer acquires any such pair and never releases it."""
        return hold_count(hooklines(C, fixed=fixed), word=WORD, fixed=fixed)

    def voice_rate(fixed):
        spn = cvsd.encode(talker(64000, 7) * 1.0, params())
        ns = len(spn) // SF
        ok = np.ones(ns, bool)
        for st, v in fixed.items():
            ok &= spn[st:ns * SF:SF] == v
        run = np.zeros(ns + 1, int)
        for i in range(ns):
            run[i + 1] = run[i] + 1 if ok[i] else 0
        return float((run[4:] >= 4).mean())

    print(f'  {"layout":32s} {"F word every lane":>18s} {"one data, worst":>16s} '
          f'{"idle every":>12s} {"voice 4-run":>12s}')
    for name, fixed in LAYOUTS:
        slot = slot_map(fixed)
        nch = len(slot)
        every = scan([W] * nch + [sil] * (NCH - nch), fixed)
        worst = 0
        for j in range(nch):
            C = [W if i == j else sil for i in range(NCH)]
            worst = max(worst, scan(C, fixed))
        idle_all = scan([sil] * NCH, fixed)
        p4 = voice_rate(fixed)
        vr = f'1 in {1 / max(p4, 1e-12):.0f}' if p4 else 'never'
        print(f'  {name:32s} {f"{every} / 2560":>18s} {f"{worst} / 2560":>16s} '
              f'{f"{idle_all} / 2560":>12s} {vr:>12s}', flush=True)
    print('\n  "voice 4-run" is how often speech satisfies the two pads four')
    print('  superframes running — the residual chance-acquisition the guard')
    print('  counter has to release.')


# --------------------------------------------------- 5: false locks, battery

def payloads(nf):
    sp = cvsd_lane(nf, 'speech', 1)
    sil = cvsd_lane(nf, 'silence')
    z = np.zeros(nf, np.uint8)
    o = np.ones(nf, np.uint8)
    rg = np.random.default_rng(5)
    rnd = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    W = wordlane(WORD, nf)
    G = guard_lane(FIXED, nf)
    idle = [np.roll(sil, 13 * j) for j in range(NCH)]
    oct8 = octet(0xB2, nf)
    return {
        'speech':                 [np.roll(sp, 977 * j) for j in range(NCH)],
        'idle (CVSD silence)':    idle,
        'all constant 0':         [z] * NCH,
        'all constant 1':         [o] * NCH,
        'random data':            rnd,
        'octet 10110010':         [oct8] * NCH,
        'one data card, idle':    [oct8 if j == 3 else idle[j] for j in range(NCH)],
        'THE 10-bit F WORD':      [W] * NCH,
        'F word beside silence':  [W if j == 3 else idle[j] for j in range(NCH)],
        'F word + guard pattern': [W if j < 4 else G for j in range(NCH)],
        'period-2 all lanes':     [pattern([1, 0] * (nf // 2 + 1), nf)] * NCH,
        'octet 0xFE all':         [octet(0xFE, nf)] * NCH,
        'octet 0xAA all':         [octet(0xAA, nf)] * NCH,
    }


def locks():
    nf = 8000
    print('FALSE LOCKS — every payload class, every start-up skew\n')
    print(f'  word 0x{WORD:03X}  S at bit {SBIT}  guard {FIXED}')
    print(f'  {2 ** NCH} hook states x {FLEN} skews = {2 ** NCH * FLEN} in the')
    print('  exhaustive rows.\n')
    hooks0 = (0, 0, 0, 1, 0, 0, 0, 0)
    pay = payloads(nf)
    print(f'  {"payload":32s} {"locks":>6s} {"false":>6s} {"wrong sf":>9s} '
          f'{"acq frames":>11s}')
    for nm, C in pay.items():
        A = [np.full(nf, hooks0[j], np.uint8) for j in range(NCH)]
        ln = build(C, A)
        got = [framer(ln, skew=k) for k in range(FLEN)]
        lk = sum(g['lock_bit'] is not None for g in got)
        fl = sum(bool(g['false_lock']) for g in got)
        ws = sum(1 for g in got if g['sf_offset'] not in (None, 0))
        acq = [g['lock_bit'] / FLEN for g in got if g['lock_bit'] is not None]
        a = f'{min(acq):.0f}-{max(acq):.0f}' if acq else '-'
        print(f'  {nm:32s} {lk:>6d} {fl:>6d} {ws:>9d} {a:>11s}', flush=True)

    print('\n  Exhaustive over hook states: (hook, wrong-skew) pairs that hold')
    print('  the check for two superframes (analytic; a pass is forever).')
    print(f'  Denominator {2 ** NCH} hooks × {FLEN} start-up skews.\n')
    tot = 2 ** NCH * FLEN
    print(f'  {"payload":32s} {"holds":>16s}')
    for nm in ('idle (CVSD silence)', 'all constant 0', 'all constant 1',
               'one data card, idle', 'THE 10-bit F WORD', 'F word beside silence',
               'F word + guard pattern', 'period-2 all lanes', 'octet 0xFE all',
               'octet 0xAA all'):
        n = hold_count(hooklines(pay[nm]))
        print(f'  {nm:32s} {f"{n} / {tot}":>16s}', flush=True)


# ------------------------------------------ 6: analytic holds and slot rule

def hooklines(C, sbit=SBIT, word=WORD, fixed=None, slot=None):
    """One payload under every hook state: (256, nfr*FLEN) bits, nfr = 2*SF+1
    frames from frame 200."""
    fixed = FIXED if fixed is None else fixed
    slot = slot_map(fixed) if slot is None else slot
    cb = cbit(sbit)
    n0 = 200
    nfr = 2 * SF + 1
    sfc = np.arange(nfr) % SF
    base = np.zeros((nfr, FLEN), np.uint8)
    base[:, 0] = fbits(word)[sfc]
    for j in range(NCH):
        base[:, cb[j]] = C[j][n0:n0 + nfr]
    nH = 2 ** NCH
    H = np.array(list(hooks()), np.uint8)
    s = np.zeros((nH, nfr), np.uint8)
    for st, ch in slot.items():
        s[:, sfc == st] = H[:, ch:ch + 1]
    for st, v in fixed.items():
        s[:, sfc == st] = v
    out = np.broadcast_to(base, (nH, nfr, FLEN)).copy()
    out[:, :, sbit] = s
    return out.reshape(nH, -1)


def holds(lines, sbit=SBIT, word=WORD, fixed=None):
    """Wrong bit alignment, any receiver phase, passes the check for 2
    superframes.  Periodic lanes: a pass is a pass forever."""
    fixed = FIXED if fixed is None else fixed
    nfr = 2 * SF
    fr = np.arange(nfr)
    idxf = np.arange(1, FLEN)[:, None] + FLEN * fr[None, :]
    R = (np.arange(SF)[:, None] + fr[None, :]) % SF
    exp = fbits(word)
    F = lines[:, idxf][:, :, None, :]
    S = lines[:, idxf + sbit][:, :, None, :]
    ok = (F == exp[R][None, None])
    for st, v in fixed.items():
        ok &= (R != st)[None, None] | (S == v)
    perskew = ok.all(axis=3).any(axis=2)          # (nH, nskew)
    return perskew.any(axis=1)


def hold_count(lines, sbit=SBIT, word=WORD, fixed=None):
    """Number of (hook, wrong-skew) pairs that hold.  Max 256×9; the true
    alignment is not in the skew axis."""
    fixed = FIXED if fixed is None else fixed
    nfr = 2 * SF
    fr = np.arange(nfr)
    idxf = np.arange(1, FLEN)[:, None] + FLEN * fr[None, :]
    R = (np.arange(SF)[:, None] + fr[None, :]) % SF
    exp = fbits(word)
    F = lines[:, idxf][:, :, None, :]
    S = lines[:, idxf + sbit][:, :, None, :]
    ok = (F == exp[R][None, None])
    for st, v in fixed.items():
        ok &= (R != st)[None, None] | (S == v)
    return int(ok.all(axis=3).any(axis=2).sum())


def sweep(sbit, idle, W, kind='octet', fixed=None):
    """Every pattern in every seat, then W in seat i against every pattern in
    seat j.  kind='octet' is a real data card (256 bytes); kind='word10' is
    every 10-bit repeating lane (1024)."""
    nf = len(idle[0])
    if kind == 'octet':
        patterns = [octet(b, nf) for b in range(256)]
        labels = list(range(256))
    else:
        patterns = [wordlane(w, nf) for w in range(2 ** SF)]
        labels = list(range(2 ** SF))
    single = []
    for seat in range(NCH):
        bad = [labels[p] for p, lane in enumerate(patterns)
               if holds(hooklines([lane if i == seat else idle[i]
                                   for i in range(NCH)], sbit, fixed=fixed),
                        sbit, fixed=fixed).any()]
        single.append(bad)
    pairs = {}
    for i in range(NCH):
        for j in range(i + 1, NCH):
            n = 0
            for lane in patterns:
                n += int(holds(hooklines(
                    [W if k == i else (lane if k == j else idle[k])
                     for k in range(NCH)], sbit, fixed=fixed),
                    sbit, fixed=fixed).sum())
                n += int(holds(hooklines(
                    [W if k == j else (lane if k == i else idle[k])
                     for k in range(NCH)], sbit, fixed=fixed),
                    sbit, fixed=fixed).sum())
            if n:
                pairs[i + 1, j + 1] = n
    return single, pairs


def seats():
    print('SLOT RULES — 10-bit frame, S at bit 5, word 0x3FE\n')
    print('  Two guards: 0,5 = 0,1 (the lean analogue, which `guard` found')
    print('  admits a one-data-card hole) and 0,6 = 0,1 (same parity).\n')
    for gname, fixed in (('0,5 = 0,1', {0: 0, 5: 1}),
                         ('0,6 = 0,1', {0: 0, 6: 1})):
        _seats_one(gname, fixed)


def _seats_one(gname, fixed):
    print(f'  --- guard {gname} ---\n')
    nf = 400
    sil = cvsd_lane(nf, 'silence')
    idle = [np.roll(sil, 13 * i) for i in range(NCH)]
    W = wordlane(WORD, nf)
    G = guard_lane(fixed, nf)

    print('  1. Analytic: a hold is a wrong alignment the check passes for two')
    print('     superframes.  One data card, rest CVSD idle; then the F word in')
    print('     one seat against every pattern in another.\n')

    print('     (a) PCM data cards — every 8-bit octet, every seat:')
    single, pairs = sweep(SBIT, idle, W, 'octet', fixed=fixed)
    print('         one card, octets that hold:  '
          + '  '.join(f'seat {s + 1}: {len(b)}' for s, b in enumerate(single)))
    unsafe = sorted(pairs)
    print('         two cards, F word vs every octet:')
    if not unsafe:
        print('           none hold')
    for pr in unsafe:
        print(f'           seats {pr[0]},{pr[1]}: {pairs[pr]} (octet, hook) holds')
    safe = [(i, j) for i in range(1, NCH + 1) for j in range(i + 1, NCH + 1)
            if (i, j) not in unsafe]
    print('           safe: ' + ' '.join(f'({i},{j})' for i, j in safe), flush=True)

    if 6 in fixed:
        print('\n     (b) period-10 lanes — every 10-bit word, every seat (the')
        print('         adversarial "data card" that can carry the F word itself):')
        single10, pairs10 = sweep(SBIT, idle, W, 'word10', fixed=fixed)
        print('         one card, 10-bit words that hold:  '
              + '  '.join(f'seat {s + 1}: {len(b)}' for s, b in enumerate(single10)))
        unsafe10 = sorted(pairs10)
        print('         two cards, F word vs every 10-bit word:')
        if not unsafe10:
            print('           none hold')
        for pr in unsafe10:
            print(f'           seats {pr[0]},{pr[1]}: {pairs10[pr]} (word, hook) holds')
        safe10 = [(i, j) for i in range(1, NCH + 1) for j in range(i + 1, NCH + 1)
                  if (i, j) not in unsafe10]
        print('           safe: ' + ' '.join(f'({i},{j})' for i, j in safe10),
              flush=True)
    else:
        print('\n     (b) period-10 sweep skipped on 0,5 — `guard` already found')
        print('         a one-card hole against idle; the 1024-word scan is on 0,6.')

    print('\n  2. Same analytic hold, named layouts.  Denominator 2560.\n')
    tot = 2 ** NCH * FLEN

    def scan(C, label):
        n = hold_count(hooklines(C, fixed=fixed), fixed=fixed)
        print(f'  {label:52s} {f"{n} / {tot}":>12s}', flush=True)

    print(f'  {"layout":52s} {"holds":>12s}')
    for j in range(NCH):
        scan([W if i == j else idle[i] for i in range(NCH)],
             f'  seat {j + 1} = F word, rest idle')
    for j, k2 in ((0, 4), (1, 5), (2, 6), (3, 7), (0, 1), (3, 4), (4, 5)):
        scan([W if i == j else (G if i == k2 else idle[i]) for i in range(NCH)],
             f'  seats {j + 1},{k2 + 1} = F word, guard pattern; rest idle')
    rg = np.random.default_rng(17)
    R = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    scan(R, '  eight data cards, random content')
    scan([octet(0xFE, nf)] * NCH, '  eight PCM cards carrying 0xFE')

    print('\n  3. Residual: F word in seat 1, VOICE in seat 5 (five apart).')
    print('     Guard lands on speech.  Forced at the first 24 four-superframe')
    print('     matches, 0.5 s runs.\n')
    spnom = cvsd.encode(talker(8 * 64000, 9), params())
    ns = len(spnom) // SF
    ok = np.ones(ns, bool)
    for st, v in fixed.items():
        ok &= spnom[st:ns * SF:SF] == v
    run = np.zeros(ns + 1, int)
    for i in range(ns):
        run[i + 1] = run[i] + 1 if ok[i] else 0
    p4 = float((run[4:] >= 4).mean())
    print(f'     Speech satisfies the {gname} pads four superframes running once in '
          f'{1 / max(p4, 1e-12):.0f}.')
    nf3 = 32000
    sil3 = cvsd_lane(nf3, 'silence')
    slot = slot_map(fixed)
    starts = [int(s) for s in np.flatnonzero(run == 4) - 4
              if s >= 1 and SF * (s - 1) + nf3 <= len(spnom)][:24]
    print(f'     {"tracking":42s} {"acquired":>9s} {"released, frames":>17s} '
          f'{"mean":>10s} {"never":>6s}')
    for gtrip, nm in ((None, 'frame counter only'),
                      (12, 'frame + guard counters')):
        rel = []
        stuck = acq = 0
        for si in starts:
            o = SF * (si - 1)
            C = [wordlane(WORD, nf3) if i == 0 else
                 (spnom[o:o + nf3] if i == 4 else np.roll(sil3, 13 * i))
                 for i in range(NCH)]
            g = framer(build(C, [np.zeros(nf3, np.uint8)] * NCH,
                             fixed=fixed, slot=slot),
                       skew=1, gtrip=gtrip, fixed=fixed)
            if g['false_lock']:
                acq += 1
                if g['release'] is None:
                    stuck += 1
                else:
                    rel.append(g['release'])
        mean = f'{np.mean(rel) / RATE * 1e3:.2f} ms' if rel else '-'
        rng = f'{min(rel)}-{max(rel)}' if rel else '-'
        print(f'     {nm:42s} {f"{acq}/{len(starts)}":>9s} {rng:>17s} '
              f'{mean:>10s} {stuck:>6d}', flush=True)
    print()


# --------------------------------------------- 7: line errors, resync

def errors():
    """Tracking under BER and resync, with the surviving guard 0,6 = 0,1."""
    fixed = {0: 0, 6: 1}
    slot = slot_map(fixed)
    nf = 200000
    rg = np.random.default_rng(11)
    C = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    A = [np.full(nf, (0, 0, 0, 1, 0, 0, 0, 0)[j], np.uint8) for j in range(NCH)]
    ln = build(C, A, fixed=fixed, slot=slot)
    print('LINE ERRORS — tracking, +2/-1 trip-12, 10-bit frame, guard 0,6 = 0,1\n')
    print(f'  {"line BER":>9s} {"locked frames":>14s} {"LOF events":>11s} '
          f'{"of which guard":>15s} {"off-phase":>10s} {"time down":>10s}')
    for ber in (0.0, 1e-4, 1e-3, 1e-2, 3e-2):
        x = impair(ln, ber=ber, seed=5) if ber else ln
        st = framer(x, fixed=fixed)
        down = 100.0 * (1.0 - st['frames'] / nf)
        print(f'  {ber:9.0e} {st["frames"]:>14d} {st["lof_events"]:>11d} '
              f'{st["guard_lof"]:>15d} {st["off_phase"]:>10d} {down:>9.2f}%',
              flush=True)

    print('\nRESYNC after an induced slip, every slip size\n')
    at = (nf // 2) * FLEN
    print(f'  {"slip":>5s} {"frames misaligned":>19s} {"frames to relock":>18s}')
    for k in range(1, FLEN):
        sl = slip(ln, at, n=k)
        st = framer(sl, fixed=fixed)
        pos = st['pos']
        pre, post = pos[pos < at], pos[pos >= at]
        if len(pre) == 0 or len(post) == 0:
            print(f'  {k:>5d} {"-":>19s} {"-":>18s}')
            continue
        base = pre[0] % FLEN
        good = (((post + k) % FLEN) == base)
        bad = int((~good).sum())
        rel = int(np.flatnonzero(good)[0]) if good.any() else -1
        print(f'  {k:>5d} {bad:>19d} {rel if rel >= 0 else "never":>18}',
              flush=True)


TARGETS = {
    'word': word, 'sfphase': sfphase, 'skew': skew, 'guard': guard,
    'locks': locks, 'seats': seats, 'errors': errors,
}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
