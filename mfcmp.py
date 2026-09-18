"""
docs/mfspec.md (8-bit frame, 6 x 64 kbps, F + sub-commutated S) measured against
the 16-bit 7-channel frame, on the same 512 kbps line.

The two formats share the line code exactly, so nothing here touches the PHY.
What differs is the header, and the header is what this repo has spent its
measurements on:

  mfspec F bit  = period-2 alternating          -> spec.md 3.3 row 2, rejected
  mfspec S lane = 8-state superframe, 2 pads    -> a phase nothing else pins

Usage:  python3 mfcmp.py            everything
        python3 mfcmp.py stage1     is 'F alternates' a filter against CVSD?
        python3 mfcmp.py sfphase    the superframe-phase enumeration
        python3 mfcmp.py bitlock    bit-alignment false locks, mfspec vs spec 7
"""
import sys, gc, itertools, numpy as np
from scipy import signal
import audio, cvsd, run, link, fast, phy, s4_simple, framing_review as fr

RATE = 64000                      # mfspec: 64 kbps per channel
LINE_RATE = 512e3                 # both formats, same pair
NCH = 6
FLEN = 8
PADS = {3: 1, 7: 0}               # mfspec 4: frame 3 carries 1, frame 7 carries 0
SLOT = {0: 0, 1: 1, 2: 2, 4: 3, 5: 4, 6: 5}   # superframe frame -> channel index


# ---------------------------------------------------------------- transmitter

def build(C, A):
    """mfspec 3: [F][S][C1..C6], F alternating, S sub-commutated over 8 frames."""
    nf = min(len(c) for c in C)
    f = np.arange(nf)
    line = np.zeros((nf, FLEN), np.uint8)
    line[:, 0] = f & 1                                    # F
    sf = f & 7
    s = np.zeros(nf, np.uint8)
    for fr_i, ch in SLOT.items():
        s[sf == fr_i] = A[ch][sf == fr_i]
    for fr_i, v in PADS.items():
        s[sf == fr_i] = v
    line[:, 1] = s
    for j in range(NCH):
        line[:, 2 + j] = C[j][:nf]
    return line.reshape(-1)


# ------------------------------------------------------------------- receiver

