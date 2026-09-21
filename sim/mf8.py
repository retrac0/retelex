"""
Reference model and validation battery for the 8-bit superframe carrier.

This is the design mf8/mf8-spec.md specifies.  It is mf8/mfspec.md's frame
with the header replaced, because the original header was measured broken in
three independent ways (mf8-spec.md 1):

    mfspec                          mf8
    F = 1010 (period 2)             F = 11111110, period 8
    superframe phase pinned by      superframe phase pinned by F itself
      two pads 4 apart, gated by
      hook bits -> 56/64 wrong
    no tracking rule                +2/-1 floor 0 trip 12, F and guard
                                      counted separately
    no acquisition count            32 consecutive good frames
    S beside F                      S half a frame from F

Frame, 8 bits at a 64 kHz frame rate:

    [ F ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ]

Superframe, 8 frames = 125 us:

    state   0   1   2   3   4   5   6   7
    F       1   1   1   1   1   1   1   0      one zero in eight
    S       0  A1  A2  A3   1  A4  A5  A6      six hook bits, two guard bits;
                                               A_n sits where C_n sits in the frame

Usage:  python3 sim/mf8.py            the whole battery
        python3 sim/mf8.py word       choose the F word
        python3 sim/mf8.py locks      false locks over every payload class
        python3 sim/mf8.py sfphase    superframe phase, exhaustive
        python3 sim/mf8.py guard      why the guard is at 0 and 4
        python3 sim/mf8.py sbit       why S sits half a frame from F
        python3 sim/mf8.py seats      the slot rule, every byte in every seat
        python3 sim/mf8.py errors     line errors, acquisition, resync

The 10-bit eight-channel header of exchange/mf8-unit.md is sim/mf8_10.py.
The 16-bit eight-channel header (8 C + 6 overhead) is sim/mf8_16.py.
"""
import sys, itertools, numpy as np
import audio, cvsd

RATE = 64000
NCH = 6
FLEN = 8
SF = 8
NOMINAL_RMS = 0.15                # nominal line level; CVSD steps are tuned for it
SLEW = {16000: 7000.0, 32000: 12000.0, 64000: 16000.0}
# MIL-STD-188-113, the DNVT's law, carried to 64 kbps (mf8-spec.md 12.1): 3-bit
# window, 5 ms syllabic, 1 ms integrator, and 16:1 between the steps at 30 % and
# 0 % run-of-threes -- 34.2 dB in cvsd.py's full-scale terms.  cvsd_law.py.
BASE = dict(run_length=3, tau_syl=0.005, tau_int=0.001, companding_db=34.2)


def params(rate=RATE):
    """CVSD parameters for a per-channel rate (mf8-spec.md 12.1's engine)."""
    return cvsd.CVSDParams(rate=rate, slew=SLEW[rate], **BASE)


def impair(line, ber=0.0, seed=1):
    """Random line bit errors."""
    out = line.copy()
    if ber > 0:
        out[np.random.default_rng(seed).random(out.size) < ber] ^= 1
    return out


def slip(line, at, n=1):
    """A cycle slip: delete n line bits at bit index `at`.  This is what forces
    a reframe on a real link, and the only way channel slots can rotate."""
    return np.concatenate([line[:at], line[at + n:]])


SBIT = 4                                          # S sits half a frame from F
CBIT = [b for b in range(FLEN) if b not in (0, SBIT)]    # C1..C6 -> bits 1,2,3,5,6,7
FIXED = {0: 0, 4: 1}                              # S guard: 0 at state 0, 1 at state 4
SLOT = {CBIT[j]: j for j in range(NCH)}           # superframe state -> channel: A_n sits
                                                  # at the state that is C_n's frame bit

# S is at bit 4, not beside F, because the check reads two bits and at a wrong
# alignment those two bits land somewhere else.  With S at bit 1 a skew of 1
# reads S as F and C1 as the guard, and a skew of 7 reads C6 as F and the
# next frame's F as the guard: two alignments where ONE data card supplies
# half the check and the header the other half, and both are deterministic
# holes -- with the guard at 3,5 as it then was, 0x7F (G.711 silence) in seat
# 6, and 64 bytes in seat 1 with every channel off-hook; every guard has its
# own pair.  Nothing in tracking can release them, because the check never
# fails.  With S half a frame from F the only skew that maps a header
# bit onto a header position is 4, where the header reads ITSELF and fails
# for every hook state, and every other skew reads two payload lanes 3
# apart.  4 is the only spacing with that property in an 8-bit frame.
# `mf8.py sbit` measures both layouts over every byte in every seat.

