"""
Framing battery for a 10-bit eight-channel frame with a 16-state superframe:
exchange/analysis/eight-channel-mf8.md §4.1 (reopened) — the lean with binary SF, not SF = FLEN.

Frame, 10 bits at 64 kHz, 640 kbps / 1.280 MBaud:

    bit:   0     1     2     3     4     5     6     7     8     9
         [ F ][ C0 ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ][ C7 ]

Superframe 16 frames (4 kHz), same as the 16-bit line.  F word 0xFFFE,
zero at state 15 (4-bit counter wrap).  Guard 0,8 = 0,1 (same-parity pads;
half of ten is odd, so 0,5 dies as in mf8_10.py).  Eight A bits at states
1–7 and 9; states 10–15 spare at 4 kHz (R / K-like levels without 64 kbps
seats).  Octet = q[2:0], free.  S is not full.

mf8_10.py (SF = 10) and mf8_16.py are not touched.

Usage:  python3 sim/mf8_10_16.py
        python3 sim/mf8_10_16.py word|sfphase|skew|guard|seats|errors
"""
import os, sys, itertools
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio, cvsd

RATE = 64000
NCH = 8
FLEN = 10
SF = 16
SBIT = 5
WORD = 0xFFFE                               # 1111111111111110, zero at 15
FIXED = {0: 0, 8: 1}
CSEATS = [1, 2, 3, 4, 6, 7, 8, 9]           # C0..C7 frame bits; five apart on wire
ASEATS = [1, 2, 3, 4, 5, 6, 7, 9]           # A0..A7 superframe states (same as 16-bit)
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
    """A_n at ASEATS, skipping guard states.  Not the C wire bits: SF ≠ FLEN."""
    fixed = FIXED if fixed is None else fixed
    return {s: i for i, s in enumerate(ASEATS) if s not in fixed}


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
    print('THE F WORD — 10-bit frame, 16-state superframe\n')
    print('  F is a 16-bit word over the superframe (same as mf8_16.py).')
    print('  Acquisition wants 32 consecutive matches.\n')
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
    print('\n  0xFFFE is the same wrap as the 16-bit line: one NAND of q3..q0.')


def sfphase():
    print('SUPERFRAME PHASE — 0xFFFE on a 10-bit frame\n')
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
    print(f'\n  wrong superframe phases admissible over all {2 ** NCH} hook states:')
    print(f'  {bad}')


def skew():
    print('SKEW — 10-bit frame, S at bit 5\n')
    print('  Check reads bit 0 as F and bit 5 as S.  At skew d it reads')
    print('  bit d as F and bit (d+5) mod 10 as S.\n')
    names = {0: 'F', SBIT: 'S'}
    for i, b in enumerate(CSEATS):
        names[b] = f'C{i}'
    print(f'  {"skew":>5s}  {"as F":>6s}  {"as S":>6s}  what')
    for d in range(FLEN):
        f_l, s_l = names[d], names[(d + SBIT) % FLEN]
        if d == 0:
            what = 'true alignment'
        elif {f_l, s_l} == {'F', 'S'}:
            what = 'header on itself'
        elif f_l.startswith('C') and s_l.startswith('C'):
            what = f'payload pair, five apart ({f_l},{s_l})'
        else:
            what = f'{f_l} and {s_l}'
        print(f'  {d:>5d}  {f_l:>6s}  {s_l:>6s}  {what}')
    print('\n  Payload pairs five apart: (C0,C4) (C1,C5) (C2,C6) (C3,C7).')
    print('  Four unkeyable pairs at an exchange (cf. one on 16-bit).')


def guard():
    print('GUARD — 10-bit frame, 16-state SF, pads on S\n')
    print('  Default candidate 0,8 = 0,1 (same parity as mf8_16).  Half of ten')
    print('  is odd, so 0,5 = 0,1 is the dead analogue (period-2 satisfies it).\n')
    nf = 512
    sil = cvsd_lane(nf, 'silence')
    W = wordlane(WORD, nf)
    LAYOUTS = [
        ('0,8 = 0,1  (family)', {0: 0, 8: 1}),
        ('0,5 = 0,1  (half of ten)', {0: 0, 5: 1}),
        ('0,6 = 0,1  (mf8_10 lean)', {0: 0, 6: 1}),
        ('0,8 = 1,1  (F-word hole)', {0: 1, 8: 1}),
    ]

    def holds_at(C, fixed):
        n = 0
        for h in hooks():
            A = [np.full(nf, h[j], np.uint8) for j in range(NCH)]
            for d in range(FLEN):
                st = framer(build(C, A, fixed=fixed, slot=slot_map(fixed)),
                            skew=d, fixed=fixed)
                if st['false_lock']:
                    n += 1
        return n

    def voice_rate(fixed):
        spnom = cvsd.encode(talker(8 * 64000, 9), params())
        ns = len(spnom) // SF
        ok = np.ones(ns, bool)
        for st, v in fixed.items():
            ok &= spnom[st:ns * SF:SF] == v
        run = np.zeros(ns + 1, int)
        for i in range(ns):
            run[i + 1] = run[i] + 1 if ok[i] else 0
        return float((run[4:] >= 4).mean())

    tot = 2 ** NCH * FLEN
    print(f'  {"layout":36s} {"F word every":>14s} {"one data, worst":>16s} '
          f'{"idle every":>12s} {"voice 4-run":>12s}')
    for name, fixed in LAYOUTS:
        every = holds_at([W] * NCH, fixed)
        worst = 0
        for j in range(NCH):
            C = [W if i == j else sil for i in range(NCH)]
            worst = max(worst, holds_at(C, fixed))
        idle_all = holds_at([sil] * NCH, fixed)
        p4 = voice_rate(fixed)
        vr = f'1 in {1 / max(p4, 1e-12):.0f}' if p4 else 'never'
        print(f'  {name:36s} {f"{every} / {tot}":>14s} {f"{worst} / {tot}":>16s} '
              f'{f"{idle_all} / {tot}":>12s} {vr:>12s}', flush=True)
    print('\n  Prefer 0,8 = 0,1 if clean: same decode as 16-bit, free octet counter.')



