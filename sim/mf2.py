"""
Reference model for the 4-bit / two-channel MF2 frame (mf2/spec.md).

Frame, 4 bits at a 64 kHz frame rate (256 kbps line):

    [ F ][ C1 ][ S ][ C2 ]

Superframe, 8 frames = 125 us (octet counter kept):

    state   0   1   2   3   4   5   6   7
    F       1   1   1   1   1   1   1   0
    S       0  A1   -   -   1  A2   -   -     guard at 0,4; A at 1 and 5
                                              (mf2/spec.md §14 sketch)

Framer rules match mf8.py (32-frame acquire, +2/-1 F and guard counters).
Line PHY for noisy runs is sim/mf2_line.py, which calls mf8_line.rx_ami
at line=256e3 — do not fork the AMI decode rule (mf2/ami.md).

Usage:  python3 sim/mf2.py            smoke: build + clean framer lock
        (full word/guard/seats battery: mf2/sim.md — still to port)
"""
import sys, itertools
import numpy as np
import audio, cvsd

RATE = 64000
NCH = 2
FLEN = 4
SF = 8
LINE = FLEN * RATE                # 256 kbps
NOMINAL_RMS = 0.15
SLEW = {16000: 7000.0, 32000: 12000.0, 64000: 16000.0}
BASE = dict(run_length=3, tau_syl=0.005, tau_int=0.001, companding_db=34.2)

SBIT = 2                          # half a frame from F (L=4 → s=2)
CBIT = [1, 3]                     # C1, C2
FIXED = {0: 0, 4: 1}              # S guard
# A_n at superframe states 1 and 5 (spec §14 sketch; freeze vs 1&3 later)
SLOT = {1: 0, 5: 1}


def params(rate=RATE):
    return cvsd.CVSDParams(rate=rate, slew=SLEW[rate], **BASE)


def fword(k, word=0xFE):
    return (word >> (7 - k)) & 1


def build(C, A, word=0xFE, sbit=None):
    """Pack NCH channel bitstreams and A bits into an MF2 line bit vector."""
    sbit = SBIT if sbit is None else sbit
    cb = [b for b in range(FLEN) if b not in (0, sbit)]
    nf = min(len(c) for c in C)
    f = np.arange(nf)
    sfc = f & 7
    line = np.zeros((nf, FLEN), np.uint8)
    line[:, 0] = np.array([fword(k, word) for k in range(8)], np.uint8)[sfc]
    s = np.zeros(nf, np.uint8)
    for st, ch in SLOT.items():
        s[sfc == st] = A[ch][sfc == st]
    for st, v in FIXED.items():
        s[sfc == st] = v
    line[:, sbit] = s
    for j in range(NCH):
        line[:, cb[j]] = C[j][:nf]
    return line.reshape(-1)


