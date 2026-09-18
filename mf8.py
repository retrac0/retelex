"""
Reference model and validation battery for the 8-bit superframe carrier.

This is the design docs/mf8-spec.md specifies.  It is docs/mfspec.md's frame
with the header replaced, because the original header was measured broken in
three independent ways (docs/mf-vs-16bit.md 4.1-4.3):

    mfspec                          mf8
    F = 1010 (period 2)             F = 11110000-class word, period 8
    superframe phase pinned by      superframe phase pinned by F itself
      two pads 4 apart, gated by
      hook bits -> 56/64 wrong
    no tracking rule                +1/-1 floor 0 trip 16 (spec.md 7.3)
    no acquisition count            32 consecutive good frames (spec.md 7.2)

Frame, 8 bits at a 64 kHz frame rate:

    [ F ][ S ][ C1 ][ C2 ][ C3 ][ C4 ][ C5 ][ C6 ]

Superframe, 8 frames = 125 us:

    state   0   1   2   3   4   5   6   7
    F       1   1   1   1   1   1   1   0      one zero in eight
    S      A1  A2  A3   1  A4   0  A5  A6      six hook bits, two guard bits

Usage:  python3 mf8.py            the whole battery
        python3 mf8.py word       choose the F word
        python3 mf8.py locks      false locks over every payload class
        python3 mf8.py sfphase    superframe phase, exhaustive
        python3 mf8.py errors     line errors, acquisition, resync
"""
import sys, itertools, numpy as np
import audio, cvsd, run, link

RATE = 64000
NCH = 6
FLEN = 8
SF = 8
SLOT = {0: 0, 1: 1, 2: 2, 4: 3, 6: 4, 7: 5}      # superframe state -> channel
FIXED = {3: 1, 5: 0}                              # S guard, and the positions matter

# The guard positions are chosen against two payload classes at once:
#   SAME PARITY (3 and 5 are both odd) with DIFFERENT required values, so a
#     period-2 lane -- CVSD silence -- gives the same value at both and fails
#     deterministically.  mfspec's pads at 3 and 7 had this property too.
#   DIFFERENT FROM THE F WORD at those states: 0xFE is 1 at both 3 and 5, so a
#     data lane carrying the framing word satisfies F but fails the guard.
#     mfspec's pads were 1,0 at states 3,7 -- exactly what 0xFE does there --
#     so the guard added nothing.  Measured: 384/512 false locks before this
#     change, and the battery below after it.


# --------------------------------------------------------------- transmitter

def fword(k, word=0xFE):
    """F at superframe state k.  0xFE = 11111110, MSB is state 0."""
    return (word >> (7 - k)) & 1


def build(C, A, word=0xFE):
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
    line[:, 1] = s
    for j in range(NCH):
        line[:, 2 + j] = C[j][:nf]
    return line.reshape(-1)


# ------------------------------------------------------------------ receiver

