"""
Framing battery for a 16-bit eight-channel frame: exchange/mf8-unit.md §4.2.

Family geometry, 16 bits at a 64 kHz frame rate, 1024 kbps / 2.048 MBaud:

    bit  0    1  2  3  4  5  6  7     8    9   10 11 12 13 14 15
       [ F ][ C0 C1 C2 C3 C4 C5 C6 ][ S ][ C7][ P  R  K0 K1 K2 K3 ]

F at 0, S at 8 (opposite, same as N = 14).  Eight payload C.  Six overhead
seats that are not ports: parity, remote alarm, four condition bits.
Superframe 16 frames; F word 0xFFFE = 1111111111111110, zero at state 15
(the 4-bit counter's wrap).  Guard 0,8 = 0,1.

The 8-bit spec model in mf8.py and the 10-bit battery in mf8_10.py are not
touched.

Usage:  python3 sim/mf8_16.py            the whole battery
        python3 sim/mf8_16.py word
        python3 sim/mf8_16.py sfphase
        python3 sim/mf8_16.py skew
        python3 sim/mf8_16.py guard
        python3 sim/mf8_16.py seats
        python3 sim/mf8_16.py errors
"""
import os, sys, itertools
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio, cvsd

RATE = 64000
NCH = 8
FLEN = 16
SF = 16
SBIT = 8
WORD = 0xFFFE                               # 1111111111111110, zero at 15
FIXED = {0: 0, 8: 1}
CSEATS = [1, 2, 3, 4, 5, 6, 7, 9]           # C0..C7; (C0, C7) are eight apart
OSEATS = [10, 11, 12, 13, 14, 15]           # P, R, K0..K3 — not ports
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


def slot_map(fixed=None):
    """A_n sits at the superframe state equal to C_n's frame bit."""
    fixed = FIXED if fixed is None else fixed
    return {s: i for i, s in enumerate(CSEATS) if s not in fixed}


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
    return pattern([(b >> (7 - k)) & 1 for k in range(8)], nf)


def wordlane(word, nf, nbits=SF):
    return pattern(fbits(word, nbits), nf)


def talker(n, seed=1):
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


def build(C, A, word=WORD, sbit=SBIT, fixed=None, slot=None):
    fixed = FIXED if fixed is None else fixed
    slot = slot_map(fixed) if slot is None else slot
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
    for j, b in enumerate(CSEATS):
        line[:, b] = C[j][:nf]
    # overhead seats idle low: the unit generates them, they are not data
    return line.reshape(-1)


def framer(line, skew=0, confirm=CONFIRM, up=2, dn=1, trip=TRIP, gtrip=TRIP,
           word=WORD, sbit=SBIT, fixed=None):
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
        run = mx = 0
        for v in (lane == e):
            run = run + 1 if v else 0
            mx = max(mx, run)
        best = max(best, mx)
    return best


def hooks():
    return itertools.product((0, 1), repeat=NCH)