# The guard is at states 0 and 4, values 0 and 1, and each part of that is
# load-bearing:
#   SAME PARITY (both even) with DIFFERENT required values, so a period-2 lane
#     -- CVSD silence, and the empty-slot fill -- gives the same value at both
#     and fails deterministically.
#   DIFFERENT FROM THE F WORD at those states: 0xFE is 1 at both 0 and 4, so a
#     data lane carrying the framing word satisfies F but fails the guard.
#     mfspec's pads were 1,0 at states 3,7 -- exactly what 0xFE does there --
#     so they added nothing: 192/512 false locks on the F word (`mf8.py guard`;
#     384/512 with S beside F).
#   THE MIRROR.  With the guard at 0 and 4 the hook bits sit at states
#     1,2,3,5,6,7 = CBIT: channel n's A bit is at the superframe state that is
#     its C bit's frame position, so the '259 and the '151 share one address
#     map.  The decode is enable = NOR(q1,q0), expected = q2: one gate.
#   HISTORY.  Before 3.4 the guard was at 3,5.  With S beside F, 3,7 was
#     unusable: a half-superframe shift maps 3 and 7 onto each other, the S
#     lane can impersonate F at that shift with every channel off-hook, and
#     the guard then read C1 -- one data card in seat 1 false-locked.  With S
#     at bit 4 that shift reads the F lane and is dead for any guard, so every
#     same-parity pair is clean (`mf8.py guard`).  What 0,4 costs is the
#     residual: speech satisfies two states 4 apart more often than 2 apart,
#     so a data card carrying the F word three seats from voice is acquired by
#     chance about 2.5x as often as with 3,5 -- 1 in ~520 attempts against 1
#     in ~1300 -- and released by the guard counter either way (`seats` 3).


# --------------------------------------------------------------- transmitter

def fword(k, word=0xFE):
    """F at superframe state k.  0xFE = 11111110, MSB is state 0."""
    return (word >> (7 - k)) & 1


def build(C, A, word=0xFE, sbit=None):
    sbit = SBIT if sbit is None else sbit           # `mf8.py sbit` builds both layouts
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


# ------------------------------------------------------------------ receiver

def framer(line, skew=0, confirm=32, up=2, dn=1, trip=12, gtrip=12, word=0xFE,
           sbit=None):
    """The mf8 receiver.

        good   :=  F == word[sfc]
                   AND (sfc != 0 OR S == 0)
                   AND (sfc != 4 OR S == 1)

                   F is bit 0 of the frame and S is bit SBIT, so at a wrong
                   alignment the two halves of the check land on two lanes
                   SBIT apart -- see the note at SBIT for why that is 4.

        acquire:  the word has exactly one zero, at state 7, so F == 0 IS the
                  phase marker and the superframe phase is READ, never searched.
                  At a bit alignment with no candidate phase yet:
                    F == 0            -> load sfc = 7, start the count
                    8 frames, no zero -> this cannot be the F lane, so slip one
                                         line bit and hunt at the next alignment
                  With a candidate, the check is predictive and any mismatch
                  slips one bit and restarts the hunt.  That makes acquisition a
                  search over 8 bit alignments, not 8 x 8.

        track  :  the same check, +2 bad / -1 good, floor 0, trip at `trip`.
                  +2/-1 trips above a THIRD of frames failing.  +1/-1 needs a
                  half, and at a wrong alignment this check fails at almost
                  exactly a half -- the word is 7 ones and 1 zero, so a random
                  payload lane matches it 50% of the time -- which makes the
                  counter random-walk instead of climbing.  Measured over the
                  line: a transient false lock held 28050 frames with +1/-1.
                  spec.md 7.3 measured +2/-1 as correct for a PREDICTIVE check
                  (one line error spoils one frame, not four).

                  A SECOND counter, same rule, fed only by the two guard
                  checks a superframe, states 0 and 4 (`gtrip`; None disables
                  it).  The guard
                  is 2 checks in 8, so on the frame counter a lock whose F
                  check always passes and whose guard never does peaks at 3
                  against a trip of 12 and holds forever: the guard protected
                  acquisition and nothing else.  Counted alone it trips above
                  a third of GUARD checks failing.  Voice under the guard
                  fails half of them and is released in about a millisecond;
                  at 3e-2 BER it fails 3% and the counter never trips
                  (`mf8.py seats`, `mf8.py errors`).

    The superframe counter is the only phase state, it is shared with the
    signalling demux, and nothing else tracks a multiframe.
    """
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

        if not locked and cc == 0:              # hunting the marker
            if f_bit == 0:
                sfc = 7                          # this frame is state 7
                cc = 1; wait = 0
                i += FLEN; sfc = 0
            else:
                wait += 1
                if wait >= 8:                    # no zero in eight: not F
                    wait = 0; i += 1
                else:
                    i += FLEN
            continue

        good_f = (f_bit == exp[sfc])
        good_g = (sfc not in FIXED) or (s_bit == FIXED[sfc])
        good = good_f and good_g

        if not locked:
            if good:
                cc += 1
                if cc >= confirm:
                    locked = True; gerr = 0
                    if st['lock_bit'] is None:     # the FIRST lock: acquisition
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
                st['release'] = (i - st['lock_bit']) // FLEN    # frames the false lock held
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


# ----------------------------------------------------------------- payloads

