"""
Supervision over a multiframe.

The S4 header already carries a four-frame pattern on T (1,1,1,0), and the
receiver already holds the last four T in a register.  The position of the
single zero in that register IS a multiframe phase: no counter, no search, no
second framer, and an errored T makes the register invalid (0 or 2 zeros)
rather than wrong.  This module uses that phase to time-share ONE supervision
bit position (M) among all channels, which frees the per-channel A bit.

Layouts (framing pair S,T always last, check and counter exactly spec 7):

  L1/L3/L7  [A1][C1]...[AN][CN][S][T]              the standard, for reference
  MF5       [M][C1][C2][C3][C4][C5][S][T]          8 bits, 5 channels
  MF6       [C1..C6][1][M][C1..C6][S][T]           16 bits, 6 channels at TWICE
                                                   the frame rate

  M over eight frames:  A1 A2 A3 1 A4 A5 A6 0      (MF5: the A6 slot is spare)
  T over eight frames:   1  1  1 0  1  1  1 0
  The two fixed M slots ride on the T = 0 frames and say which half follows,
  so the receiver's slot address is (latched marker, T phase) with no decode.

Usage:  python3 mf.py [core|locks|slips|sup|tones|strap|enum|rob|gates|all]
"""
import sys, itertools, numpy as np
import link

TP = (1, 1, 1, 0)
ONEZERO = tuple((4 - bin(w).count('1')) == 1 for w in range(16))    # exactly one 0 in four
# phase of the CURRENT frame from the four PREVIOUS T (bit 0 = most recent):
QTAB = {0b1110: 0, 0b1101: 1, 0b1011: 2, 0b0111: 3}
MSLOTS = (0, 1, 2, 'm1', 3, 4, 5, 'm0')          # channel index, or a marker


def legacy(n):
    return dict(name=f'L{n}', flen=2 + 2 * n, n=n, mult=1,
                cpos=[[2 * j + 1] for j in range(n)], apos=[2 * j for j in range(n)],
                mpos=None, fixed={})


LAYOUTS = {
    'L1': legacy(1), 'L3': legacy(3), 'L7': legacy(7),
    'MF5': dict(name='MF5', flen=8, n=5, mult=1, cpos=[[j + 1] for j in range(5)],
                apos=None, mpos=0, fixed={}),
    'MF6': dict(name='MF6', flen=16, n=6, mult=2, cpos=[[j, j + 8] for j in range(6)],
                apos=None, mpos=7, fixed={6: 1}),
}


# ------------------------------------------------------------------ transmit
def build(lay, C, A, mf0=0, spare=0, tpat=TP, inv=False):
    """C: (n, mult*L) channel bits at the CHANNEL rate.  A: (n, L) supervision
    at the frame rate.  mf0: the transmitter's multiframe count at frame 0."""
    C = np.atleast_2d(C); A = np.atleast_2d(A)
    n, flen, mult = lay['n'], lay['flen'], lay['mult']
    L = C.shape[1] // mult
    f = np.zeros((L, flen), np.uint8)
    for j in range(n):
        for k, p in enumerate(lay['cpos'][j]):
            f[:, p] = C[j, k:mult * L:mult]
    for p, v in lay['fixed'].items():
        f[:, p] = v
    idx = np.arange(L) + mf0
    if lay['apos'] is not None:
        for j in range(n):
            f[:, lay['apos'][j]] = A[j, :L]
    else:
        slot = idx % 8
        m = np.zeros(L, np.uint8)
        for s, what in enumerate(MSLOTS):
            sel = slot == s
            if what == 'm1':   m[sel] = 1
            elif what == 'm0': m[sel] = 0
            elif what < n:     m[sel] = A[what, :L][sel]
            else:              m[sel] = spare
        f[:, lay['mpos']] = m
    f[:, flen - 2] = 0
    f[:, flen - 1] = np.array(tpat, np.uint8)[idx % len(tpat)]
    if inv:                                           # complemented header: S = 1, T = 0,0,0,1
        f[:, flen - 2:] ^= 1
    return f.reshape(-1)


# ------------------------------------------------------------------- receive
def rx(line, lay, skew=0, confirm=32, trip=16, verify=False, sup=True, stop_at_lock=False, coast=False, inv=False):
    """Spec 7 framer, unchanged: good := S == 0 and (fewer than 3 frames since
    the slip or exactly one 0 in the last four T); 32 to lock; +1/-1 trip 16.

    Added for the MF layouts, all of it hanging off the T register:
      valid  = exactly one 0 among the four T BEFORE this frame
      q      = where that 0 is          -> this frame's phase, 0..3
      q == 3 : latch M as the half marker            (74HC74)
      else   : write M to slot (marker, q)           (74HC259), only if valid
    verify=True additionally requires the marker to have toggled since the last
    one before any write is allowed."""
    flen = lay['flen']
    if skew:
        line = np.roll(line, -skew)
    true = (flen - skew % flen) % flen
    b = line.tobytes(); N = len(b)
    sp, tp, mp = flen - 2, flen - 1, lay['mpos']
    n = lay['n']
    i = cc = err = 0; locked = False
    H = 0; seen = 0                      # previous T, newest in bit 0; frames since slip
    hl = 0; hv = False; fresh = False    # half marker, half known, last marker slot was valid
    c = 0; synced = False                # coasting slot counter (coast=True)
    lat = [0] * 8
    pos = []; supo = []; st = dict(lock_bit=None, false_lock=False, lof_events=0, writes=0, skipped=0)
    while i + flen <= N:
        s = b[i + sp] ^ inv; t = b[i + tp] ^ inv
        good = (s == 0) and (seen < 3 or ONEZERO[((H << 1) | t) & 15])
        if mp is not None and sup and coast:
            # slot counter c: overwritten from the T register whenever it is valid, counts on when it is not
            m = b[i + mp]
            if seen >= 4 and ONEZERO[H & 15]:
                c = (c & 4) | QTAB[H & 15]
                if (c & 3) == 3:
                    nxt = 4 if m else 0; synced = True
                else:
                    nxt = (c + 1) & 7
            else:
                nxt = (c + 1) & 7
            if (c & 3) != 3 and synced and locked:
                lat[c] = m; st['writes'] += 1
            c = nxt
        elif mp is not None and sup:
            if seen >= 4 and ONEZERO[H & 15]:
                q = QTAB[H & 15]; m = b[i + mp]
                if q == 3:
                    hv = (fresh and m != hl) if verify else True
                    hl = m; fresh = True
                elif hv and locked:
                    lat[(hl << 2) | q] = m; st['writes'] += 1
                elif locked:
                    st['skipped'] += 1
            else:
                hv = False; fresh = False
                if locked: st['skipped'] += 1
        H = ((H << 1) | t) & 15
        if seen < 4: seen += 1
        if not locked:
            if good:
                cc += 1
                if cc >= confirm:
                    locked = True; st['lock_bit'] = i; st['false_lock'] = (i % flen) != true
                    err = 0
                    if stop_at_lock:
                        st['pos'] = np.array(pos, np.int64); st['true'] = true
                        return st
                i += flen
            else:
                cc = 0; H = 0; seen = 0; synced = False; i += 1
            continue
        err = (err - 1 if err > 0 else 0) if good else err + 1
        if err >= trip:
            locked = False; cc = err = 0; H = 0; seen = 0; hv = False; fresh = False; synced = False
            lat = [0] * 8; st['lof_events'] += 1; i += 1
            continue
        pos.append(i)
        if mp is not None and sup:
            supo.append((lat[0], lat[1], lat[2], lat[4], lat[5], lat[6]))
        i += flen
    st['pos'] = np.array(pos, np.int64)
    if mp is not None and sup:
        st['A'] = np.array(supo, np.uint8).T[:n] if supo else np.zeros((n, 0), np.uint8)
    elif lay['apos'] is not None and len(pos):
        st['A'] = np.array([line[st['pos'] + p] for p in lay['apos']], np.uint8)
    st['true'] = true
    return st