def word():
    print('THE F WORD — 16-bit superframe\n')
    print('  F is a 16-bit word over the superframe.  Acquisition still wants')
    print('  32 consecutive matches.  A payload lane whose longest run is')
    print('  under 32 is rejected deterministically.\n')
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
        'period-2':      pattern([1, 0] * (SF // 2), nf),
    }
    CANDS = [
        (0xAAAA, '1010..  period 2'),
        (0x5555, '0101..  period 2, other'),
        (0x7FFF, '0111..1  one zero at 0'),
        (0xFFFE, '1111..10  one zero at 15  (wrap)'),
        (0xFFFD, '1111..01  one zero at 14'),
        (0xFEFE, '1111111011111110  0xFE repeated'),
        (0xFFFC, '1111..00  two zeros'),
    ]
    print('  Longest run of consecutive frames a payload lane matches the word.\n')
    names = list(lanes)
    print(f'  {"word":40s} ' + ' '.join(f'{n:>13s}' for n in names))
    for w, lbl in CANDS:
        row = [longest_run(lanes[n], w) for n in names]
        print(f'  {lbl:40s} ' + ' '.join(f'{v:13d}' for v in row), flush=True)
    print('\n  0xFFFE is the analogue of 0xFE / 0x3FE: one zero, at the last')
    print('  state, so a 4-bit counter wrapping at 15 is the F generator.')


def sfphase():
    print('SUPERFRAME PHASE — 16-bit word against itself\n')
    exp = fbits(WORD)
    print('  0xFFFE 1111111111111110\n')
    print(f'    {"offset":>7s} {"match of 16":>12s} {"longest good run":>18s}')
    for d in range(SF):
        rot = np.roll(exp, -d)
        m = (rot == exp)
        seq = np.tile(m, 4)
        run = mx = 0
        for v in seq:
            run = run + 1 if v else 0
            mx = max(mx, run)
        print(f'    {d:>7d} {int(m.sum()):>12d} {mx:>18d}')
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
    print(f'\n  wrong superframe phases admissible over all {2 ** NCH} hook')
    print(f'  states, 0xFFFE and guard 0,8 = 0,1: {bad}')


def skew():
    print('SKEW — which two lanes the check reads at a wrong bit alignment\n')
    print('  The check reads bit 0 as F and bit 8 as S.  At skew d it reads')
    print('  bit d as F and bit (d+8) mod 16 as S.\n')
    names = {0: 'F', SBIT: 'S'}
    for i, b in enumerate(CSEATS):
        names[b] = f'C{i}'
    for i, b in enumerate(OSEATS):
        names[b] = f'K{i}'
    print(f'  {"skew":>5s}  {"as F":>6s}  {"as S":>6s}  what')
    for d in range(FLEN):
        f_l, s_l = names[d], names[(d + SBIT) % FLEN]
        if d == 0:
            what = 'true alignment'
        elif d == SBIT:
            what = 'header on itself'
        elif {d, (d + SBIT) % FLEN} <= set(CSEATS):
            what = 'two payload lanes, eight seats apart'
        else:
            what = 'payload or overhead, eight seats apart'
        print(f'  {d:>5d}  {f_l:>6s}  {s_l:>6s}  {what}')
    print('\n  Eight C plus F and S opposite cannot avoid every C-C pair at')
    print('  distance 8: (C0, C7) are bits 1 and 9.  Overhead occupies the')
    print('  other six partners.  Header-on-itself is skew 8.')


def hooklines(C, sbit=SBIT, word=WORD, fixed=None, slot=None):
    fixed = FIXED if fixed is None else fixed
    slot = slot_map(fixed) if slot is None else slot
    n0 = 200
    nfr = 2 * SF + 1
    sfc = np.arange(nfr) % SF
    base = np.zeros((nfr, FLEN), np.uint8)
    base[:, 0] = fbits(word)[sfc]
    for j, b in enumerate(CSEATS):
        base[:, b] = C[j][n0:n0 + nfr]
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


def hold_count(lines, sbit=SBIT, word=WORD, fixed=None):
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


def holds(lines, sbit=SBIT, word=WORD, fixed=None):
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
    return ok.all(axis=3).any(axis=2).any(axis=1)


def guard():
    print('GUARD POSITION — 16-state superframe\n')
    print('  0 and 8 are half a superframe, both even.  A period-2 lane fails')
    print('  0,8 = 0,1.  256 hook states × 16 skews = 4096 per cell.\n')
    nf = 1200
    sil = cvsd_lane(nf, 'silence')
    W = wordlane(WORD, nf)
    LAYOUTS = [
        ('0,8 = 0,1  (family analogue)', {0: 0, 8: 1}),
        ('0,8 = 1,0',                    {0: 1, 8: 0}),
        ('0,7 = 0,1  (odd, analogue of 0,5)', {0: 0, 7: 1}),
        ('0,4 = 0,1',                    {0: 0, 4: 1}),
        ('0,8 = F word there',           {0: int(fbits()[0]), 8: int(fbits()[8])}),
    ]

    def scan(C, fixed):
        return hold_count(hooklines(C, fixed=fixed), word=WORD, fixed=fixed)

    def voice_rate(fixed):
        spn = cvsd.encode(talker(64000, 7), params())
        ns = len(spn) // SF
        ok = np.ones(ns, bool)
        for st, v in fixed.items():
            ok &= spn[st:ns * SF:SF] == v
        run = np.zeros(ns + 1, int)
        for i in range(ns):
            run[i + 1] = run[i] + 1 if ok[i] else 0
        return float((run[4:] >= 4).mean())

    tot = 2 ** NCH * FLEN
    print(f'  {"layout":36s} {"F word every":>14s} {"one data, worst":>16s} '
          f'{"idle every":>12s} {"voice 4-run":>12s}')
    for name, fixed in LAYOUTS:
        nch = len(slot_map(fixed))
        every = scan([W] * nch + [sil] * (NCH - nch), fixed)
        worst = 0
        for j in range(nch):
            C = [W if i == j else sil for i in range(NCH)]
            worst = max(worst, scan(C, fixed))
        idle_all = scan([sil] * NCH, fixed)
        p4 = voice_rate(fixed)
        vr = f'1 in {1 / max(p4, 1e-12):.0f}' if p4 else 'never'
        print(f'  {name:36s} {f"{every} / {tot}":>14s} {f"{worst} / {tot}":>16s} '
              f'{f"{idle_all} / {tot}":>12s} {vr:>12s}', flush=True)
    print('\n  0xFFFE is 1 at states 0 and 8, so the F word fails 0,8 = 0,1.')


def sweep_octet(idle, W, fixed=None):
    nf = len(idle[0])
    patterns = [octet(b, nf) for b in range(256)]
    single = []
    for seat in range(NCH):
        bad = [b for b, lane in enumerate(patterns)
               if holds(hooklines([lane if i == seat else idle[i]
                                   for i in range(NCH)], fixed=fixed),
                        fixed=fixed).any()]
        single.append(bad)
    pairs = {}
    for i in range(NCH):
        for j in range(i + 1, NCH):
            n = 0
            for lane in patterns:
                n += int(holds(hooklines(
                    [W if k == i else (lane if k == j else idle[k])
                     for k in range(NCH)], fixed=fixed),
                    fixed=fixed).sum())
                n += int(holds(hooklines(
                    [W if k == j else (lane if k == i else idle[k])
                     for k in range(NCH)], fixed=fixed),
                    fixed=fixed).sum())
            if n:
                pairs[i + 1, j + 1] = n
    return single, pairs


def seats():
    print('SLOT RULES — 16-bit frame, S at bit 8, word 0xFFFE, guard 0,8 = 0,1\n')
    print('  Payload seats C0..C7 at bits 1-7 and 9.  The only payload pair')
    print('  eight wire-bits apart is (C0, C7).\n')
    nf = 400
    sil = cvsd_lane(nf, 'silence')
    idle = [np.roll(sil, 13 * i) for i in range(NCH)]
    W = wordlane(WORD, nf)
    tot = 2 ** NCH * FLEN

    print('  1. PCM octets, every seat, then F word vs every octet in another.\n')
    single, pairs = sweep_octet(idle, W)
    print('     one card, octets that hold:  '
          + '  '.join(f'C{s}: {len(b)}' for s, b in enumerate(single)))
    unsafe = sorted(pairs)
    print('     two cards, F word vs every octet:')
    if not unsafe:
        print('       none hold')
    for pr in unsafe:
        print(f'       C{pr[0] - 1},C{pr[1] - 1}: {pairs[pr]} (octet, hook) holds')
    print(flush=True)

    print('  2. Named layouts.  Denominator 256 hooks × 16 skews.\n')
    print(f'  {"layout":52s} {"holds":>12s}')

    def scan(C, label):
        n = hold_count(hooklines(C), fixed=FIXED)
        print(f'  {label:52s} {f"{n} / {tot}":>12s}', flush=True)

    for j in range(NCH):
        scan([W if i == j else idle[i] for i in range(NCH)],
             f'  C{j} = F word, rest idle')
    scan([W if i in (0, 7) else idle[i] for i in range(NCH)],
         '  C0 and C7 = F word (eight apart); rest idle')
    scan([W if i == 0 else idle[i] for i in range(NCH)],
         '  C0 = F word, C7 idle')
    rg = np.random.default_rng(17)
    R = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    scan(R, '  eight data cards, random content')
    scan([octet(0xFE, nf)] * NCH, '  eight PCM cards carrying 0xFE')
    scan([W] * NCH, '  F word in every payload seat')

    print('\n  3. Residual: F word in C0, VOICE in C7 (eight apart).\n')
    spnom = cvsd.encode(talker(8 * 64000, 9), params())
    ns = len(spnom) // SF
    ok = np.ones(ns, bool)
    for st, v in FIXED.items():
        ok &= spnom[st:ns * SF:SF] == v
    run = np.zeros(ns + 1, int)
    for i in range(ns):
        run[i + 1] = run[i] + 1 if ok[i] else 0
    p4 = float((run[4:] >= 4).mean())
    print(f'     Speech satisfies 0,8 four superframes running once in '
          f'{1 / max(p4, 1e-12):.0f}.')
    nf3 = 32000
    sil3 = cvsd_lane(nf3, 'silence')
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
                 (spnom[o:o + nf3] if i == 7 else np.roll(sil3, 13 * i))
                 for i in range(NCH)]
            g = framer(build(C, [np.zeros(nf3, np.uint8)] * NCH),
                       skew=1, gtrip=gtrip)
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