def framer(line, skew=0, confirm=32, up=2, dn=1, trip=12, word=0xFE):
    """The mf8 receiver.

        good   :=  F == word[sfc]
                   AND (sfc != 3 OR S == 1)
                   AND (sfc != 5 OR S == 0)

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

    The superframe counter is the only phase state, it is shared with the
    signalling demux, and nothing else tracks a multiframe.
    """
    if skew:
        line = np.roll(line, -skew)
    true = (FLEN - skew % FLEN) % FLEN
    exp = np.array([fword(k, word) for k in range(8)], np.uint8)
    i = cc = wait = err = sfc = 0
    locked = False
    st = dict(lock_bit=None, false_lock=False, sf_offset=None,
              lof_events=0, frames=0, off_phase=0)
    pos = []
    N = line.size
    while i + FLEN <= N:
        f_bit = int(line[i]); s_bit = int(line[i + 1])

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

        good = (f_bit == exp[sfc])
        if good and sfc in FIXED:
            good = (s_bit == FIXED[sfc])

        if not locked:
            if good:
                cc += 1
                if cc >= confirm:
                    locked = True
                    st['lock_bit'] = i
                    st['false_lock'] = (i % FLEN) != true
                    st['sf_offset'] = (sfc - ((i + skew) // FLEN)) & 7
                i += FLEN; sfc = (sfc + 1) & 7
            else:
                cc = 0; wait = 0; i += 1
            continue

        err = max(0, err - dn) if good else err + up
        if err >= trip:
            locked = False; cc = err = wait = 0
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

def payloads(nf, secs=None):
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    sp = cvsd.encode(x, p)[:nf]
    sil = cvsd.encode(np.zeros(nf), p)
    z = np.zeros(nf, np.uint8); o = np.ones(nf, np.uint8)
    rg = np.random.default_rng(5)
    rnd = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    oct8 = np.tile(np.array([1, 0, 1, 1, 0, 0, 1, 0], np.uint8), nf // 8 + 1)[:nf]
    wordlane = np.tile(np.array([1, 1, 1, 1, 1, 1, 1, 0], np.uint8), nf // 8 + 1)[:nf]
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
        # guard would land on carries a pattern chosen to satisfy the guard
        # (bit 3 = 1, bit 5 = 0).  Every adjacent pair is set up this way.
        'F word + guard pattern': [(wordlane if j % 2 == 0 else
                                    np.tile(np.array([0, 0, 0, 1, 0, 0, 0, 0], np.uint8),
                                            nf // 8 + 1)[:nf]) for j in range(NCH)],
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
    p = run.params(RATE)
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
    print(f'  {"payload":24s} {"locks":>6s} {"false":>6s} {"wrong sf":>9s} '
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
        print(f'  {nm:24s} {lk:>6d} {fl:>6d} {ws:>9d} {a:>11s}', flush=True)

    print('\n  Exhaustive over hook states: all 64 combinations x all 8 skews,')
    print('  on the payloads that can hold a wrong alignment open.\n')
    print(f'  {"payload":24s} {"false locks":>14s} {"wrong sf phase":>16s}')
    for nm in ('idle (CVSD silence)', 'all constant 0', 'all constant 1',
               'one data card, idle', 'THE F WORD as data', 'F word beside silence',
               'F word + guard pattern'):
        C = pay[nm]
        fl = ws = 0
        for h in itertools.product((0, 1), repeat=NCH):
            A = [np.full(nf // 4, h[j], np.uint8) for j in range(NCH)]
            ln = build([c[:nf // 4] for c in C], A)
            for k in range(FLEN):
                g = framer(ln, skew=k)
                fl += bool(g['false_lock'])
                ws += (g['sf_offset'] not in (None, 0))
        print(f'  {nm:24s} {f"{fl} / 512":>14s} {f"{ws} / 512":>16s}', flush=True)


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
        A = [h[0], h[1], h[2], h[3], h[4], h[5], 1, 0]
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
    print('LINE ERRORS -- tracking, with the +2/-1 trip-12 counter\n')
    print(f'  {"line BER":>9s} {"locked frames":>14s} {"LOF events":>11s} '
          f'{"off-phase":>10s} {"time down":>10s}')
    for ber in (0.0, 1e-4, 1e-3, 1e-2, 3e-2):
        x = link.impair(ln, ber=ber, seed=5) if ber else ln
        st = framer(x)
        down = 100.0 * (1.0 - st['frames'] / nf)
        print(f'  {ber:9.0e} {st["frames"]:>14d} {st["lof_events"]:>11d} '
              f'{st["off_phase"]:>10d} {down:>9.2f}%', flush=True)
    print('\n  Compare mf-vs-16bit 7.2: mfspec, with no counter, took 10011')
    print('  unlocks and 60.7% downtime at 1e-2 on the same class of line.')

    print('\n\nRESYNC after an induced slip, every slip size\n')
    at = (nf // 2) * FLEN
    print(f'  {"slip":>5s} {"frames misaligned":>19s} {"frames to relock":>18s}')
    for k in range(1, FLEN):
        sl = link.slip(ln, at, n=k)
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


# --------------------------------------------------- 5: slot rules for data

def seats():
    """A data card can carry the F word, and the lane beside it can carry a
    pattern that satisfies the guard.  Then BOTH halves of the check are
    arbitrary data and a wrong alignment holds.  spec.md 3.4 closed the same
    class on the 16-bit frame with slot rules; this finds the rule here.

    Geometry: at skew k the F check lands on one lane and the guard on the
    NEXT one.  Frame is [F][S][C1..C6], so the pairs that matter are
    (S,C1), (C1,C2) ... (C5,C6), (C6, next frame's F).
    """
    nf = 3000
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    sp = cvsd.encode(x, p)[:nf]
    sil = cvsd.encode(np.zeros(nf), p)
    W = np.tile(np.array([1, 1, 1, 1, 1, 1, 1, 0], np.uint8), nf // 8 + 1)[:nf]
    G = np.tile(np.array([0, 0, 0, 1, 0, 0, 0, 0], np.uint8), nf // 8 + 1)[:nf]
    rg = np.random.default_rng(17)
    R = [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]

    def scan(C, label):
        fl = 0
        for h in itertools.product((0, 1), repeat=NCH):
            A = [np.full(nf, h[j], np.uint8) for j in range(NCH)]
            ln = build(C, A)
            for k in range(FLEN):
                fl += bool(framer(ln, skew=k)['false_lock'])
        print(f'  {label:44s} {f"{fl} / 512":>10s}', flush=True)
        return fl

    print('SLOT RULES -- what a data card may sit next to\n')
    print('  The adversarial content is the F word (11111110) in one lane and a')
    print('  guard-satisfying pattern (bit 3 = 1, bit 5 = 0) in the next.\n')
    print(f'  {"layout  (V voice, D data, . silence)":44s} {"false":>10s}')

    print('\n  -- one data card, any seat, voice elsewhere:')
    worst = 0
    for j in range(NCH):
        C = [W if i == j else np.roll(sp, 977 * i) for i in range(NCH)]
        worst = max(worst, scan(C, f'  seat {j + 1} = F word, rest voice'))
    for j in range(NCH):
        C = [G if i == j else np.roll(sil, 13 * i) for i in range(NCH)]
        worst = max(worst, scan(C, f'  seat {j + 1} = guard pattern, rest idle'))

    print('\n  -- two ADJACENT data cards, worst content:')
    adj = 0
    for j in range(NCH - 1):
        C = [W if i == j else (G if i == j + 1 else np.roll(sp, 977 * i))
             for i in range(NCH)]
        adj = max(adj, scan(C, f'  seats {j + 1},{j + 2} = word,guard; rest voice'))

    print('\n  -- two NON-adjacent data cards, worst content:')
    non = 0
    for j, k2 in ((0, 2), (0, 3), (0, 5), (1, 3), (1, 5), (2, 5), (3, 5)):
        C = [W if i == j else (G if i == k2 else np.roll(sp, 977 * i))
             for i in range(NCH)]
        non = max(non, scan(C, f'  seats {j + 1},{k2 + 1} = word,guard; rest voice'))

    print('\n  -- random data in every seat (the ordinary data case):')
    scan(R, '  six data cards, random content')

    print('\n  THE RULE.  One data card is safe in any seat whatever it carries;')
    print('  two data cards are safe when they are not adjacent; two ADJACENT')
    print('  data cards are not safe, because a wrong alignment can put the F')
    print('  check on one and the guard on the other and neither is constrained.')
    print('  This is the same shape of rule framing-review.md 5 found for the')
    print('  4-bit word ("any seat, but never two adjacent") and spec.md 3.4')
    print('  avoided on the 16-bit frame by strapping a data card\'s A bit -- a')
    print('  bit this frame does not have, because signalling is sub-commutated.')
    print('\n  Note that ordinary random data in all six seats is safe: the hole')
    print('  needs the framing word specifically, not merely arbitrary data.')


TARGETS = {'word': word, 'locks': locks, 'sfphase': sfphase,
           'seats': seats, 'errors': errors}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