def chans(line, lay, st, skew=0):
    """Channel bits at the channel rate, from the emitted frames."""
    if skew:
        line = np.roll(line, -skew)
    out = []
    for j in range(lay['n']):
        cols = [line[st['pos'] + p] for p in lay['cpos'][j]]
        out.append(np.stack(cols, 1).reshape(-1))
    return np.array(out, np.uint8)


# ------------------------------------------------------------------ material
_MAT = {}


def material(secs=3.0):
    """CVSD speech and CVSD silence at 32 kbps, from the same source the framing
    review used."""
    if secs not in _MAT:
        import framing_review as fr
        _MAT[secs] = fr.load(secs)
    return _MAT[secs]


def voice(lay, cv, L, idle=False, sil=None):
    """n independent-looking channel streams at the channel rate."""
    n, mult = lay['n'], lay['mult']
    src = sil if idle else cv
    reps = int(np.ceil(mult * L / len(src))) + 1
    big = np.tile(src, reps)
    return np.array([np.roll(big, (13 if idle else 977) * (j + 1))[:mult * L] for j in range(n)], np.uint8)


def hooks_slow(n, L, rate):
    """Every channel changes hook state on its own slow schedule, so a bit
    delivered to the wrong channel is visible."""
    t = np.arange(L) / rate
    return np.array([(((t * (3.0 + 1.7 * j)).astype(int) + j + 1) & 1) for j in range(n)], np.uint8)


def expected_latch(lay, A, mf0, L):
    """What the receiver's latch for each channel must hold at every frame:
    that channel's A as sampled by the transmitter at its most recent slot."""
    n = lay['n']; idx = np.arange(L) + mf0; slot = idx % 8
    out = np.zeros((n, L), np.uint8)
    for s, what in enumerate(MSLOTS):
        if isinstance(what, int) and what < n:
            fr_ = np.flatnonzero(slot == s)
            last = np.full(L, -1, np.int64); last[fr_] = fr_
            last = np.maximum.accumulate(last)
            ok = last >= 0
            out[what, ok] = A[what, last[ok]]
    return out