def framer(line, skew=0, stage1=8, guards=1, track='acquire'):
    """The mfspec 5 receiver, as written.

    Stage 1: the F lane alternates across `stage1` consecutive frames.
    Stage 2: local frame counter state 3 -> S == 1, state 7 -> S == 0.
    Mismatch: swallow one line bit, reset the hunt.

    `guards` is the number of superframes the Stage 2 signature must hold; the
    spec implies 1.  The local superframe counter free-runs -- mfspec gives it
    nothing to load from.

    mfspec 5 gives NO tracking rule, so `track` spans the two readings it
    leaves open, and they bound the real behaviour:

      'acquire'  stop at first lock (what the acquisition tests want)
      'strict'   re-verify both pads every superframe; any mismatch unlocks
                 and re-hunts.  No hysteresis, because the spec gives none.
      'none'     after lock, never check again: a slip is never detected.

    `unlocks` counts unlock events; `pos` is the bit index of every frame
    emitted while locked; `off_phase` counts those emitted at a wrong phase.
    """
    if skew:
        line = np.roll(line, -skew)
    true = (FLEN - skew % FLEN) % FLEN
    i = 0
    N = line.size
    st = dict(lock_bit=None, false_lock=False, sf_offset=None,
              unlocks=0, frames=0, off_phase=0)
    sfc = 0                 # local frame counter; nothing ever loads it
    alt = 0                 # consecutive confirmed F transitions
    prev = None             # last F sample; None = no comparison available yet
    hits = 0                # superframes whose full signature has held
    seen3 = False           # state 3 verified in the superframe now in progress
    locked = False
    pos = []

    def swallow():          # mfspec 5: shift phase by one bit, reset the hunt
        return i + 1, None, 0, 0, False

    while i + FLEN <= N:
        if locked and track == 'none':          # locked and never re-checked
            st['frames'] += 1
            if (i % FLEN) != true:
                st['off_phase'] += 1
            pos.append(i); i += FLEN; sfc = (sfc + 1) & 7
            continue
        f_bit = int(line[i]); s_bit = int(line[i + 1])
        if prev is None:
            pass                               # first sample after a slip
        elif f_bit != prev:
            alt += 1
        else:
            if locked:
                locked = False; st['unlocks'] += 1
            i, prev, alt, hits, seen3 = swallow(); continue
        prev = f_bit
        if (locked or alt >= stage1) and sfc in PADS:   # stage 2 / tracking
            if s_bit != PADS[sfc]:
                if locked:
                    locked = False; st['unlocks'] += 1
                i, prev, alt, hits, seen3 = swallow(); continue
            if sfc == 3:
                seen3 = True
            elif seen3:                         # state 7, and state 3 held too
                seen3 = False
                if not locked:
                    hits += 1
                    if hits >= guards:
                        locked = True
                        if st['lock_bit'] is None:
                            st['lock_bit'] = i
                            st['false_lock'] = (i % FLEN) != true
                            st['sf_offset'] = (sfc - ((i + skew) // FLEN)) & 7
                        if track == 'acquire':
                            st['pos'] = np.array(pos, np.int64)
                            return st
        if locked:
            st['frames'] += 1
            if (i % FLEN) != true:
                st['off_phase'] += 1
            pos.append(i)
        i += FLEN; sfc = (sfc + 1) & 7
    st['pos'] = np.array(pos, np.int64)
    return st


# ------------------------------------------------- 1: is stage 1 any filter?

def stage1():
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=8.0)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    lanes = {'CVSD speech': cvsd.encode(x, p),
             'CVSD silence': cvsd.encode(np.zeros(len(x)), p),
             'CVSD, -40 dB tone': cvsd.encode(0.15 * 0.01 * np.sqrt(2) *
                                              np.sin(2 * np.pi * 1004 *
                                                     np.arange(len(x)) / RATE), p),
             'data, all ones': np.ones(len(x), np.uint8),
             'data, octet 10110010': np.tile(np.array([1, 0, 1, 1, 0, 0, 1, 0], np.uint8),
                                             len(x) // 8),
             'random data': (np.random.default_rng(3).random(len(x)) < 0.5).astype(np.uint8)}
    print('STAGE 1 -- "the F lane alternates over 8 consecutive frames"')
    print('  A wrong bit alignment puts this test on a payload lane.  A lane that')
    print('  passes is a lane that holds stage 1 open.\n')
    print(f'  {"payload lane":24s} {"P(bit flips)":>13s} {"P(8 in a row)":>14s} {"windows passing":>16s}')
    for nm, b in lanes.items():
        b = np.asarray(b, np.uint8)
        d = (b[1:] != b[:-1])
        # fraction of 8-frame windows that alternate throughout
        w = np.lib.stride_tricks.sliding_window_view(d, 8).all(axis=1).mean()
        print(f'  {nm:24s} {d.mean():13.3f} {d.mean() ** 8:14.3f} {w:16.3f}')
    print('\n  CVSD silence is exactly 1010..., so it alternates by construction.')
    print('  spec.md 3.3: an alternating header is "imitated by CVSD silence" --')
    print('  7/8 and 15/16 skews false-locked, permanently.  Stage 1 is that header.')


# ------------------------------------- 2: the superframe phase, exhaustively

def sfphase():
    """Which local superframe offsets does the stage-2 signature admit?

    Offset d means the local frame counter reads true superframe index (s+d)&7.
    The signature passes iff  A[(3+d)&7] == 1  and  A[(7+d)&7] == 0,
    where A = [a1,a2,a3,1,a4,a5,a6,0] and an is channel n's hook bit.
    """
    print('SUPERFRAME PHASE -- all 64 hook-state combinations, all 8 local offsets')
    print('  Bit alignment is correct here.  Only the superframe phase is in question,')
    print('  and the two pads are the only thing that pins it.\n')
    admits = {}
    counts = []
    for hooks in itertools.product((0, 1), repeat=NCH):
        A = [hooks[0], hooks[1], hooks[2], 1, hooks[3], hooks[4], hooks[5], 0]
        bad = [d for d in range(1, 8)
               if A[(3 + d) & 7] == 1 and A[(7 + d) & 7] == 0]
        admits[hooks] = bad
        counts.append(len(bad))
    counts = np.array(counts)
    print(f'  hook combinations admitting >= 1 wrong superframe phase: '
          f'{(counts > 0).sum()} / 64  ({100.0 * (counts > 0).mean():.1f}%)')
    print(f'  wrong phases admitted, mean {counts.mean():.2f}, max {counts.max()}')
    print(f'  offsets never admitted: {[d for d in range(1, 8) if all(d not in v for v in admits.values())]}')
    print('\n  Why: the pads sit 4 apart in an 8-state superframe, so the signature')
    print('  only ever compares channels 4 apart -- (1,4), (2,5), (3,6).  One wrong')
    print('  phase is admitted per pair whose two channels differ in hook state:')
    for pair, d in ((('ch4', 'ch1'), (1, 5)), (('ch5', 'ch2'), (2, 6)), (('ch6', 'ch3'), (3, 7))):
        print(f'    {pair[0]} off-hook, {pair[1]} on-hook -> offset {d[0]} holds;  '
              f'reversed -> offset {d[1]} holds')
    print('\n  Worked example, ch4 on a call and ch1 idle (a1=0, a4=1):')
    ex = (0, 0, 0, 1, 0, 0)
    print(f'    hook states {ex} -> offsets {admits[ex]} pass the signature forever.')
    print('    At offset 1 the receiver is bit- and frame-aligned, audio is bit-exact,')
    print('    and every hook state is delivered to the wrong channel latch.')
    print('    Nothing in mfspec 5 can detect it.')


# --------------------------------- 3: bit-alignment locks, mfspec vs spec 7

def _lanes(kind, nf):
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    sp = cvsd.encode(x, p)[:nf]
    sil = cvsd.encode(np.zeros(nf), p)
    oct8 = np.tile(np.array([1, 0, 1, 1, 0, 0, 1, 0], np.uint8), nf // 8 + 1)[:nf]
    if kind == 'speech':
        return [np.roll(sp, 977 * j) for j in range(NCH)]
    if kind == 'idle':
        return [np.roll(sil, 13 * j) for j in range(NCH)]
    if kind == 'idle + one data card':
        return [oct8 if j == 3 else np.roll(sil, 13 * j) for j in range(NCH)]
    if kind == 'speech + one data card':
        return [oct8 if j == 3 else np.roll(sp, 977 * j) for j in range(NCH)]
    raise ValueError(kind)


def bitlock():
    nf = 3 * RATE
    hooks = (0, 0, 0, 1, 0, 0)          # ch4 on a call, the rest idle
    print('BIT-ALIGNMENT LOCK -- every start-up skew, mfspec receiver as written')
    print(f'  hook states {hooks}; "false" = locked off the true bit phase\n')
    print(f'  {"payload":26s} {"locks":>7s} {"false":>7s} {"wrong sf phase":>15s}')
    for kind in ('speech', 'idle', 'idle + one data card', 'speech + one data card'):
        C = _lanes(kind, nf)
        A = [np.full(nf, hooks[j], np.uint8) for j in range(NCH)]
        ln = build(C, A)
        got = [framer(ln, skew=k) for k in range(FLEN)]
        locks = sum(g['lock_bit'] is not None for g in got)
        false = sum(bool(g['false_lock']) for g in got)
        wsf = sum(1 for g in got if g['sf_offset'] not in (None, 0))
        print(f'  {kind:26s} {locks:>7d} {false:>7d} {wsf:>15d}')

    print('\n  One data card beside idle voice, swept over every octet phase')
    print('  (a byte-aligned 64 kbps data channel, seat 4, all channels on-hook):')
    p = run.params(RATE)
    sil = cvsd.encode(np.zeros(nf), p)
    word = [1, 0, 1, 1, 0, 0, 1, 0]
    tot = fl = 0
    for rot in range(8):
        oct8 = np.tile(np.array(word[rot:] + word[:rot], np.uint8), nf // 8 + 1)[:nf]
        C = [oct8 if j == 3 else np.roll(sil, 13 * j) for j in range(NCH)]
        A = [np.zeros(nf, np.uint8) for _ in range(NCH)]
        got = [framer(build(C, A), skew=k) for k in range(FLEN)]
        fl += sum(bool(g['false_lock']) for g in got); tot += FLEN
    print(f'    permanent false bit locks: {fl} / {tot} (8 octet phases x 8 skews)')

    print('\n  Effect of demanding the stage-2 signature over more superframes')
    print('  (speech + one data card, the cheapest available fix):')
    C = _lanes('speech + one data card', nf)
    A = [np.full(nf, hooks[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)
    for g in (1, 2, 4, 8):
        got = [framer(ln, skew=k, guards=g) for k in range(FLEN)]
        print(f'    signature held over {g:2d} superframe(s) ({g * 125:4d} us): '
              f'{sum(bool(x["false_lock"]) for x in got)} false of '
              f'{sum(x["lock_bit"] is not None for x in got)} locks')
    print('\n  CONTROL -- the 16-bit 7-channel frame, same line rate, same clip.')
    print('  Both old headers: the original static (0,1) and the current S=0 T=1110.')
    print('  A data card here straps A=1 and rides C (spec.md 3.4).\n')
    p = run.params(32000)
    src, fs = audio.read_wav('speech30.wav', seconds=3.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, 32000)
    sp = cvsd.encode(x, p)
    sil7 = cvsd.encode(np.zeros(len(sp)), p)
    L = len(sp)
    oct8 = np.tile(np.array([1, 0, 1, 1, 0, 0, 1, 0], np.uint8), L // 8 + 1)[:L]
    hk = (0, 0, 0, 1, 0, 0, 0)
    sets = {'speech': ([np.roll(sp, 977 * j) for j in range(7)],
                       [np.full(L, hk[j], np.uint8) for j in range(7)]),
            'idle': ([np.roll(sil7, 13 * j) for j in range(7)],
                     [np.full(L, hk[j], np.uint8) for j in range(7)]),
            'idle + one data card': ([oct8 if j == 3 else np.roll(sil7, 13 * j) for j in range(7)],
                                     [np.full(L, 1 if j == 3 else hk[j], np.uint8) for j in range(7)])}
    print(f'  {"payload":26s} {"header":>16s} {"locks":>7s} {"false":>7s}')
    for kind, (C7, A7) in sets.items():
        C7 = np.array(C7); A7 = np.array(A7)
        for hname, sch in (('static (0,1)', 'S0 static (0,1)'),
                           ('S=0 T=1110', 'S4 T=1110 period 4')):
            ln7 = fr.gbuild(C7, A7, fr.SCHEMES[sch])
            if sch.startswith('S4'):
                got = [s4_simple.framer_single(ln7, 7, skew=k) for k in range(16)]
            else:
                got = [fr.gframer(ln7, 7, fr.SCHEMES[sch], skew=k)[1] for k in range(16)]
            print(f'  {kind:26s} {hname:>16s} '
                  f'{sum(g["lock_bit"] is not None for g in got):>7d} '
                  f'{sum(bool(g["false_lock"]) for g in got):>7d}')


# ------------------------------------------------------------ 4: line errors

def errors():
    print('LINE ERRORS -- what one bad F bit costs')
    nf = 2 * RATE
    C = _lanes('speech', nf)
    A = [np.full(nf, 0, np.uint8) for _ in range(NCH)]
    ln = build(C, A)
    print('\n  mfspec 5 gives no tracking rule and no bad-frame counter, so a single')
    print('  F-bit error is a lost lock and a swallowed bit.  Mean time between')
    print('  F-bit errors, at a 64 kHz frame rate:\n')
    print(f'  {"BER":>8s} {"F errors/s":>12s} {"mean time between":>19s}')
    for ber in (1e-4, 1e-3, 1e-2, 3e-2):
        r = ber * RATE
        print(f'  {ber:8.0e} {r:12.1f} {1000.0 / r:16.2f} ms')
    print('\n  spec.md 7.3 carries a +1/-1 trip-16 counter for exactly this reason,')
    print('  and measures 0 false reframes to 3e-2 (0-1 at 3e-2, 8 at 5e-2).')
    st = framer(link.impair(ln, ber=1e-3, seed=5), skew=0)
    print(f'\n  mfspec receiver at 1e-3, true skew: first lock at bit {st["lock_bit"]}, '
          f'sf offset {st["sf_offset"]}')


# ------------------------------------------- 5: encoder, gate-level identity

def tx():
    """Does the mfspec frame fall out of counter taps with no offset logic?

    spec.md 4.3 does this for the 16-bit frame, where the framing bits sit at
    the END of the frame so the mux address needs no offset, at the cost of an
    S/T select gate and an override path.  mfspec puts them at the START, as
    mux inputs 0 and 1, which removes the override.  Checked bit for bit.
    """
    rng = np.random.default_rng(7)
    nf = 4096
    C = [(rng.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    A = [(rng.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]

    out = []
    bitc = 0            # 3-stage frame counter, b0..b2  (74xx393 half)
    sfcnt = 0           # 3-stage superframe counter     (74xx393 half)
    for f in range(nf):
        for _ in range(FLEN):
            # signalling mux: 8:1 addressed by the superframe counter.
            # inputs 3 and 7 are tied high and low -- the two pads.
            smux = (1 if sfcnt == 3 else 0 if sfcnt == 7 else A[SLOT[sfcnt]][f])
            # frame mux: 8:1 addressed directly by the frame counter.
            # input 0 = F = superframe counter LSB.  input 1 = signalling mux.
            frame_mux = [sfcnt & 1, smux] + [C[j][f] for j in range(NCH)]
            out.append(frame_mux[bitc])
            bitc = (bitc + 1) & 7
            if bitc == 0:
                sfcnt = (sfcnt + 1) & 7
    model = np.array(out, np.uint8)
    ref = build(C, A)
    n = min(len(model), len(ref))
    ok = bool((model[:n] == ref[:n]).all())

    print('ENCODER -- gate-level model against the frame builder')
    print(f'  4096 frames, random payload and hook states: '
          f'{"bit-exact" if ok else "MISMATCH"}\n')
    print('  The model needs, and only needs:')
    print('    3-stage frame counter          b0..b2, addresses the frame mux directly')
    print('    3-stage superframe counter     addresses the signalling mux; its LSB IS F')
    print('    8:1 frame mux                  in0 = F, in1 = signalling mux, in2..7 = C1..C6')
    print('    8:1 signalling mux             in3 tied high, in7 tied low, rest = A1..A6')
    print('\n  No S/T select gate, no framing-data AND, no mux-output override, and no')
    print('  multiframe pattern generator.  The 16-bit frame needs all four, plus a')
    print('  second 8:1 mux and a selector to reach 14 payload positions')
    print('  (seven-channel.md 3.2: "one extra package on the transmitter, possibly two").')
    print('\n  Placing the pads at states 3 and 7 does pay off as claimed: both are')
    print('  b1.b0 = 1, and the expected value is the complement of b2, so the RX')
    print('  guard is one AND for the enable and one XOR for the compare.')

    print('\nBIT BUDGET at 512 kbps, both formats')
    print(f'  {"":26s} {"16-bit, N=7":>14s} {"8-bit, mfspec":>14s}')
    rows = [('frame length, bits', 16, 8),
            ('frame rate, kHz', 32, 64),
            ('voice channels', 7, 6),
            ('per-channel rate, kbps', 32, 64),
            ('voice payload, kbps', 7 * 32, 6 * 64),
            ('signalling, kbps', 7 * 32, 6 * 8),
            ('framing, kbps', 2 * 32, 64 + 2 * 8)]
    for nm, a, b in rows:
        print(f'  {nm:26s} {a:>14} {b:>14}')
    print(f'  {"voice, % of line":26s} {100 * 7 * 32 / 512:>13.1f}% {100 * 6 * 64 / 512:>13.1f}%')
    print(f'  {"signalling per channel":26s} {"32 kbps":>14s} {"8 kbps":>14s}')
    print('\n  Same line, same code, same baud: 1.71x the voice payload, because the')
    print('  16-bit frame spends 43.75% of the line sending hook states 32000 times a')
    print('  second.  spec.md 9 needs one bit per 2 ms.')


# ------------------------------------------------------ 6: constant payload

def constant():
    """Can lock be held with constant 1 or 0 on the channel lanes?

    Two separate questions: can a WRONG alignment hold (false lock), and can
    the TRUE alignment be held (tracking).  Constant payload is the case that
    breaks the 16-bit frame's original static (0,1) header -- spec.md 3.3, "a
    constant data slot beside the opposite static A bit" -- so it is worth
    asking of this header too.
    """
    nf = 6400                                   # 0.1 s at a 64 kHz frame rate
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    sp = cvsd.encode(x, p)[:nf]
    sil = cvsd.encode(np.zeros(nf), p)
    z = np.zeros(nf, np.uint8); o = np.ones(nf, np.uint8)

    sets = {'all six lanes constant 0': [z] * NCH,
            'all six lanes constant 1': [o] * NCH,
            'lanes alternate 0 / 1': [z if j % 2 == 0 else o for j in range(NCH)],
            'one constant 0 in silence': [z if j == 3 else np.roll(sil, 13 * j) for j in range(NCH)],
            'one constant 1 in silence': [o if j == 3 else np.roll(sil, 13 * j) for j in range(NCH)],
            'one constant 0 in speech': [z if j == 3 else np.roll(sp, 977 * j) for j in range(NCH)],
            'two adjacent constants 0,1': [z if j == 2 else o if j == 3
                                           else np.roll(sil, 13 * j) for j in range(NCH)]}

    print('CONSTANT PAYLOAD -- false locks over all 64 hook states x all 8 skews')
    print('  (bit level, no line impairment; 0.1 s = 6400 frames per run)\n')
    print(f'  {"payload":28s} {"false locks":>12s} {"no lock at all":>15s}')
    hooksets = list(itertools.product((0, 1), repeat=NCH))
    for nm, C in sets.items():
        fl = nolock = 0
        for hooks in hooksets:
            A = [np.full(nf, hooks[j], np.uint8) for j in range(NCH)]
            ln = build(C, A)
            for k in range(FLEN):
                st = framer(ln, skew=k)
                if st['lock_bit'] is None:
                    nolock += 1
                elif st['false_lock']:
                    fl += 1
        tot = len(hooksets) * FLEN
        print(f'  {nm:28s} {f"{fl} / {tot}":>12s} {f"{nolock} / {tot}":>15s}')

    print('\n  Why constant payload is SAFE for this header, both ways round:')
    print('    F position: a constant lane never alternates -> stage 1 fails at once.')
    print('    S position: a constant lane cannot be both 1 at state 3 and 0 at')
    print('                state 7 -> the guard fails deterministically.')
    print('    The S lane itself cannot alternate for 8 frames either: an')
    print('    alternating run needs index 3 = 1 and index 7 = 0, and both')
    print('    01010101 and 10101010 fail one of them.  So skew 1 never holds.')

    print('\n  TRACKING at the true alignment (mfspec 5 re-verified every superframe,')
    print('  strictest reading: any pad mismatch unlocks):\n')
    print(f'  {"payload":28s} {"locked frames":>14s} {"unlocks":>8s} {"off-phase":>10s}')
    for nm, C in sets.items():
        A = [np.full(nf, (0, 0, 0, 1, 0, 0)[j], np.uint8) for j in range(NCH)]
        st = framer(build(C, A), skew=0, track='strict')
        print(f'  {nm:28s} {st["frames"]:>14d} {st["unlocks"]:>8d} {st["off_phase"]:>10d}')
    print('\n  Lock is held on every constant payload: F and S are dedicated bits,')
    print('  so the header is independent of what the channels carry.  This is a')
    print('  real advantage over the original static (0,1) header, which a constant')
    print('  data slot false-locks permanently (spec.md 3.3, 40/192 measured).')


# --------------------------------------------------- 7: over the line, 2 codes

def _lp(x, fc, FS, order=2):
    b, a = signal.butter(order, min(0.99, 2 * fc / FS))
    return signal.lfilter(b, a, x)


def rx_biphase(line, sd=0.0, imp=0.0, atten=1.0, seed=1, os_bit=32, cable=1.8e6):
    """spec.md 5-6: differential Manchester, hysteretic slicer, 0.75-cell
    monostable interval classifier.

    Three impairments, each swept on its own axis:
      sd     Gaussian floor, referred to the TRANSMITTED peak
      imp    impulse events/s, phy.plant_noise, amp 0.5-3x peak as
             repeater.py uses -- damped rings, the plant impairment
      atten  cable loss: the signal is scaled and the noise floor and the
             comparator hysteresis are NOT, so attenuation costs real margin.
             spec.md 5.1 notes the lowpass models dispersion, not loss.
    """
    FS = LINE_RATE * os_bit
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, os_bit // 2)
    x = _lp(x, cable, FS, 1); x /= np.abs(x).max()
    if atten != 1.0:
        x *= atten
    if sd:
        x += rng.normal(0, sd, len(x))
    if imp:
        x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
    w = fast.slice_hyst(_lp(x, 2 * LINE_RATE, FS, 2), 0.05)
    del x; gc.collect()
    b = fast.mono_decode(w, os_bit, thr=0.75, dead=0.25)
    del w; gc.collect()
    return b


def rx_ami(line, sd=0.0, imp=0.0, atten=1.0, seed=1, os_bit=32,
           cable=1.8e6, gain=1.0):
    """AMI: one symbol per bit, so half the biphase symbol rate and a receive
    filter at 512 kHz instead of 1.024 MHz -- that narrower noise bandwidth is
    AMI's whole advantage.  The decoder estimates its own peak (free AGC), so
    these numbers are optimistic; `gain` injects the amplitude error spec.md 5
    rejected it for."""
    FS = LINE_RATE * os_bit
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.ami_encode(line), os_bit)
    x = _lp(x, cable, FS, 1); x /= np.abs(x).max()
    if atten != 1.0:
        x *= atten
    if sd:
        x += rng.normal(0, sd, len(x))
    if imp:
        x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
    x = _lp(x, LINE_RATE, FS, 2)
    peak = gain * np.percentile(np.abs(x), 99) if gain != 1.0 else None
    b = fast.ami_decode(x, os_bit, thresh=0.5, peak=peak)
    del x; gc.collect()
    return b


def _seg_lane_ber(rb, pos, C, nch=NCH, off=2, stride=1, flen=FLEN,
                  minlen=200, win=80):
    """Lane BER aligned independently inside each contiguous locked segment.

    An impulse can make the interval classifier gain or lose a bit, which
    re-phases everything downstream.  A single global offset then reports ~50%
    for the whole remainder -- a bookkeeping artefact, not an error rate.  Each
    locked run is therefore aligned on its own, near its own position in the
    stream.  Returns (weighted lane BER, segments used).
    """
    if len(pos) == 0:
        return 1.0, 0
    brk = np.flatnonzero(np.diff(pos) != flen) + 1
    tot = 0; acc = 0.0; used = 0
    for sg in np.split(pos, brk):
        if len(sg) < minlen:
            continue
        got = [rb[sg + off + stride * j] for j in range(nch)]
        c0 = int(sg[0]) // flen
        best = (1.0, None)
        for d in range(max(0, c0 - win), c0 + win):
            n = min(len(got[0]), len(C[0]) - d)
            if n < minlen:
                break
            e = float((got[0][:n] != C[0][d:d + n]).mean())
            if e < best[0]:
                best = (e, d)
            if e == 0.0:
                break
        if best[1] is None:
            continue
        d = best[1]; n = min(len(got[0]), len(C[0]) - d)
        per = float(np.mean([(got[j][:n] != C[j][d:d + n]).mean() for j in range(nch)]))
        acc += per * n; tot += n; used += 1
    return (acc / tot if tot else 1.0), used


def _raw_ber(rb, ln):
    """Decoded stream against the transmitted line bits, best global offset."""
    best = 1.0
    for o in range(0, 40):
        n = min(len(rb) - o, len(ln))
        if n < 1000:
            break
        e = float((rb[o:o + n] != ln[:n]).mean())
        if e < best:
            best = e
        if best == 0.0:
            break
    return best


def _lane_check(rb, pos, C, nch=NCH, off=2, stride=1):
    """Are the channel lanes recovered, and are they in the right order?

    Returns (rotated, identity BER).  `rotated` is True only when some other
    lane assignment beats the identity by a clear margin -- with constant or
    silent payload every lane is bit-identical, so lane identity is undefined
    and there is nothing to get wrong.  The global offset is found once from
    lane 0 and applied across every lane: spec.md 4.1 records that finding a
    separate lag per pair is the way to fool yourself.
    """
    if len(pos) < 200:
        return None, 1.0
    pos = pos[:len(pos) - 2]
    got = [rb[pos + off + stride * j] for j in range(nch)]
    best = (1.0, 0)
    for d in range(0, 160):                      # must exceed the lock delay
        n = min(len(got[0]), len(C[0]) - d)
        if n < 100:
            break
        e = float((got[0][:n] != C[0][d:d + n]).mean())
        if e < best[0]:
            best = (e, d)
        if e == 0.0:
            break
    d = best[1]
    n = min(len(got[0]), len(C[0]) - d)
    ident, rotated = [], False
    for j in range(nch):
        cand = [float((got[j][:n] != C[k][d:d + n]).mean()) for k in range(nch)]
        ident.append(cand[j])
        if min(cand) < cand[j] - 0.05:           # another lane fits clearly better
            rotated = True
    return rotated, float(np.mean(ident))


def _sig_check(rb, pos, hooks):
    """Demux the S lane the way the '259 would and see which channel each hook
    state lands in.  A wrong superframe phase permutes them."""
    if len(pos) < 64:
        return None
    pos = pos[:len(pos) - 2]
    s = rb[pos + 1]
    got = []
    for state in range(8):
        if state in PADS:
            continue
        v = s[state::8]
        got.append(1 if v.mean() > 0.5 else 0)
    # got[i] is what the receiver latched for the channel at superframe slot i
    order = [SLOT[st] for st in range(8) if st not in PADS]
    out = [0] * NCH
    for slot_i, ch in enumerate(order):
        out[ch] = got[slot_i]
    return tuple(out) == tuple(hooks), tuple(out)


def line():
    nf = 8000                                   # 0.125 s, 64000 line bits
    hooks = (0, 0, 0, 1, 0, 0)
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    sp = cvsd.encode(x, p)[:nf]
    sil = cvsd.encode(np.zeros(nf), p)
    pay = {'speech': [np.roll(sp, 977 * j) for j in range(NCH)],
           'idle (silence)': [np.roll(sil, 13 * j) for j in range(NCH)],
           'constant 0': [np.zeros(nf, np.uint8)] * NCH,
           'constant 1': [np.ones(nf, np.uint8)] * NCH}
    A = [np.full(nf, hooks[j], np.uint8) for j in range(NCH)]
    SDS = (0.0, 0.4, 0.5, 0.6, 0.7)

    print('OVER THE LINE -- the mfspec receiver on a real waveform, both codes')
    print(f'  512 kbps, one 1.8 MHz cable, {nf} frames, hook states {hooks}.')
    print('  Noise sd is referred to the signal peak: one rail-limited driver,')
    print('  one cable, one noise floor, so the two codes are compared on the')
    print('  same physical line.  Biphase symbol rate 1.024 MBaud with a')
    print('  1.024 MHz RX filter; AMI 512 kBaud with a 512 kHz RX filter.\n')
    print('  lock = locked at the true bit phase and the six lanes in the right')
    print('  order;  sig = hook states delivered to the right channels.\n')
    print('  Mark density and the longest run of zeros -- AMI sends nothing for a')
    print('  zero, so this is what its clock recovery has to live on:\n')
    print(f'  {"payload":16s} {"mark %":>8s} {"longest 0 run":>15s}')
    for nm, C in pay.items():
        ln = build(C, A)
        d = np.diff(np.flatnonzero(np.concatenate(([1], ln, [1]))))
        print(f'  {nm:16s} {100.0 * ln.mean():8.1f} {int(d.max()) - 1:15d}')
    print()

    print(f'  {"payload":16s} {"code":8s} {"sd":>4s} {"mark%":>6s} {"lock":>5s} '
          f'{"lanes":>6s} {"sig":>4s} {"unlk":>5s} {"payload BER":>12s}')
    for nm, C in pay.items():
        ln = build(C, A)
        mark = 100.0 * ln.mean()
        for cn, rx in (('biphase', rx_biphase), ('ami', rx_ami)):
            for sd in SDS:
                rb = rx(ln, sd)
                st = framer(rb, skew=0, track='strict')
                if st['lock_bit'] is None:
                    print(f'  {nm:16s} {cn:8s} {sd:4.1f} {mark:6.1f} {"NO":>5s} '
                          f'{"-":>6s} {"-":>4s} {"-":>5s} {"-":>12s}', flush=True)
                    continue
                rot, be = _lane_check(rb, st['pos'], C)
                sg = _sig_check(rb, st['pos'], hooks)
                ok = (not st['false_lock']) and not rot
                print(f'  {nm:16s} {cn:8s} {sd:4.1f} {mark:6.1f} '
                      f'{"yes" if ok else "NO":>5s} '
                      f'{("rot" if rot else "ok"):>6s} '
                      f'{("ok" if sg and sg[0] else "BAD"):>4s} '
                      f'{st["unlocks"]:>5d} {be:12.1e}', flush=True)
                del rb; gc.collect()

    print('\n  RAW line BER, no framer -- the PHY on its own, so the two codes are')
    print('  compared without the protocol amplifying a small error (below).')
    print('  AMI `gain` is the receive amplitude error spec.md 5 rejected it for.\n')
    ln = build(pay['speech'], A)
    print(f'  {"code":22s} ' + ' '.join(f'{s:>9.1f}' for s in SDS))
    cases = [('biphase', lambda l, sd: rx_biphase(l, sd)),
             ('ami, exact amplitude', lambda l, sd: rx_ami(l, sd)),
             ('ami, 0.8x amplitude', lambda l, sd: rx_ami(l, sd, gain=0.8)),
             ('ami, 0.6x amplitude', lambda l, sd: rx_ami(l, sd, gain=0.6))]
    for cn, fn in cases:
        r = []
        for sd in SDS:
            rb = fn(ln, sd)
            e = _raw_ber(rb, ln)
            r.append('       ok' if e == 0 else f'{e:9.1e}')
            del rb; gc.collect()
        print(f'  {cn:22s} ' + ' '.join(r), flush=True)
    print('\n  Biphase decides on transition TIMING against a 0.75-cell monostable,')
    print('  so noise must displace an edge by a quarter cell to cause an error.')
    print('  AMI decides on AMPLITUDE against a threshold at half the received')
    print('  peak, and at equal peak line voltage that is the smaller margin --')
    print('  which is why AMI loses here despite half the noise bandwidth.')

    print('\n  CONTROL -- the 16-bit 7-channel frame, S=0 T=1110, same line and')
    print('  same noise (32 kHz frame rate, 7 x 32 kbps):\n')
    p32 = run.params(32000)
    n32 = nf // 2
    src, fs = audio.read_wav('speech30.wav', seconds=n32 / 32000 + 0.5)
    x32 = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, 32000)
    sp32 = cvsd.encode(x32, p32)[:n32]
    sil32 = cvsd.encode(np.zeros(n32), p32)
    C7 = {'speech': np.array([np.roll(sp32, 977 * j) for j in range(7)]),
          'idle (silence)': np.array([np.roll(sil32, 13 * j) for j in range(7)]),
          'constant 0': np.zeros((7, n32), np.uint8),
          'constant 1': np.ones((7, n32), np.uint8)}
    A7 = np.array([np.full(n32, (0, 0, 0, 1, 0, 0, 0)[j], np.uint8) for j in range(7)])
    S4 = fr.SCHEMES['S4 T=1110 period 4']
    print(f'  {"payload":16s} {"code":8s} {"sd":>4s} {"lock":>5s} {"lanes":>6s} '
          f'{"LOF":>4s} {"payload BER":>12s}')
    for nm, Cx in C7.items():
        ln7 = fr.gbuild(Cx, A7, S4)
        for cn, rx in (('biphase', rx_biphase), ('ami', rx_ami)):
            for sd in SDS:
                rb = rx(ln7, sd)
                st = s4_simple.framer_single(rb, 7)
                if st['lock_bit'] is None:
                    print(f'  {nm:16s} {cn:8s} {sd:4.1f} {"NO":>5s} {"-":>6s} '
                          f'{"-":>4s} {"-":>12s}', flush=True)
                    continue
                rot, be = _lane_check(rb, st['pos'], Cx, nch=7, off=1, stride=2)
                ok = (not st['false_lock']) and not rot
                print(f'  {nm:16s} {cn:8s} {sd:4.1f} {"yes" if ok else "NO":>5s} '
                      f'{("rot" if rot else "ok"):>6s} {st["lof_events"]:>4d} '
                      f'{be:12.1e}', flush=True)
                del rb; gc.collect()


# -------------------------------------------- 8: random data, long run, resync

def _slip_cost(ln, at, k, mode='strict'):
    """Frames emitted at a wrong phase after a k-bit slip, and frames to
    re-lock.  Same convention as s4_simple.lof_worst: positions after the slip
    map back through +k."""
    sl = link.slip(ln, at, n=k)
    st = framer(sl, track=mode)
    pos = st['pos']
    if len(pos) == 0:
        return None
    pre, post = pos[pos < at], pos[pos >= at]
    if len(pre) == 0 or len(post) == 0:
        return None
    base = pre[0] % FLEN
    good = (((post + k) % FLEN) == base)
    bad = int((~good).sum())
    relock = int(np.flatnonzero(good)[0]) if good.any() else None
    return bad, relock, st['unlocks']


def randdata():
    NF = 2_000_000                              # 31.25 s at a 64 kHz frame rate
    rng = np.random.default_rng(11)
    C = [(rng.random(NF) < 0.5).astype(np.uint8) for _ in range(NCH)]
    hooks = (0, 0, 0, 1, 0, 0)
    A = [np.full(NF, hooks[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)
    print('RANDOM DATA ON ALL SIX CHANNELS')
    print(f'  {NF} frames = {NF / RATE:.2f} s of line time, {ln.size} line bits.')
    print('  Unconstrained random data is the BENIGN end of the payload space:')
    print('  a random lane alternates with p=0.5, so it passes stage 1 on only')
    print('  0.4% of windows (4.1).  It is octet-PERIODIC data that is fatal (4.2).\n')

    print('  Long run on a clean line, both readings of mfspec 5:\n')
    print(f'  {"reading":34s} {"locked frames":>14s} {"unlocks":>8s} {"off-phase":>10s}')
    for mode, lbl in (('strict', "'strict': any pad mismatch unlocks"),
                      ('none', "'none': never re-checked after lock")):
        st = framer(ln, track=mode)
        print(f'  {lbl:34s} {st["frames"]:>14d} {st["unlocks"]:>8d} '
              f'{st["off_phase"]:>10d}', flush=True)
    print('\n  Lock is held for the full 31 s with zero unlocks: F and S are')
    print('  dedicated bits, so random payload cannot disturb a correct lock,')
    print('  exactly as constant payload cannot (5).')

    print('\n  Long run with line errors, strict reading:\n')
    print(f'  {"line BER":>9s} {"locked frames":>14s} {"unlocks":>8s} {"off-phase":>10s} '
          f'{"off-phase %":>12s} {"mean resync":>12s}')
    for ber in (0.0, 1e-5, 1e-4, 1e-3, 1e-2):
        imp = link.impair(ln, ber=ber, seed=5) if ber else ln
        st = framer(imp, track='strict')
        tot = st['frames'] + st['off_phase']
        pct = 100.0 * st['off_phase'] / max(tot, 1)
        gap = (NF - st['frames']) / max(st['unlocks'], 1)
        print(f'  {ber:9.0e} {st["frames"]:>14d} {st["unlocks"]:>8d} '
              f'{st["off_phase"]:>10d} {pct:11.3f}% '
              f'{gap:9.1f} fr', flush=True)
        if ber:
            del imp; gc.collect()
    print('\n  Every unlock costs a full re-acquisition, and mfspec has no')
    print('  hysteresis to absorb one bad pad sample.  spec.md 7.3 measures 0')
    print('  false reframes to 3e-2 on the same class of line.')

    print('\n  RESYNC after an induced slip, every slip size, clean line:\n')
    print(f'  {"slip":>5s} ' + ' '.join(f'{m:>22s}' for m in ("strict: bad / relock", "none: bad frames")))
    at = (NF // 2) * FLEN
    for k in range(1, FLEN):
        r1 = _slip_cost(ln, at, k, 'strict')
        r2 = _slip_cost(ln, at, k, 'none')
        a = f'{r1[0]} / {r1[1]}' if r1 and r1[1] is not None else (f'{r1[0]} / never' if r1 else '-')
        b = f'{r2[0]}' if r2 else '-'
        print(f'  {k:>5d} ' + f'{a:>22s} {b:>22s}', flush=True)
    print('\n  bad = frames emitted at a wrong phase after the slip;')
    print('  relock = frames until the first correctly-phased frame.')
    print("  Under 'none' a slip is NEVER detected and the channels stay rotated")
    print('  for the rest of the run -- which is spec.md 7.4\'s point restated:')
    print('  a misaligned frame fails only part of the time, so a rule that needs')
    print('  a run of bad frames does not fire.  mfspec has neither rule.')

    print('\n  Where a resync can LAND: false locks over many hunts on random data')
    print('  (8 skews x 250 payload seeds, 2000 frames each):\n')
    nf2 = 2000
    fl = tot = 0
    acq = []
    for sd_i in range(250):
        r2 = np.random.default_rng(1000 + sd_i)
        C2 = [(r2.random(nf2) < 0.5).astype(np.uint8) for _ in range(NCH)]
        A2 = [np.full(nf2, hooks[j], np.uint8) for j in range(NCH)]
        l2 = build(C2, A2)
        for k in range(FLEN):
            st = framer(l2, skew=k, track='acquire')
            tot += 1
            if st['lock_bit'] is None:
                continue
            if st['false_lock']:
                fl += 1
            else:
                acq.append(st['lock_bit'] / FLEN)
    print(f'  false locks: {fl} / {tot}  ({100.0 * fl / tot:.2f}% of hunts)')
    print(f'  acquisition, true phase: {min(acq):.0f}-{max(acq):.0f} frames, '
          f'mean {np.mean(acq):.1f} = {1000 * np.mean(acq) / RATE:.3f} ms')
    print('\n  Confirmation strength.  Analytically, ONE wrong phase tested once')
    print('  against random data passes with probability')
    print('    stage 1, 8 alternating frames   0.5^8 = 3.9e-03')
    print('    stage 2, two pad bits           0.25')
    print('    product                               = 9.8e-04  ~ 2^-10')
    print('  against the 16-bit framer\'s 32 good frames at <=50% each = 2^-32.')
    print('  The MEASURED per-hunt rate is lower than that product (0 of 2000,')
    print('  so <=1.8e-03 at 95%), because a failing phase is abandoned after one')
    print('  bad frame rather than retried -- the hunt walks away before it can')
    print('  accumulate an 8-frame run.  So against random data the weak')
    print('  confirmation does not bite in practice; 4.2\'s periodic-data hole is')
    print('  structural rather than statistical, and no confirmation count')
    print('  reaches it.  What mfspec buys for the weaker check is speed: 15-40')
    print('  frames at 64 kHz against 31-49 at 32 kHz, so about 3x faster in time.')

    print('\n  CONTROL -- 16-bit 7-channel, S=0 T=1110, random data on all seven')
    print('  C bits with A strapped to 1 (spec.md 3.4), same line length:\n')
    n32 = NF // 2
    r3 = np.random.default_rng(12)
    C7 = np.array([(r3.random(n32) < 0.5).astype(np.uint8) for _ in range(7)])
    A7 = np.ones((7, n32), np.uint8)
    ln7 = fr.gbuild(C7, A7, fr.SCHEMES['S4 T=1110 period 4'])
    print(f'  {"line BER":>9s} {"locked frames":>14s} {"LOF events":>11s} {"off-phase":>10s}')
    for ber in (0.0, 1e-4, 1e-3, 1e-2):
        imp = link.impair(ln7, ber=ber, seed=5) if ber else ln7
        st = s4_simple.framer_single(imp, 7)
        pos = st['pos']
        off = int((pos % 16 != (pos[0] % 16)).sum()) if len(pos) else 0
        print(f'  {ber:9.0e} {len(pos):>14d} {st["lof_events"]:>11d} {off:>10d}',
              flush=True)
        if ber:
            del imp; gc.collect()


# ------------------------- 9: impulse and attenuation, independently, 2 codes

def plant():
    nf = 16000                                  # 0.25 s
    rng = np.random.default_rng(21)
    C = [(rng.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    hooks = (0, 0, 0, 1, 0, 0)
    A = [np.full(nf, hooks[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)
    C7 = np.array([(rng.random(nf // 2) < 0.5).astype(np.uint8) for _ in range(7)])
    A7 = np.ones((7, nf // 2), np.uint8)
    ln7 = fr.gbuild(C7, A7, fr.SCHEMES['S4 T=1110 period 4'])
    SEEDS = (1, 2, 3, 4)

    def run_case(rx, **kw):
        """Four seeds; unlocks, % of frames not locked, segment-aligned BER."""
        unl = 0; lk = 0; pay = []
        for sd_i in SEEDS:
            rb = rx(ln, seed=sd_i, **kw)
            st = framer(rb, track='strict')
            unl += st['unlocks']; lk += st['frames']
            be, _ = _seg_lane_ber(rb, st['pos'], C)
            pay.append(be)
            del rb; gc.collect()
        down = 100.0 * (1.0 - lk / (nf * len(SEEDS)))
        return unl, down, float(np.mean(pay))

    def run_ctrl(rx, **kw):
        lof = 0; lk = 0; pay = []
        for sd_i in SEEDS:
            rb = rx(ln7, seed=sd_i, **kw)
            st = s4_simple.framer_single(rb, 7)
            lof += st['lof_events']; lk += len(st['pos'])
            be, _ = _seg_lane_ber(rb, st['pos'], C7, nch=7, off=1, stride=2, flen=16)
            pay.append(be)
            del rb; gc.collect()
        down = 100.0 * (1.0 - lk / ((nf // 2) * len(SEEDS)))
        return lof, down, float(np.mean(pay))

    print('BIT COUNT UNDER IMPULSE -- the mechanism behind 8.1')
    print('  A decoder that emits a different NUMBER of bits than were sent has')
    print('  slipped: the frame re-phases and must reacquire.  Emitted minus sent,')
    print(f'  over 4 seeds, {len(ln)} line bits:\n')
    print(f'  {"impulse/s":>10s} {"biphase":>26s} {"ami":>16s}')
    for imp in (0.0, 10.0, 100.0, 1000.0):
        db = []; da = []
        for sd_i in SEEDS:
            rb = rx_biphase(ln, imp=imp, seed=sd_i); db.append(len(rb) - len(ln))
            ra = rx_ami(ln, imp=imp, seed=sd_i); da.append(len(ra) - len(ln))
            del rb, ra; gc.collect()
        print(f'  {imp:10.0f} {str(db):>26s} {str(da):>16s}', flush=True)
    print('\n  The monostable decides on transition TIMING and has no independent')
    print('  time reference, so a transient that adds or swallows an edge changes')
    print('  the bit count.  AMI is clocked: it emits exactly one bit per recovered')
    print('  clock period whatever the line does, so the count cannot drift and the')
    print('  +1/-1 counter only ever sees ordinary bit errors.  The -1 at zero')
    print('  impulses is a constant end effect, not a slip.\n')

    print('LINE IMPAIRMENTS, SWEPT INDEPENDENTLY -- random data, both codes')
    print(f'  {nf} frames x 4 noise seeds per cell.  Each impairment is applied')
    print('  on its own, with the other two off, so the axes do not confound.')
    print('  mfspec: unlock events, strict reading.  16-bit: loss-of-frame events.')
    print('  "down %" is frames not locked -- availability, which is well defined')
    print('  across a slip where a phase comparison is not.  "lane BER" is aligned')
    print('  inside each locked run, so a re-phasing slip is not counted as errors.\n')

    for title, axis, kwname, vals in (
            ('IMPULSE NOISE (phy.plant_noise: damped rings at 0.5-3x the signal\n'
             '  peak as repeater.py uses, 15-80 kHz, 20-200 us decay, Poisson)',
             'events/s', 'imp', (0.0, 10.0, 100.0, 1000.0, 5000.0)),
            ('ATTENUATION (signal scaled; noise floor sd 0.10 and the 0.05\n'
             '  comparator hysteresis both held fixed, so loss costs margin.\n'
             '  Hysteresis as a fraction of received amplitude: 5% at 1.0, 10%\n'
             '  at 0.5, 20% at 0.25, 42% at 0.12 -- spec.md 6.1 allows 10%, and\n'
             '  20% on a single span)',
             'atten', 'atten', (1.0, 0.5, 0.25, 0.12, 0.06)),
            ('GAUSSIAN FLOOR, for reference on the same clip',
             'sd', 'sd', (0.0, 0.4, 0.5, 0.6, 0.7))):
        print(f'  {title}\n')
        print(f'  {axis:>10s} {"code":8s} | mfspec: {"unlk":>5s} {"down %":>7s} '
              f'{"lane BER":>10s} | 16-bit: {"LOF":>4s} {"down %":>7s} {"lane BER":>10s}')
        for v in vals:
            kw = {kwname: v}
            if kwname == 'atten':
                kw['sd'] = 0.10
            for cn, rx in (('biphase', rx_biphase), ('ami', rx_ami)):
                unl, down, pay = run_case(rx, **kw)
                clof, cdown, cpay = run_ctrl(rx, **kw)
                print(f'  {v:>10.4g} {cn:8s} |         {unl:>5d} {down:>6.2f}% '
                      f'{pay:10.1e} |         {clof:>4d} {cdown:>6.2f}% {cpay:10.1e}',
                      flush=True)
        print()


# ------------------------------------------- 10: AMI clock recovery, measured

def _maxrun0(ln):
    d = np.diff(np.flatnonzero(np.concatenate(([1], ln, [1]))))
    return int(d.max()) - 1


def clock():
    """Can an AMI receiver recover the clock from this frame?

    The frame bounds the zero run, so no B8ZS/HDB3 is needed.  What it costs
    is a clock: differential Manchester has a transition every cell and the
    monostable needs no clock at all (spec.md 6.1), while AMI sends nothing
    for a zero and must flywheel across the gaps.
    """
    nf = 4096
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=nf / RATE + 0.5)
    xa = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    sp = cvsd.encode(xa, p)[:nf]; sil = cvsd.encode(np.zeros(nf), p)
    z = np.zeros(nf, np.uint8); o = np.ones(nf, np.uint8)
    oct8 = np.tile(np.array([1, 0, 1, 1, 0, 0, 1, 0], np.uint8), nf // 8)[:nf]
    rg = np.random.default_rng(9)
    sets = {'all constant 0': [z] * NCH, 'all constant 1': [o] * NCH,
            'CVSD silence': [np.roll(sil, 13 * j) for j in range(NCH)],
            'CVSD speech': [np.roll(sp, 977 * j) for j in range(NCH)],
            'octet 10110010': [oct8] * NCH,
            'random data': [(rg.random(nf) < 0.5).astype(np.uint8) for j in range(NCH)]}

    print('ZERO RUNS -- the frame bounds them, so AMI needs no zero substitution')
    print('  Worst run of zeros on the line, over all 64 hook states:\n')
    worst = 0
    for nm, C in sets.items():
        m = max(_maxrun0(build(C, [np.full(nf, h[j], np.uint8) for j in range(NCH)]))
                for h in itertools.product((0, 1), repeat=NCH))
        worst = max(worst, m)
        print(f'  {nm:18s} {m:3d}')
    print(f'\n  worst over everything: {worst} bits.')
    print('  F alternates, so a mark lands every 2 frames = 16 line bits whatever')
    print('  the payload does.  15 is STRUCTURAL, not statistical, and it is the')
    print('  8-bit frame that makes it so.  B8ZS substitutes at 8 zeros and HDB3')
    print('  at 4, so neither is needed -- the framing bit already does the job.')
    print('  T = 1110 on F (10, item 1) keeps the same bound: F is 0 one frame in')
    print('  four, so the longest gap is still 2 frames.')

    # ---------------------------------------------------------------- tank
    OSB = 32; FS = LINE_RATE * OSB

    def ami_an(line, sd=0.0, seed=1):
        x = np.repeat(fast.ami_encode(line), OSB)
        x = _lp(x, 1.8e6, FS, 1); x /= np.abs(x).max()
        if sd:
            x += np.random.default_rng(seed).normal(0, sd, len(x))
        return _lp(x, LINE_RATE, FS, 2)

    def tank(x, foff, Q):
        r = np.abs(x); r = r - r.mean()
        b, a = signal.iirpeak(LINE_RATE * (1.0 + foff) / (FS / 2), Q)
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

    n2 = 6000
    A0 = [np.zeros(n2, np.uint8) for _ in range(NCH)]
    ln0 = build([np.zeros(n2, np.uint8)] * NCH, A0)          # the 15-zero case
    r2 = np.random.default_rng(4)
    lnr = build([(r2.random(n2) < 0.5).astype(np.uint8) for _ in range(NCH)], A0)
    SKIP = 60 * OSB

    x = ami_an(lnr); t = tank(x, 0.0, 100.0)
    cal, bb = 0, 1.0
    for ph in range(OSB):
        b, idx = tank_bits(x, t, ph, SKIP)
        e = ber_at(b, lnr, int(idx[0]) // OSB if len(idx) else 0)
        if e < bb:
            bb, cal = e, ph

    print('\n\nOPTION A -- analog tank (rectify, resonator, flywheel)')
    print(f'  Sampling phase trimmed once at nominal: phase {cal}, BER {bb:.1e}.')
    print('  BER on the worst payload (constant 0), tank detuned:\n')
    offs = (0.0, 0.001, 0.0025, 0.005, 0.01, 0.02)
    print(f'  {"Q":>6s} {"amp left":>9s} ' + ' '.join(f'{f * 100:>7.2f}%' for f in offs))
    for Q in (20.0, 50.0, 100.0, 200.0, 500.0):
        row = []
        for f in offs:
            x = ami_an(ln0); t = tank(x, f, Q)
            b, idx = tank_bits(x, t, cal, SKIP)
            row.append(ber_at(b, ln0, int(idx[0]) // OSB if len(idx) else 0))
            del x, t; gc.collect()
        print(f'  {Q:6.0f} {np.exp(-np.pi * 15 / Q):9.2f} '
              + ' '.join(('     ok' if e == 0 else f'{e:7.1e}') for e in row), flush=True)
    print('\n  Two effects, and the second is the binding one:')
    print('    coasting decay over 15 idle cycles = exp(-pi*15/Q)  -> wants Q high')
    print('    static phase shift when detuned    = atan(2*Q*df/f) -> wants Q low')
    print('  The measured edge sits at df/f ~ 1/(2Q): ok at 0.25% with Q=100,')
    print('  broken at 0.5%.  So a tank wants Q ~ 100 AND tuning inside ~0.25%.')
    print('  A 1% L and a 1% C give about 1% -- an LC tank does not reach it.')
    print('  That is a ceramic resonator or a crystal, per line rate, on the')
    print('  receiver\'s rate plug (line-receiver.md 8).')

    # ---------------------------------------------------------------- DPLL
    print('\n\nOPTION B -- oversampling DPLL off the local 4.096 MHz crystal')
    print('  The RX sampling clock is the local crystal; the far end\'s is an')
    print('  independent one, so the offset is what two crystals disagree by.\n')
    print('  4.096 MHz divides every family rate exactly:')
    print('    ' + ',  '.join(f'{r} kbps -> {4096 // r}x' for r in (1024, 512, 256, 128, 64)))

    def ami_dpll(line, sd=0.0, ppm=0.0, seed=1, sub=4):
        """Sample the analog waveform on the RX clock, offset by ppm from the
        TX clock, at FS/sub = 4.096 MHz = 8x the 512 kHz bit rate."""
        x = ami_an(line, sd=sd, seed=seed)
        step = sub * (1.0 + ppm * 1e-6)
        idx = np.round(np.arange(0, len(x) - 1, step)).astype(np.int64)
        return fast.ami_decode(x[idx], OSB // sub, thresh=0.5)

    n3 = 12000
    A3 = [np.zeros(n3, np.uint8) for _ in range(NCH)]
    l0 = build([np.zeros(n3, np.uint8)] * NCH, A3)
    r3 = np.random.default_rng(4)
    lr = build([(r3.random(n3) < 0.5).astype(np.uint8) for _ in range(NCH)], A3)
    fmt = lambda e: '        ok' if e == 0 else f'{e:10.1e}'
    print(f'\n  {"TX ppm":>8s} {"const 0":>10s} {"random":>10s}   clean line')
    for ppm in (0, 100, 200, 500, 1000, 5000):
        print(f'  {ppm:8d} {fmt(_raw_ber(ami_dpll(l0, ppm=ppm), l0))} '
              f'{fmt(_raw_ber(ami_dpll(lr, ppm=ppm), lr))}', flush=True)
    print(f'\n  {"TX ppm":>8s} {"sd":>5s} {"const 0":>10s} {"random":>10s}   with noise')
    for ppm in (0, 100):
        for sd in (0.3, 0.4, 0.5):
            print(f'  {ppm:8d} {sd:5.1f} {fmt(_raw_ber(ami_dpll(l0, sd=sd, ppm=ppm), l0))} '
                  f'{fmt(_raw_ber(ami_dpll(lr, sd=sd, ppm=ppm), lr))}', flush=True)
    print('\n  Two crystals at +/-100 ppm disagree by at most 200 ppm = 0.02%,')
    print(f'  a phase slip of {15 * 2e-4:.4f} bit across a 15-zero gap.  Against the')
    print('  tank\'s 0.25% requirement that is 12x margin on frequency, and the')
    print('  coast is nothing.  Error-free to 1000 ppm on the worst payload.')
    print('\n  The cost is architectural, not electrical: spec.md 6.1\'s receiver')
    print('  has NO clock on the timing path, and this gives it one.  That is the')
    print('  property being traded, and 6.3 already prices it -- the oversampling')
    print('  DPLL is the reference receiver there.')


# ------------------------------- 11: impulse susceptibility and what it costs

def impulse():
    """How susceptible is differential Manchester to impulse noise, and what
    does it cost the audio?

    Note on names: in this repository "biphase" and "differential Manchester"
    are the SAME code -- fast.dm_encode is the only biphase encoder and
    spec.md 5 names it differential Manchester.  This is one code's
    susceptibility, not two.
    """
    OSB = 32; FS = LINE_RATE * OSB
    secs = 1.0
    nf = int(secs * RATE)
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=secs + 0.5)
    ref = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)[:nf]
    sp = cvsd.encode(ref, p)
    C = [np.roll(sp, 977 * j) for j in range(NCH)]
    A = [np.full(nf, (0, 0, 0, 1, 0, 0)[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)

    def wave(sd=0.0, imp=0.0, amp=(0.5, 3.0), hyst=0.05, hp=0.0, seed=1):
        rng = np.random.default_rng(seed)
        x = np.repeat(fast.dm_encode(ln).astype(np.float64) * 2 - 1, OSB // 2)
        x = _lp(x, 1.8e6, FS, 1); x /= np.abs(x).max()
        if sd:
            x += rng.normal(0, sd, len(x))
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=amp, seed=seed + 7)
        if hp:                                   # transformer: AC coupling
            b, a = signal.butter(1, min(0.99, 2 * hp / FS), btype='high')
            x = signal.lfilter(b, a, x)
        return _lp(x, 2 * LINE_RATE, FS, 2), hyst

    def decode(w_h, dead=0.25):
        w, hyst = w_h
        s = fast.slice_hyst(w, hyst)
        b = fast.mono_decode(s, OSB, thr=0.75, dead=dead)
        del s; gc.collect()
        return b

    # -------------------------------------------- susceptibility threshold
    print('IMPULSE SUSCEPTIBILITY -- differential Manchester (== "biphase" here)')
    print('  Mechanism: the rings are 15-80 kHz against a 512 kHz symbol rate, so')
    print('  each one acts as a slowly varying OFFSET.  With the signal at +/-1 and')
    print('  hysteresis h, an offset A sticks the comparator when A > 1-h: one')
    print('  polarity stops crossing, every transition in the ring is lost, and the')
    print('  decoder loses that many bits.  Ring length 20-200 us = 10-100 bits.\n')
    print('  Bits lost vs impulse amplitude, fixed rate 200/s, 4 seeds:\n')
    print(f'  {"amplitude":>10s} {"predicted":>10s} {"bits lost":>26s}')
    for a in (0.2, 0.5, 0.8, 0.95, 1.1, 1.5, 3.0):
        d = []
        for sd_i in (1, 2, 3, 4):
            w = wave(imp=200.0, amp=(a, a), seed=sd_i)
            b = decode(w); d.append(len(ln) - len(b))
            del w, b; gc.collect()
        pred = 'sticks' if a > 1.0 - 0.05 else '-'
        print(f'  {a:10.2f} {pred:>10s} {str(d):>26s}', flush=True)
    print('\n  The threshold sits where predicted, just below 1.0x the signal peak.')
    print('  An impulse smaller than the signal cannot blank a polarity and costs')
    print('  nothing; one larger than it costs the whole ring.')

    print('\n  Hysteresis moves that threshold the WRONG way (A > 1-h), fixed')
    print('  amplitude 0.9, rate 200/s -- so the impulse-optimal comparator is')
    print('  a tight one, which is the opposite of what Gaussian noise wants:\n')
    print(f'  {"hysteresis":>10s} {"threshold":>10s} {"bits lost":>26s}')
    for h in (0.02, 0.05, 0.10, 0.20):
        d = []
        for sd_i in (1, 2):
            w = wave(imp=200.0, amp=(0.9, 0.9), hyst=h, seed=sd_i)
            b = decode(w); d.append(len(ln) - len(b))
            del w, b; gc.collect()
        print(f'  {h:10.2f} {1.0 - h:10.2f} {str(d):>26s}', flush=True)

    # -------------------------------------------------- what it costs audio
    print('\n\nLINK QUALITY -- recovered voice through the full chain, 1.0 s clip')
    print('  segSNR of channel 1 against the SAME codec with no link in the path,')
    print('  so the figure is what the carrier adds (seven-channel.md 4).')
    print('  Receiver is the spec.md 7 framer on the 16-bit frame -- a properly')
    print('  built one -- so this isolates the LINE CODE, not mfspec\'s missing')
    print('  loss-of-frame counter.\n')

    n32 = nf // 2
    p32 = run.params(32000)
    ref32 = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, 32000)[:n32]
    sp32 = cvsd.encode(ref32, p32)
    C7 = np.array([np.roll(sp32, 977 * j) for j in range(7)])
    A7 = np.ones((7, n32), np.uint8)
    ln7 = fr.gbuild(C7, A7, fr.SCHEMES['S4 T=1110 period 4'])
    alone = run.score(ref32, cvsd.decode(sp32, p32), 32000)[0]
    print(f'  CVSD alone, no link, whole clip: {alone:.2f} dB segSNR.')
    print('  "vs codec" below compares against the codec over the SAME window,')
    print('  so it is the carrier\'s contribution and not which speech landed in')
    print('  the stretch.  A stretch under 200 ms is reported as too short.\n')

    def wave7(imp=0.0, amp=(0.5, 3.0), hp=0.0, seed=1):
        rng = np.random.default_rng(seed)
        x = np.repeat(fast.dm_encode(ln7).astype(np.float64) * 2 - 1, OSB // 2)
        x = _lp(x, 1.8e6, FS, 1); x /= np.abs(x).max()
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=amp, seed=seed + 7)
        if hp:
            b, a = signal.butter(1, min(0.99, 2 * hp / FS), btype='high')
            x = signal.lfilter(b, a, x)
        s = fast.slice_hyst(_lp(x, 2 * LINE_RATE, FS, 2), 0.05)
        del x; gc.collect()
        b = fast.mono_decode(s, OSB, thr=0.75, dead=0.25)
        del s; gc.collect()
        return b

    def audio_cost(imp, hp=0.0, seed=1):
        """Scored on the LONGEST unbroken locked stretch.

        A slip deletes bits, so the recovered audio's time base shifts at every
        reframe.  Scoring the whole clip against one alignment then reports a
        collapse that is mostly bookkeeping -- the same artefact as 8.1's raw
        BER.  What a listener actually gets is clean audio between disruptions,
        so that is what is measured, alongside how often the disruptions come.
        """
        rb = wave7(imp=imp, hp=hp, seed=seed)
        st = s4_simple.framer_single(rb, 7)
        pos = st['pos']
        if len(pos) < 200:
            del rb; gc.collect()
            return None, None, st['lof_events'], 100.0, 0.0
        down = 100.0 * (1.0 - len(pos) / n32)
        brk = np.flatnonzero(np.diff(pos) != 16) + 1
        segs = [g for g in np.split(pos, brk) if len(g) > 400]
        if not segs:
            del rb; gc.collect()
            return None, None, st['lof_events'], down, 0.0
        g = max(segs, key=len)
        got = rb[g[:len(g) - 2] + 1]              # channel 1 C bits
        i0 = int(g[0]) // 16
        longest = len(g) / 32000.0
        del rb; gc.collect()
        if longest < 0.20:                        # too little audio to score
            return None, None, st['lof_events'], down, longest
        r = ref32[i0:i0 + len(got)]
        seg = run.score(r, cvsd.decode(got, p32), 32000)[0]
        # the control must be the SAME audio over the SAME window, or the
        # delta measures which speech landed in the stretch, not the carrier
        base = run.score(r, cvsd.decode(sp32[i0:i0 + len(got)], p32), 32000)[0]
        return seg, seg - base, st['lof_events'], down, longest

    print(f'  {"impulse/s":>10s} {"segSNR":>8s} {"vs codec":>9s} {"breaks/s":>9s} '
          f'{"down %":>8s} {"longest clean":>14s}')
    for imp in (0.0, 1.0, 10.0, 100.0, 1000.0):
        seg, d, lof, down, lg = audio_cost(imp)
        if seg is None:
            lbl = 'no lock' if lg == 0.0 else 'too short'
            print(f'  {imp:10.0f} {lbl:>8s} {"-":>9s} {lof / secs:>9.0f} '
                  f'{down:>7.2f}% {1000 * lg:>11.0f} ms')
        else:
            print(f'  {imp:10.0f} {seg:8.2f} {d:+9.2f} {lof / secs:>9.0f} '
                  f'{down:>7.2f}% {1000 * lg:>11.0f} ms', flush=True)
    print('\n  Impulse noise costs BOTH continuity and fidelity, and the cliff is')
    print('  between 1 and 10 events/s:')
    print('    1/s     carrier exactly transparent, +0.00 dB, no breaks')
    print('    10/s    5 reframes/s AND -2.35 dB within the unbroken stretches --')
    print('            impulses that never unseat the framer still corrupt bits')
    print('    100/s   longest unbroken stretch 71 ms; no usable audio')
    print('    1000/s  the framer never locks at all')
    print('  Each reframe is a mute (spec.md 10), so the audible result at 10/s is')
    print('  five dropouts a second over speech that is already 2.3 dB degraded.')

    # ------------------------------------------------ the transformer caveat
    print('\n\nTHE TRANSFORMER -- the model above has none, and that matters')
    print('  The line is transformer coupled (spec.md 5).  The rings are 15-80 kHz')
    print('  against a 512 kHz symbol rate, so AC coupling should reject much of')
    print('  each one.  Same runs with a first-order high pass ahead of the slicer:\n')
    print('  The lowest signal fundamental is 256 kHz (an all-ones payload), so a')
    print('  corner well above the 15-80 kHz rings is available.\n')
    print(f'  {"HP corner":>10s} {"impulse/s":>10s} {"breaks/s":>9s} {"down %":>8s}')
    for hp in (0.0, 30e3, 60e3, 120e3, 200e3):
        for imp in (100.0, 1000.0):
            seg, d, lof, down, lg = audio_cost(imp, hp=hp)
            lbl = 'none' if hp == 0 else f'{hp / 1e3:.0f} kHz'
            print(f'  {lbl:>10s} {imp:10.0f} {lof / secs:>9.0f} {down:>7.2f}%', flush=True)

    # ------------------------------------------------------- dead time
    print('\n\nMITIGATION -- the dead time is already in the receiver')
    print('  spec.md 6.1 ignores transitions within 0.2 cell of the last accepted')
    print('  one; rx_review.py measures 0.05-0.30 usable.  Bits lost at 200/s,')
    print('  amplitude 1.5, 2 seeds:\n')
    print(f'  {"dead":>8s} {"bits lost":>20s}')
    for dead in (0.05, 0.15, 0.25, 0.35, 0.45):
        d = []
        for sd_i in (1, 2):
            w = wave(imp=200.0, amp=(1.5, 1.5), seed=sd_i)
            b = decode(w, dead=dead); d.append(len(ln) - len(b))
            del w, b; gc.collect()
        print(f'  {dead:8.2f} {str(d):>20s}', flush=True)
    print('\n  Dead time rejects edges that arrive too EARLY.  A stuck comparator')
    print('  removes edges instead, so there is nothing for it to reject: it is')
    print('  the wrong tool for this failure and does not help.')


def impulse_ami():
    """Section 10's test, run again with AMI.

    Prediction to check: AMI decides |x| > 0.5*peak, so an offset of 0.5 either
    fakes a mark on a zero slot or cancels a real one -- HALF the 1-h offset
    that sticks the biphase comparator.  If that holds, AMI is MORE susceptible
    per impulse in raw error terms, and 8.1's advantage is not immunity but
    that its errors are bit ERRORS rather than bit-count slips.
    """
    OSB = 32; FS = LINE_RATE * OSB
    secs = 1.0
    nf = int(secs * RATE)
    p = run.params(RATE)
    src, fs = audio.read_wav('speech30.wav', seconds=secs + 0.5)
    ref = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)[:nf]
    sp = cvsd.encode(ref, p)
    C = [np.roll(sp, 977 * j) for j in range(NCH)]
    A = [np.full(nf, (0, 0, 0, 1, 0, 0)[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)

    def a_wave(line, imp=0.0, amp=(0.5, 3.0), hp=0.0, seed=1):
        x = np.repeat(fast.ami_encode(line), OSB)
        x = _lp(x, 1.8e6, FS, 1); x /= np.abs(x).max()
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=amp, seed=seed + 7)
        if hp:
            b, a = signal.butter(1, min(0.99, 2 * hp / FS), btype='high')
            x = signal.lfilter(b, a, x)
        return _lp(x, LINE_RATE, FS, 2)

    def a_dec(x, thresh=0.5, fixed_peak=False):
        peak = 1.0 if fixed_peak else None
        return fast.ami_decode(x, OSB, thresh=thresh, peak=peak)

    print('IMPULSE SUSCEPTIBILITY -- AMI, the same test as 10')
    print('  AMI decides |x| > thresh*peak.  An offset of ~0.5 either fakes a mark')
    print('  on a zero slot or cancels a real one, against the 1-h = 0.95 that')
    print('  sticks the biphase comparator -- so AMI should start erring at HALF')
    print('  the impulse amplitude.  What differs is the KIND of error.\n')
    print('  Fixed rate 200/s, 4 seeds.  "bits lost" is emitted minus sent (a')
    print('  count slip); "BER" is ordinary bit errors at preserved count.\n')
    print(f'  {"amplitude":>10s} {"bits lost":>18s} {"raw BER":>10s}   biphase bits lost')
    bip = {0.2: '1, 1, 1, 1', 0.5: '1, 2, 1, 1', 0.8: '9, 16, 13, 2',
           0.95: '31, 39, 50, 25', 1.1: '250, 278, 301, 206',
           1.5: '1665, 1820, 1966, 1423', 3.0: '6413, 7050, 7657, 5694'}
    for a in (0.2, 0.5, 0.8, 0.95, 1.1, 1.5, 3.0):
        d = []; e = []
        for sd_i in (1, 2, 3, 4):
            x = a_wave(ln, imp=200.0, amp=(a, a), seed=sd_i)
            b = a_dec(x); d.append(len(ln) - len(b)); e.append(_raw_ber(b, ln))
            del x, b; gc.collect()
        print(f'  {a:10.2f} {str(d):>18s} {np.mean(e):10.1e}   {bip[a]}', flush=True)

    print('\n  A prediction that did NOT survive: ami_decode sets its threshold')
    print('  from the 99th percentile of |x|, so the impulses should inflate it')
    print('  and push real marks under.  Pinning the threshold to the nominal')
    print('  signal peak instead makes no difference -- the AGC is not the problem:\n')
    print(f'  {"amplitude":>10s} {"BER, self-AGC":>14s} {"BER, fixed peak":>16s}')
    for a in (0.5, 0.95, 1.5, 3.0):
        e1 = []; e2 = []
        for sd_i in (1, 2):
            x = a_wave(ln, imp=200.0, amp=(a, a), seed=sd_i)
            e1.append(_raw_ber(a_dec(x), ln))
            e2.append(_raw_ber(a_dec(x, fixed_peak=True), ln))
            del x; gc.collect()
        print(f'  {a:10.2f} {np.mean(e1):14.1e} {np.mean(e2):16.1e}', flush=True)

    # -------------------------------------------------- what it costs audio
    print('\n\nLINK QUALITY -- AMI, same chain, same 1.0 s clip, same framer')
    n32 = nf // 2
    p32 = run.params(32000)
    ref32 = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, 32000)[:n32]
    sp32 = cvsd.encode(ref32, p32)
    C7 = np.array([np.roll(sp32, 977 * j) for j in range(7)])
    A7 = np.ones((7, n32), np.uint8)
    ln7 = fr.gbuild(C7, A7, fr.SCHEMES['S4 T=1110 period 4'])
    alone = run.score(ref32, cvsd.decode(sp32, p32), 32000)[0]
    print(f'  CVSD alone, no link, whole clip: {alone:.2f} dB segSNR\n')

    def cost(imp, hp=0.0, seed=1):
        x = a_wave(ln7, imp=imp, hp=hp, seed=seed)
        rb = a_dec(x); del x; gc.collect()
        st = s4_simple.framer_single(rb, 7)
        pos = st['pos']
        if len(pos) < 200:
            del rb; gc.collect()
            return None, None, st['lof_events'], 100.0, 0.0
        down = 100.0 * (1.0 - len(pos) / n32)
        brk = np.flatnonzero(np.diff(pos) != 16) + 1
        segs = [g for g in np.split(pos, brk) if len(g) > 400]
        if not segs:
            del rb; gc.collect()
            return None, None, st['lof_events'], down, 0.0
        g = max(segs, key=len)
        got = rb[g[:len(g) - 2] + 1]
        i0 = int(g[0]) // 16
        longest = len(g) / 32000.0
        del rb; gc.collect()
        if longest < 0.20:
            return None, None, st['lof_events'], down, longest
        r = ref32[i0:i0 + len(got)]
        seg = run.score(r, cvsd.decode(got, p32), 32000)[0]
        base = run.score(r, cvsd.decode(sp32[i0:i0 + len(got)], p32), 32000)[0]
        return seg, seg - base, st['lof_events'], down, longest

    print(f'  {"impulse/s":>10s} {"segSNR":>9s} {"vs codec":>9s} {"breaks/s":>9s} '
          f'{"down %":>8s} {"longest clean":>14s}   biphase')
    bipa = {0.0: '+0.00 dB, 0 breaks', 1.0: '+0.00 dB, 0 breaks',
            10.0: '-2.35 dB, 5 breaks/s', 100.0: 'too short, 65 breaks/s',
            1000.0: 'never locks'}
    for imp in (0.0, 1.0, 10.0, 100.0, 1000.0):
        seg, d, lof, down, lg = cost(imp)
        if seg is None:
            lbl = 'no lock' if lg == 0.0 else 'too short'
            bk = '-' if lg == 0.0 else f'{lof / secs:.0f}'
            print(f'  {imp:10.0f} {lbl:>9s} {"-":>9s} {bk:>9s} '
                  f'{down:>7.2f}% {1000 * lg:>11.0f} ms   {bipa[imp]}', flush=True)
        else:
            print(f'  {imp:10.0f} {seg:9.2f} {d:+9.2f} {lof / secs:>9.0f} '
                  f'{down:>7.2f}% {1000 * lg:>11.0f} ms   {bipa[imp]}', flush=True)

    print('\n\nMITIGATIONS -- AMI')
    print('  Transformer (AC coupling), the same sweep as 10.3:\n')
    print(f'  {"HP corner":>10s} {"impulse/s":>10s} {"breaks/s":>9s} {"down %":>8s}')
    for hp in (0.0, 60e3, 120e3):
        for imp in (100.0, 1000.0):
            seg, d, lof, down, lg = cost(imp, hp=hp)
            lbl = 'none' if hp == 0 else f'{hp / 1e3:.0f} kHz'
            print(f'  {lbl:>10s} {imp:10.0f} {lof / secs:>9.0f} {down:>7.2f}%', flush=True)
    print('\n  Decision threshold, the AMI knob with no biphase equivalent')
    print('  (100 events/s, 2 seeds):\n')
    print(f'  {"thresh":>8s} {"breaks/s":>9s} {"raw BER":>10s}')
    for th in (0.3, 0.4, 0.5, 0.6, 0.7):
        lf = []; eb = []
        for sd_i in (1, 2):
            x = a_wave(ln7, imp=100.0, seed=sd_i)
            rb = a_dec(x, thresh=th); del x; gc.collect()
            lf.append(s4_simple.framer_single(rb, 7)['lof_events'])
            eb.append(_raw_ber(rb, ln7)); del rb; gc.collect()
        print(f'  {th:8.2f} {np.mean(lf) / secs:>9.0f} {np.mean(eb):10.1e}', flush=True)


def polarity():
    """Is AMI polarity-neutral the way differential Manchester is?

    spec.md 5 claims biphase is polarity-blind and "verified bit-identical":
    the decision is same-vs-different half cells, and inverting the line
    inverts both halves.

    AMI should be blind for a different reason -- it decides |x| > thresh, so
    the sign never enters.  Two distinct tests, because they answer different
    questions and conflating them is easy:

      exact     invert the COMPLETE received waveform, impairments included.
                That is what swapping tip and ring does: everything arriving
                differentially on the pair flips together.  The requirement is
                bit-identical output.
      ensemble  invert the signal only, with receiver-referred noise added
                afterwards.  Then the two runs are different experiments and
                individual errors will differ; what must match is the BER
                over seeds.
    """
    OSB = 32; FS = LINE_RATE * OSB
    nf = 8000
    rng = np.random.default_rng(31)
    C = [(rng.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)]
    A = [np.full(nf, (0, 0, 0, 1, 0, 0)[j], np.uint8) for j in range(NCH)]
    ln = build(C, A)

    def chain(line, code, inv_sig=False, inv_all=False, sd=0.0, imp=0.0,
              atten=1.0, seed=1):
        if code == 'biphase':
            x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OSB // 2)
        else:
            x = np.repeat(fast.ami_encode(line), OSB)
        x = _lp(x, 1.8e6, FS, 1); x /= np.abs(x).max()
        if atten != 1.0:
            x *= atten
        if inv_sig:
            x = -x
        r = np.random.default_rng(seed)
        if sd:
            x += r.normal(0, sd, len(x))
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
        if inv_all:                              # tip/ring swap at the receiver
            x = -x
        if code == 'biphase':
            w = fast.slice_hyst(_lp(x, 2 * LINE_RATE, FS, 2), 0.05)
            del x; gc.collect()
            b = fast.mono_decode(w, OSB, thr=0.75, dead=0.25)
            del w; gc.collect()
            return b
        x = _lp(x, LINE_RATE, FS, 2)
        b = fast.ami_decode(x, OSB, thresh=0.5)
        del x; gc.collect()
        return b

    cases = [('clean', dict()),
             ('noise sd 0.4', dict(sd=0.4)),
             ('noise sd 0.6', dict(sd=0.6)),
             ('impulse 100/s', dict(imp=100.0)),
             ('attenuated 0.25x', dict(atten=0.25, sd=0.10))]

    print('POLARITY -- is AMI blind to a tip/ring swap, as biphase is?\n')
    print('  EXACT TEST: the complete received waveform is inverted, impairments')
    print('  included, which is what swapping the two conductors actually does.\n')
    print(f'  {"condition":22s} {"code":8s} {"identical":>10s} {"bits differing":>15s}')
    allsame = True
    for nm, kw in cases:
        for cn in ('biphase', 'ami'):
            a = chain(ln, cn, **kw)
            b = chain(ln, cn, inv_all=True, **kw)
            n = min(len(a), len(b))
            same = (len(a) == len(b)) and bool((a[:n] == b[:n]).all())
            diff = int((a[:n] != b[:n]).sum()) + abs(len(a) - len(b))
            allsame &= same
            print(f'  {nm:22s} {cn:8s} {("YES" if same else "no"):>10s} {diff:>15d}',
                  flush=True)
    print(f'\n  All conditions bit-identical: {allsame}.')
    print('  Both codes are exactly polarity-blind, including while the link is')
    print('  making errors -- the errors themselves are the same errors.\n')

    print('  ENSEMBLE TEST: signal inverted, receiver-referred noise added after,')
    print('  so the two runs are genuinely different experiments.  Individual')
    print('  errors MUST differ; the error RATE must not.  Mean BER over 6 seeds:\n')
    print(f'  {"condition":22s} {"code":8s} {"normal":>10s} {"inverted":>10s}')
    for nm, kw in cases[1:]:
        for cn in ('biphase', 'ami'):
            e0 = []; e1 = []
            for sd_i in range(1, 7):
                e0.append(_raw_ber(chain(ln, cn, seed=sd_i, **kw), ln))
                e1.append(_raw_ber(chain(ln, cn, inv_sig=True, seed=sd_i, **kw), ln))
            print(f'  {nm:22s} {cn:8s} {np.mean(e0):10.1e} {np.mean(e1):10.1e}',
                  flush=True)
    print('\n  The rates match; only which bits happened to break differs.  An')
    print('  earlier version of this test compared those two columns bit for bit')
    print('  and appeared to show AMI failing -- it was comparing two different')
    print('  noise experiments, not two polarities.')

    print('\n  END TO END, 16-bit frame, spec.md 7 framer, clean line:\n')
    n32 = nf // 2
    r3 = np.random.default_rng(32)
    C7 = np.array([(r3.random(n32) < 0.5).astype(np.uint8) for _ in range(7)])
    A7 = np.ones((7, n32), np.uint8)
    ln7 = fr.gbuild(C7, A7, fr.SCHEMES['S4 T=1110 period 4'])
    print(f'  {"code":8s} {"polarity":>10s} {"locks":>6s} {"lanes":>6s} {"LOF":>5s}')
    for cn in ('biphase', 'ami'):
        for inv in (False, True):
            rb = chain(ln7, cn, inv_all=inv)
            st = s4_simple.framer_single(rb, 7)
            rot, be = _lane_check(rb, st['pos'], C7, nch=7, off=1, stride=2)
            ok = st['lock_bit'] is not None and not rot and be == 0.0
            print(f'  {cn:8s} {("swapped" if inv else "normal"):>10s} '
                  f'{("yes" if st["lock_bit"] is not None else "NO"):>6s} '
                  f'{("ok" if ok else "NO"):>6s} {st["lof_events"]:>5d}', flush=True)
            del rb; gc.collect()

    print('\n  Why AMI is blind, and why it costs nothing:')
    print('    The decision is |x| > thresh*peak, so the sign never enters')
    print('    (phy.ami_decode; c_ami_decode uses fabs).')
    print('    A full-wave front end is not an extra part bolted on for this --')
    print('    AMI NEEDS one anyway, because marks arrive as both + and - pulses')
    print('    and a half-wave receiver would miss every other one.  Polarity')
    print('    neutrality comes free with the receiver you must build regardless.')
    print('    The alternation rule is symmetric too: inverting +,-,+,- gives')
    print('    -,+,-,+, still valid, and a bipolar violation stays a violation')
    print('    under either polarity, so even BPV error detection survives.')
    print('  Biphase is blind for a different reason: the decision is same-vs-')
    print('  different half cells and inversion flips both (spec.md 5).')


def rxclock():
    """Does an AMI receiver need a local clock?

    Three architectures, measured:
      A  none at all -- quantise the gap between marks, the way the monostable
         quantises a half-cell against a full cell for biphase
      B  a tank flywheeled off the line (9.2)
      C  the local 4.096 MHz crystal plus an oversampling DPLL (9.3)
    """
    OSB = 32; FS = LINE_RATE * OSB
    nf = 6000
    A0 = [np.zeros(nf, np.uint8) for _ in range(NCH)]
    rg = np.random.default_rng(4)
    lnr = build([(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)], A0)
    ln0 = build([np.zeros(nf, np.uint8)] * NCH, A0)      # 15-zero gaps

    def a_wave(line, sd=0.0, seed=1):
        x = np.repeat(fast.ami_encode(line), OSB)
        x = _lp(x, 1.8e6, FS, 1); x /= np.abs(x).max()
        if sd:
            x += np.random.default_rng(seed).normal(0, sd, len(x))
        return _lp(x, LINE_RATE, FS, 2)

    def clockless(x, tol=0.0, thresh=0.5):
        """No frequency reference: time the gap between marks with an RC whose
        period is off by `tol`, round to whole bit periods."""
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
        # the decoded stream starts at the FIRST MARK, so slide ln, not b
        best = 1.0
        for o in range(0, 80):
            n = min(len(b), len(ln) - o)
            if n < 500:
                break
            best = min(best, float((b[:n] != ln[o:o + n]).mean()))
            if best == 0.0:
                break
        return best

    print('WHY AMI NEEDS A TIME REFERENCE AND BIPHASE DOES NOT')
    print('  It is the DYNAMIC RANGE of the timing measurement, not the presence')
    print('  of timing information:\n')
    print('    biphase  intervals are 0.5 or 1.0 cell   -> 2:1, and spec.md 6.2')
    print('             measures +/-13% tolerance as sufficient')
    print('    AMI      gaps run 1 to 16 bit periods    -> 16:1, and a gap of k')
    print('             mis-rounds once tol*k > 0.5, so 16 needs tol < 3.1%')
    print('  Same information, four times the precision, purely because the frame')
    print('  lets zeros run 15 long (9.1).\n')

    print('OPTION A -- no clock at all: quantise the gap between marks\n')
    print(f'  {"RC tol":>7s} {"random BER":>11s} {"count":>7s} | {"const 0 BER":>12s} {"count":>8s}')
    for tol in (0.0, 0.005, 0.01, 0.02, 0.03, 0.05, 0.10):
        r = []
        for ln in (lnr, ln0):
            x = a_wave(ln)
            b = clockless(x, tol=tol)
            r.append((ber_mark(b, ln), len(b) - len(ln)))
            del x, b; gc.collect()
        print(f'  {tol * 100:6.1f}% {r[0][0]:11.1e} {r[0][1]:7d} | '
              f'{r[1][0]:12.1e} {r[1][1]:8d}', flush=True)
    print('\n  ("count" is emitted minus sent; the -8 / -15 at small tol is the')
    print('  stream starting at the first mark and ending at the last, not slips.)')
    print('\n  Error-free to 2%, broken at 3% -- the 3.1% predicted above.')
    print('  spec.md 6.2: a 1% resistor and a 2% C0G capacitor give +/-3%.')
    print('  So a clockless AMI receiver lands exactly ON its failure point with')
    print('  no margin for temperature or ageing, where the same components give')
    print('  biphase +/-13% against a +/-3% need -- four times the margin it needs.')
    print('\n  And look at what it does when it fails: at 3% the constant-0 case')
    print('  loses 765 bits.  A mis-rounded gap emits the wrong NUMBER of zeros,')
    print('  so the failures are SLIPS.  A clockless receiver would hand back the')
    print('  one property that made AMI worth considering (11.1: bit count exactly')
    print('  preserved under every impulse tested).  It is not a real option.')

    # ------------------------------------------------- does a local clock slip?
    print('\n\nOPTION C -- local crystal: does it reintroduce slips?')
    print('  spec.md 1 rests on "no rate mismatch anywhere and slips are')
    print('  structurally impossible", so this is the question that matters.')
    print('  The crystal is a SAMPLING reference; the DPLL recovers bit phase')
    print('  from the line, so the bit clock stays locked to the far transmitter.')
    print('  If that is right, the decoder emits exactly as many bits as were')
    print('  sent however far the two crystals drift apart.\n')

    def dpll(line, ppm=0.0, sub=4, sd=0.0, seed=1):
        x = a_wave(line, sd=sd, seed=seed)
        step = sub * (1.0 + ppm * 1e-6)
        idx = np.round(np.arange(0, len(x) - 1, step)).astype(np.int64)
        b = fast.ami_decode(x[idx], OSB // sub, thresh=0.5)
        del x; gc.collect()
        return b

    print(f'  {"crystal offset":>15s} {"drift over the clip":>20s} '
          f'{"bits emitted - sent":>21s} {"BER":>9s}')
    for ppm in (0, 100, 200, 1000, 5000):
        b = dpll(ln0, ppm=ppm)
        drift = ppm * 1e-6 * len(ln0)
        print(f'  {ppm:12d} ppm {drift:17.1f} bits {len(b) - len(ln0):21d} '
              f'{_raw_ber(b, ln0):9.1e}', flush=True)
        del b; gc.collect()
    print('\n  The bit count is exact at every offset, including 5000 ppm where')
    print('  the two clocks drift by 240 bits across the clip.  The DPLL absorbs')
    print('  the drift as phase, not as bits, so spec.md 1 survives: a local')
    print('  crystal used as a SAMPLING reference does not cause slips.  Only a')
    print('  free-running local clock used as the DATA clock would.')

    print('\n\nSUMMARY -- what an AMI receiver needs')
    print(f'  {"option":34s} {"reference":22s} {"verdict"}')
    rows = [('A  quantise mark-to-mark gaps', 'one RC, no crystal',
             'needs <3.1%, RC gives 3% -- and fails by slipping'),
            ('B  tank flywheeled off the line', 'resonator per rate',
             'needs Q~100 AND +/-0.25% (9.2): ceramic, not LC'),
            ('C  local crystal + DPLL', '4.096 MHz, already specified',
             'works to 5000 ppm, no slips, every rate an exact divide')]
    for a, b, c in rows:
        print(f'  {a:34s} {b:22s} {c}')
    print('\n  So: yes, the receiver needs a frequency reference, and C is the one')
    print('  that works.  What it costs is not a part -- the crystal is already')
    print('  on the board -- but the ARCHITECTURAL property spec.md 6.1 opens')
    print('  with: "No PLL, no oversampling, no clock on the receive timing path".')
    print('\n  It is NOT a loss of rate-blindness: the receiver already carries a')
    print('  per-rate plug (spec.md 2.2, line-receiver.md 8) for the input filter,')
    print('  classifier, dead time and carrier detect.  On that axis C is better --')
    print('  the per-rate change becomes a counter tap, exact and digital, instead')
    print('  of matched RC values, and 4.096 MHz divides every rate exactly.')
    print('  Repeaters are unaffected either way: they slice and re-drive and')
    print('  never see the frame (spec.md 2.2).')


def codes():
    """Every line code that could plausibly carry this frame, side by side.

    Only differential Manchester and AMI have been through the full chain
    (6, 8, 10-13).  This measures the STRUCTURAL properties of the rest on the
    same frame, which is enough to decide whether any of them is worth
    simulating: a code that cannot cross a transformer is not a candidate
    whatever its noise performance.
    """
    def manchester(b):       # biphase-L: 1 -> hi,lo   0 -> lo,hi.  LEVEL carries data
        o = np.empty(2 * len(b)); o[0::2] = np.where(b == 1, 1, -1)
        o[1::2] = np.where(b == 1, -1, 1); return o

    def diffman(b):          # biphase-S == differential Manchester, spec.md 5
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

    def nrzi(b):             # level flips on a 1
        v = np.where(np.cumsum(b) % 2 == 1, 1.0, -1.0)
        o = np.empty(2 * len(b)); o[0::2] = v; o[1::2] = v; return o

    def cmi(b):              # 0 -> lo,hi ; 1 -> full cell, alternating polarity
        o = np.empty(2 * len(b)); pol = 1.0
        for i, bit in enumerate(b):
            if bit == 0:
                o[2 * i], o[2 * i + 1] = -1.0, 1.0
            else:
                o[2 * i] = o[2 * i + 1] = pol; pol = -pol
        return o

    def miller(b):           # delay modulation
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

    CODES = [('Manchester (biphase-L)', manchester), ('differential Manchester', diffman),
             ('AMI', ami_c), ('unipolar NRZ', uni_nrz), ('unipolar RZ', uni_rz),
             ('polar NRZ', polar_nrz), ('NRZI', nrzi), ('CMI', cmi), ('Miller', miller)]

    def props(w):
        """w at 2 samples/bit.  Intervals and disparity in BIT periods."""
        lv = len(np.unique(np.round(w, 6)))
        tr = np.flatnonzero(np.diff(w) != 0)
        if len(tr) < 3:
            mn = mx = float('inf')
        else:
            d = np.diff(tr) / 2.0; mn = d.min(); mx = d.max()
        disp = np.cumsum(w) / 2.0
        return lv, mn, mx, w.mean(), float(disp.max() - disp.min())

    nf = 4000
    A = [np.zeros(nf, np.uint8) for _ in range(NCH)]
    rg = np.random.default_rng(7)
    pay = {'random': [(rg.random(nf) < 0.5).astype(np.uint8) for _ in range(NCH)],
           'constant 0': [np.zeros(nf, np.uint8)] * NCH,
           'constant 1': [np.ones(nf, np.uint8)] * NCH}

    print('LINE CODES ON THE mfspec FRAME -- structural properties, measured')
    print('  Intervals and disparity in BIT periods.  min interval sets the max')
    print('  fundamental; max interval sets what clock recovery must coast; the')
    print('  disparity swing is the DC wander a transformer has to pass.\n')
    for pn, C in pay.items():
        ln = build(C, A)
        print(f'  --- payload: {pn}  (line ones density {ln.mean():.3f})')
        print(f'  {"code":26s} {"levels":>6s} {"min int":>8s} {"max int":>8s} '
              f'{"mean DC":>9s} {"disparity":>10s}')
        for nm, fn in CODES:
            lv, mn, mx, dc, ds = props(fn(ln))
            print(f'  {nm:26s} {lv:6d} {mn:8.2f} {mx:8.2f} {dc:+9.3f} {ds:10.1f}')
        print()

    print('  READING IT.  The disparity column decides the candidate set, because')
    print('  the pair is transformer coupled (spec.md 5) and a transformer cannot')
    print('  pass unbounded DC wander:')
    print('    bounded, order 1 bit period : Manchester, differential Manchester,')
    print('                                  AMI, CMI  -> viable')
    print('    data-dependent, 5-500 bits  : Miller, NRZI              -> not viable')
    print('    100s to 10000s of bits      : unipolar NRZ/RZ, polar NRZ -> not viable')
    print('\n  That is the whole answer to "is there anything we skipped".  The two')
    print('  skipped codes with a REAL advantage are Miller and NRZI: both halve')
    print('  the bandwidth (min interval 1.0 bit against the biphase family\'s 0.5),')
    print('  and Miller also bounds its max interval at 2.0 bits, which would make')
    print('  clock recovery nearly as easy as biphase.  Both fail on DC: Miller')
    print('  swings 96 bit periods on random payload and 502 on constant 0, NRZI')
    print('  186 and 30.  Miller-squared exists precisely to patch this, at the')
    print('  cost of encoder state.  Neither is worth simulating as it stands.')
    print('\n  CMI is the interesting near-miss: two levels, DC-free, disparity 1.5,')
    print('  max interval 1.5 bits.  It matches differential Manchester on every')
    print('  axis and beats it on none -- same 0.5-bit min interval, so the same')
    print('  bandwidth and the same reach.  No reason to prefer it.')
    print('\n  Manchester (biphase-L) is structurally identical to differential')
    print('  Manchester in this table.  It differs in ONE respect the table cannot')
    print('  show: it carries data in the DIRECTION of the mid-cell transition, so')
    print('  inverting the pair swaps ones and zeros.  It is not polarity-blind,')
    print('  and 12 measured that differential Manchester is -- for free.  That is')
    print('  the entire reason to prefer the differential form.')


def framerate():
    """What should the frame rate be?

    In this frame the frame rate IS the per-channel rate, and the line rate is
    8x it.  So one knob sets audio quality, capacity AND reach at once -- which
    is why it looks like a hard choice.  It is less hard than it looks, because
    frame LENGTH is a second knob that trades against it at constant reach.
    """
    OSB = 32
    RATES = (16000, 32000, 64000)

    # ---------------------------------------------------------- the family
    print('THE FAMILY.  F + S + N channels must be a power of two, so N = 2, 6, 14')
    print('  (the 16-bit frame\'s 2+2N rule gave N = 1, 3, 7; this frame gives more')
    print('  channels per bit because signalling is sub-commutated, 2).\n')
    print(f'  {"frame":>6s} {"N":>3s} {"per-ch":>7s} {"line":>7s} {"baud":>9s} '
          f'{"capacity":>9s} {"reach":>6s} {"superframe":>11s}')
    for N in (2, 6, 14):
        flen = 2 + N
        sf = 4 if N == 2 else (8 if N == 6 else 16)
        for r in RATES:
            line = flen * r
            reach = (256000.0 / line) ** 0.5
            print(f'  {flen:5d}b {N:3d} {r // 1000:6d}k {line // 1000:6d}k '
                  f'{2 * line / 1e6:8.3f}M {N * r // 1000:8d}k {reach:5.2f}x '
                  f'{sf:8d} fr')
        print()
    print('  reach is the sqrt(f) law scaled to the 256 kbps reference, as')
    print('  spec.md 2.1 does -- ratios sound, absolutes not measured.\n')
    print('  Read it by ROW for "what does 64 kHz cost me", but read it by')
    print('  COLUMN for the choice that actually matters.  At one line rate --')
    print('  one reach -- the frame length decides how it is divided:\n')
    print('    256 kbps, 1.00x reach (order 1.7 km):')
    print('       4-bit frame @ 64 kHz ->  2 channels x 64 kbps   (DS0 rate)')
    print('       8-bit frame @ 32 kHz ->  6 channels x 32 kbps')
    print('      16-bit frame @ 16 kHz -> 14 channels x 16 kbps')
    print('    512 kbps, 0.71x reach (order 1.2 km):')
    print('       8-bit frame @ 64 kHz ->  6 channels x 64 kbps   (DS0 rate)')
    print('      16-bit frame @ 32 kHz -> 14 channels x 32 kbps')
    print('\n  So "64 kHz or 32 kHz" is not the question.  Pick the reach the')
    print('  plant needs, then pick how to divide it.  64 kbps channels are')
    print('  available at ANY reach -- at 2 channels for 1.7 km, 6 for 1.2 km.')

    # -------------------------------------------------------- audio quality
    print('\n\nWHAT THE PER-CHANNEL RATE COSTS THE AUDIO')
    secs = 2.0
    src, fs = audio.read_wav('speech30.wav', seconds=secs + 0.5)
    print(f'  CVSD alone, {secs:.0f} s clip, one talker:\n')
    got = {}
    for r in RATES:
        p = run.params(r)
        ref = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, r)[:int(secs * r)]
        got[r] = run.score(ref, cvsd.decode(cvsd.encode(ref, p), p), r)[0]
    print(f'  {"per-channel":>12s} {"segSNR":>9s} {"vs 64 kbps":>11s}')
    for r in RATES:
        print(f'  {r // 1000:10d}k {got[r]:6.2f} dB {got[r] - got[64000]:+8.2f} dB')
    print('\n  (spec.md 2.1 on seven talkers: 10.8 dB at 16k, 17.4 at 32k,')
    print('  23.3 at 64k, worst talker 9.0 / 14.9 / 19.7.  Specify against the')
    print('  worst talker: 16 kbps voice is intelligible but visibly degraded,')
    print('  32 kbps is the quality knee, 64 kbps is comfortable.)')

    # ------------------------------------------- reach vs robustness, measured
    print('\n\nREACH IS NOT FREE EITHER -- the same span at three line rates')
    print('  Attenuation goes as sqrt(f), so a fixed physical span costs each')
    print('  rate a different loss.  Referenced to 12 dB at 256 kbps:\n')
    L0 = 12.0
    print(f'  {"line":>7s} {"loss":>7s} {"amplitude":>10s} {"hysteresis % of rx":>19s}')
    plan = []
    for line in (128000, 256000, 512000):
        dB = L0 * (line / 256000.0) ** 0.5
        amp = 10 ** (-dB / 20.0)
        plan.append((line, amp))
        print(f'  {line // 1000:6d}k {dB:6.1f}dB {amp:10.3f} {100 * 0.05 / amp:18.0f}%')
    print('\n  spec.md 6.1 allows 10% hysteresis, 20% on a single span, so the')
    print('  512 kbps column is already outside it on this span -- 8.2 measured')
    print('  the cliff exactly there.\n')

    def chain(ln, line_rate, atten=1.0, sd=0.0, imp=0.0, seed=1):
        FS = line_rate * OSB
        x = np.repeat(fast.dm_encode(ln).astype(np.float64) * 2 - 1, OSB // 2)
        x = _lp(x, 1.8e6, FS, 1); x /= np.abs(x).max()
        x *= atten
        r = np.random.default_rng(seed)
        if sd:
            x += r.normal(0, sd, len(x))
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=(0.5, 3.0), seed=seed + 7)
        w = fast.slice_hyst(_lp(x, 2 * line_rate, FS, 2), 0.05)
        del x; gc.collect()
        b = fast.mono_decode(w, OSB, thr=0.75, dead=0.25)
        del w; gc.collect()
        return b

    secs2 = 0.25
    SEEDS2 = (1, 2, 3, 4)
    print('  Link on that span, 0.25 s x 4 seeds, random payload, 100 impulses/s.')
    print('  Noise floor and impulse rate are FIXED in absolute terms; only the')
    print('  rate changes.  Everything is reported in TIME, not in frames: a')
    print('  re-acquisition costs a fixed number of FRAMES (7.4), which is four')
    print('  times longer in wall-clock at a 16 kHz frame rate than at 64 kHz,')
    print('  so a frame-counted outage would flatter the low rates.\n')
    print(f'  {"line":>7s} {"amp":>6s} {"breaks/s":>9s} {"ms per break":>13s} '
          f'{"time down":>10s}')
    for line, amp in plan:
        nfr = int(secs2 * line / 8)
        frame_hz = line / 8.0
        A = [np.zeros(nfr, np.uint8) for _ in range(NCH)]
        rg = np.random.default_rng(13)
        ln = build([(rg.random(nfr) < 0.5).astype(np.uint8) for _ in range(NCH)], A)
        u = 0; lk = 0
        for sd_i in SEEDS2:
            rb = chain(ln, line, atten=amp, imp=100.0, seed=sd_i)
            st = framer(rb, track='strict')
            u += st['unlocks']; lk += st['frames']
            del rb; gc.collect()
        tot_s = secs2 * len(SEEDS2)
        down_s = (nfr * len(SEEDS2) - lk) / frame_hz
        per = 1000.0 * down_s / max(u, 1)
        print(f'  {line // 1000:6d}k {amp:6.3f} {u / tot_s:9.0f} {per:12.1f} ms '
              f'{100.0 * down_s / tot_s:9.1f}%', flush=True)
    print('\n  The two effects pull OPPOSITE ways, which is not the intuition:')
    print('    a lower rate breaks LESS OFTEN -- its signal is larger against a')
    print('      fixed impulse amplitude, so fewer rings clear the 1-h threshold')
    print('      (10.1), and each ring spans fewer bits')
    print('    but each break costs MORE TIME -- re-acquisition is counted in')
    print('      frames, and frames are longer')
    print('  On these numbers the second effect wins and the lower rate is down')
    print('  for more of the time.  So reach does NOT buy impulse robustness for')
    print('  free; it buys fewer, longer outages.  Which is preferable is a')
    print('  question about the traffic, not about the link: for voice, fewer')
    print('  long mutes are worse than more short ones.')
    print('\n  (0.25 s x 4 seeds at one impulse rate.  The ORDERING is the result;')
    print('  the magnitudes are thin and should not be quoted as rates.)')

    # -------------------------------------------------------- the PCM point
    print('\n\nTHE PCM ARGUMENT -- stronger than it first looks')
    print('  A 64 kbps slot is a DS0 rate, so a data card at a 64 kHz frame rate')
    print('  is a G.711 pipe.  But rate alone is not enough: PCM needs OCTET')
    print('  alignment to know where a sample starts, and data-card.md records')
    print('  that the pipe is "not octet-aligned -- the framer establishes bit')
    print('  alignment and slot identity, and nothing coarser".')
    print('\n  This frame fixes that for free.  One channel takes one bit per')
    print('  frame, and the superframe is 8 frames, so:\n')
    print(f'  {"N":>3s} {"superframe":>11s} {"bits/ch/sf":>11s} {"frame kHz":>10s} '
          f'{"superframe kHz":>15s} {"= PCM 8 kHz?":>13s}')
    for N, sf in ((2, 4), (6, 8), (14, 16)):
        for r in RATES:
            sfr = r / sf / 1000.0
            tag = 'YES' if (sf == 8 and abs(sfr - 8.0) < 1e-6) else ''
            print(f'  {N:3d} {sf:8d} fr {sf:11d} {r // 1000:9d}k {sfr:14.1f}k {tag:>13s}')
        print()
    print('  The elegant case is N = 6 at a 64 kHz frame rate, and it is better')
    print('  than a rate coincidence.  THE SUPERFRAME COUNTER IS THE OCTET')
    print('  COUNTER.  It has 8 phases; a channel takes one bit per frame; so')
    print('  superframe state k IS bit k of that channel\'s octet.  The same three')
    print('  bits that address the signalling demux (the 74xx259) do the byte')
    print('  framing, with no extra counter and no extra state:\n')
    print('    superframe state   0  1  2  3  4  5  6  7')
    print('    signalling S       A1 A2 A3 P1 A4 A5 A6 P0   -> the 259 address')
    print('    channel n octet    b0 b1 b2 b3 b4 b5 b6 b7   -> the byte boundary')
    print('\n  And at a 64 kHz frame rate the superframe rate is 64/8 = 8 kHz,')
    print('  the PCM sample rate exactly, so one superframe carries one sample.')
    print('  A PCM card is then a shift register clocked by the frame clock and')
    print('  transferred at state 7 -- one 74xx164 plus a latch per channel.')
    print('  OCTET ALIGNMENT COMES FREE.  The slot becomes a true DS0, not merely')
    print('  a 64 kbps pipe -- which is what data-card.md says it is not today.')
    print('\n  No other combination lands on 8 kHz: N = 6 at 32 kHz gives a 4 kHz')
    print('  superframe (an octet, but at half the PCM rate), and N = 14 at 64 kHz')
    print('  gives 16 bits at 4 kHz -- two octets per superframe, also usable, but')
    print('  it is N = 6 at 64 kHz that is one-for-one with a DS0.')
    print('\n  The catch, and it is a serious one: 4.3 measured that the')
    print('  superframe phase is admitted wrong for 56 of 64 hook states.  Today')
    print('  that misroutes signalling.  If PCM octet alignment is carried on the')
    print('  same phase, a wrong phase ROTATES EVERY PCM SAMPLE -- garbage audio')
    print('  on a link that is otherwise bit-perfect.  Relying on the superframe')
    print('  for octets raises 4.3 from a signalling bug to a payload bug, and')
    print('  makes 15 item 3 a precondition rather than a recommendation.')


TARGETS = {'stage1': stage1, 'sfphase': sfphase, 'bitlock': bitlock, 'errors': errors,
           'tx': tx, 'constant': constant, 'line': line, 'random': randdata,
           'plant': plant, 'clock': clock, 'impulse': impulse,
           'impulse_ami': impulse_ami, 'polarity': polarity,
           'rxclock': rxclock, 'codes': codes, 'framerate': framerate}

if __name__ == '__main__':
    which = sys.argv[1:] or list(TARGETS)
    for k in which:
        TARGETS[k]()
        print()