def framer(line, skew=0, confirm=32, up=2, dn=1, trip=12, gtrip=12, word=0xFE,
           sbit=None, use_guard=True):
    """MF2 receiver — same acquire/track rules as mf8.framer, FLEN=4.

    `use_guard=False` makes the receiver check the F word ALONE, with the
    transmitter still inserting the guard.  That is the honest "F only"
    column: `gtrip=None` only disables the separate guard LOF counter, it
    does not take the guard out of the acquisition check."""
    sbit = SBIT if sbit is None else sbit
    if skew:
        line = np.roll(line, -skew)
    true = (FLEN - skew % FLEN) % FLEN
    exp = np.array([fword(k, word) for k in range(8)], np.uint8)
    i = cc = wait = err = gerr = sfc = 0
    locked = False
    st = dict(lock_bit=None, false_lock=False, sf_offset=None,
              lof_events=0, guard_lof=0, frames=0, off_phase=0, release=None)
    pos = []
    N = line.size
    while i + FLEN <= N:
        f_bit = int(line[i]); s_bit = int(line[i + sbit])

        if not locked and cc == 0:
            if f_bit == 0:
                sfc = 7
                cc = 1; wait = 0
                i += FLEN; sfc = 0
            else:
                wait += 1
                if wait >= SF:
                    wait = 0; i += 1
                else:
                    i += FLEN
            continue

        good_f = (f_bit == exp[sfc])
        good_g = (not use_guard) or (sfc not in FIXED) or (s_bit == FIXED[sfc])
        good = good_f and good_g

        if not locked:
            if good:
                cc += 1
                if cc >= confirm:
                    locked = True; gerr = 0
                    if st['lock_bit'] is None:
                        st['lock_bit'] = i
                        st['false_lock'] = (i % FLEN) != true
                        st['sf_offset'] = (sfc - ((i + skew) // FLEN)) & 7
                i += FLEN; sfc = (sfc + 1) & 7
            else:
                cc = 0; wait = 0; i += 1
            continue

        err = max(0, err - dn) if good else err + up
        if gtrip and sfc in FIXED:
            gerr = max(0, gerr - dn) if good_g else gerr + up
        if err >= trip or (gtrip and gerr >= gtrip):
            if gtrip and gerr >= gtrip:
                st['guard_lof'] += 1
            if st['false_lock'] and st['release'] is None and (i % FLEN) != true:
                st['release'] = (i - st['lock_bit']) // FLEN
            locked = False; cc = err = gerr = wait = 0
            st['lof_events'] += 1
            i += 1
            continue
        st['frames'] += 1
        if (i % FLEN) != true:
            st['off_phase'] += 1
        pos.append(i)
        i += FLEN; sfc = (sfc + 1) & 7
    st['pos'] = np.array(pos, np.int64)
    return st


# ------------------------------------------------------- analytic machinery
# Ported from mf8.py for FLEN=4 / NCH=2.  The shapes shrink a long way: MF8
# sweeps 64 hook states x 8 skews = 512 start-ups, MF2 sweeps 4 x 4 = 16.

_FR = np.arange(16)
_IDXF = np.arange(1, FLEN)[:, None] + FLEN * _FR[None, :]   # 3 wrong skews x 16
_R = (np.arange(8)[:, None] + _FR[None, :]) & 7             # 8 phases x 16
_HOOKS = np.array(list(itertools.product((0, 1), repeat=NCH)), np.uint8)
NSTART = len(_HOOKS) * FLEN                                 # 16 start-ups


def octet(b, nf):
    """A data lane carrying the byte b in every octet, MSB at state 0."""
    bits = [(b >> (7 - k)) & 1 for k in range(8)]
    return np.tile(np.array(bits, np.uint8), nf // 8 + 1)[:nf]


def guard_byte():
    """The byte that satisfies the guard at the receiver's own phase: bit st = v
    at each guard state, 0 elsewhere.  0x08 for the 0,4 = 0,1 guard."""
    return sum(v << (7 - st) for st, v in FIXED.items())


def hooklines(C, sbit=None):
    """One payload under all 2**NCH hook states, 17 frames from frame 200."""
    sbit = SBIT if sbit is None else sbit
    cb = [b for b in range(FLEN) if b not in (0, sbit)]
    n0 = 200
    nh = len(_HOOKS)
    sfc = np.arange(17) & 7
    base = np.zeros((17, FLEN), np.uint8)
    base[:, 0] = np.array([fword(k) for k in range(8)], np.uint8)[sfc]
    for j in range(NCH):
        base[:, cb[j]] = C[j][n0:n0 + 17]
    s = np.zeros((nh, 17), np.uint8)
    for st, ch in SLOT.items():
        s[:, sfc == st] = _HOOKS[:, ch:ch + 1]
    for st, v in FIXED.items():
        s[:, sfc == st] = v
    out = np.broadcast_to(base, (nh, 17, FLEN)).copy()
    out[:, :, sbit] = s
    return out.reshape(nh, -1)


def holds(lines, sbit=None):
    """Per row: does ANY wrong bit alignment, at ANY superframe phase, pass the
    predictive check for 16 straight frames?  Every lane here is periodic in the
    superframe, so a pass is a pass forever -- the deterministic hole, found
    analytically rather than by running the framer."""
    sbit = SBIT if sbit is None else sbit
    exp = np.array([fword(k) for k in range(8)], np.uint8)
    F = lines[:, _IDXF][:, :, None, :]
    S = lines[:, _IDXF + sbit][:, :, None, :]
    ok = (F == exp[_R][None, None])
    for st, v in FIXED.items():
        ok &= (_R != st)[None, None] | (S == v)
    return ok.all(axis=3).any(axis=(1, 2))


def sweep(sbit, idle, W):
    """Every byte in every seat (rest idle), then the F word in one seat against
    every byte in the other, all hook states throughout."""
    nf = len(idle[0])
    single = [[b for b in range(256)
               if holds(hooklines([octet(b, nf) if i == seat else idle[i]
                                   for i in range(NCH)], sbit), sbit).any()]
              for seat in range(NCH)]
    pairs = {}
    for i in range(NCH):
        for j in range(NCH):
            if i == j:
                continue
            n = sum(int(holds(hooklines(
                [W if k == i else (octet(b, nf) if k == j else idle[k])
                 for k in range(NCH)], sbit), sbit).sum()) for b in range(256))
            if n:
                pairs[i + 1, j + 1] = n
    return single, pairs


def _idle(nf):
    sil = cvsd.encode(np.zeros(nf), params())
    return [np.roll(sil, 13 * i) for i in range(NCH)]


def _speech(nf, rms=0.15):
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * rms, fs, RATE)
    return cvsd.encode(x, params())[:nf]


def _scan(C, sbit=None, **kw):
    """Run the framer from every hook state x every skew.  Returns
    (false acquisitions, still-wrong-at-the-end)."""
    sbit = SBIT if sbit is None else sbit
    nf = len(C[0])
    fl = held = 0
    for h in _HOOKS:
        A = [np.full(nf, h[j], np.uint8) for j in range(NCH)]
        ln = build(C, A, sbit=sbit)
        for k in range(FLEN):
            g = framer(ln, skew=k, sbit=sbit, **kw)
            fl += bool(g['false_lock'])
            held += bool(g['frames'] and g['off_phase'] == g['frames'])
    return fl, held


# ------------------------------------------------------------ 1: the F word

def word():
    """Why 11111110 on N = 2.  mf8.py's question, re-asked on a 4-bit frame:
    only N = 6 had a validated F word (mf2/spec.md §3.1)."""
    nf = 24000
    print('THE F WORD -- candidates on a 4-bit frame\n')
    print('  Longest run of consecutive frames in which a payload lane matches a')
    print('  candidate word.  A lane that matches for 32 frames is an acquisition')
    print('  the framer cannot tell from the real thing.\n')
    lanes = {
        'CVSD speech': _speech(nf),
        'CVSD silence (idle)': cvsd.encode(np.zeros(nf), params()),
        'constant 0': np.zeros(nf, np.uint8),
        'constant 1': np.ones(nf, np.uint8),
        'random data': (np.random.default_rng(5).random(nf) < 0.5).astype(np.uint8),
        'octet 10110010': octet(0xB2, nf),
    }
    cands = [(0xFE, '11111110  period 8, this spec'),
             (0xFC, '11111100  period 8'),
             (0xF0, '11110000  period 8'),
             (0xAA, '10101010  period 2 -- cannot pin an 8-state SF'),
             (0xCC, '11001100  period 4 -- cannot pin an 8-state SF')]
    print(f'  {"candidate":38s} ' + ' '.join(f'{k[:13]:>14s}' for k in lanes))
    for w, name in cands:
        exp = np.array([fword(k, w) for k in range(8)], np.uint8)
        row = []
        for lane in lanes.values():
            n = len(lane) // 8 * 8
            m = (lane[:n].reshape(-1, 8) == exp).all(axis=1)
            best = cur = 0
            for v in m:
                cur = cur + 1 if v else 0
                best = max(best, cur)
            row.append(best * 8)
        print(f'  {name:38s} ' + ' '.join(f'{v:14d}' for v in row), flush=True)
    print('\n  Runs are in frames.  Acquisition is 32 (mf2/spec.md §4), so any')
    print('  candidate reaching 32 on a payload lane is a word a data card can')
    print('  imitate.  Period-4 and period-2 words are excluded structurally, not')
    print('  by this table: they cannot pin an 8-state superframe, so the octet')
    print('  counter and RX_OCT would have no phase (mf2/spec.md §6).')


# -------------------------------------------------- 2: wrong superframe phase

def sfphase():
    """Wrong superframe phases admitted, F alone against F + guard."""
    nf = 3000
    idle = _idle(nf)
    sp = _speech(nf)
    print('SUPERFRAME PHASE -- wrong phases admitted\n')
    print(f'  Every hook state x every bit alignment = {NSTART} start-ups a payload.')
    print('  "false" is an acquisition at a wrong bit alignment; "held" is one')
    print('  still wrong when the clip ends.\n')
    cases = {
        'CVSD speech both channels': [np.roll(sp, 977 * i) for i in range(NCH)],
        'CVSD idle both channels': idle,
        'constant 0 both': [np.zeros(nf, np.uint8)] * NCH,
        'constant 1 both': [np.ones(nf, np.uint8)] * NCH,
        'random data both': [(np.random.default_rng(7 + i).random(nf) < 0.5)
                             .astype(np.uint8) for i in range(NCH)],
        'the F word in C1, idle in C2': [octet(0xFE, nf), idle[1]],
        'the F word in both': [octet(0xFE, nf)] * NCH,
    }
    print(f'  {"payload":44s} {"F only":>16s} {"F + guard":>16s}')
    for name, C in cases.items():
        a = _scan(C, use_guard=False, gtrip=None)
        b = _scan(C)
        print(f'  {name:44s} {f"{a[0]}/{NSTART} false":>16s} '
              f'{f"{b[0]}/{NSTART} false":>16s}', flush=True)
    print('\n  "F only" takes the guard out of the RECEIVER\'s check while the')
    print('  transmitter still sends it, which is what isolates the guard\'s')
    print('  contribution.  MF8 closed this at 0 wrong phases with F + guard')
    print('  (mf8-spec.md §3.3); the pass bar for MF2 is the same, 0 in the')
    print('  right-hand column.  These payloads are the benign ones -- the')
    print('  adversarial pair (F word against the guard pattern) is in `seats`,')
    print('  and it is not 0.')


# ------------------------------------------------------------ 3: the guard

def guard():
    """Guard layouts on a 4-bit frame: which pair of S states, and what values."""
    nf = 3000
    idle = _idle(nf)
    sp = _speech(nf)
    W = octet(0xFE, nf)
    print('THE GUARD -- S at two states, and why 0,4 = 0,1\n')
    print('  The guard is a second, independent condition on a lane the F word')
    print('  does not occupy.  It must reject a period-2 idle lane AND a lane')
    print('  carrying the F word (mf2/spec.md §3.2).\n')
    layouts = [({0: 0, 4: 1}, 'states 0,4 = 0,1   same parity, this spec'),
               ({0: 1, 4: 0}, 'states 0,4 = 1,0   same parity, swapped'),
               ({0: 0, 2: 1}, 'states 0,2 = 0,1   same parity, closer'),
               ({1: 0, 5: 1}, 'states 1,5 = 0,1   would displace A1, A2'),
               ({0: 0}, 'state 0 only        one bit, no parity pair')]
    saved = dict(FIXED)
    cases = {'F word in C1, idle in C2': [W, idle[1]],
             'F word in both': [W] * NCH,
             'idle both': idle,
             'speech both': [np.roll(sp, 977 * i) for i in range(NCH)]}
    print(f'  {"guard":44s} ' + ' '.join(f'{k[:18]:>20s}' for k in cases))
    try:
        for g, name in layouts:
            FIXED.clear(); FIXED.update(g)
            row = [f'{_scan(C)[0]}/{NSTART}' for C in cases.values()]
            print(f'  {name:44s} ' + ' '.join(f'{v:>20s}' for v in row), flush=True)
    finally:
        FIXED.clear(); FIXED.update(saved)
    print('\n  False acquisitions per payload.  A guard that lets the F-word lane')
    print('  through has not done its job; the geometry rule is two states of the')
    print('  SAME parity carrying values different from each other and from F')
    print('  (mf8-spec.md §3.2, and mf2/spec.md §3.2 for L = 4).')


# ------------------------------------------------- 4: where S sits, and seats

def sbit():
    """Why S sits half a frame from F.  On a 4-bit frame s = 2 is the unique
    opposite spacing (2s = 0 mod 4); the alternative is S beside F at bit 1."""
    nf = 400
    idle = _idle(nf)
    W = octet(0xFE, nf)
    print('S POSITION -- half a frame from F, not beside it\n')
    print('  At a wrong bit alignment the check reads two lanes SBIT apart.  A')
    print('  wrong alignment is a HOLE when both carry fixed content that')
    print('  satisfies the check: the framer acquires it and nothing releases it.')
    print('  Analytically, every byte a data card could carry, in every seat,')
    print(f'  under all {len(_HOOKS)} hook states, CVSD idle elsewhere:\n')
    for sb, name in ((1, 'S at bit 1, beside F     [F][S][C1][C2]'),
                     (2, 'S at bit 2, opposite F   [F][C1][S][C2]  this spec')):
        single, pairs = sweep(sb, idle, W)
        print(f'  {name}')
        print('    one data card, bytes that hold a wrong alignment:  '
              + '  '.join(f'seat {s + 1}: {len(b)}' for s, b in enumerate(single)))
        for s, b in enumerate(single):
            if b:
                print(f'      seat {s + 1}: ' + ' '.join(f'0x{x:02X}' for x in b[:8])
                      + (' ...' if len(b) > 8 else ''))
        unsafe = sorted({tuple(sorted(pr)) for pr in pairs})
        print('    two data cards, the F word in one and every byte in the other:')
        print('      unsafe pairs  ' + (' '.join(f'({i},{j})' for i, j in unsafe)
                                        or 'none'))
        print()
    print('  On a 4-bit frame the unique opposite spacing is s = 2 (2s = 0 mod 4).')
    print('  At skew 2 the receiver reads F and S swapped onto each other, so the')
    print('  F word lands on itself and the guard fails.  Skews 1 and 3 read')
    print('  (C1, C2) -- the only payload pair -- which is the seating problem')
    print('  below.')


def seats():
    """THE critical MF2 row (mf2/sim.md §2.6).  On MF8 the forbidden spacing is
    three seats apart and there are six seats.  On MF2 the F-to-S spacing IS the
    only two channel seats, so the forbidden pair is the entire payload."""
    nf = 3000
    idle = _idle(nf)
    sp = _speech(nf)
    spnom = _speech(30 * RATE, rms=NOMINAL_RMS)   # the whole 30 s clip
    W = octet(0xFE, nf)
    G = octet(guard_byte(), nf)
    rg = np.random.default_rng(17)
    R = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]

    print('SLOT RULES -- what may sit in the two seats\n')
    print('  1. Exhaustive and analytic: every byte, every seat, every hook')
    print('     state, CVSD idle elsewhere.\n')
    single, pairs = sweep(SBIT, idle, W)
    print('     one data card, bytes that hold:  '
          + '  '.join(f'seat {s + 1}: {len(b)}' for s, b in enumerate(single)))
    unsafe = sorted({tuple(sorted(pr)) for pr in pairs})
    print('     two data cards, the F word in one and every byte in the other:')
    for pr in unsafe:
        n = pairs.get(pr, 0) + pairs.get(pr[::-1], 0)
        print(f'       seats {pr[0]},{pr[1]}: holds, {n} (byte, hook state) combinations')
    if not unsafe:
        print('       none')

    print(f'\n  2. The framer, all {len(_HOOKS)} hook states x {FLEN} skews '
          f'({NSTART} start-ups).\n')
    print(f'  {"layout":46s} {"false":>12s} {"held":>12s}')
    for label, C in (
            ('  seat 1 = F word, seat 2 = voice', [W, np.roll(sp, 977)]),
            ('  seat 2 = F word, seat 1 = voice', [np.roll(sp, 977), W]),
            ('  seat 1 = F word, seat 2 = guard pattern', [W, G]),
            ('  seat 2 = F word, seat 1 = guard pattern', [G, W]),
            ('  both seats = F word', [W, W]),
            ('  two data cards, random content', R),
            ('  one data card (0xB2), one voice', [octet(0xB2, nf), np.roll(sp, 977)]),
            ('  two voice cards', [np.roll(sp, 977 * i) for i in range(NCH)])):
        fl, held = _scan(C)
        print(f'  {label:46s} {f"{fl}/{NSTART}":>12s} {f"{held}/{NSTART}":>12s}',
              flush=True)

    print('\n  3. The residual: the F word in one seat and VOICE in the other.')
    print('     The guard lands on voice, which satisfies it by chance, and the')
    print('     framer acquires when that happens 4 superframes running.  Speech')
    print(f'     at nominal line level ({NOMINAL_RMS} rms, as mf2_line.py).')
    ns = len(spnom) // 8
    ok = np.ones(ns, bool)
    for st, v in FIXED.items():
        ok &= spnom[st:ns * 8:8] == v
    run = np.zeros(ns + 1, int)
    for i in range(ns):
        run[i + 1] = run[i] + 1 if ok[i] else 0
    p4 = float((run[4:] >= 4).mean())
    if p4 <= 0:
        print('     No 4-superframe run in this clip.')
        return
    print(f'     Over {len(spnom) / RATE:.0f} s of speech that is once in '
          f'{1 / p4:.0f} attempts at that skew.\n')
    nf2 = 32000
    sil2 = cvsd.encode(np.zeros(nf2), params())
    starts = [int(s) for s in np.flatnonzero(run == 4) - 4
              if s >= 1 and 8 * (s - 1) + nf2 <= len(spnom)][:24]
    print(f'     {"tracking":42s} {"acquired":>9s} {"released, frames":>17s} '
          f'{"mean":>9s} {"never":>6s}')
    for gtrip, nm in ((None, 'frame counter only'),
                      (12, 'frame counter + guard counter (this spec)')):
        rel = []; stuck = acq = 0
        for si in starts:
            o = 8 * (si - 1)
            C = [octet(0xFE, nf2), spnom[o:o + nf2]]
            g = framer(build(C, [np.zeros(nf2, np.uint8)] * NCH),
                       skew=1, gtrip=gtrip)
            if g['false_lock']:
                acq += 1
                if g['release'] is None:
                    stuck += 1
                else:
                    rel.append(g['release'])
        print(f'     {nm:42s} {f"{acq}/{len(starts)}":>9s} '
              f'{(f"{min(rel)}-{max(rel)}" if rel else "-"):>17s} '
              f'{(f"{np.mean(rel) / 64:.2f} ms" if rel else "-"):>9s} {stuck:>6d}',
              flush=True)

    print('\n  THE RULE.  MF8 forbids data cards three seats apart and has six')
    print('  seats, so the rule costs it almost nothing.  On MF2 the F-to-S')
    print('  spacing IS the only two channel seats: the forbidden pair is the')
    print('  entire payload.  There is no seat to move to, so TWO DATA CARDS ARE')
    print('  NOT A CONFIGURATION -- keying must enforce it mechanically, and the')
    print('  silkscreen must not reuse MF8\'s "seats 1-3" story (mf2/spec.md §5).')


def smoke():
    """Build a short clean frame and confirm the framer locks on-phase."""
    p = params()
    nf = 8000
    z = np.zeros(nf, np.uint8)
    src, fs = audio.read_wav('talker1.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * NOMINAL_RMS, fs, RATE)[:nf]
    c0 = cvsd.encode(x, p)[:nf]
    c1 = cvsd.encode(np.roll(x, 17), p)[:nf]
    ln = build([c0, c1], [z, z])
    st = framer(ln)
    ok = (st['lock_bit'] is not None and not st['false_lock']
          and st['lof_events'] == 0 and st['frames'] > nf // 2)
    print(f'MF2 smoke: lock_bit={st["lock_bit"]} false={st["false_lock"]} '
          f'lof={st["lof_events"]} frames={st["frames"]} '
          f'{"PASS" if ok else "FAIL"}')
    return ok


TARGETS = {'smoke': smoke, 'word': word, 'sfphase': sfphase,
           'guard': guard, 'sbit': sbit, 'seats': seats}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