def errors():
    nf = 200000
    rg = np.random.default_rng(11)
    C = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    A = [np.full(nf, (0, 0, 0, 1, 0, 0, 0, 0)[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)
    print('LINE ERRORS — tracking, +2/-1 trip-12, 16-bit frame, guard 0,8 = 0,1\n')
    print(f'  {"line BER":>9s} {"locked frames":>14s} {"LOF events":>11s} '
          f'{"of which guard":>15s} {"off-phase":>10s} {"time down":>10s}')
    for ber in (0.0, 1e-4, 1e-3, 1e-2, 3e-2):
        x = impair(ln, ber=ber, seed=5) if ber else ln
        st = framer(x)
        down = 100.0 * (1.0 - st['frames'] / nf)
        print(f'  {ber:9.0e} {st["frames"]:>14d} {st["lof_events"]:>11d} '
              f'{st["guard_lof"]:>15d} {st["off_phase"]:>10d} {down:>9.2f}%',
              flush=True)

    print('\nRESYNC after an induced slip, every slip size\n')
    at = (nf // 2) * FLEN
    print(f'  {"slip":>5s} {"frames misaligned":>19s} {"frames to relock":>18s}')
    for k in range(1, FLEN):
        sl = slip(ln, at, n=k)
        st = framer(sl)
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
    'seats': seats, 'errors': errors,
}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