def octet(b, nf):
    """A data lane carrying the byte b in every octet, MSB at state 0."""
    bits = [(b >> (7 - k)) & 1 for k in range(8)]
    return np.tile(np.array(bits, np.uint8), nf // 8 + 1)[:nf]


def guard_byte():
    """The byte that satisfies the guard at the receiver's own phase: bit st = v
    at each guard state, 0 elsewhere.  0x08 for the 0,4 = 0,1 guard."""
    return sum(v << (7 - st) for st, v in FIXED.items())


def beside_holes(seat, idle):
    """Bytes a data card in `seat` can carry that hold a wrong alignment with S
    BESIDE F (bit 1), rest idle -- the holes S at bit 4 closes (`mf8.py sbit`)."""
    nf = len(idle[0])
    return [b for b in range(256)
            if holds(hooklines([octet(b, nf) if i == seat else idle[i]
                                for i in range(NCH)], 1), 1).any()]


def payloads(nf, secs=None):
    p = params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    sp = cvsd.encode(x, p)[:nf]
    sil = cvsd.encode(np.zeros(nf), p)
    z = np.zeros(nf, np.uint8); o = np.ones(nf, np.uint8)
    rg = np.random.default_rng(5)
    rnd = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    oct8 = octet(0xB2, nf)
    wordlane = octet(0xFE, nf)
    idle = [np.roll(sil, 13 * j) for j in range(NCH)]
    return {
        'speech':                [np.roll(sp, 977 * j) for j in range(NCH)],
        'idle (CVSD silence)':   [np.roll(sil, 13 * j) for j in range(NCH)],
        'all constant 0':        [z] * NCH,
        'all constant 1':        [o] * NCH,
        'random data':           rnd,
        'octet 10110010':        [oct8] * NCH,
        'one data card, idle':   [oct8 if j == 3 else np.roll(sil, 13 * j)
                                  for j in range(NCH)],
        'one data card, speech': [oct8 if j == 3 else np.roll(sp, 977 * j)
                                  for j in range(NCH)],
        'THE F WORD as data':    [wordlane] * NCH,
        'F word beside silence': [wordlane if j == 3 else np.roll(sil, 13 * j)
                                 for j in range(NCH)],
        # the adversarial case: one lane carries the F word, and the lane the
        # guard would land on -- SBIT bits along, so three seats over --
        # carries the byte that satisfies the guard.  Every pair three apart
        # is set up this way.
        'F word + guard pattern': [wordlane if j < 3 else octet(guard_byte(), nf)
                                   for j in range(NCH)],
        # the two single-card holes S beside F has under this guard, the worst
        # byte in each seat (`mf8.py sbit`)
        **{f'S-beside-F hole, seat {s + 1} (0x{h[0]:02X})':
           [octet(h[0], nf) if j == s else idle[j] for j in range(NCH)]
           for s, h in ((5, beside_holes(5, idle)), (0, beside_holes(0, idle))) if h},
    }


# ------------------------------------------------------------ 1: the F word

def word():
    """Why 11111110, against the alternatives this project has already killed."""
    print('THE F WORD')
    print('  F carries an 8-bit word over the superframe, so it pins BIT phase')
    print('  and SUPERFRAME phase with one check.  mfspec used 1010, which')
    print('  spec.md 3.3 lists as "imitated by CVSD silence" and mf-vs-16bit 4.1')
    print('  measured passing 100% of windows on an idle channel.\n')
    nf = 8192
    p = params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    lanes = {'CVSD speech': cvsd.encode(x, p)[:nf],
             'CVSD silence': cvsd.encode(np.zeros(nf), p),
             'constant 1': np.ones(nf, np.uint8),
             'constant 0': np.zeros(nf, np.uint8),
             'random': (np.random.default_rng(3).random(nf) < 0.5).astype(np.uint8)}
    CANDS = [(0xAA, '10101010  period 2 -- mfspec'),
             (0xEE, '11101110  period 4 -- spec.md 3.3 T'),
             (0xFE, '11111110  one zero in eight'),
             (0xFC, '11111100  two zeros, adjacent'),
             (0xEC, '11101100  five ones, period 8')]
    print('  Longest run of consecutive frames a payload lane can match the word,')
    print('  over every superframe phase.  Acquisition needs 32 in a row, so any')
    print('  lane whose longest run is under 32 is rejected DETERMINISTICALLY.\n')
    print(f'  {"word":32s} ' + ' '.join(f'{n:>12s}' for n in lanes))
    for w, lbl in CANDS:
        exp = np.array([fword(k, w) for k in range(8)], np.uint8)
        row = []
        for nm, lane in lanes.items():
            best = 0
            for ph in range(8):
                e = exp[(np.arange(len(lane)) + ph) & 7]
                m = (lane == e).astype(np.int8)
                # longest run of 1s
                run_ = 0; mx = 0
                for v in m:
                    run_ = run_ + 1 if v else 0
                    if run_ > mx:
                        mx = run_
                best = max(best, mx)
            row.append(best)
        print(f'  {lbl:32s} ' + ' '.join(f'{v:12d}' for v in row), flush=True)
    print('\n  0xAA is matched indefinitely by CVSD silence -- it IS CVSD silence.')
    print('  0xEE has period 4, so it cannot pin an 8-state superframe at all.')
    print('  0xFE, 0xFC and 0xEC all reject silence and constants outright.')
    print('  0xFE is chosen because its generator is the cheapest: F = 0 only at')
    print('  state 7, so TX F = NAND(q2,q1,q0) -- one 3-input gate, and the')
    print('  receiver forms the same term from its own counter.')
    print('\n  A WRONG SUPERFRAME PHASE at the right bit alignment is rejected')
    print('  deterministically too: 11111110 rotated against itself mismatches')
    print('  at 2 of every 8 frames, so the longest good run is 6 and 32')
    print('  consecutive is unreachable.  That is what mfspec had no answer for.')


# --------------------------------------------------- 2: false locks, battery

def locks():
    nf = 12000
    print('FALSE LOCKS -- every payload class, every start-up skew\n')
    hooks = (0, 0, 0, 1, 0, 0)
    pay = payloads(nf)
    print(f'  {"payload":32s} {"locks":>6s} {"false":>6s} {"wrong sf":>9s} '
          f'{"acq frames":>11s}')
    for nm, C in pay.items():
        A = [np.full(nf, hooks[j], np.uint8) for j in range(NCH)]
        ln = build(C, A)
        got = [framer(ln, skew=k) for k in range(FLEN)]
        lk = sum(g['lock_bit'] is not None for g in got)
        fl = sum(bool(g['false_lock']) for g in got)
        ws = sum(1 for g in got if g['sf_offset'] not in (None, 0))
        acq = [g['lock_bit'] / FLEN for g in got if g['lock_bit'] is not None]
        a = f'{min(acq):.0f}-{max(acq):.0f}' if acq else '-'
        print(f'  {nm:32s} {lk:>6d} {fl:>6d} {ws:>9d} {a:>11s}', flush=True)

    print('\n  Exhaustive over hook states: all 64 combinations x all 8 skews,')
    print('  on the payloads that can hold a wrong alignment open.\n')
    print(f'  {"payload":32s} {"false locks":>14s} {"wrong sf phase":>16s}')
    for nm in ('idle (CVSD silence)', 'all constant 0', 'all constant 1',
               'one data card, idle', 'THE F WORD as data', 'F word beside silence',
               'F word + guard pattern') + tuple(n for n in pay if n.startswith('S-beside-F')):
        C = pay[nm]
        fl = ws = 0
        for h in itertools.product((0, 1), repeat=NCH):
            A = [np.full(nf // 4, h[j], np.uint8) for j in range(NCH)]
            ln = build([c[:nf // 4] for c in C], A)
            for k in range(FLEN):
                g = framer(ln, skew=k)
                fl += bool(g['false_lock'])
                ws += (g['sf_offset'] not in (None, 0))
        print(f'  {nm:32s} {f"{fl} / 512":>14s} {f"{ws} / 512":>16s}', flush=True)


# ------------------------------------------------- 3: superframe phase, exact

def sfphase():
    """mf-vs-16bit 4.3 found mfspec admits a wrong superframe phase for 56 of
    64 hook states.  The same enumeration for mf8."""
    print('SUPERFRAME PHASE -- can a wrong one be held?\n')
    print('  mfspec: the only thing pinning the phase was two pads in the S lane,')
    print('  4 apart, so the check only ever compared channels 4 apart and any')
    print('  pair differing in hook state admitted a wrong phase -- 56 of 64.\n')
    print('  mf8: F itself carries the phase.  At offset d the receiver expects')
    print('  11111110 and sees it rotated by d, which mismatches at 2 frames in')
    print('  8 for every d != 0.  Hook states cannot enter into it.\n')
    exp = np.array([fword(k) for k in range(8)], np.uint8)
    print(f'  {"offset":>7s} {"frames matching of 8":>22s} {"longest good run":>18s}')
    for d in range(8):
        rot = np.roll(exp, -d)
        m = (rot == exp)
        seq = np.tile(m, 8)
        run_ = 0; mx = 0
        for v in seq:
            run_ = run_ + 1 if v else 0
            mx = max(mx, run_)
        print(f'  {d:>7d} {int(m.sum()):>22d} {mx:>18d}')
    print('\n  Every wrong offset tops out at 6 consecutive good frames, against')
    print('  the 32 acquisition needs.  Rejected deterministically, for every')
    print('  hook state, with no enumeration required -- but here it is anyway:')
    bad = 0
    for h in itertools.product((0, 1), repeat=NCH):
        A = [0] * 8                                  # the S lane at this hook state
        for st, ch in SLOT.items():
            A[st] = h[ch]
        for st, v in FIXED.items():
            A[st] = v
        for d in range(1, 8):
            ok = True
            for k in range(8):
                if exp[k] != exp[(k + d) & 7]:
                    ok = False; break
                if k in FIXED and A[(k + d) & 7] != FIXED[k]:
                    ok = False; break
            bad += ok
    print(f'  wrong superframe phases admissible over all 64 hook states: {bad}')


# --------------------------------------------- 4: line errors, resync, audio

def errors():
    nf = 400000                                  # 6.25 s
    rg = np.random.default_rng(11)
    C = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    A = [np.full(nf, (0, 0, 0, 1, 0, 0)[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)
    print('LINE ERRORS -- tracking, with the +2/-1 trip-12 counters\n')
    print(f'  {"line BER":>9s} {"locked frames":>14s} {"LOF events":>11s} '
          f'{"of which guard":>15s} {"off-phase":>10s} {"time down":>10s}')
    for ber in (0.0, 1e-4, 1e-3, 1e-2, 3e-2):
        x = impair(ln, ber=ber, seed=5) if ber else ln
        st = framer(x)
        down = 100.0 * (1.0 - st['frames'] / nf)
        print(f'  {ber:9.0e} {st["frames"]:>14d} {st["lof_events"]:>11d} '
              f'{st["guard_lof"]:>15d} {st["off_phase"]:>10d} {down:>9.2f}%', flush=True)
    print('\n  Compare mf-vs-16bit 7.2: mfspec, with no counter, took 10011')
    print('  unlocks and 60.7% downtime at 1e-2 on the same class of line.')

    print('\n\nRESYNC after an induced slip, every slip size\n')
    at = (nf // 2) * FLEN
    print(f'  {"slip":>5s} {"frames misaligned":>19s} {"frames to relock":>18s}')
    for k in range(1, FLEN):
        sl = slip(ln, at, n=k)
        st = framer(sl)
        pos = st['pos']
        pre, post = pos[pos < at], pos[pos >= at]
        if len(pre) == 0 or len(post) == 0:
            print(f'  {k:>5d} {"-":>19s} {"-":>18s}'); continue
        base = pre[0] % FLEN
        good = (((post + k) % FLEN) == base)
        bad = int((~good).sum())
        rel = int(np.flatnonzero(good)[0]) if good.any() else -1
        print(f'  {k:>5d} {bad:>19d} {rel if rel >= 0 else "never":>18}', flush=True)


def guard():
    """Why the guard sits at superframe states 0 and 4.  Four layouts,
    exhaustively over hook states and skews, and how often voice under the
    guard lets a wrong alignment in."""
    nf = 2000
    p = params(RATE)
    sil = cvsd.encode(np.zeros(nf), p)
    src, fs = audio.read_wav('speech30.wav')
    x = audio.resample_to(audio.bandlimit(src, fs), fs, RATE)
    spn = cvsd.encode(x * (NOMINAL_RMS / max(x.std(), 1e-9)), p)   # nominal level
    W = octet(0xFE, nf)
    LAYOUTS = [
        ('0,4 = 0,1  (this spec)',     {0: 0, 4: 1}),
        ('3,5 = 1,0  (before 3.4)',    {3: 1, 5: 0}),
        ('3,7 = 0,1  (regular)',       {3: 0, 7: 1}),
        ('3,7 = 1,0  (mfspec values)', {3: 1, 7: 0}),
    ]
    global SLOT, FIXED
    keep = (SLOT, FIXED)

    def scan(C):
        fl = 0
        for h in itertools.product((0, 1), repeat=NCH):
            A = [np.full(nf, h[j], np.uint8) for j in range(NCH)]
            ln = build(C, A)
            fl += sum(bool(framer(ln, skew=k)['false_lock']) for k in range(FLEN))
        return fl

    def voice(fixed):
        """How often speech satisfies this guard 4 superframes running."""
        ns = len(spn) // 8
        ok = np.ones(ns, bool)
        for st, v in fixed.items():
            ok &= spn[st:ns * 8:8] == v
        run = np.zeros(ns + 1, int)
        for i in range(ns):
            run[i + 1] = run[i] + 1 if ok[i] else 0
        return float((run[4:] >= 4).mean())

    print('GUARD POSITION -- why 0 and 4\n')
    print('  False locks over all 64 hook states x 8 skews (512 per cell).  "one')
    print('  data card" is the F word in ONE seat, voice elsewhere -- legal under the')
    print('  slot rule, so it has to be 0 in every seat for the rule to mean anything.')
    print('  "voice" is how often speech at nominal level satisfies the guard 4')
    print('  superframes running, which is what a chance acquisition on the residual')
    print('  case (`mf8.py seats` 3) needs.\n')
    print(f'  {"layout":28s} {"F word, every lane":>19s} {"one data card, worst seat":>26s} '
          f'{"voice":>12s}')
    rate = {}
    try:
        for name, fixed in LAYOUTS:
            FIXED = fixed
            free = [s for s in range(8) if s not in fixed]
            SLOT = {s: i for i, s in enumerate(free)}
            every = scan([W] * NCH)
            worst = max(scan([W if i == j else np.roll(sil, 13 * i) for i in range(NCH)])
                        for j in range(NCH))
            rate[name] = voice(fixed)
            print(f'  {name:28s} {f"{every} / 512":>19s} {f"{worst} / 512":>26s} '
                  f'{f"1 in {1 / max(rate[name], 1e-9):.0f}":>12s}', flush=True)
    finally:
        SLOT, FIXED = keep
    r = rate[LAYOUTS[0][0]] / max(rate[LAYOUTS[1][0]], 1e-9)
    print('\n  Any two same-parity states with different values reject CVSD idle, which')
    print('  gives the same value at both.  mfspec\'s values copy the F word at 3 and 7,')
    print('  so they add nothing.  Every other layout is clean; what separates them is')
    print('  cost and the residual.  0,4 = 0,1 decodes as enable = NOR(q1,q0),')
    print('  expected = q2 -- one gate, no XOR -- and it makes the S lane mirror the')
    print('  frame: A_n sits at the state that is C_n\'s frame bit, so the signalling')
    print('  mux and demux share the frame mux\'s address map.  Its price is the')
    print('  residual: speech satisfies two states 4 apart more often than 2 apart,')
    print(f'  so the chance acquisition of `seats` 3 is {r:.1f}x as frequent as with')
    print('  3,5 -- and released by the guard counter either way.')
    print('\n  3,5 was chosen when S sat beside F.  A half-superframe shift maps 3 and')
    print('  7 onto each other, and with every channel off-hook the S lane has one')
    print('  zero and impersonates F at exactly that shift; the guard then read C1,')
    print('  and one data card in seat 1 false-locked (1 / 512) under 3,7.  With S')
    print('  half a frame from F that shift reads the F lane, not C1, and is dead for')
    print('  any guard (`mf8.py sbit`), which is what freed the choice.')


# ------------------------------------------ 5: where S sits, and slot rules

_FR = np.arange(16)
_IDXF = np.arange(1, FLEN)[:, None] + FLEN * _FR[None, :]     # (7 wrong skews, 16 frames)
_R = (np.arange(8)[:, None] + _FR[None, :]) & 7               # (8 receiver phases, 16 frames)
_HOOKS = np.array(list(itertools.product((0, 1), repeat=NCH)), np.uint8)


def hooklines(C, sbit=None):
    """One payload under all 64 hook states: a (64, 136) bit array, 17 frames
    from frame 200 (past CVSD idle's start-up, at superframe state 0)."""
    sbit = SBIT if sbit is None else sbit
    cb = [b for b in range(FLEN) if b not in (0, sbit)]
    n0 = 200
    sfc = np.arange(17) & 7
    base = np.zeros((17, FLEN), np.uint8)
    base[:, 0] = np.array([fword(k) for k in range(8)], np.uint8)[sfc]
    for j in range(NCH):
        base[:, cb[j]] = C[j][n0:n0 + 17]
    s = np.zeros((64, 17), np.uint8)
    for st, ch in SLOT.items():
        s[:, sfc == st] = _HOOKS[:, ch:ch + 1]
    for st, v in FIXED.items():
        s[:, sfc == st] = v
    out = np.broadcast_to(base, (64, 17, FLEN)).copy()
    out[:, :, sbit] = s
    return out.reshape(64, -1)


def holds(lines, sbit=None):
    """Per row: does ANY wrong bit alignment, at ANY superframe phase, pass the
    predictive check for 16 straight frames?  Every lane here is periodic in
    the superframe, so a pass is a pass forever: the framer acquires it, the
    check never fails, and no tracking rule can ever see it.  This is the
    deterministic hole, found analytically rather than by running the framer."""
    sbit = SBIT if sbit is None else sbit
    exp = np.array([fword(k) for k in range(8)], np.uint8)
    F = lines[:, _IDXF][:, :, None, :]                    # (64, 7, 1, 16)
    S = lines[:, _IDXF + sbit][:, :, None, :]
    ok = (F == exp[_R][None, None])
    for st, v in FIXED.items():
        ok &= (_R != st)[None, None] | (S == v)
    return ok.all(axis=3).any(axis=(1, 2))


def sweep(sbit, idle, W):
    """Every byte in every seat (rest idle), then the F word in seat i against
    every byte in seat j, all 64 hook states throughout.  Returns the bytes
    that hold per seat, and {(i, j): (byte, hook state) combinations that hold}."""
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
            n = sum(int(holds(hooklines([W if k == i else (octet(b, nf) if k == j else idle[k])
                                         for k in range(NCH)], sbit), sbit).sum())
                    for b in range(256))
            if n:
                pairs[i + 1, j + 1] = n
    return single, pairs


def sbit():
    """Why S sits half a frame from F.  Both layouts, every byte in every
    seat, every hook state, exhaustively."""
    nf = 400
    sil = cvsd.encode(np.zeros(nf), params(RATE))
    idle = [np.roll(sil, 13 * i) for i in range(NCH)]
    W = octet(0xFE, nf)
    print('S POSITION -- why S sits half a frame from F, not beside it\n')
    print('  The check reads two bits, F and S.  At a wrong bit alignment they land')
    print('  on two other lanes, SBIT apart.  A wrong alignment is a HOLE when both')
    print('  of those lanes carry fixed content that satisfies the check: the framer')
    print('  acquires it, the check never fails, and nothing can release it.')
    print('  Analytically, over every byte a data card could carry, in every seat,')
    print('  under all 64 hook states, with CVSD idle elsewhere:\n')
    found = {}
    for sb, name in ((1, 'S at bit 1, beside F      [F][S][C1][C2][C3][C4][C5][C6]'),
                     (4, 'S at bit 4, opposite F    [F][C1][C2][C3][S][C4][C5][C6]')):
        single, pairs = sweep(sb, idle, W)
        found[sb] = single
        print(f'  {name}')
        print('    one data card, bytes that hold a wrong alignment:  '
              + '  '.join(f'seat {s + 1}: {len(b)}' for s, b in enumerate(single)))
        for s, b in enumerate(single):
            if b:
                print(f'      seat {s + 1}: ' + ' '.join(f'0x{x:02X}' for x in b[:8])
                      + (' ...' if len(b) > 8 else ''))
        unsafe = sorted({tuple(sorted(p)) for p in pairs})
        safe = [(i, j) for i in range(1, NCH + 1) for j in range(i + 1, NCH + 1)
                if (i, j) not in unsafe]
        print('    two data cards, the F word in one and every byte in the other:')
        print('      unsafe pairs  ' + (' '.join(f'({i},{j})' for i, j in unsafe) or 'none'))
        print('      safe pairs    ' + (' '.join(f'({i},{j})' for i, j in safe) or 'none'),
              flush=True)
        print()
    print('  The framer confirms the holes S beside F has, all 64 hook states x 8 skews:')
    nf = 3000
    sil = cvsd.encode(np.zeros(nf), params(RATE))
    idle = [np.roll(sil, 13 * i) for i in range(NCH)]
    for seat, bad in enumerate(found[1]):
        if not bad:
            continue
        b = bad[0]
        C = [octet(b, nf) if i == seat else idle[i] for i in range(NCH)]
        fl = held = 0
        for h in itertools.product((0, 1), repeat=NCH):
            ln = build(C, [np.full(nf, h[j], np.uint8) for j in range(NCH)], sbit=1)
            for k in range(FLEN):
                g = framer(ln, skew=k, sbit=1)
                fl += bool(g['false_lock'])
                held += bool(g['frames'] and g['off_phase'] == g['frames'])
        print(f'    seat {seat + 1} = 0x{b:02X}, rest idle:  {fl} / 512 false locks, '
              f'{held} held to the end', flush=True)
    print()
    print('  With S beside F, skew 1 reads S as F and C1 as the guard, and skew 7')
    print('  reads C6 as F and the NEXT frame\'s F as the guard.  Each is one data')
    print('  card plus the header, and the header is fixed content.  Seat 6: one')
    print('  byte passes for the word while the real F lane, at a fixed offset, reads')
    print('  exactly the guard\'s values.  Seat 1: with every channel off-hook S has')
    print('  one zero and passes for the word, and the guard then wants two')
    print('  particular bits of C1 -- 64 bytes.  Which bytes depends on the guard:')
    print('  with the guard at 3,5, as first found, they were 0x7F -- G.711 silence')
    print('  -- and 0x40; every guard has its own pair.  Both are deterministic, and')
    print('  both passed the old battery, whose "worst content" was one fixed')
    print('  pattern at one alignment.  Any pair that includes seat 1 or 6 inherits')
    print('  the hole, which is why only three pairs were actually safe.')
    print('\n  With S half a frame from F, the only skew that puts a header bit on a')
    print('  header position is 4, where the receiver reads S as F and F as S: S')
    print('  passes for the word only with every channel off-hook, and the F lane')
    print('  then reads 1,1 where the guard wants 0,1.  Every other skew reads two')
    print('  payload lanes three apart, so the slot rule becomes "not three apart".')
    print('  4 is the only spacing in an 8-bit frame that maps the header onto itself.')


def seats():
    """The slot rule, measured: every byte a data card could carry, in every
    seat, under every hook state, with the framer as the final judge, and the
    one probabilistic case the rule leaves, which the guard counter closes."""
    nf = 3000
    p = params(RATE)
    src, fs = audio.read_wav('speech30.wav')
    x = audio.resample_to(audio.bandlimit(src, fs), fs, RATE)
    sp = cvsd.encode(x * 0.15, p)[:nf]                  # the battery's level, as elsewhere here
    spnom = cvsd.encode(x * (NOMINAL_RMS / max(x.std(), 1e-9)), p)   # nominal line level, as mf8_line.py
    sil = cvsd.encode(np.zeros(nf), p)
    idle = [np.roll(sil, 13 * i) for i in range(NCH)]
    W = octet(0xFE, nf)
    G = octet(guard_byte(), nf)                           # satisfies the guard in phase
    rg = np.random.default_rng(17)
    R = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]

    def scan(C, label):
        fl = held = 0
        for h in itertools.product((0, 1), repeat=NCH):
            A = [np.full(nf, h[j], np.uint8) for j in range(NCH)]
            ln = build(C, A)
            for k in range(FLEN):
                g = framer(ln, skew=k)
                fl += bool(g['false_lock'])
                held += bool(g['frames'] and g['off_phase'] == g['frames'])
        print(f'  {label:48s} {f"{fl} / 512":>10s} {f"{held} / 512":>12s}', flush=True)

    print('SLOT RULES -- what a data card may sit where\n')
    print('  1. Exhaustive and analytic: every byte, every seat, every hook state,')
    print('     CVSD idle elsewhere.  A "hold" is a wrong alignment the check passes')
    print('     for a whole superframe, which on periodic lanes is forever.\n')
    single, pairs = sweep(SBIT, idle, W)
    print('     one data card, bytes that hold:  '
          + '  '.join(f'seat {s + 1}: {len(b)}' for s, b in enumerate(single)))
    unsafe = sorted({tuple(sorted(pr)) for pr in pairs})
    print('     two data cards, the F word in one and every byte in the other:')
    for pr in unsafe:
        n = pairs.get(pr, 0) + pairs.get(pr[::-1], 0)
        print(f'       seats {pr[0]},{pr[1]}: holds, {n} (byte, hook state) combinations')
    safe = [(i, j) for i in range(1, NCH + 1) for j in range(i + 1, NCH + 1)
            if (i, j) not in unsafe]
    print('       safe: ' + ' '.join(f'({i},{j})' for i, j in safe))

    print('\n  2. The framer, all 64 hook states x 8 skews (512 start-ups).  "false"')
    print(f'     is a false acquisition; "held" is one still wrong at the end.  The')
    print(f'     guard pattern is 0x{guard_byte():02X}, the byte that satisfies the guard in phase.\n')
    print(f'  {"layout":48s} {"false":>10s} {"held":>12s}')
    for j in range(NCH):
        scan([W if i == j else np.roll(sp, 977 * i) for i in range(NCH)],
             f'  seat {j + 1} = F word, rest voice')
    for j, k2 in ((0, 3), (1, 4), (2, 5), (0, 1), (2, 3), (4, 5)):
        scan([W if i == j else (G if i == k2 else np.roll(sp, 977 * i)) for i in range(NCH)],
             f'  seats {j + 1},{k2 + 1} = F word, guard pattern; rest voice')
    scan(R, '  six data cards, random content')

    print('\n  3. The residual: the F word in seat 1 and VOICE in seat 4, three apart.')
    print('     The guard lands on voice, which satisfies it by chance, and the')
    print('     framer acquires when that happens 4 superframes running.  Speech')
    print('     at nominal line level here (0.15 rms, as mf8_line.py), because the')
    print('     quieter lane the rest of this battery uses is closer to idle.')
    ns = len(spnom) // 8
    ok = np.ones(ns, bool)
    for st, v in FIXED.items():
        ok &= spnom[st:ns * 8:8] == v
    run = np.zeros(ns + 1, int)
    for i in range(ns):
        run[i + 1] = run[i] + 1 if ok[i] else 0
    p4 = float((run[4:] >= 4).mean())
    print(f'     Over {len(spnom) / RATE:.0f} s of speech that is once in {1 / p4:.0f} attempts at'
          f' that skew.  Forced at\n     the first 24 such points, 0.5 s runs:\n')
    nf2 = 32000
    sil2 = cvsd.encode(np.zeros(nf2), p)
    starts = [int(s) for s in np.flatnonzero(run == 4) - 4
              if s >= 1 and 8 * (s - 1) + nf2 <= len(spnom)][:24]
    print(f'     {"tracking":42s} {"acquired":>9s} {"released, frames":>17s} '
          f'{"mean":>8s} {"never":>6s}')
    for gtrip, nm in ((None, 'frame counter only'),
                      (12, 'frame counter + guard counter (this spec)')):
        rel = []; stuck = acq = 0
        for si in starts:
            o = 8 * (si - 1)
            C = [octet(0xFE, nf2) if i == 0 else
                 (spnom[o:o + nf2] if i == 3 else np.roll(sil2, 13 * i)) for i in range(NCH)]
            g = framer(build(C, [np.zeros(nf2, np.uint8)] * NCH), skew=1, gtrip=gtrip)
            if g['false_lock']:
                acq += 1
                if g['release'] is None:
                    stuck += 1
                else:
                    rel.append(g['release'])
        print(f'     {nm:42s} {f"{acq}/{len(starts)}":>9s} '
              f'{(f"{min(rel)}-{max(rel)}" if rel else "-"):>17s} '
              f'{(f"{np.mean(rel) / 64:.2f} ms" if rel else "-"):>8s} {stuck:>6d}', flush=True)

    print('\n  THE RULE.  Two data cards may not sit three slots apart: not (1,4),')
    print('  not (2,5), not (3,6).  One data card is safe in any seat whatever it')
    print('  carries, adjacent data cards are safe, ordinary random data is safe in')
    print('  all six seats, and three data cards fit as 1,2,3 or 4,5,6.  A data card')
    print(f'  carrying the F word three seats from VOICE is acquired by chance about')
    print(f'  once in {1 / p4:.0f} attempts at that skew, and the guard counter releases it')
    print('  within milliseconds, where the frame counter alone never would: with F')
    print('  always passing the guard is 2 checks in 8, and +2/-1 needs a third.')


TARGETS = {'word': word, 'locks': locks, 'sfphase': sfphase, 'guard': guard,
           'sbit': sbit, 'seats': seats, 'errors': errors}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