def holds(lines, word=WORD, fixed=None):
    """Wrong bit alignment passes the check for 2 superframes (periodic)."""
    fixed = FIXED if fixed is None else fixed
    nfr = 2 * SF
    fr = np.arange(nfr)
    idxf = np.arange(1, FLEN)[:, None] + FLEN * fr[None, :]
    R = (np.arange(SF)[:, None] + fr[None, :]) % SF
    exp = fbits(word)
    F = lines[:, idxf][:, :, None, :]
    S = lines[:, idxf + SBIT][:, :, None, :]
    ok = (F == exp[R][None, None])
    for st, v in fixed.items():
        ok &= (R != st)[None, None] | (S == v)
    perskew = ok.all(axis=3).any(axis=2)
    return perskew.any(axis=1)


def hold_count(lines, word=WORD, fixed=None):
    fixed = FIXED if fixed is None else fixed
    nfr = 2 * SF
    fr = np.arange(nfr)
    idxf = np.arange(1, FLEN)[:, None] + FLEN * fr[None, :]
    R = (np.arange(SF)[:, None] + fr[None, :]) % SF
    exp = fbits(word)
    F = lines[:, idxf][:, :, None, :]
    S = lines[:, idxf + SBIT][:, :, None, :]
    ok = (F == exp[R][None, None])
    for st, v in fixed.items():
        ok &= (R != st)[None, None] | (S == v)
    perskew = ok.all(axis=3).any(axis=2)
    return int(perskew.sum())


def hooklines(C, fixed=None):
    fixed = FIXED if fixed is None else fixed
    slot = slot_map(fixed)
    nf = len(C[0])
    lines = []
    for h in hooks():
        A = [np.full(nf, h[j], np.uint8) for j in range(NCH)]
        lines.append(build(C, A, fixed=fixed, slot=slot))
    return np.stack(lines)


def seats():
    print('SLOT RULES — 10-bit × 16-SF, S at 5, word 0xFFFE, guard 0,8\n')
    print('  Analytic hold on named layouts; PCM sample (not every octet×pair).\n')
    nf = 2 * SF * 4
    sil = cvsd_lane(nf, 'silence')
    idle = [np.roll(sil, 13 * i) for i in range(NCH)]
    W = wordlane(WORD, nf)
    tot = 2 ** NCH * (FLEN - 1)

    print('  1. PCM sample — one card every seat, octets 0x00/0xFE/0xAA/0x55;')
    print('     then F word vs those octets on every pair.\n')
    sample = [0x00, 0xFE, 0xAA, 0x55, 0xFF, 0x01]
    patterns = [(b, octet(b, nf)) for b in sample]
    for seat in range(NCH):
        bad = [b for b, lane in patterns
               if holds(hooklines([lane if i == seat else idle[i]
                                   for i in range(NCH)])).any()]
        print(f'     C{seat} one-card sample holds: {bad if bad else "none"}')
    pair_hits = []
    for i in range(NCH):
        for j in range(i + 1, NCH):
            for b, lane in patterns:
                n = int(holds(hooklines(
                    [W if k == i else (lane if k == j else idle[k])
                     for k in range(NCH)])).sum())
                if n:
                    pair_hits.append((i, j, b, n))
    print('     F word vs sample octet:')
    if not pair_hits:
        print('       none hold')
    for i, j, b, n in pair_hits:
        print(f'       C{i},C{j} octet 0x{b:02X}: {n} holds')
    print(flush=True)

    print('  2. Named layouts.  Denominator 256 hooks × 9 wrong skews.\n')
    print(f'  {"layout":52s} {"holds":>12s}')

    def scan(C, label):
        n = hold_count(hooklines(C))
        print(f'  {label:52s} {f"{n} / {tot}":>12s}', flush=True)

    for j in range(NCH):
        scan([W if i == j else idle[i] for i in range(NCH)],
             f'  C{j} = F word, rest idle')
    for a, b in ((0, 4), (1, 5), (2, 6), (3, 7)):
        scan([W if i in (a, b) else idle[i] for i in range(NCH)],
             f'  C{a} and C{b} = F word (five apart); rest idle')
    rg = np.random.default_rng(17)
    R = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    scan(R, '  eight data cards, random content')
    scan([octet(0xFE, nf)] * NCH, '  eight PCM cards carrying 0xFE')
    scan([W] * NCH, '  F word in every payload seat')

    print('\n  3. Residual: F word in C0, VOICE in C4 (five apart).\n')
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
                 (spnom[o:o + nf3] if i == 4 else np.roll(sil3, 13 * i))
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
    print('LINE ERRORS — 10-bit × 16-SF, guard 0,8 = 0,1\n')
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