# --------------------------------------------------------------------- core
def do_core(secs=2.0):
    import s4_simple, framing_review as fr, time
    cv, sil = material(secs); L = len(cv)
    print('1. RECEIVER MODEL AGAINST THE SPEC REFERENCE (s4_simple.framer_single), layout L3')
    lay = LAYOUTS['L3']; S4 = fr.SCHEMES['S4 T=1110 period 4']
    C = voice(lay, cv, L); A = np.array([np.full(L, j % 2, np.uint8) for j in range(3)])
    ln = build(lay, C, A)
    same_build = np.array_equal(ln, fr.gbuild(C, A, S4))
    agree = 0; total = 0
    for ber in (0.0, 1e-2, 3e-2, 5e-2):
        x = link.impair(ln, ber=ber, seed=5) if ber else ln
        for k in range(8):
            a = s4_simple.framer_single(x, 3, skew=k); b = rx(x, lay, skew=k)
            total += 1
            agree += (a['lock_bit'] == b['lock_bit'] and a['lof_events'] == b['lof_events']
                      and np.array_equal(a['pos'], b['pos']))
    t0 = time.time(); rx(ln, lay); dt = time.time() - t0
    print(f'   frame build identical: {same_build};  lock bit, LOF events and every emitted frame '
          f'identical in {agree}/{total} runs;  {dt:.2f} s per {L} frames')

    print('\n2. CLEAN LINE: every start-up skew x every transmitter multiframe phase')
    print(f'   {"layout":10s} {"runs":>5s} {"false lk":>8s} {"LOF":>4s} {"channels bit-exact":>19s} '
          f'{"supervision exact":>18s} {"first write after lock":>23s}')
    for name, coast in (('MF5', False), ('MF5', True), ('MF6', False)):
        lay = LAYOUTS[name]; n, flen, mult = lay['n'], lay['flen'], lay['mult']
        Lf = L // mult
        C = voice(lay, cv, Lf); A = hooks_slow(n, Lf, 32000 // mult)
        runs = fl = lofs = cbad = sbad = 0; first = []
        for mf0 in range(8):
            ln = build(lay, C, A, mf0=mf0)
            exp = expected_latch(lay, A, mf0, Lf)
            for k in range(flen):
                st = rx(ln, lay, skew=k, coast=coast); runs += 1
                fl += st['false_lock']; lofs += st['lof_events']
                got = chans(ln, lay, st, skew=k)
                f0 = (st['pos'] + k) // flen                  # transmitter frame index of each emitted frame
                f0 = f0[f0 < Lf]; m = len(f0)
                ref = np.array([C[j].reshape(-1, mult)[f0].reshape(-1) for j in range(n)])
                cbad += int((got[:, :m * mult] != ref).sum())
                # supervision: exact once one multiframe has passed since lock (the '259 is clear until lock)
                sbad += int((st['A'][:, 8:m] != exp[:, f0[8:]]).sum())
                w = np.flatnonzero((st['A'][:, :m] != exp[:, f0]).any(0))
                first.append(int(w.max()) + 1 if len(w) else 0)
        print(f'   {name + (" coast" if coast else ""):10s} {runs:5d} {fl:8d} {lofs:4d} {cbad:>13d} wrong {sbad:>12d} wrong '
              f'{"<= %d frames" % max(first):>23s}', flush=True)



# -------------------------------------------------------------------- locks
# Seats, per C slot:  V speech   S CVSD silence   E empty (fill = channel-rate toggle)
#                     g guard, strapped 1         d data        (a data pipe is the PAIR g,d)
#   negative controls: z data held at constant 0  b bare data, no guard   l guard strapped LOW
def scene(lay, seats, cv, sil, L, data=None, hook='mixed', mf0=0):
    n, mult = lay['n'], lay['mult']; Lc = mult * L
    V = voice(lay, cv, L); S = voice(lay, cv, L, idle=True, sil=sil)
    C = np.zeros((n, Lc), np.uint8)
    for j in range(n):
        k = seats[j % len(seats)]
        if k == 'V': C[j] = V[j]
        elif k == 'S': C[j] = S[j]
        elif k == 'E': C[j] = (np.arange(Lc) + (mf0 if mult == 1 else 0)) & 1
        elif k == 'g': C[j] = 1
        elif k in ('z', 'l'): C[j] = 0
        elif k in ('d', 'b'): C[j] = np.resize(data, Lc)
    if lay['apos'] is not None:                       # standard layout: data card straps A high
        A = np.array([np.full(L, 1 if seats[j % len(seats)] in 'db' else 0, np.uint8) for j in range(n)])
    else:
        A = np.zeros((n, L), np.uint8)
    h = {'on': 0, 'off': 1}.get(hook)
    for j in range(n):
        if seats[j % len(seats)] in 'VS':
            A[j] = (j % 2) if h is None else h
    return C, A


def data_patterns(L, mult):
    Lc = mult * L; i = np.arange(Lc)
    P = {'0': np.zeros(Lc, np.uint8), '1': np.ones(Lc, np.uint8), '1010': (i & 1).astype(np.uint8),
         '1110': np.array(TP, np.uint8)[i % 4], '0111': np.array((0, 1, 1, 1), np.uint8)[i % 4],
         '1100': np.array((1, 1, 0, 0), np.uint8)[i % 4], '0001': np.array((0, 0, 0, 1), np.uint8)[i % 4],
         'random': np.random.default_rng(4).integers(0, 2, Lc).astype(np.uint8)}
    if mult == 2:                                     # follows 1110 at BOTH of its positions in the frame
        P['11111100'] = np.array(TP, np.uint8)[(i // 2) % 4]
    return P


def falses(lay, C, A, mf0s=(0, 3)):
    flen = lay['flen']; bad = 0; runs = 0
    for mf0 in mf0s:
        ln = build(lay, C, A, mf0=mf0)
        for k in range(flen):
            st = rx(ln, lay, skew=k, sup=False, stop_at_lock=True)
            bad += bool(st['false_lock']); runs += 1
    return bad, runs


def do_locks(secs=1.5):
    cv, sil = material(secs)
    print('FALSE LOCKS, first lock from every start-up skew x two multiframe phases')
    print('(worst over hook states on/off/mixed and, for data, over every data pattern)\n')
    for name in ('L3', 'MF5', 'MF6'):
        lay = LAYOUTS[name]; mult = lay['mult']; L = len(cv) // mult
        P = data_patterns(L, mult)
        def worst(seats, datas=(None,), hooks=('on', 'off', 'mixed')):
            w = (0, 0, '')
            for dn in datas:
                for hk in hooks:
                    C, A = scene(lay, seats, cv, sil, L, data=P.get(dn), hook=hk)
                    b, r = falses(lay, C, A)
                    if b >= w[0]: w = (b, r, f'{dn}/{hk}' if b else '')
            return w
        if name == 'L3':                              # the standard, same harness: data card = A high
            rows = [('speech', 'V', (None,)), ('idle voice', 'S', (None,)), ('empty chassis', 'E', (None,)),
                    ('data cards (A high), any data', 'd', tuple(P)), ('voice / empty / data', 'VEd', tuple(P))]
        else:
            rows = [('speech', 'V', (None,)), ('idle voice', 'S', (None,)), ('empty chassis', 'E', (None,)),
                    ('data pipes g,d in every pair of seats', 'gd', tuple(P)),
                    ('voice, then pipes:  V g d g d', 'Vgdgd' if lay['n'] == 5 else 'Vgdgdg', tuple(P)),
                    ('voice / empty / pipe:  V E g d', 'VEgd', tuple(P)),
                    ('pipe in the last seats', 'VVVgd' if lay['n'] == 5 else 'VVVVgd', tuple(P)),
                    ('CONTROL bare data after constant-0 data: z b', 'zb', tuple(P)),
                    ('CONTROL guard strapped LOW: l d', 'ld', tuple(P))]
        for label, seats, datas in rows:
            b, r, which = worst(seats, datas)
            print(f'  {name:4s} {label:48s} {b:>3d}/{r:<4d}' + (f'  <-- {which}' if b else ''), flush=True)
        print()


# -------------------------------------------------------------------- tones
def _s4pass(b):
    """Per-frame result of the T-window test on a bit stream sampled once a frame."""
    z = (b == 0).astype(np.int8)
    w = np.convolve(z, np.ones(4, np.int8), 'valid')
    out = np.zeros(len(b), bool); out[3:] = (w == 1)
    return out


def _longest(x):
    r = link.runs_of(x.astype(np.uint8), 1)
    return int(r.max()) if len(r) else 0


def tone_inputs(rate, secs):
    import run
    t = np.arange(int(secs * rate)) / rate; out = []
    for off in (1e-3, 1e-2, 3e-2, 0.1, 0.2, 0.25, 0.3, 0.4):
        for sg in (1, -1):
            out.append((f'DC {sg * off:+g}', np.full(len(t), sg * off)))
    for f in (60.0, 300.0, 1004.0, 2600.0, 3000.0, 3400.0, 3800.0):
        for db in (-40, -20, 0):
            a = run.NOMINAL_RMS * 10 ** (db / 20) * np.sqrt(2)
            out.append((f'{f:.0f} Hz {db:+d} dB', a * np.sin(2 * np.pi * f * t)))
    return out


def do_tones(secs=4.0):
    """A misaligned framer reads one payload position once per frame.  In the
    standard and in MF5 that is every bit of a CVSD stream.  In MF6, and under a
    channel-count mis-strap, it is every SECOND (or fourth) bit.  Can a CVSD
    limit cycle, decimated, reproduce 1110?"""
    import cvsd, run
    print('CVSD limit cycles against the T-window test: longest run of passing frames / pass fraction')
    print('(a run >= 32 can complete an acquisition; a fraction >= 0.50 is a slip the counter cannot see)\n')
    flagged = []
    for rate in (16000, 32000, 64000):
        p = run.params(rate)
        print(f'  CVSD {rate // 1000} kbps   {"input":16s} {"every bit":>14s} {"every 2nd":>14s} {"every 4th":>14s}')
        for name, x in tone_inputs(rate, secs):
            b = cvsd.encode(x, p)[int(0.5 * rate):]
            cells = []; bad = False
            for dec in (1, 2, 4):
                best = (0, 0.0)
                for ph in range(dec):
                    ps = _s4pass(b[ph::dec])
                    best = max(best, (_longest(ps), float(ps.mean())))
                mark = '!' if (best[0] >= 32 or best[1] >= 0.5) else ' '
                bad |= mark == '!'
                cells.append(f'{best[0]:>7d}/{best[1]:4.2f}{mark}')
            if bad or name.startswith('DC +0.001') or 'Hz +0 dB' in name or 'Hz -40' in name:
                print(f'  {"":14s} {name:16s} ' + ' '.join(f'{c:>14s}' for c in cells), flush=True)
            if bad:
                flagged.append((rate, name))
        print()
    print('  flagged:', ', '.join(f'{r // 1000}k {n}' for r, n in flagged) if flagged else '  flagged: none')


# ---------------------------------------------------------------- tonesweep
def _sweep_one(args):
    import cvsd, run
    rate, f, db, secs = args
    p = run.params(rate); t = np.arange(int(secs * rate)) / rate
    a = run.NOMINAL_RMS * 10 ** (db / 20) * np.sqrt(2)
    b = cvsd.encode(a * np.sin(2 * np.pi * f * t), p)[int(0.5 * rate):]
    out = {}
    for dec in (1, 2, 4):
        best = (0, 0.0)
        for ph in range(dec):
            ps = _s4pass(b[ph::dec]); best = (max(best[0], _longest(ps)), max(best[1], float(ps.mean())))
        out[dec] = best
    return rate, f, db, out


def do_tonesweep(secs=3.0):
    """Fine sweep: steady tones 300..3800 Hz x -30..+3 dB re nominal, every rate,
    read every bit / every 2nd / every 4th."""
    from multiprocessing import Pool
    freqs = np.arange(300.0, 3801.0, 100.0); dbs = np.arange(-30, 4, 3)
    jobs = [(r, float(f), float(d), secs) for r in (16000, 32000, 64000) for f in freqs for d in dbs]
    with Pool(8) as pool:
        res = pool.map(_sweep_one, jobs, chunksize=8)
    print(f'STEADY TONES, {len(freqs)} frequencies x {len(dbs)} levels per rate, against the T-window test')
    print(f'  {"CVSD":>5s} {"read":>10s} {"longest run":>12s} {"at":>20s} {"runs >= 32":>11s} '
          f'{"highest fraction":>17s} {"at":>20s} {"fraction >= 0.5":>16s}')
    for rate in (16000, 32000, 64000):
        rr = [x for x in res if x[0] == rate]
        for dec, lab in ((1, 'every bit'), (2, 'every 2nd'), (4, 'every 4th')):
            lr = max(rr, key=lambda x: x[3][dec][0]); hf = max(rr, key=lambda x: x[3][dec][1])
            n32 = sum(1 for x in rr if x[3][dec][0] >= 32); n50 = sum(1 for x in rr if x[3][dec][1] >= 0.5)
            print(f'  {rate // 1000:>4d}k {lab:>10s} {lr[3][dec][0]:>12d} {f"{lr[1]:.0f} Hz {lr[2]:+.0f} dB":>20s} '
                  f'{f"{n32}/{len(rr)}":>11s} {hf[3][dec][1]:>17.2f} {f"{hf[1]:.0f} Hz {hf[2]:+.0f} dB":>20s} '
                  f'{f"{n50}/{len(rr)}":>16s}', flush=True)
        print()
    return res


# ------------------------------------------------------------------ tonee2e
def cvsd_src(rate, kind, secs, f=None, db=None):
    """A CVSD bit stream at `rate`: 'tone', 'idle' or 'speech'."""
    import cvsd, run, audio
    p = run.params(rate); n = int(secs * rate)
    if kind == 'idle':
        return cvsd.encode(np.zeros(n), p)
    if kind == 'tone':
        t = np.arange(n) / rate
        return cvsd.encode(run.NOMINAL_RMS * 10 ** (db / 20) * np.sqrt(2) * np.sin(2 * np.pi * f * t), p)
    x, fs = audio.read_wav('speech30.wav', seconds=secs)
    x = audio.bandlimit(x, fs); x = x * run.NOMINAL_RMS / np.std(x)
    return cvsd.encode(audio.resample_to(x, fs, rate), p)[:n]


def do_tonee2e(secs=2.0):
    """The tone-sweep hazards, end to end with the real framer."""
    print('A. MF6 (channels at twice the frame rate): a steady tone beside an idle channel')
    print(f'   {"channel rate":>12s} {"tone":>16s} {"false locks / runs":>19s} {"worst frames misaligned after a slip":>38s}')
    lay = LAYOUTS['MF6']; flen = 16
    for rate, f, db in ((16000, 2000.0, -30.0), (16000, 1000.0, -21.0), (32000, 3800.0, -3.0), (64000, 3500.0, -27.0)):
        tone = cvsd_src(rate, 'tone', secs, f, db); idle = cvsd_src(rate, 'idle', secs); sp = cvsd_src(rate, 'speech', secs)
        Lc = len(tone) - len(tone) % 2; L = Lc // 2
        bad = runs = 0; worst = 0
        for ph in (0, 1):                                   # both idle phases of the neighbour
            C = np.array([np.roll(idle, ph)[:Lc], tone[:Lc], np.roll(idle, ph + 1)[:Lc],
                          np.roll(sp, 977)[:Lc], np.roll(idle, ph)[:Lc], np.roll(sp, 1954)[:Lc]])
            A = np.zeros((6, L), np.uint8)
            ln = build(lay, C, A)
            for k in range(flen):
                bad += bool(rx(ln, lay, skew=k, sup=False, stop_at_lock=True)['false_lock']); runs += 1
            at = (L // 3) * flen
            for k in range(1, flen):
                st = rx(link.slip(ln, at, n=k), lay, sup=False); pp = st['pos']; after = pp[pp >= at]
                if len(after):
                    worst = max(worst, int((((after + k) % flen) != (pp[0] % flen)).sum()))
        never = worst >= (L - L // 3) - 64
        print(f'   {rate // 1000:>10d}k {f"{f:.0f} Hz {db:+.0f} dB":>16s} {f"{bad}/{runs}":>19s} '
              f'{"NEVER DETECTED" if never else str(worst):>38s}', flush=True)

    print('\nB. CONTROL, MF5 (every channel at the frame rate), the same tones')
    lay = LAYOUTS['MF5']; flen = 8
    for rate, f, db in ((16000, 2000.0, -30.0), (32000, 3800.0, -3.0)):
        tone = cvsd_src(rate, 'tone', secs, f, db); idle = cvsd_src(rate, 'idle', secs); sp = cvsd_src(rate, 'speech', secs)
        L = len(tone); bad = runs = 0; worst = 0
        for ph in (0, 1):
            C = np.array([np.roll(idle, ph), tone, np.roll(idle, ph + 1), np.roll(sp, 977), np.roll(idle, ph)])
            ln = build(lay, C, np.zeros((5, L), np.uint8))
            for k in range(flen):
                bad += bool(rx(ln, lay, skew=k, sup=False, stop_at_lock=True)['false_lock']); runs += 1
            at = (L // 3) * flen
            for k in range(1, flen):
                st = rx(link.slip(ln, at, n=k), lay, sup=False); pp = st['pos']; after = pp[pp >= at]
                if len(after):
                    worst = max(worst, int((((after + k) % flen) != (pp[0] % flen)).sum()))
        print(f'   {rate // 1000:>10d}k {f"{f:.0f} Hz {db:+.0f} dB":>16s} {f"{bad}/{runs}":>19s} {worst:>38d}', flush=True)

    print('\nC. THE STANDARD, channel-count mis-strap with a steady tone on an on-hook channel')
    print('   (spec 10.3 measured speech, idle and data; every frame width divides the wider ones)')
    for txn, rxn, rate, f, db in ((1, 7, 64000, 2000.0, -27.0), (1, 3, 64000, 3500.0, -27.0),
                                  (3, 7, 32000, 3800.0, -3.0), (1, 7, 64000, 1004.0, 0.0)):
        tone = cvsd_src(rate, 'tone', secs, f, db); idle = cvsd_src(rate, 'idle', secs); L = len(tone)
        tl, rl = LAYOUTS[f'L{txn}'], LAYOUTS[f'L{rxn}']
        C = np.array([tone] + [np.roll(idle, j) for j in range(1, txn)]); A = np.zeros((txn, L), np.uint8)
        ln = build(tl, C, A)
        locks = sum(1 for k in range(rl['flen']) if rx(ln, rl, skew=k, sup=False, stop_at_lock=True)['lock_bit'] is not None)
        st = rx(ln, rl, sup=False)
        held = len(st['pos']) / max(1, (len(ln) // rl['flen']))
        print(f'   N={txn} @ {rate // 1000}k into N={rxn}, {f:.0f} Hz {db:+.0f} dB: locks on {locks}/{rl["flen"]} skews; '
              f'locked for {100 * held:.0f}% of the clip, {st["lof_events"]} loss-of-frame events', flush=True)


# -------------------------------------------------------------------- slips
def _after_slip(ln, lay, at, k, A=None, mf0=0, verify=False, coast=False):
    """Frames emitted at a wrong alignment after deleting k bits at `at`; and,
    if A is given, supervision latch samples that differ from what the
    transmitter sent, over every frame emitted after the slip."""
    flen = lay['flen']
    st = rx(link.slip(ln, at, n=k), lay, verify=verify, coast=coast); pp = st['pos']
    sel = pp >= at
    if not sel.any():
        return 0, 0, st
    wrong = ((pp[sel] + k) % flen) != (pp[0] % flen)
    supbad = 0
    if A is not None and 'A' in st:
        L = A.shape[1]
        f0 = np.minimum((pp[sel] + k) // flen, L - 1)
        exp = expected_latch(lay, A, mf0, L) if lay['mpos'] is not None else A
        got = st['A'][:, sel]
        supbad = int((got != exp[:, f0]).sum())
    return int(wrong.sum()), supbad, st


def do_slips(secs=3.0):
    cv, sil = material(secs)
    print('LOSS OF FRAME.  Worst over every slip size 1 .. frame-1: frames emitted misaligned, and')
    print('supervision samples delivered wrong (all channels, all frames after the slip).\n')
    print(f'  {"layout":6s} {"traffic":22s} {"misaligned":>11s} {"sup. samples wrong":>19s}   '
          f'{"false reframes @ 1e-3 / 1e-2 / 3e-2 / 5e-2":>42s}')
    for name in ('L3', 'MF5'):
        lay = LAYOUTS[name]; flen = lay['flen']; L = len(cv); n = lay['n']
        P = data_patterns(L, 1)
        Ah = hooks_slow(n, L, 32000)
        cases = [('idle voice', scene(lay, 'S', cv, sil, L, hook='mixed')),
                 ('speech', scene(lay, 'V', cv, sil, L, hook='mixed')),
                 ('empty + data idling 1', scene(lay, 'Ed' if name == 'L3' else 'Egd', cv, sil, L, data=P['1']))]
        for label, (C, A) in cases:
            if label != 'empty + data idling 1':
                A = Ah
            ln = build(lay, C, A); at = (L // 3) * flen
            wm = ws = 0
            for k in range(1, flen):
                m, sb, _ = _after_slip(ln, lay, at, k, A=A)
                wm = max(wm, m); ws = max(ws, sb)
            rf = ''
            if label == 'speech':
                rf = ' / '.join(str(rx(link.impair(ln, ber=b, seed=5), lay, sup=False)['lof_events'])
                                for b in (1e-3, 1e-2, 3e-2, 5e-2))
            never = wm >= (L - L // 3) - 64
            print(f'  {name:6s} {label:22s} {"NEVER" if never else wm:>11} {ws:>19d}   {rf:>42s}', flush=True)
        print()

    print('WHOLE-FRAME SLIPS (frame alignment survives, the multiframe does not): MF5, speech')
    print(f'  {"decode":>7s} {"bits deleted":>13s} {"LOF events":>11s} {"misaligned":>11s} {"sup. samples wrong":>19s}')
    lay = LAYOUTS['MF5']; flen = 8; L = len(cv)
    C, _ = scene(lay, 'V', cv, sil, L); A = hooks_slow(5, L, 32000)
    ln = build(lay, C, A); at = (L // 3) * flen
    for coast in (False, True):
        for k in (8, 16, 24, 32, 40, 72):
            m, sb, st = _after_slip(ln, lay, at, k, A=A, coast=coast)
            print(f'  {"coast" if coast else "comb":>7s} {k:>13d} {st["lof_events"]:>11d} {m:>11d} {sb:>19d}', flush=True)


# ---------------------------------------------------------------------- sup
def rc_schmitt_fast(bits, fs, tau=2e-3, hi=0.58, lo=0.40):
    """link.rc_schmitt, vectorised: same RC, same thresholds."""
    from scipy import signal
    a = 1.0 - np.exp(-1.0 / (fs * tau))
    v = signal.lfilter([a], [1.0, -(1.0 - a)], bits.astype(float))
    ev = np.zeros(len(v), np.int8); ev[v > hi] = 1; ev[v < lo] = -1
    idx = np.where(ev != 0, np.arange(len(v)), -1); idx = np.maximum.accumulate(idx)
    out = np.where(idx >= 0, ev[np.maximum(idx, 0)], -1)
    return (out == 1).astype(np.uint8)


def _sup_job(args):
    name, rate, ber, mode, secs, tau = args; verify = mode == 'verify'
    lay = LAYOUTS[name]; n = lay['n']; flen = lay['flen']
    L = int(secs * rate); rng = np.random.default_rng(7)
    C = rng.integers(0, 2, (n, L)).astype(np.uint8)          # payload content is irrelevant at the true alignment
    # ch1 idle, ch2 off-hook, ch3 dial pulsing 10 pps 40 ms break / 60 ms make, rest idle
    A = np.zeros((n, L), np.uint8); A[1] = 1
    t0 = np.arange(int(secs * 10) - 3) * 0.100 + 0.20
    for a0 in t0:
        A[2, int(a0 * rate):int((a0 + 0.060) * rate)] = 1
    ln = build(lay, C, A)
    st = rx(link.impair(ln, ber=ber, seed=13) if ber else ln, lay, skew=3, verify=verify, coast=mode == 'coast')
    got = st['A']
    f1 = rc_schmitt_fast(got[0], rate, tau); f2 = rc_schmitt_fast(got[1], rate, tau); f3 = rc_schmitt_fast(got[2], rate, tau)
    raw = link.runs_of(got[0])
    mk = link.runs_of(f3) / rate * 1000.0; mk = mk[mk > 5]
    return dict(name=name, rate=rate, ber=ber, mode=mode, tau=tau, lof=st['lof_events'],
                rawbad=int(got[0].sum()), rawlong=1000.0 * (raw.max() if len(raw) else 0) / rate,
                spur=len(link.runs_of(f1)), drop=len(link.runs_of(1 - f2[int(0.05 * rate):])),
                sent=len(t0), rcvd=len(mk), mean=float(mk.mean()) if len(mk) else 0.0,
                sd=float(mk.std()) if len(mk) else 0.0)


def do_sup(secs=60.0):
    from multiprocessing import Pool
    variants = [('L3', '', 2e-3), ('MF5', 'comb', 2e-3), ('MF5', 'verify', 2e-3), ('MF5', 'coast', 2e-3),
                ('MF5', 'comb', 4e-3), ('MF5', 'coast', 4e-3), ('L3', '', 4e-3)]
    jobs = [(nm, r, b, md, secs, tau) for r in (16000, 32000, 64000) for nm, md, tau in variants
            for b in (0.0, 1e-3, 1e-2, 3e-2, 6e-2)]
    with Pool(8) as pool:
        res = pool.map(_sup_job, jobs)
    print(f'SUPERVISION UNDER LINE ERRORS, {secs:.0f} s per cell, RC + Schmitt as spec 9')
    print('  ch1 idle: spurious assertions;  ch2 off-hook: dropouts;  ch3 dial pulses 10 pps, 60 ms make')
    print('  comb = phase straight from the T register;  verify = comb + marker must toggle;')
    print('  coast = 3-bit slot counter overwritten by the T register when valid, counting on when not\n')
    print(f'  {"frame rate":>10s} {"layout":>16s} {"BER":>6s} {"LOF":>5s} {"ch1 wrong":>10s} {"longest":>9s} '
          f'{"SPURIOUS":>9s} {"DROPOUTS":>9s} {"pulses":>9s} {"make mean":>10s} {"sd":>7s}')
    for r in res:
        lab = f'{r["name"]} {r["mode"]} {1000 * r["tau"]:.0f}ms'.replace('  ', ' ')
        print(f'  {r["rate"] // 1000:>8d} k {lab:>16s} {r["ber"]:>6.0e} {r["lof"]:>5d} {r["rawbad"]:>10d} '
              f'{r["rawlong"]:>7.2f}ms {r["spur"]:>9d} {r["drop"]:>9d} {str(r["rcvd"]) + "/" + str(r["sent"]):>9s} '
              f'{r["mean"]:>8.2f}ms {r["sd"]:>5.2f}ms', flush=True)
    return res


# ---------------------------------------------------------------------- rob
def encode_forced(x, p, every, value, inloop=True):
    """cvsd.encode with every `every`-th bit replaced by the supervision value.
    inloop=True: the forced bit drives the encoder's own integrator, so encoder
    and decoder stay in step and the loop corrects the disturbance.
    inloop=False: classic robbed bit, overwritten after the encoder."""
    import cvsd
    if not inloop:
        b = cvsd.encode(x, p).copy(); b[every - 1::every] = value
        return b
    n = len(x); dt = np.full(n, 1.0 / p.rate)
    k, a_syl, a_int = cvsd._coeffs(p, dt)
    bits = np.zeros(n, np.uint8); mask = (1 << p.run_length) - 1
    span = p.step_max - p.step_min; smin = p.step_min; y = syl = 0.0; hist = 0
    for i in range(n):
        b = value if (i % every) == every - 1 else (1 if x[i] >= y else 0)
        bits[i] = b
        hist = ((hist << 1) | b) & mask
        coin = 1.0 if (hist == 0 or hist == mask) else 0.0
        syl += (coin - syl) * a_syl[i]
        step = smin + syl * span
        y = (y + (step if b else -step) * k[i]) * a_int[i]
    return bits


def _rob_job(args):
    import cvsd, run, audio
    rate, every, value, inloop, secs = args
    p = run.params(rate)
    x = run.load('speech', rate, secs)
    if every is None:
        b = cvsd.encode(x, p); bi = cvsd.encode(np.zeros(len(x)), p)
    else:
        b = encode_forced(x, p, every, value, inloop); bi = encode_forced(np.zeros(len(x)), p, every, value, inloop)
    seg = run.score(x, cvsd.decode(b, p), rate)[0]
    ref = audio.reconstruct(cvsd.decode(cvsd.encode(x, p), p), rate)
    idle = audio.reconstruct(cvsd.decode(bi, p), rate)[int(0.5 * rate):]
    idle_db = 20 * np.log10(max(idle.std(), 1e-12) / ref.std())
    return rate, every, value, inloop, seg, idle_db


def do_rob(secs=10.0):
    from multiprocessing import Pool
    jobs = [(r, None, 0, True, secs) for r in (16000, 32000, 64000)]
    jobs += [(r, e, v, il, secs) for r in (16000, 32000, 64000) for e in (8, 16, 32, 64)
             for il in (True, False) for v in (1, 0)]
    with Pool(8) as pool:
        res = pool.map(_rob_job, jobs)
    base = {r[0]: (r[4], r[5]) for r in res if r[1] is None}
    print(f'ROBBED-BIT SUPERVISION ON CVSD, {secs:.0f} s of speech: segSNR change, and idle-channel output re speech')
    print('  in loop = the forced bit also drives the encoder integrator;  classic = overwritten after the encoder\n')
    print(f'  {"rate":>5s} {"1 bit in":>9s} {"A":>2s}   {"in loop: segSNR":>16s} {"idle":>9s}   {"classic: segSNR":>16s} {"idle":>9s}')
    for rate in (16000, 32000, 64000):
        print(f'  {rate // 1000:>4d}k {"none":>9s} {"":>2s}   {base[rate][0]:>13.2f} dB {base[rate][1]:>6.1f} dB')
        for e in (8, 16, 32, 64):
            for v in (1, 0):
                a = next(r for r in res if r[:4] == (rate, e, v, True)); c = next(r for r in res if r[:4] == (rate, e, v, False))
                print(f'  {"":>5s} {e:>9d} {v:>2d}   {a[4] - base[rate][0]:>+13.2f} dB {a[5]:>6.1f} dB   '
                      f'{c[4] - base[rate][0]:>+13.2f} dB {c[5]:>6.1f} dB')
        print()


# --------------------------------------------------------------------- enum
def _pass_fraction(xs, ys):
    """Fraction of the 8-frame period on which a misaligned framer's check
    passes, for cyclic sequences x (S position) and y (T position)."""
    ok = 0
    for f in range(8):
        w = [ys[(f - j) % 8] for j in range(4)]
        ok += (xs[f] == 0) and (w.count(0) == 1)
    return ok / 8.0


def _choices(kind, role, hooks, spare, n):
    """Every sequence a bit position of this kind can present over 8 frames.
    CVSD as y is handled by measurement (it never passes half the frames nor 32
    in a row, do_tonesweep), so it is reported separately; CVSD as x is given to
    the adversary outright."""
    if kind == 'S': return [[0] * 8]
    if kind == 'T': return [[TP[f % 4] for f in range(8)]]
    if kind == 'g': return [[1] * 8]
    if kind == 'E': return [[(f + p) & 1 for f in range(8)] for p in (0, 1)]
    if kind == 'M':
        seq = []
        for what in MSLOTS:
            seq.append(1 if what == 'm1' else 0 if what == 'm0' else hooks[what] if what < n else spare)
        return [seq]
    if kind in ('d', 'b', 'V'):                      # free
        if role == 'x': return [[0] * 8]
        return [[(v >> f) & 1 for f in range(8)] for v in range(256)]
    raise ValueError(kind)


def enum_layout(seats, n=5):
    """Worst pass fraction over every wrong alignment, hook state and free bit.
    Returns (worst fraction that does not rest on a CVSD bit in the T position,
             worst alignment description)."""
    worst = (0.0, '')
    voices = [j for j in range(n) if seats[j] == 'V']
    for hv in itertools.product((0, 1), repeat=len(voices)):
        hooks = [0] * 6
        for j, v in zip(voices, hv): hooks[j] = v
        for spare in (0, 1):
            kinds = ['M'] + list(seats) + ['S', 'T']
            for k in range(1, 8):
                xk, yk = kinds[(6 + k) % 8], kinds[(7 + k) % 8]
                if yk == 'V':
                    continue                          # bounded by measurement, not by enumeration
                for xs in _choices(xk, 'x', hooks, spare, n):
                    for ys in _choices(yk, 'y', hooks, spare, n):
                        p = _pass_fraction(xs, ys)
                        if p > worst[0]:
                            worst = (p, f'shift {k}: ({xk},{yk})')
    return worst


def legal(seats):
    """Every d is the second seat of a pipe g,d; every g is followed by its d."""
    for j, k in enumerate(seats):
        if k == 'd' and (j == 0 or seats[j - 1] != 'g'): return False
        if k == 'g' and (j == len(seats) - 1 or seats[j + 1] != 'd'): return False
    return True


def do_enum():
    print('MF5, EVERY CARD MIX x EVERY STATIC HOOK STATE x EVERY WRONG ALIGNMENT, data free to do anything')
    print('  a mix is UNSAFE if some wrong alignment can pass the framer check on half the frames or more')
    print('  (then the +1/-1 counter never trips); 1.00 means it can also complete an acquisition\n')
    allm = [m for m in itertools.product('VEgd', repeat=5)]
    leg = [m for m in allm if legal(m)]
    res = [(m, enum_layout(m)) for m in leg]
    bad = [r for r in res if r[1][0] >= 0.5]
    hi = max(res, key=lambda r: r[1][0])
    print(f'  legal mixes (V voice, E empty, g,d a data pipe): {len(leg)};  unsafe: {len(bad)};  '
          f'highest pass fraction anywhere: {hi[1][0]:.3f} at {"".join(hi[0])} {hi[1][1]}')
    ctrl = [m for m in itertools.product('VEgdb', repeat=5) if 'b' in m and legal(tuple(c for c in m if c != 'b') if False else m.__class__(c if c != 'b' else 'V' for c in m))]
    cb = [(m, enum_layout(m)) for m in ctrl]
    nb = sum(1 for r in cb if r[1][0] >= 0.5)
    print(f'  CONTROL, mixes that also contain a bare data bit b (no guard): {len(ctrl)};  unsafe: {nb}')
    ex = next(r for r in cb if r[1][0] >= 0.5)
    print(f'     e.g. {"".join(ex[0])}: pass fraction {ex[1][0]:.2f} at {ex[1][1]}')
    safe_b = [r for r in cb if r[1][0] < 0.5]
    if safe_b:
        print(f'     bare data that happens to be safe ({len(safe_b)} mixes), e.g. {"".join(safe_b[0][0])}: '
              f'it follows T or a guard, never a bit that can stay 0')


# -------------------------------------------------------------------- strap
def do_strap(secs=1.5):
    cv, sil = material(secs); L = len(cv)
    P = data_patterns(L, 1)

    def line(name, seats, data=None, hook='on', inv=False):
        lay = LAYOUTS[name]
        C, A = scene(lay, seats, cv, sil, L, data=data, hook=hook)
        return build(lay, C, A, inv=inv)

    def locks(ln, rxname, inv=False):
        lay = LAYOUTS[rxname]
        return sum(1 for k in range(lay['flen'])
                   if rx(ln, lay, skew=k, sup=False, stop_at_lock=True, inv=inv)['lock_bit'] is not None), lay['flen']

    print('A. NARROW TRANSMITTER INTO A WIDE RECEIVER (every width divides the wider ones): skews that lock')
    print(f'   {"TX":>4s} -> {"RX":<4s} {"speech":>9s} {"idle":>9s} {"data 1110":>10s}')
    for txn, rxn in (('L1', 'MF5'), ('L1', 'L3'), ('L3', 'L7'), ('MF5', 'L7')):
        dseat = 'd' if txn.startswith('L') else 'gd'
        cells = [locks(line(txn, 'V'), rxn), locks(line(txn, 'S'), rxn), locks(line(txn, dseat, P['1110']), rxn)]
        print(f'   {txn:>4s} -> {rxn:<4s} ' + ' '.join(f'{a:>6d}/{b:<3d}' for a, b in cells), flush=True)

    print('\nB. SAME WIDTH, DIFFERENT FORMAT (the standard L3 and MF5 are both 8 bits with S,T last)')
    print(f'   {"TX":>10s} -> {"RX":<10s} {"speech":>9s} {"idle":>9s}')
    for txn, tinv, rxn, rinv in (('L3', False, 'MF5', False), ('MF5', False, 'L3', False),
                                 ('L3', False, 'MF5', True), ('MF5', True, 'L3', False)):
        cells = [locks(line(txn, 'V', inv=tinv), rxn, inv=rinv), locks(line(txn, 'S', inv=tinv), rxn, inv=rinv)]
        print(f'   {txn + (" compl." if tinv else ""):>10s} -> {rxn + (" compl." if rinv else ""):<10s} '
              + ' '.join(f'{a:>6d}/{b:<3d}' for a, b in cells), flush=True)

    print('\nC. MF5 WITH THE COMPLEMENTED HEADER (S = 1, T = 0001, guard strapped 0): false locks / runs')
    lay = LAYOUTS['MF5']
    for label, seats, datas in (('speech', 'V', (None,)), ('idle voice', 'S', (None,)), ('empty chassis', 'E', (None,)),
                                ('data pipes, guard 0', 'ld', tuple(P)), ('CONTROL data pipes, guard 1', 'gd', tuple(P))):
        w = 0; runs = 0
        for dn in datas:
            for hk in ('on', 'off', 'mixed'):
                C, A = scene(lay, seats, cv, sil, L, data=P.get(dn), hook=hk)
                for mf0 in (0, 3):
                    ln = build(lay, C, A, mf0=mf0, inv=True)
                    b = sum(1 for k in range(8) if rx(ln, lay, skew=k, sup=False, stop_at_lock=True, inv=True)['false_lock'])
                    w = max(w, b)
                runs = 16
        print(f'   {label:32s} {w:>3d}/{runs}', flush=True)


# -------------------------------------------------------------------- gates
def _nand(*a):
    return 0 if all(a) else 1


def tx_gates(C, A, L, mf0=0, spare=0):
    """MF5 transmitter as the parts would do it.  Counters b (line bits) and m
    (frames); two 74HC151; one NAND; the spec 4.3 select and framing terms."""
    out = np.zeros(L * 8, np.uint8)
    m = mf0 & 7
    for f in range(L):
        m0, m1, m2 = m & 1, (m >> 1) & 1, (m >> 2) & 1
        T = _nand(m0, m1)                                             # 1,1,1,0
        sup = (A[0, f], A[1, f], A[2, f], 1, A[3, f], A[4, f], spare, 0)[(m2 << 2) | (m1 << 1) | m0]   # '151 no. 2
        for b in range(8):
            b0, b1, b2 = b & 1, (b >> 1) & 1, (b >> 2) & 1
            pay = (sup, C[0, f], C[1, f], C[2, f], C[3, f], C[4, f], 0, 0)[b]                           # '151 no. 1
            select = b1 & b2
            framing = b0 & T
            out[f * 8 + b] = framing if select else pay                                                  # '157
        m = (m + 1) & 7
    return out


def rx_gates(frames, lock_from, coast):
    """MF5 receiver multiframe logic as the parts would do it, fed whole frames
    at the framer's alignment.  r0..r3: the framer's T register (r0 newest).
    comb : q = (NAND(r2,r3), NAND(r1,r3));  marker latch;  '259 address (hl,q1,q0)
    coast: 74HC163 loaded when the register is valid, counting when it is not."""
    r = [0, 0, 0, 0]; hl = hv = 0; c = 0; lat = [0] * 8; out = []
    for f, fr_ in enumerate(frames):
        M, T = int(fr_[0]), int(fr_[7])
        valid = int(sum(r) == 3)                                      # the framer's 'exactly one 0' decode
        q0, q1 = _nand(r[1], r[3]), _nand(r[2], r[3])
        locked = f >= lock_from
        if coast:
            if locked and (c & 3) != 3:
                lat[c] = M                                            # '259: address c, data M
        else:
            if valid and (q1 & q0):
                hl = M; hv = 1                                        # marker latch, '74
            elif valid and hv and locked:
                lat[(hl << 2) | (q1 << 1) | q0] = M
            if not valid:
                hv = 0
        r = [T] + r[:3]                                               # the register shifts at T time
        if coast:
            v2 = int(sum(r) == 3)
            if v2:                                                    # '163 LOAD: next slot from the new register
                n0, n1 = _nand(r[1], r[3]), _nand(r[2], r[3])
                c2 = ((c >> 2) & 1) if r[0] else M                    # newest T = 0: this was a marker frame
                c = (c2 << 2) | (n1 << 1) | n0
            else:
                c = (c + 1) & 7
        out.append((lat[0], lat[1], lat[2], lat[4], lat[5]))
    return np.array(out, np.uint8).T


def do_gates(L=40000):
    rng = np.random.default_rng(3); lay = LAYOUTS['MF5']
    C = rng.integers(0, 2, (5, L)).astype(np.uint8); A = hooks_slow(5, L, 4000)
    same = all(np.array_equal(tx_gates(C, A, L, mf0=p, spare=sp), build(lay, C, A, mf0=p, spare=sp))
               for p in range(8) for sp in (0, 1))
    print(f'MF5 transmitter, gate level against the behavioural frame, 8 multiframe phases x 2 spare values, '
          f'{L} frames each: identical = {same}')
    print('MF5 receiver multiframe logic, gate level against the behavioural receiver (latch outputs, every locked frame):')
    for ber in (0.0, 1e-2, 3e-2):
        for p in (0, 5):
            ln = build(lay, C, A, mf0=p)
            if ber:
                e = link.impair(ln, ber=ber, seed=9); e[:8 * 200] = ln[:8 * 200]; ln = e   # clean while acquiring
            for coast in (False, True):
                st = rx(ln, lay, coast=coast)
                if st['lof_events']:
                    print(f'   BER {ber:g}: the framer reframed; comparison needs an unbroken lock'); continue
                g = rx_gates(ln.reshape(-1, 8), 32, coast)
                f0 = st['pos'] // 8
                bad = int((g[:, f0] != st['A']).sum())
                print(f'   BER {ber:<5g} multiframe phase {p}  {"coast" if coast else "comb ":5s}  '
                      f'{len(f0)} frames x 5 channels: {bad} differences', flush=True)

# ==== sections above ====
SECTIONS = {'core': do_core, 'locks': do_locks, 'tones': do_tones, 'tonesweep': do_tonesweep, 'tonee2e': do_tonee2e, 'slips': do_slips, 'sup': do_sup, 'rob': do_rob, 'enum': do_enum, 'strap': do_strap, 'gates': do_gates}

if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    for k, fn in SECTIONS.items():
        if what in (k, 'all'):
            fn()
            print()
