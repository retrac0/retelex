"""
The exchange of exch/docs: a fabric of 8-slot highways, a marker that hunts ports
by class in fixed order, and features that are lines.

    tandem    why the fabric switches bits and not voice band: N codecs in tandem
    fabric    the highway, cell by cell: commutate, select, capture, re-time
    calls     one exchange, tick by tick: the hotline rule, the release rule, the
              hunts for 0 and 9, registers as a pool, and what each party hears
    announce  a recorded message as a ROM image of CVSD bits, and its two seams
    aline     digits as serial characters on the A bit, through one to seven trunk hops
    flood     the timing of a network call: dial pulses on A, flooded and claimed
    monitor   the junctor monitor: which rules keep a flood from ever claiming a wrong number

The fabric is modelled at the cell (one highway slot, 1.95 us): a '151 puts port
k's bit on its block's highway during cell k; every port's '151 pair picks a
highway and a slot strobe, a flip-flop captures at mid-cell and a second re-times
at the frame edge.  The exchange is modelled at the 1 kHz tick, as the marker and
the release detectors would run: ports, latches, BUSY, class marks, cards that
behave (phones, tones, registers, announcements, conference legs, a CO line).

Usage:  python3 exch/exch.py            everything, ~7 min     (exch.log is the run)
        python3 exch/exch.py tandem     exch-protocol.md  §2
        python3 exch/exch.py fabric     exch-protocol.md  §4
        python3 exch/exch.py calls      exch-marker.md    §§3-6, exch-features.md
        python3 exch/exch.py announce   exch-features.md  §3
        python3 exch/exch.py aline      exch-network.md   §8
        python3 exch/exch.py flood      exch-network.md   §4
        python3 exch/exch.py monitor    exch-monitor.md   §5

The network of exch-network.md (`net`) is the second pass and is not here.
"""
import os, sys, time, zlib
import numpy as np
from scipy import signal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import audio, cvsd, mf8

RATE = 64000
P = mf8.params(RATE)
NB, NS = 8, 8                     # highways in a group, slots on a highway
NP = NB * NS                      # 64 ports, 00-77 octal


def oc(p):
    """A port as it is dialled: two octal digits."""
    return f'{p >> 3}{p & 7}'


def talker(j, secs, offset=0.0):
    x, fs = audio.read_wav(os.path.join(ROOT, f'talker{j}.wav'), seconds=secs + 0.5, offset=offset)
    x = audio.bandlimit(x, fs)
    x = x * (mf8.NOMINAL_RMS / max(x.std(), 1e-9))
    return audio.resample_to(x, fs, RATE)[:int(secs * RATE)]


# ------------------------------------------------------------------ tandem

def tandem():
    """N 64 kbps codecs in analog tandem: what a voice-band fabric costs per
    exchange, against a bit fabric where N stays 1 whatever the path."""
    SECS, NMAX = 12, 5
    print('TANDEM -- N codecs of mf8-spec 12.1 in analog tandem, 7 talkers x 12 s.')
    print('  Each stage: encode, decode, 3.4 kHz reconstruction; the next card filters 300-3400 Hz')
    print('  and is trimmed back to nominal level.  segSNR dB, two scorers:')
    print('    total  against the source: codec noise plus the droop of the cascaded filters')
    print('    codec  against the source through the same filters with no codec in the chain\n')
    T, C = [], []
    for j in range(1, 8):
        src = talker(j, SECS)
        sig, lin, t, c = src, src, [], []
        for n in range(NMAX):
            y = audio.reconstruct(cvsd.decode(cvsd.encode(sig, P), P), RATE)
            l = audio.reconstruct(lin, RATE)
            for ref, acc in ((src, t), (l, c)):
                a, b, _ = audio.align(ref, y)
                acc.append(audio.seg_snr_db(a, audio.gain_match(a, b), RATE))
            sig = audio.bandlimit(y, RATE); sig = sig * (mf8.NOMINAL_RMS / sig.std())
            lin = audio.bandlimit(l, RATE); lin = lin * (mf8.NOMINAL_RMS / lin.std())
        T.append(t); C.append(c)
        print(f'  talker{j}   total ' + ' '.join(f'{v:6.2f}' for v in t)
              + '    codec ' + ' '.join(f'{v:6.2f}' for v in c), flush=True)
    print(f'\n  {"codecs in the chain":>22s} ' + ' '.join(f'{n:7d}' for n in range(1, NMAX + 1)))
    for name, M in (('codec noise alone', C), ('against the source', T)):
        m = np.mean(M, 0)
        print(f'  {name:>22s} ' + ' '.join(f'{v:7.2f}' for v in m))
        print(f'  {"loss":>22s} ' + ' '.join(f'{v - m[0]:+7.2f}' for v in m))
    print('\n  Codecs in the chain, by fabric (a CVSD phone holds its own codec; an FXS card holds one):')
    print(f'  {"call":46s} {"voice band":>11s} {"bits":>6s}')
    for name, vf, bits in [
            ('CVSD phone to CVSD phone, one exchange', 2, 1),
            ('  ... across one MF8 trunk', 3, 1),
            ('  ... through a transit exchange', 4, 1),
            ('CVSD phone to analog phone, one exchange', 1, 1),
            ('analog phone to analog phone, one exchange', 0, 1),
            ('  ... across one MF8 trunk', 1, 1),
            ('  ... through a transit exchange', 2, 1),
            ('64 kbps data', 'cannot', 0)]:
        print(f'  {name:46s} {vf!s:>11s} {bits:6d}')


# ------------------------------------------------------------------ fabric

def fill(nf, f0=0):
    """FILL: TX_CLK / 2, one bit a frame alternating -- CVSD silence."""
    return ((np.arange(nf) + f0) & 1).astype(np.uint8)


def highway(ctx, atx, listen, writes=()):
    """The fabric, cell by cell.

    ctx, atx   [NP, nf]  what each card puts on C_TX / A_TX, changing on the frame edge.
                         A row of None is an empty slot: C pulled to FILL, A to 0.
    listen     [NP]      each port's latch: the address it listens to
    writes     [(cell, port, address)]  marker writes, at any cell

    Returns crx, arx [NP, nf]: what each card sees on C_RX / A_RX in each frame.
    Frame f's bit is captured at mid-cell of the SOURCE's slot and re-timed at the
    frame edge, so a card sees it throughout frame f+1 whatever the two slots are.
    """
    nf = max(len(c) for c in ctx if c is not None)
    F = fill(nf)
    C = np.array([F if c is None else c for c in ctx], np.uint8)
    A = np.array([np.zeros(nf, np.uint8) if a is None else a for a in atx], np.uint8)
    L = np.array(listen, np.int64).copy()
    cap_c = np.zeros(NP, np.uint8); cap_a = np.zeros(NP, np.uint8)
    crx = np.zeros((NP, nf), np.uint8); arx = np.zeros((NP, nf), np.uint8)
    W = {}
    for cell, port, addr in writes:
        W.setdefault(cell, []).append((port, addr))
    for f in range(nf):
        crx[:, f], arx[:, f] = cap_c, cap_a               # the re-timing flip-flops, clocked at the edge
        for k in range(NS):
            for port, addr in W.get(f * NS + k, ()):      # the marker writes before mid-cell
                L[port] = addr
            hw_c = C[k::NS, f]                            # each block's '151, all at input k
            hw_a = A[k::NS, f]
            hit = (L & 7) == k                            # the slot-strobe '151
            cap_c = np.where(hit, hw_c[L >> 3], cap_c)    # the highway '151, captured at mid-cell
            cap_a = np.where(hit, hw_a[L >> 3], cap_a)
    return crx, arx


def fabric():
    rng = np.random.default_rng(1)
    nf = 2048
    print('FABRIC -- the highway cell by cell: 8 slots x 64 kHz = 512 kbps a block, up to 8 blocks.')
    print(f'  {nf} frames a run, random data on every fitted port.\n')

    print('  1. Every source slot to every listening slot: 64 maps, port p listens to p+m (mod 64).')
    ctx = [rng.integers(0, 2, nf, dtype=np.uint8) for _ in range(NP)]
    atx = [rng.integers(0, 2, nf, dtype=np.uint8) for _ in range(NP)]
    err = pairs = 0
    for m in range(NP):
        L = (np.arange(NP) + m) % NP
        crx, arx = highway(ctx, atx, L)
        for p in range(NP):
            err += int(np.sum(crx[p, 1:] != ctx[L[p]][:-1])) + int(np.sum(arx[p, 1:] != atx[L[p]][:-1]))
            pairs += 1
    print(f'     {pairs} (source, listener) pairs, C and A: {err} bit errors at a delay of exactly 1 frame.')

    print('\n  2. Growth: random maps with 1 to 8 blocks fitted; an absent block or an empty slot is FILL / A=0.')
    print(f'     {"blocks":>7s} {"maps":>5s} {"bits checked":>13s} {"errors":>7s} {"listening to nothing":>21s}')
    for nb in range(1, NB + 1):
        e = nbits = hollow = 0
        for _ in range(8):
            fitted = [p < nb * NS and rng.random() < 0.85 and p != 0 for p in range(NP)]
            c = [rng.integers(0, 2, nf, dtype=np.uint8) if fitted[p] else None for p in range(NP)]
            a = [rng.integers(0, 2, nf, dtype=np.uint8) if fitted[p] else None for p in range(NP)]
            L = rng.integers(0, NP, NP)
            crx, arx = highway(c, a, L)
            F = fill(nf)
            for p in range(NP):
                s = L[p]
                want_c = c[s] if c[s] is not None else F
                want_a = a[s] if a[s] is not None else np.zeros(nf, np.uint8)
                e += int(np.sum(crx[p, 1:] != want_c[:-1])) + int(np.sum(arx[p, 1:] != want_a[:-1]))
                nbits += 2 * (nf - 1)
                hollow += c[s] is None
        print(f'     {nb:7d} {8:5d} {nbits:13d} {e:7d} {hollow:21d}')

    print('\n  3. Fan-out: 63 ports listen to port 25.')
    L = np.full(NP, 0o25)
    crx, _ = highway(ctx, atx, L)
    same = all(np.array_equal(crx[p], crx[0]) for p in range(NP))
    print(f'     all 64 received streams identical: {same};  errors against the source: '
          f'{int(np.sum(crx[:, 1:] != ctx[0o25][None, :-1]))}')

    print('\n  4. Idle: a cleared latch listens to port 00, which is never fitted.')
    c = list(ctx); a = list(atx); c[0] = a[0] = None
    crx, arx = highway(c, a, np.zeros(NP, np.int64))
    y = audio.reconstruct(cvsd.decode(np.tile(crx[5, 1:], 40), P), RATE)
    print(f'     C_RX is FILL (1010): {np.array_equal(crx[5, 1:], fill(nf)[:-1])};  A_RX is 0: {not arx.any()};  '
          f'decoded level {20 * np.log10(y[2000:].std() / mf8.NOMINAL_RMS + 1e-12):.1f} dB re nominal speech')

    print('\n  5. Octets: a source sends bytes b0-first on TX_OCT; the listener frames on RX_OCT = TX_OCT + 1 frame.')
    nby = nf // 8
    by = rng.integers(0, 256, nby, dtype=np.uint8)
    bits = np.unpackbits(by[:, None], axis=1, bitorder='little').reshape(-1)       # b0 first, state 0
    c = list(ctx); c[0o31] = bits
    L = np.arange(NP); L[0o52] = 0o31; L[0o07] = 0o31
    crx, _ = highway(c, atx, L)
    for p in (0o52, 0o07):
        got = np.packbits(crx[p, 1:1 + (nby - 1) * 8].reshape(-1, 8), axis=1, bitorder='little').reshape(-1)
        print(f'     port {oc(p)} <- 31: {nby - 1} octets, {int(np.sum(got != by[:nby - 1]))} wrong')
    got = np.packbits(crx[0o52, :(nby - 1) * 8].reshape(-1, 8), axis=1, bitorder='little').reshape(-1)
    print(f'     framed on TX_OCT instead (no delay allowed for): {int(np.sum(got != by[:nby - 1]))} of {nby - 1} wrong')

    print('\n  6. The marker re-points a latch at a random cell: 4000 writes.')
    n = 64
    cs = [x[:n] for x in ctx]; as_ = [x[:n] for x in atx]
    kinds = {'new source from the write frame on': 0, 'old source for the write frame, then new': 0,
             'one bit held over (neither slot strobed in the write frame), then new': 0, 'anything else': 0}
    for _ in range(4000):
        p, s0, s1 = (int(v) for v in rng.integers(1, NP, 3))
        cell = int(rng.integers(8 * 16, 8 * 48)); fw, k = divmod(cell, 8)
        L = np.zeros(NP, np.int64); L[p] = s0
        crx, _ = highway(cs, as_, L, writes=[(cell, p, s1)])
        got = crx[p, 1:]                                  # got[f] is what was captured in frame f
        old, new = ctx[s0][:n - 1], ctx[s1][:n - 1]
        if not (np.array_equal(got[:fw], old[:fw]) and np.array_equal(got[fw + 1:], new[fw + 1:])):
            kinds['anything else'] += 1
        elif (s1 & 7) >= k:
            kinds['new source from the write frame on'] += got[fw] == new[fw] or 0
        elif (s0 & 7) < k:
            kinds['old source for the write frame, then new'] += got[fw] == old[fw] or 0
        else:
            kinds['one bit held over (neither slot strobed in the write frame), then new'] += got[fw] == old[fw - 1] or 0
    for name, v in kinds.items():
        print(f'     {name:72s} {v:5d}')
    print(f'     accounted for: {sum(kinds.values()) - kinds["anything else"]} of 4000.  '
          f'The worst a re-point does is repeat one bit: the slip of mf8-backplane.md 7.')

    print('\n  7. A trunk block: six ports on slots 1,2,3,5,6,7 of highway 1 are an MF8 frame (mf8.build / mf8.framer).')
    nft = 8192
    src = [rng.integers(0, 2, nft, dtype=np.uint8) for _ in range(NP)]
    asrc = [np.repeat(rng.integers(0, 2, nft // 64 + 1, dtype=np.uint8), 64)[:nft] for _ in range(NP)]
    near = [0o20 + j for j in range(6)]                     # six callers at exchange X
    L = np.zeros(NP, np.int64)
    for j, b in enumerate(mf8.CBIT):
        L[0o10 + b] = near[j]                               # trunk port j listens to caller j
    cx, ax = highway(src, asrc, L)
    Ctx = [cx[0o10 + b] for b in mf8.CBIT]; Atx = [ax[0o10 + b] for b in mf8.CBIT]
    line = mf8.build(Ctx, Atx)
    at = 3000 * 8 + 3
    for name, ln, cut in (('clean', line, None), ('one line bit slipped at frame 3000', mf8.slip(line, at), at)):
        st = mf8.framer(ln)
        pos = st['pos']
        fi = (pos + (0 if cut is None else (pos >= cut))) // 8       # the frame each locked position was built as
        own = sum(int(np.sum(ln[pos + b] != Ctx[j][fi])) for j, b in enumerate(mf8.CBIT))
        bad = np.flatnonzero(np.any([ln[pos + b] != Ctx[j][fi] for j, b in enumerate(mf8.CBIT)], axis=0))
        span = f' (all in frames {fi[bad[0]]}-{fi[bad[-1]]}, before the framer let go)' if bad.size else ''
        other = np.mean([np.mean(ln[pos + b] != Ctx[(j + 1) % 6][fi]) for j, b in enumerate(mf8.CBIT)])
        Y = [None] * NP; YA = [None] * NP                            # and on through exchange Y's fabric
        for j, b in enumerate(mf8.CBIT):
            Y[0o10 + b] = ln[pos + b]; YA[0o10 + b] = np.zeros(pos.size, np.uint8)
        LY = np.zeros(NP, np.int64)
        for j, b in enumerate(mf8.CBIT):
            LY[0o40 + j] = 0o10 + b
        cy, _ = highway(Y, YA, LY)
        e = sum(int(np.sum(cy[0o40 + j, 1:] != Y[0o10 + b][:-1])) for j, b in enumerate(mf8.CBIT))
        print(f'     {name:36s} frames delivered {pos.size:5d} of {ln.size // 8}, re-frames {st["lof_events"]}; '
              f'bits wrong on their own port {own}{span}; against a neighbour\'s source {100 * other:.0f} %; '
              f'far fabric errors {e}')
    st = mf8.framer(line); pos = st['pos']; fi = pos // 8
    ea = 0
    for j, b in enumerate(mf8.CBIT):
        m = (fi & 7) == b                                   # A_j rides S at superframe state CBIT[j]
        ea += int(np.sum(line[pos[m] + mf8.SBIT] != Atx[j][fi[m]]))
    print(f'     A through the S bit, clean line: {ea} errors in {int(((fi & 7) != 0).sum() * 6 // 7)} samples')

    print('\n  8. A tie block: highway 7 of group X crossed to highway 7 of group Y, same clock, no framer.')
    LX = np.zeros(NP, np.int64); LYY = np.zeros(NP, np.int64)
    for k in range(NS):
        LX[0o70 + k] = 0o20 + k                             # junctor k listens to a caller in X
        LYY[0o30 + k] = 0o70 + k                            # a listener in Y listens to junctor k
    cx, ax = highway(src, asrc, LX)
    Y = [None] * NP; YA = [None] * NP
    for k in range(NS):
        Y[0o70 + k] = cx[0o70 + k]; YA[0o70 + k] = ax[0o70 + k]      # the crossover: X's C_RX is Y's C_TX
    cy, ay = highway(Y, YA, LYY)
    e = sum(int(np.sum(cy[0o30 + k, 2:] != src[0o20 + k][:-2])) + int(np.sum(ay[0o30 + k, 2:] != asrc[0o20 + k][:-2]))
            for k in range(NS))
    print(f'     8 junctors, C and A: {e} errors at a delay of exactly 2 frames (one per fabric)')


# ------------------------------------------------------------------ calls

UNEQ, LINE, OPER, EXT, TRUNK, DIAL, NOGO, REG = range(8)
CLASS = ['unequipped', 'line', 'operator', 'external', 'trunk', 'dial tone', 'cannot-complete', 'register']
T_FALL, T_RISE, TOL = 256, 16, 0.20          # release detector: fall, arm, RC tolerance
T_DTMF = 40                                   # MT8870 guard: tone present this long before StD
T_HIT, T_ID = 8, 128                          # register.md 2: a break is a pulse; a make ends the digit
T_NODIGIT = 10000                             # register held with nothing dialled
RING_ON, RING_OFF = 2000, 4000


class Card:
    cls = UNEQ
    name = ''
    def __init__(self): self.M = 0; self.key = None
    def step(self, ex, p, t): pass
    def sound(self): return 'silence'


class Tone(Card):
    def __init__(self, cls, name): super().__init__(); self.cls = cls; self.name = name
    def sound(self): return self.name


class Phone(Card):
    """A subscriber.  script: [(ms, 'off' | 'on' | 'key', digit)].  answer: ms of
    being rung before the hook lifts (None: never answers)."""
    def __init__(self, script=(), answer=None, cls=LINE, keylen=80):
        super().__init__(); self.cls = cls; self.script = sorted(script, key=lambda e: e[0])
        self.answer = answer; self.keylen = keylen; self.rung = 0; self.key_end = -1
    def step(self, ex, p, t):
        if self.key is not None and t >= self.key_end:
            self.key = None
        while self.script and self.script[0][0] <= t:
            _, what, *arg = self.script.pop(0)
            if what == 'off' or what == 'make': self.M = 1
            elif what == 'break': self.M = 0
            elif what == 'on': self.M = 0; self.rung = 0
            elif what == 'key': self.key = arg[0]; self.key_end = t + self.keylen
        if self.answer is not None and not self.M:
            self.rung = self.rung + 1 if ex.rung(p) else 0
            if self.rung >= self.answer:
                self.M = 1; self.answer = None
    def sound(self): return 'voice'


class Announce(Card):
    """A ROM message as a line: answers when rung, plays, drops M."""
    def __init__(self, cls=OPER, answer=300, play=3000, name='announcement'):
        super().__init__(); self.cls = cls; self.answer = answer; self.play = play
        self.name = name; self.rung = 0; self.left = 0
    def step(self, ex, p, t):
        if self.M:
            self.left -= 1
            if self.left <= 0 or not ex.E[p]:
                self.M = 0; self.rung = 0
        else:
            self.rung = self.rung + 1 if ex.rung(p) else 0
            if self.rung >= self.answer:
                self.M = 1; self.left = self.play
    def sound(self): return self.name


class Leg(Announce):
    """A meet-me conference leg: answers when rung and stays while the caller does."""
    def __init__(self): super().__init__(cls=LINE, answer=200, play=10 ** 9, name='conference')


class COLine(Card):
    """An FXO card on a CO line.  ring: [(ms on, ms off)] bursts from the CO.
    hold=True is the exchange build: A_TX = ringing, stretched across the cadence
    gap, OR loop closed.  hold=False is mf8-cards.md 3.5 as it stands: ringing only."""
    def __init__(self, ring=(), hold=True):
        super().__init__(); self.cls = EXT; self.ring = list(ring); self.hold = hold
        self.loop = 0; self.last_ring = -10 ** 9; self.answered = False
    def step(self, ex, p, t):
        self.loop = ex.E[p]                                  # A_RX closes the loop toward the CO
        self.answered |= bool(self.loop)
        ringing = (not self.answered) and any(a <= t < b for a, b in self.ring)
        if ringing: self.last_ring = t
        if self.hold:
            self.M = int(self.loop or t - self.last_ring < 5000)      # a retriggerable 5 s hold on ring detect
        else:
            self.M = int(ringing)
    def sound(self): return 'CO line'


class Register(Card):
    """A register as a line: it hears the caller through its own latch."""
    cls = REG
    def __init__(self):
        super().__init__(); self.cls = REG; self.heard = 0; self.done = False
        self.brk = self.make = self.count = 0
    def step(self, ex, p, t):
        src = ex.latch[p]
        if not src:
            self.brk = self.make = self.count = 0
        elif not ex.E[p]:                                    # the caller's hook, on this port's own A_RX
            self.brk += 1; self.make = 0
        else:
            if self.brk >= T_HIT: self.count += 1            # a break has just ended, and was a pulse
            self.brk = 0; self.make += 1
            if self.make == T_ID and self.count:
                ex.marker_digit(p, str(self.count % 10), t); self.count = 0
        k = ex.card[src].key if src else None
        if k is None:
            self.heard = 0; self.done = False
        else:
            self.heard += 1
            if self.heard >= T_DTMF and not self.done:
                self.done = True
                ex.marker_digit(p, k, t)
    def sound(self): return 'silence'


class Exchange:
    def __init__(self, cards, seed=1, log=True, tfall=None, settle=True, ringgate=True):
        self.card = [cards.get(p, Card()) for p in range(NP)]
        self.act = [p for p in range(NP) if type(self.card[p]) is not Card]
        self.settle, self.ringgate = settle, ringgate
        self.pinged = 0; self.killed = 0
        self.t_wr = [-1] * NP; self.t_fell = [[-1, -1] for _ in range(NP)]; self.was = [[0, 0] for _ in range(NP)]
        self.latch = [0] * NP; self.busy = [0] * NP
        self.E = [0] * NP
        rng = np.random.default_rng(seed)
        self.tf = [[tfall or int(T_FALL * (1 + TOL * (2 * rng.random() - 1))) for _ in range(2)] for _ in range(NP)]
        self.filt = [[0, 0] for _ in range(NP)]      # filtered M, filtered E
        self.cnt = [[0, 0] for _ in range(NP)]
        self.scan = 0
        self.calls = {}                              # register port -> [caller, digits, t of last event]
        self.t = 0
        self.log = log; self.watch = []; self.last = {}
        self.dangle = {}; self.max_dangle = 0; self.overhear = 0; self.events = []

    # -- what the hardware is
    def cls(self, p): return self.card[p].cls
    def inflight(self, p):
        """A release detector still timing out: its filter high, its input already low."""
        return self.settle and ((self.filt[p][0] and not self.card[p].M) or (self.filt[p][1] and not self.E[p]))
    def free(self, p): return not self.busy[p] and not self.card[p].M and not self.inflight(p)
    def rung(self, p):
        """On-hook with E high: the hotline rule's ring condition, before the cadence.
        ringgate: on-hook means the FILTERED hook too, so a phone just hung up is not rung."""
        return bool(self.E[p] and not self.card[p].M and not (self.ringgate and self.filt[p][0])
                    and self.cls(p) in (LINE, OPER))
    def ringing(self, p): return self.rung(p) and self.t % (RING_ON + RING_OFF) < RING_ON
    def hears(self, p):
        s = self.latch[p]
        if not s: return 'silence'
        c = self.card[s]
        if self.rung(s):
            return 'ringback'                         # RBT, substituted at the rung port
        if c.cls in (LINE, OPER, EXT, TRUNK):
            return f'{c.sound()} {oc(s)}' if c.M or c.cls == EXT else 'silence'
        return c.sound()

    # -- the marker
    def hunt(self, cls, free=True):
        for p in range(NP):                           # fixed order, from 00
            if self.cls(p) == cls and (not free or self.free(p)):
                return p
        return None
    def write(self, p, src, busy): self.latch[p] = src; self.busy[p] = busy; self.t_wr[p] = self.t
    def note(self, s):
        if self.log: self.events.append((self.t, s))
    def connect(self, a, b):
        self.write(a, b, 1); self.write(b, a, 1); self.note(f'marker: {oc(a)} <-> {oc(b)}')
    def nogo(self, a, why):
        n = self.hunt(NOGO, free=False)
        self.write(a, n or 0, 1); self.note(f'marker: {oc(a)} -> cannot-complete ({why})')
    def release_reg(self, r):
        self.write(r, 0, 0); self.calls.pop(r, None)
    def request(self, p):
        if self.cls(p) == EXT:                        # a CO line ringing in: as if it had dialled 0
            o = self.hunt(OPER)
            if o is not None: self.connect(p, o)
            return
        r = self.hunt(REG)
        if r is None:
            return                                    # no dial tone yet; the scanner comes round again
        d = self.hunt(DIAL, free=False)
        self.write(r, p, 1); self.write(p, d or 0, 1)
        self.calls[r] = [p, [], self.t]
        self.note(f'marker: register {oc(r)} -> {oc(p)}, dial tone from {oc(d) if d else "nowhere"}')
    def marker_digit(self, r, k, t):
        if r not in self.calls: return
        a, digits, _ = self.calls[r]
        digits.append(k); self.calls[r][2] = t
        if len(digits) == 1:
            self.write(a, 0, 1)                       # dial tone off at the first digit
            if k == '0' or k == '9':
                q = self.hunt(OPER if k == '0' else EXT)
                self.connect(a, q) if q is not None else self.nogo(a, f'no free class {2 if k == "0" else 3}')
            elif k not in '234567':
                self.nogo(a, f'first key {k}')
            else:
                return
        else:
            if k not in '01234567':
                self.nogo(a, f'second key {k}')
            else:
                q = int(digits[0]) * 8 + int(k)
                c = self.cls(q)
                if c in (UNEQ, REG): self.nogo(a, f'{oc(q)} is {CLASS[c]}')
                elif c in (DIAL, NOGO): self.write(a, q, 1)
                elif q == a or not self.free(q): self.nogo(a, f'{oc(q)} busy')
                else: self.connect(a, q)
        self.release_reg(r)

    # -- one tick
    def step(self):
        t = self.t
        for p in self.act:
            s = self.latch[p]; self.E[p] = self.card[s].M if s else 0
        for p in self.act:
            self.card[p].step(self, p, t)
        for p in self.act:                            # the release detectors, one pair a port
            for i, v in enumerate((self.card[p].M, self.E[p])):
                if self.was[p][i] and not v: self.t_fell[p][i] = t
                self.was[p][i] = v
                if v == self.filt[p][i]:
                    self.cnt[p][i] = 0
                    continue
                self.cnt[p][i] += 1
                if v and self.cnt[p][i] >= T_RISE:
                    self.filt[p][i] = 1; self.cnt[p][i] = 0
                elif not v and self.cnt[p][i] >= self.tf[p][i]:
                    self.filt[p][i] = 0; self.cnt[p][i] = 0
                    if self.latch[p] or self.busy[p]:
                        self.note(f'port {oc(p)} releases itself ({"ME"[i]} fell)')
                        if self.t_wr[p] > self.t_fell[p][i] + 1:
                            self.killed += 1          # the marker wrote this latch AFTER the fall being timed
                    self.latch[p] = 0; self.busy[p] = 0
        for r in [r for r in self.calls if not self.busy[r]]:
            self.calls.pop(r)                         # the caller went away and the register let go
        for r, (a, digits, t0) in list(self.calls.items()):
            if t - t0 > T_NODIGIT:
                self.nogo(a, 'nothing dialled'); self.release_reg(r)
        for _ in range(8):                            # the scanner: 8 ports a tick, 64 in 8 ms
            p = self.scan; self.scan = (self.scan + 1) % NP
            if (self.card[p].M and not self.busy[p] and not self.latch[p] and not self.inflight(p)
                    and self.cls(p) in (LINE, OPER, EXT)):
                self.request(p)
        for p in self.act:                            # who is listening to a party that is not listening back
            s = self.latch[p]
            if s and self.cls(p) != REG and self.cls(s) in (LINE, OPER, EXT, TRUNK) and self.latch[s] != p:
                self.dangle[p] = self.dangle.get(p, 0) + 1
                self.max_dangle = max(self.max_dangle, self.dangle[p])
                if self.busy[s] and self.cls(self.latch[s]) in (LINE, OPER, EXT, TRUNK) and self.card[s].M:
                    self.overhear += 1
            else:
                self.dangle.pop(p, None)
        for p in self.act:
            if self.E[p] and not self.card[p].M and self.filt[p][0] and self.cls(p) in (LINE, OPER):
                self.pinged += self.rung(p)           # rung within the release window of its own hang-up
        for p in self.watch:
            now = (self.hears(p), self.rung(p), self.busy[p])
            if now != self.last.get(p):
                self.last[p] = now
                self.note(f'{oc(p)} hears {now[0]}' + (', is being rung' if now[1] else '') + ('' if now[2] else ', free'))
        self.t += 1

    def run(self, ms, watch=()):
        self.watch = list(watch)
        self.last = {}
        for _ in range(ms):
            self.step()
        for t, s in self.events:
            print(f'       {t / 1000:7.3f}  {s}')
        stuck = [oc(p) for p in range(NP) if self.latch[p] or self.busy[p]]
        print(f'     end: {"every latch idle, every BUSY clear" if not stuck else "STUCK " + " ".join(stuck)};  '
              f'longest a port listened to a party no longer listening back {self.max_dangle} ms;  '
              f'overheard another call {self.overhear} ms')
        return not stuck


def layout(phones, regs=3, tones=True, extra=None):
    cards = {}
    if tones:
        cards[0o01] = Tone(DIAL, 'dial tone'); cards[0o02] = Tone(NOGO, 'cannot-complete tone')
    for k in range(regs):
        cards[0o03 + k] = Register()
    cards.update(phones)
    cards.update(extra or {})
    return cards


def keys(t, digits, gap=250):
    return [(t + k * gap, 'key', d) for k, d in enumerate(digits)]


def pulses(t, digits, pps=10.0, brk=0.60, pause=700):
    """A rotary dial: the hook broken n times a digit, ten for 0."""
    ev = []; per = 1000.0 / pps
    for d in digits:
        for _ in range(int(d) or 10):
            ev += [(int(t), 'break'), (int(t + per * brk), 'make')]; t += per
        t += pause
    return ev, int(t)


def calls():
    print('CALLS -- one exchange, one 1 kHz tick at a time.  Ports are dialled in octal, 00-77.')
    print('  00 idle (never fitted), 01 dial tone, 02 cannot-complete tone, 03-05 registers; subscribers 20-77.')
    print(f'  Release: M or E low for {T_FALL} ms (each port\'s two detectors +-{TOL:.0%}), after {T_RISE} ms high.  '
          f'Scanner: 8 ports a tick.\n')
    ok = True

    def scene(title, cards, ms, watch, **kw):
        nonlocal ok
        print(f'  {title}')
        ok &= Exchange(cards, **kw).run(ms, watch)
        print()

    P_ = Phone
    scene('1. A local call; the caller hangs up first, the called party stays off-hook and gets dial tone.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(9000, 'on')]),
                  0o21: P_([(12000, 'on')], answer=3000)}), 13500, [0o20, 0o21])
    scene('2. The called party hangs up first.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(11000, 'on')]),
                  0o21: P_([(8000, 'on')], answer=2500)}), 12500, [0o20, 0o21])
    scene('3. Busy: 22 calls 21 while 20 and 21 are talking.  Then 22 dials itself.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(9000, 'on')]),
                  0o21: P_([(9200, 'on')], answer=1500),
                  0o22: P_([(4000, 'off')] + keys(4800, '21') + [(6500, 'on'), (7000, 'off')] + keys(7800, '22')
                           + [(9000, 'on')])}), 10500, [0o22])
    scene('4. Numbers that are not there: 26 (empty slot), 1 (reserved), 8, 2 then 9, 03 cannot be dialled at all.',
          layout({0o20: P_([(100, 'off')] + keys(900, '26') + [(2500, 'on'), (3000, 'off')] + keys(3800, '1')
                           + [(5000, 'on'), (5500, 'off')] + keys(6300, '8') + [(7500, 'on'), (8000, 'off')]
                           + keys(8800, '29') + [(10500, 'on')])}), 11500, [0o20])
    scene('5. Abandoned while ringing: the called phone must stop ringing and be free.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(4000, 'on')]), 0o21: P_()}), 5500, [0o20, 0o21])
    scene('6. Abandoned while dialling: the register must let go by itself.',
          layout({0o20: P_([(100, 'off')] + keys(900, '2') + [(1500, 'on')])}), 3000, [0o20, 0o03])
    scene('7. Permanent signal: off-hook and nothing dialled.',
          layout({0o20: P_([(100, 'off'), (13000, 'on')])}), 14500, [0o20, 0o03])
    scene('8. Two callers dial each other at the same instant; and a called phone that lifts 3 ms before the test.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(3000, 'on'), (4000, 'off')] + keys(4800, '23')
                           + [(7000, 'on')]),
                  0o21: P_([(100, 'off')] + keys(900, '20') + [(3000, 'on')]),
                  0o23: P_([(5087, 'off'), (7000, 'on')])}), 8500, [0o20, 0o21, 0o23])

    ops = lambda first: {0o30: P_(first, answer=1500, cls=OPER), 0o31: P_([(9000, 'on')], answer=1500, cls=OPER),
                         0o32: Announce(OPER, play=2500, name='night announcement')}
    scene('9a. 0: the first operator is free.',
          layout({0o20: P_([(100, 'off')] + keys(900, '0') + [(6000, 'on')]), **ops([(6200, 'on')])}),
          7500, [0o20, 0o30, 0o31])
    scene('9b. 0: the first operator is in a call, so the hunt falls to the second position.',
          layout({0o20: P_([(3000, 'off')] + keys(3800, '0') + [(8000, 'on')]),
                  0o23: P_([(100, 'off')] + keys(900, '30') + [(9000, 'on')]), **ops([(9200, 'on')])}),
          10500, [0o20, 0o30, 0o31])
    scene('9c. 0: both positions off-hook, so the announcement card answers, plays and drops; the caller is back at dial tone.',
          layout({0o20: P_([(1000, 'off')] + keys(1800, '0') + [(8000, 'on')]),
                  0o30: P_([(100, 'off'), (8500, 'on')], cls=OPER), 0o31: P_([(100, 'off'), (8500, 'on')], cls=OPER),
                  0o32: Announce(OPER, play=2500, name='night announcement')}), 9500, [0o20, 0o32])
    scene('9d. 0 with no operator class fitted.',
          layout({0o20: P_([(100, 'off')] + keys(900, '0') + [(3000, 'on')])}), 4000, [0o20])

    scene('10. 9: two CO lines at 10 and 11, three callers.',
          layout({0o20: P_([(100, 'off')] + keys(900, '9') + [(7000, 'on')]),
                  0o22: P_([(1000, 'off')] + keys(1800, '9') + [(7000, 'on')]),
                  0o23: P_([(2000, 'off')] + keys(2800, '9') + [(7000, 'on')]),
                  0o10: COLine(), 0o11: COLine()}), 8500, [0o20, 0o22, 0o23])
    ring = [(500 + k * 6000, 2500 + k * 6000) for k in range(4)]
    scene('11a. A CO line rings in: routed as 0.  The exchange FXO build holds A_TX across the cadence gap and while the loop is closed.',
          layout({0o10: COLine(ring, hold=True), 0o30: P_([(14000, 'on')], answer=8000, cls=OPER)}),
          16000, [0o10, 0o30])
    scene('11b. The same with mf8-cards.md 3.5 as it stands (A_TX = ringing only): the call is torn down in every gap, and on answer.',
          layout({0o10: COLine(ring, hold=False), 0o30: P_([(14000, 'on')], answer=8000, cls=OPER)}),
          16000, [0o10, 0o30])

    scene('12a. The dial-tone card is pulled; a second class-5 card at 06 serves.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(5000, 'on')]), 0o21: P_([(5200, 'on')], answer=1000),
                  0o01: Card(), 0o06: Tone(DIAL, 'dial tone (spare)')}), 6500, [0o20])
    scene('12b. No tone cards at all: silence where the tones would be, and the call still completes.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(5000, 'on')]), 0o21: P_([(5200, 'on')], answer=1000)},
                 tones=False), 6500, [0o20])
    scene('13. One register, two callers lifting together: the second waits for dial tone.',
          layout({0o20: P_([(100, 'off')] + keys(1500, '24') + [(6000, 'on')]),
                  0o22: P_([(102, 'off')] + keys(3500, '25') + [(6000, 'on')]),
                  0o24: P_([(6200, 'on')], answer=1000), 0o25: P_([(6200, 'on')], answer=1000)}, regs=1),
          7500, [0o20, 0o22])
    scene('14. Meet-me: three callers dial the three legs at 70, 71, 72.',
          layout({0o20: P_([(100, 'off')] + keys(900, '70') + [(6000, 'on')]),
                  0o22: P_([(600, 'off')] + keys(1400, '71') + [(7000, 'on')]),
                  0o23: P_([(1100, 'off')] + keys(1900, '72') + [(8000, 'on')]),
                  0o70: Leg(), 0o71: Leg(), 0o72: Leg()}), 9500, [0o20, 0o22, 0o23])
    ev, end = pulses(900, '20', 10, 0.60)
    scene('15a. A rotary phone dials 20 on the A line: 10 pps, 60 % break.  The register counts its own A_RX; 0 is ten pulses.',
          layout({0o24: P_([(100, 'off')] + ev + [(end + 4000, 'on')]), 0o20: P_([(end + 4200, 'on')], answer=1500)}),
          end + 5500, [0o24, 0o20])
    ev, end = pulses(900, '27', 7, 0.72)
    scene(f'15b. The slowest dial register.md allows, 7 pps at 72 % (103 ms breaks), with every release detector at its shortest, {int(T_FALL * (1 - TOL))} ms.',
          layout({0o24: P_([(100, 'off')] + ev + [(end + 3000, 'on')]), 0o27: P_([(end + 3200, 'on')], answer=1000)}),
          end + 4500, [0o24, 0o27], tfall=int(T_FALL * (1 - TOL)))
    print(f'  Every scenario ended idle: {ok}\n')

    # ---- the two things the first run of this model found
    print('  16. 300 calls between random pairs; the two hang up within 600 ms of each other in random order, and a')
    print('      third party dials the first number freed, its last digit landing ~270 ms after that hang-up.')
    print(f'      Each port\'s two release detectors are drawn +-{TOL:.0%} about {T_FALL} ms, so one can still be timing')
    print('      out when the other has already freed the port.')
    print(f'      {"a port reads busy while a detector times out":46s} {"new calls killed by a stale release":>36s} '
          f'{"longest dangling listen ms":>27s} {"third party: connected / busy":>30s} {"not idle at 9 s":>16s} {"... not a register":>19s}')
    for settle in (False, True):
        rng = np.random.default_rng(7)
        worst = stuck = killed = conn = nogo = other = 0
        for n in range(300):
            a, b, c = (int(x) for x in rng.choice(np.arange(0o20, 0o100), 3, replace=False))
            t_a, t_b = (int(x) for x in rng.integers(5000, 5600, 2))
            ex = Exchange(layout({a: P_([(100, 'off')] + keys(900, oc(b)) + [(t_a, 'on')]),
                                  b: P_([(t_b, 'on')], answer=800),
                                  c: P_([(min(t_a, t_b) - 700, 'off')]
                                        + keys(min(t_a, t_b) + 50, oc(a if t_a < t_b else b), 180) + [(7500, 'on')])}),
                          seed=n, settle=settle)
            for _ in range(9000): ex.step()
            worst = max(worst, ex.max_dangle); killed += ex.killed
            left = [p for p in range(NP) if ex.latch[p] or ex.busy[p]]
            stuck += bool(left); other += any(ex.cls(p) != REG or p not in ex.calls for p in left)
            conn += any('<->' in e and oc(c) in e for _, e in ex.events)
            nogo += any('cannot-complete' in e and e.startswith(f'marker: {oc(c)}') for _, e in ex.events)
        print(f'      {"yes" if settle else "no":46s} {killed:36d} {worst:27d} {f"{conn} / {nogo}":>30s} {stuck:16d} {other:19d}')
    print('      Not idle at 9 s is always the same thing: the party left off-hook was given a register and hung up inside')
    print(f'      the detector\'s {T_RISE} ms arming time, so the register never saw E rise; the {T_NODIGIT // 1000} s no-digit timeout frees it.')
    print()
    print('  17. The hang-up ping: the caller of scenario 1 hangs up first while the other party is still off-hook.')
    print('      On-hook with E high is the ring condition, and it holds until the release fires.')
    print(f'      {"ring and RBT gated by the filtered hook":46s} {"caller rung (before cadence) ms":>32s} {"other party hears ringback ms":>30s}')
    for gate in (False, True):
        ex = Exchange(layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(9000, 'on')]),
                              0o21: P_([(12000, 'on')], answer=3000)}), ringgate=gate)
        rb = 0
        for _ in range(13500):
            ex.step()
            rb += ex.t > 9000 and ex.hears(0o21) == 'ringback'
        print(f'      {"yes" if gate else "no":46s} {ex.pinged:32d} {rb:30d}')
    print()

    # ---- registers as a pool: callers wait for dial tone
    print('  18. Registers under load: 48 lines, callers WAIT for a register (dial tone is late, not refused).')
    print('      200 000 calls a cell.  Holding = lift to last digit.')
    print(f'      {"calls/line/h":>13s} {"holding s":>10s} {"erlang":>7s} {"registers":>10s} {"delayed %":>10s} '
          f'{"mean wait of those s":>21s} {"wait > 1 s %":>13s} {"wait > 3 s %":>13s}')
    for rate in (3, 10):
        for hold in (4.0, 10.0):
            for c in (1, 2, 3):
                g = np.random.default_rng(3)
                n = 200000
                arr = np.cumsum(g.exponential(3600.0 / (48 * rate), n))
                svc = g.uniform(0.5 * hold, 1.5 * hold, n)
                free_at = [0.0] * c; w = np.zeros(n)
                for i in range(n):
                    k = min(range(c), key=free_at.__getitem__)
                    start = max(arr[i], free_at[k]); w[i] = start - arr[i]; free_at[k] = start + svc[i]
                d = w > 1e-9
                print(f'      {rate:13d} {hold:10.0f} {48 * rate * hold / 3600:7.2f} {c:10d} {100 * d.mean():10.2f} '
                      f'{(w[d].mean() if d.any() else 0):21.2f} {100 * (w > 1).mean():13.2f} {100 * (w > 3).mean():13.2f}')


# ------------------------------------------------------------------ announce

def announce():
    print('ANNOUNCE -- a recorded message as a ROM of CVSD bits: no codec on the card.')
    secs = 4.0
    x = talker(2, secs, offset=2.0)
    ramp = int(0.02 * RATE)
    w = np.ones(len(x)); w[:ramp] = 0.5 - 0.5 * np.cos(np.pi * np.arange(ramp) / ramp); w[-ramp:] = w[:ramp][::-1]
    pad = np.zeros(int(0.25 * RATE))
    msg = np.concatenate([pad, x * w, pad])
    img = cvsd.encode(msg, P)                                # the encoder starts from rest, as the burner's would
    rom = np.packbits(img)
    os.makedirs(os.path.join(ROOT, 'exch', 'out'), exist_ok=True)
    rom.tofile(os.path.join(ROOT, 'exch', 'out', 'announce.bin'))
    print(f'  message {secs:.1f} s + 0.25 s of silence each end = {len(img)} bits = {rom.size} bytes '
          f'(crc32 {zlib.crc32(rom.tobytes()):08x}); 8 kB a second, so 8 s fills a 64 kB part.')
    y = audio.reconstruct(cvsd.decode(img, P), RATE)
    a, b, _ = audio.align(msg, y)
    print(f'  played back through the decoder: segSNR {audio.seg_snr_db(a, audio.gain_match(a, b), RATE):.2f} dB '
          f'against the recording -- the codec\'s own figure, since the bits ARE the codec\'s.')
    print(f'  first and last 32 bits of the image: {"".join(map(str, img[:32]))} ... {"".join(map(str, img[-32:]))}\n')

    idle = int(0.5 * RATE)
    rms = x.std()
    db = lambda v: max(20 * np.log10(v / rms + 1e-30), -99.9)
    w20 = int(0.02 * RATE)
    print('  The seams.  The port sends FILL (1010) until it answers, then the image, then FILL again; a looping')
    print('  announcement joins the image\'s end to its start.  FILL free-runs, so the image can start on either')
    print('  phase of it.  Peak within 20 ms of the seam, dB re speech rms (-99.9 = nothing):')
    print(f'  {"seam":40s} {"in phase":>9s} {"a bit doubled":>14s}')
    first = int(img[0])
    for name, build, at in [
            ('idle -> image (the card answers)', lambda ok: np.concatenate([fill(idle, (first + idle + 1 - ok) & 1), img]), idle),
            ('image -> idle (the message ends)', lambda ok: np.concatenate([img, fill(idle, int(img[-1]) ^ ok)]), len(img)),
            ('image -> image (a loop)', lambda ok: np.concatenate([img, img[1 - ok:]]), len(img))]:
        pk = []
        for ok in (1, 0):
            y = audio.reconstruct(cvsd.decode(build(ok), P), RATE)
            pk.append(db(np.abs(y[at - w20:at + w20]).max()))
        print(f'  {name:40s} {pk[0]:9.1f} {pk[1]:14.1f}')
    print(f'  the image is {len(img)} bits, an even number, so a start in phase is an end in phase and a loop in phase:')
    print('  one gate that starts the address counter on the right half of FILL makes all three seams exact.\n')

    print('  An image cut out of running speech (no silence recorded round it): the decoder starts cold, with its')
    print('  integrator and its syllabic filter at idle while the recording\'s were not.')
    ref = audio.reconstruct(cvsd.decode(img, P), RATE)
    print(f'  {"cut at":>8s} {"error peak dB re speech rms":>28s} {"below -30 dB after ms":>22s}')
    for t0 in (0.8, 1.5, 2.2, 3.0):
        a0 = int(t0 * RATE) & ~1
        cut = img[a0:a0 + int(1.0 * RATE)]
        y = audio.reconstruct(cvsd.decode(np.concatenate([fill(idle, (int(cut[0]) + idle) & 1), cut]), P), RATE)
        err = np.abs(y[idle:idle + len(cut)] - ref[a0:a0 + len(cut)])[:int(0.5 * RATE)]
        over = np.flatnonzero(20 * np.log10(err / rms + 1e-30) > -30)
        print(f'  {t0:6.1f} s {db(err.max()):28.1f} {(over[-1] + 1) / RATE * 1000 if over.size else 0:22.1f}')


# ------------------------------------------------------------------ aline

FS_A = 8000                                   # A is one sample a superframe


def a_path(level, hops, ber, rng):
    """A through `hops` MF8 trunks.  Each hop: the S bit carries one sample a superframe, a line
    error flips it, the receiver's '259 holds it, then mf8-spec 14's RC (2 ms) and a 74HC14
    (0.55 / 0.35 of the swing, as mf8-cards.md 5 took them)."""
    k = 1 - np.exp(-1 / (FS_A * 0.002))
    for _ in range(hops):
        x = level ^ (rng.random(level.size) < ber)
        y = signal.lfilter([k], [1, -(1 - k)], x.astype(float), zi=[(1 - k) * float(level[0])])[0]
        hi, lo = y > 0.55, y < 0.35
        idx = np.where(hi | lo, np.arange(y.size), 0)
        np.maximum.accumulate(idx, out=idx)
        level = hi[idx].astype(np.uint8)
    return level


def chars(values, nd, tb):
    """Seized is mark.  A character: start (0), nd data bits MSB first, stop (1); back to back."""
    out = [np.ones(8 * tb, np.uint8)]
    for v in values:
        bits = [0] + [(v >> (nd - 1 - i)) & 1 for i in range(nd)] + [1]
        out.append(np.repeat(np.array(bits, np.uint8), tb))
    out.append(np.ones(8 * tb, np.uint8))
    return np.concatenate(out)


def receive(sig, nd, tb):
    """A start edge, confirmed at mid-bit; data at mid-bit; the stop bit must be mark."""
    got = []; i = 1; n = sig.size
    while i < n - (nd + 2) * tb:
        if sig[i] or not sig[i - 1]:
            i += 1; continue
        mid = i + tb // 2
        if sig[mid]:                                  # not a start bit: a hit
            i += 1; continue
        v = 0
        for b in range(nd):
            v = (v << 1) | int(sig[mid + (b + 1) * tb])
        stop = mid + (nd + 1) * tb
        got.append((i, v if sig[stop] else -1))       # -1: framing error
        i = stop if sig[stop] else stop + 1
    return got


def aline():
    rng = np.random.default_rng(5)
    N = 4000
    print('ALINE -- digits as serial characters on A: start, data bits, stop; seized is mark.')
    print('  A is sampled once a superframe (8 kHz) and crosses each trunk through a 2 ms RC and a Schmitt gate.\n')
    print('  1. What one hop does to a pulse (clean line): a 16 ms space and a 16 ms mark, as received.')
    print(f'     {"hops":>5s} {"space ms":>9s} {"mark ms":>8s} {"delay ms":>9s}')
    for hops in (1, 3, 7):
        x = np.ones(FS_A, np.uint8); x[2000:2128] = 0; x[4000:4256] = 0; x[4128:4256] = 1; x[4256:4384] = 0
        y = a_path(x, hops, 0.0, rng)
        e = np.flatnonzero(np.diff(y.astype(int)))
        print(f'     {hops:5d} {(e[1] - e[0]) / 8:9.2f} {(e[4] - e[3]) / 8:8.2f} {(e[0] + 1 - 2000) / 8:9.2f}')
    print(f'\n  2. Character errors in {N}, 3 data bits (octal), characters back to back.  A framing error counts.')
    print(f'     {"bit ms":>7s} {"4 digits ms":>12s} | ' + ' | '.join(f'{f"{h} hop" + ("s" if h > 1 else ""):^26s}' for h in (1, 3, 7)))
    print(f'     {"":>7s} {"":>12s} | ' + ' | '.join(' '.join(f'{b:>8s}' for b in ('clean', '1e-2', '6e-2')) for _ in range(3)))

    def errors(nd, tb_ms, hops, ber):
        tb = tb_ms * 8
        vals = rng.integers(0, 1 << nd, N)
        got = receive(a_path(chars(vals, nd, tb), hops, ber, rng), nd, tb)
        t0 = 8 * tb; per = (nd + 2) * tb; lag = hops * 15
        bad = 0; j = 0
        for k, v in enumerate(vals):
            want = t0 + k * per + lag
            while j < len(got) and got[j][0] < want - per // 2: j += 1
            if j < len(got) and abs(got[j][0] - want) <= per // 2 and got[j][1] == v:
                j += 1
            else:
                bad += 1
        return bad
    for tb_ms in (2, 4, 8, 16, 32):
        row = [' '.join(f'{errors(3, tb_ms, h, b):8d}' for b in (0.0, 1e-2, 6e-2)) for h in (1, 3, 7)]
        print(f'     {tb_ms:7d} {5 * tb_ms * 4:12d} | ' + ' | '.join(row))
    print(f'\n  3. The same with 4 data bits (the register\'s own code: 0-9, * and #), 7 hops.')
    print(f'     {"bit ms":>7s} {"4 digits ms":>12s} | ' + ' '.join(f'{b:>8s}' for b in ('clean', '1e-2', '6e-2')))
    for tb_ms in (8, 16, 32):
        print(f'     {tb_ms:7d} {6 * tb_ms * 4:12d} | ' + ' '.join(f'{errors(4, tb_ms, 7, b):8d}' for b in (0.0, 1e-2, 6e-2)))
    print('\n  4. Against the release rule: the longest space a character can hold, and the shortest release.')
    for nd in (3, 4):
        for tb_ms in (8, 16, 32):
            print(f'     {nd} data bits at {tb_ms:2d} ms: start + {nd} zeros = {(nd + 1) * tb_ms:4d} ms   '
                  f'against {int(T_FALL * (1 - TOL))} ms')
    print('\n  For scale: one dial pulse at 10 pps is 100 ms; the octal digit 0 is ten of them.')


# ------------------------------------------------------------------ monitor

G_ORIGIN = 128            # the origin abandons a call whose next break comes this soon after its seizure, ms
T_SCAN = 6                # a pooled monitor is given a seizure only within one scan of its rise, ms


def first_digit(y, i0, steady=False):
    """What a monitor counting from sample i0 takes as the first digit: breaks of T_HIT or more,
    ended by T_ID of make; None if the junctor releases first.  steady: the old rule - the monitor
    must see T_ID of unbroken make from the moment it attaches, or it is blind."""
    seg = y[i0:]
    if seg.size == 0 or (steady and not seg[0]):
        return None
    e = np.flatnonzero(np.diff(seg.astype(np.int8))) + 1
    starts = np.concatenate([[0], e]); lens = np.diff(np.concatenate([starts, [seg.size]])) / 8.0
    vals = seg[starts]
    if steady and lens[0] < T_ID:
        return None
    n = 0
    for v, L in zip(vals, lens):
        if not v:
            if L >= T_FALL: return None
            if L >= T_HIT: n += 1
        elif n and L >= T_ID:
            return n
    return None


def monitor():
    rng = np.random.default_rng(11)
    H, N = 7, 1500
    print('MONITOR -- which rules keep a live flood from ever claiming a wrong number.')
    print(f'  A chain: an origin and {H} exchanges whose exchange digits are 1..{H}.  A dial at 10 pps +-10 %, 60/40; the')
    print('  trigger digit, the exchange digit (1-7, or ten pulses for an exchange that is not there) and one more.')
    print('  The origin seizes 130 ms after the trigger\'s last pulse; each exchange patches the seizure onward 3-10 ms')
    print('  after its M rises; A crosses every hop through the trunk\'s A path (aline 1).  A claim cuts the onward patch.')
    print(f'  {N} calls a row.  FALSE = an exchange other than the one dialled claimed the call.\n')

    def dial(t, n, per):
        ev = []
        for _ in range(n):
            ev.append((t, t + 0.6 * per)); t += per
        return ev, ev[-1][1]

    def trial(pause_lo, pause_hi, rise_seen, origin_guard, ber):
        per = 100.0 * (1 + 0.1 * (2 * rng.random() - 1))
        e = int(rng.integers(1, 9)); e = 10 if e == 8 else e
        brk, end = dial(1000.0, 2, per)                        # the trigger digit
        t_sz = end + T_ID + T_MARK
        p1, p2 = rng.uniform(pause_lo, pause_hi, 2)
        b2, end2 = dial(end + p1, e, per)
        b3, end3 = dial(end2 + p2, int(rng.integers(2, 8)), per)
        n = int((end3 + 600) * 8)
        m = np.ones(n, np.uint8)
        for a, b in brk + b2 + b3:
            m[int(a * 8):int(b * 8)] = 0
        x = m.copy(); x[:int(t_sz * 8)] = 0
        if origin_guard and b2[0][0] - t_sz < G_ORIGIN:
            x[int(b2[0][0] * 8):] = 0                          # the origin abandons: the junctor falls and stays down
        claimers = []
        for j in range(1, H + 1):
            y = a_path(x, 1, ber, rng)
            up = np.flatnonzero(y)
            if up.size == 0: break
            rise = int(up[0])
            if rise_seen:
                late = rng.uniform(0, 600) if rng.random() < 0.2 else rng.uniform(0, T_SCAN)   # one monitor in five is busy
                got = first_digit(y, rise) if late <= T_SCAN else None
            else:
                got = first_digit(y, rise + int(rng.uniform(0, 600) * 8), steady=True)
            x = y.copy(); x[:rise + int(rng.uniform(3, 10) * 8)] = 0
            if got == j:
                claimers.append(j)
                # the claim: 2 ms after the digit is recognised the onward patch is cleared
                k = first_digit_end(y, rise)
                if k: x[k + int(T_MARK * 8):] = 0
        target = e if e <= H else None
        if any(c != target for c in claimers): return 'false'
        if target and not claimers: return 'none'
        return 'right'

    def first_digit_end(y, i0):
        seg = y[i0:]; e = np.flatnonzero(np.diff(seg.astype(np.int8))) + 1
        starts = np.concatenate([[0], e]); lens = np.diff(np.concatenate([starts, [seg.size]])) / 8.0
        n = 0
        for st, v, L in zip(starts, seg[starts], lens):
            if not v and L >= T_HIT: n += 1
            elif v and n and L >= T_ID: return i0 + int(st) + T_ID * 8
        return None

    print(f'  {"a monitor counts":44s} {"origin guard":>13s} {"pause between digits":>21s} {"line BER":>9s} | '
          f'{"right %":>8s} {"no claim %":>11s} {"FALSE":>6s}')
    rows = [(False, False), (True, False), (False, True), (True, True)]
    for rise_seen, guard in rows:
        for lo, hi in ((140, 900), (450, 900)):
            for ber in (0.0, 1e-2):
                if ber and not (rise_seen and guard): continue
                r = [trial(lo, hi, rise_seen, guard, ber) for _ in range(N)]
                name = 'only a seizure whose rise it saw' if rise_seen else 'from whenever it attaches, after 128 ms of make'
                print(f'  {name:44s} {"128 ms" if guard else "none":>13s} {f"{lo}-{hi} ms":>21s} {ber:9.0e} | '
                      f'{100 * r.count("right") / N:8.1f} {100 * r.count("none") / N:11.1f} {r.count("false"):6d}', flush=True)
    print('\n  "No claim" is the safe failure: the origin times out and returns cannot-complete.  In the rows where a')
    print('  monitor must have seen the rise, one monitor in five was busy at the seizure; with the origin guard, a caller')
    print('  whose next digit began within 258 ms of the last is abandoned too.  140 ms is the shortest pause ANY pulse')
    print('  register can read (register.md 3.2): below it two digits run together, flood or no flood.')

    print('\n  How many monitors a trunk block needs: one is wanted for ~1.1 s by every call in the district (flood 3).')
    print(f'  {"calls an hour in the district":>30s} {"erlang":>7s} | ' + ' '.join(f'{f"{k} busy %":>9s}' for k in (1, 2, 3)))
    for calls in (150, 576, 1500):
        a = calls * 1.1 / 3600
        b = [1.0]
        for k in range(1, 4): b.append(a * b[-1] / (k + a * b[-1]))
        print(f'  {calls:30d} {a:7.3f} | ' + ' '.join(f'{100 * v:9.2f}' for v in b[1:]))


# ------------------------------------------------------------------ flood

HOP = 7.0                 # a seizure crossing one exchange: A path 2 ms, scan of the trunk ports, marker
A_FALL, A_RISE = 2.0, 1.5 # the trunk's A path, per hop: mf8-cards.md 5, and `aline` 1
T_MARK = 2.0              # a marker action
GUARD = 200.0             # seizure to the sender's first break: the flood, then T_ID of steady make at every monitor
S_PER, S_BRK, S_PAUSE = 50.0, 30.0, 200.0     # the sender: 20 pps 60/40, 200 ms of make between digits


def npulses(d): return int(d) or 10


def caller(digits, how, t0=1000.0):
    """When the origin's register has each digit.  rotary: 10 pps 60/40, 800 ms from the last
    break to the next first break.  keypad: 100 ms tones 300 ms apart, StD 40 ms into the tone,
    written to the same store.  Returns [(start, end of signalling, recognised)]."""
    out = []; t = t0
    for d in digits:
        if how == 'rotary':
            end = t + (npulses(d) - 1) * 100 + 60
            out.append((t, end, end + T_ID)); t = end + 800
        else:
            out.append((t, t + 100, t + T_DTMF)); t += 300
    return out


def flood_call(number, own, chain, how, seize_at):
    """chain: exchange codes in order, origin first.  seize_at: the digit (1, 2 or 4) whose arrival
    seizes the junctors.  Returns the events and the figures of merit."""
    dg = caller(number, how)
    ev = [(0.0, 'lifts'), (10.0, 'register attached; dial tone'), (dg[0][0], f'dials {" ".join(number)}')]
    code = number[:2]
    r = [x[2] for x in dg]
    if code == own and seize_at >= 2:
        t = r[3] + T_MARK
        ev.append((t, f'own code: no flood.  Connected locally'))
        return ev, dict(pdd=t - dg[3][1], held={}, mon={})
    t_sz = r[seize_at - 1] + T_MARK
    ev.append((t_sz, f'digit {seize_at} is in: seize a junctor in each trunk block, listening to the sender'))
    J = chain.index(code) if code in chain else None
    nh = len(chain) - 1
    for j in range(1, nh + 1):
        ev.append((t_sz + HOP * j, f'  {chain[j]}: M rises; patched onward; monitor on'))
    # the sender: a digit goes when it is in the store, the junctors are up, and the last one is out
    q = []; last_end = None
    for i, d in enumerate(number):
        start = max(r[i] + T_MARK, t_sz + GUARD, (last_end + S_PAUSE) if last_end is not None else 0)
        end = start + (npulses(d) - 1) * S_PER + S_BRK
        q.append((start, end)); last_end = end
        ev.append((start, f'sender: {d}  ({npulses(d)} pulses, to {end:.0f})'))
        if code == own and i == 1:
            break
    if code == own:                                    # seize_at == 1 and the call was local all along
        t = r[1] + T_MARK
        ev.append((t, 'own code: the origin claims its own call and releases the junctors'))
        rel = t + T_FALL
        ev.append((rel, 'every flooded port has released itself'))
        t_loc = r[3] + T_MARK
        ev.append((t_loc, 'connected locally'))
        return ev, dict(pdd=t_loc - dg[3][1], held={f'{chain[j-1]}-{chain[j]}': rel - (t_sz + HOP * (j - 1)) for j in range(1, nh + 1)},
                        # the first digit is the district's and matches everywhere, so a monitor stays
                        # until the abandoned junctor releases under it
                        mon={chain[j]: rel - (t_sz + HOP * j) for j in range(1, nh + 1)})
    seen = lambda i, j: q[i][1] + A_RISE * j + T_ID    # digit i recognised at hop j
    mon = {}
    for j in range(1, nh + 1):
        k = 0 if chain[j][0] != code[0] else 1
        if j != J:
            ev.append((seen(k, j), f'  {chain[j]}: digit {k + 1} is not mine; monitor lets go'))
        mon[chain[j]] = seen(k if j != J else 3, j) - (t_sz + HOP * j)
    if J is None:
        t = q[3][1] + 2000
        ev.append((t, 'no claim in 2 s: cannot-complete tone'))
        return ev, dict(pdd=t - dg[3][1], held={}, mon=mon)
    t_claim = seen(1, J) + T_MARK
    ev.append((t_claim, f'  {chain[J]}: CLAIM; onward patch cleared; backward A = 1'))
    ev.append((t_claim + A_RISE * J, f'origin: backward A rises on the junctor'))
    if J < nh:
        ev.append((t_claim + A_FALL + T_FALL, f'  beyond {chain[J]}: ports have released themselves'))
    t_conn = seen(3, J) + T_MARK
    ev.append((t_conn, f'  {chain[J]}: has {number[2]} {number[3]}; junctor <-> line; the phone rings, RBT goes back'))
    t_cut = max(t_claim + A_RISE * J, q[3][1] + 5) + T_MARK
    ev.append((t_cut, 'origin: caller <-> junctor; register-sender freed'))
    heard = max(t_cut, t_conn)
    ev.append((heard, 'caller hears ringback'))
    held = {}
    for j in range(1, nh + 1):
        if j > J:
            held[f'{chain[j-1]}-{chain[j]}'] = t_claim + A_FALL + T_FALL - (t_sz + HOP * (j - 1))
    return ev, dict(pdd=heard - dg[3][1], held=held, mon=mon, reg=t_cut - 10.0)


def flood():
    chain = ['21', '22', '23', '24']
    print('FLOOD -- the timing of a network call.  Dial pulses on A, flooded, monitored and claimed.')
    print('  Arithmetic from measured constants, not a simulation of the gates:')
    print(f'    register windows HIT {T_HIT} / ID {T_ID} ms (register.md 2); MT8870 StD {T_DTMF} ms; A path per hop: a fall')
    print(f'    {A_FALL} ms, a rise {A_RISE} ms (aline 1); a seizure crosses an exchange in {HOP:.0f} ms; marker action {T_MARK:.0f} ms;')
    print(f'    sender 20 pps 60/40 with {S_PAUSE:.0f} ms between digits (register.md 3 read 20 pps; mf8-cards.md 5 carried it);')
    print(f'    guard, seizure to first break, {GUARD:.0f} ms; release {T_FALL} ms.  The caller starts dialling 1 s after dial tone.\n')

    print('  1. 2144 dials 2355 on 21 = 22 = 23 = 24.  A rotary caller; junctors seized when the FIRST digit is in.')
    ev, m = flood_call('2355', '21', chain, 'rotary', 1)
    for t, e in sorted(ev, key=lambda x: x[0]):
        print(f'     {t:8.0f}  {e}')
    print(f'     post-dial delay, caller\'s last pulse to ringback: {m["pdd"]:.0f} ms\n')

    print('  2. The same call, by where the junctors are seized and how the caller dials.')
    print(f'     {"caller":8s} {"seize at digit":>15s} {"post-dial delay ms":>19s} {"register-sender held s":>23s} '
          f'{"link 23-24 held ms":>19s} {"monitor at 22 / 23 / 24 held ms":>32s}')
    for how in ('rotary', 'keypad'):
        for k in (1, 2, 4):
            ev, m = flood_call('2355', '21', chain, how, k)
            mon = ' / '.join(f'{m["mon"][c]:.0f}' for c in chain[1:])
            print(f'     {how:8s} {k:15d} {m["pdd"]:19.0f} {m["reg"] / 1000:23.2f} {m["held"]["23-24"]:19.0f} {mon:>32s}')

    print('\n  3. A LOCAL call, 2144 dials 2155: what seizing at the first digit floods for nothing.')
    print(f'     {"caller":8s} {"seize at digit":>15s} {"every link held ms":>19s} {"a monitor at every exchange ms":>31s} {"local post-dial delay ms":>25s}')
    for how in ('rotary', 'keypad'):
        for k in (1, 2):
            ev, m = flood_call('2155', '21', chain, how, k)
            held = max(m['held'].values()) if m['held'] else 0
            mon = max(m['mon'].values()) if m['mon'] else 0
            print(f'     {how:8s} {k:15d} {held:19.0f} {mon:31.0f} {max(m["pdd"], 0):25.0f}')

    print('\n  4. The load of the flood itself.  4 exchanges x 48 lines x 3 calls an hour, a fifth of them to another')
    print('     exchange; erlangs of pure signalling on a link the call does not use (6 channels), and of monitor')
    print('     time at an exchange the call passes (taken as 22).')
    print(f'     {"caller":8s} {"seize at digit":>15s} {"link: local calls":>18s} {"network calls":>14s} {"total":>7s} '
          f'{"monitor: local":>15s} {"network":>8s} {"total":>7s}')
    calls = 4 * 48 * 3; net = 0.2
    for how in ('rotary', 'keypad'):
        for k in (1, 2, 4):
            _, ml = flood_call('2155', '21', chain, how, k)
            _, mn = flood_call('2355', '21', chain, how, k)
            loc = calls * (1 - net) * (max(ml['held'].values()) if ml['held'] else 0) / 3.6e6
            nw = calls * net * mn['held']['23-24'] / 3.6e6
            mloc = calls * (1 - net) * (ml['mon'].get('22', 0)) / 3.6e6
            mnw = calls * net * mn['mon']['22'] / 3.6e6
            print(f'     {how:8s} {k:15d} {loc:18.3f} {nw:14.3f} {loc + nw:7.3f} {mloc:15.3f} {mnw:8.3f} {mloc + mnw:7.3f}')

    print('\n  5. No sender: the junctors listen to the CALLER from the first digit, and his own remaining digits')
    print('     go down the flood live.  The first digit is the district\'s, the same at every exchange flooded, so')
    print('     nobody needs it again.  What must hold: every monitor is ready before his next digit begins.')
    print(f'     {"hops":>5s} | {"dial: ready after his last pulse, ms":>37s} {"margin at 500 / 800 ms between digits":>38s} | '
          f'{"keypad: ready after key release, ms":>36s} {"margin at a 200 ms gap":>23s}')
    for hops in (1, 3, 7):
        dial = T_ID + T_MARK + HOP * hops + T_ID          # digit recognised, seized, flooded, 128 ms of make seen
        keyp = T_MARK + HOP * hops                         # seized on the tone's end; a monitor needs only silence
        print(f'     {hops:5d} | {dial:37.0f} {f"{500 - dial:.0f} / {800 - dial:.0f}":>38s} | {keyp:36.0f} {200 - keyp:23.0f}')
    print('     A monitor that is not ready refuses to claim (128 ms of make not seen; or a tone already present):')
    print('     the call fails and is redialled; it is never a wrong number.')
    J = 2
    print(f'     Post-dial delay to exchange 23: dial {A_RISE * J + T_ID + T_MARK:.0f} ms after his last pulse, against '
          f'493 with a sender; keypad: connected {T_DTMF + T_MARK:.0f} ms into the last tone.')


    def live(number, domains, pause, label):
        """Live digits.  domains: [(who acts on this digit, hops the NEXT flood must cross)] for each digit
        after the first; None = nobody acts, the digit is simply heard."""
        dg = caller(number, 'rotary', t0=1000.0)
        if pause != 800:                                   # re-space the digits
            t = 1000.0; dg = []
            for d in number:
                end = t + (npulses(d) - 1) * 100 + 60
                dg.append((t, end, end + T_ID)); t = end + pause
        print(f'     {label}, {pause} ms between digits')
        print(f'     {"digit":>6s} {"its last pulse":>15s} {"acted on by":28s} {"next flood ready":>17s} {"next digit begins":>18s} {"margin ms":>10s}')
        worst = 1e9
        for i, d in enumerate(number):
            who, hops = domains[i]
            if who is None:
                print(f'     {d:>6s} {dg[i][1]:15.0f} {"-":28s}')
                continue
            ready = dg[i][1] + T_ID + T_MARK + HOP * hops + T_ID
            nxt = dg[i + 1][0] if i + 1 < len(number) else None
            m = nxt - ready if nxt else None
            if m is not None: worst = min(worst, m)
            print(f'     {d:>6s} {dg[i][1]:15.0f} {who:28s} {ready:17.0f} {nxt if nxt else 0:18.0f} {m if m is not None else 0:10.0f}')
        heard = dg[-1][1] + A_RISE * 2 + T_ID + T_MARK
        print(f'     the far phone rings {heard - dg[-1][1]:.0f} ms after the last pulse;  smallest margin {worst:.0f} ms\n')

    print('\n  6. Live, no sender: 2144 dials 2 3 5 5.  The origin acts on the first digit; exchange 23 on the second.')
    dom = [('origin 21: seize the flood', 3), ('exchange 23: claim', 0), (None, 0), (None, 0)]
    dom[1] = ('exchange 23: claim', 0)
    for pz in (800, 500):
        live('2355', [('origin 21: seize the flood', 3), (None, 0), (None, 0), (None, 0)], pz, '2 3 5 5')
    print('  7. Live, no sender: 1 8 3 2 3 5 5 -- long distance.  Each digit is acted on by one level, which patches')
    print('     the call into the next flood before the following digit.  Area codes begin with 8 or 9, which no')
    print('     exchange digit can be (they are 1-7 pulses, or ten), so a monitor knows a toll call by its first digit.')
    toll = [('origin: not my district: seize', 3), ('district toll gateway: claim', 2), ('area 83 gateway: claim', 2),
            ('district 2 gateway: claim', 3), ('exchange 23: claim', 0), (None, 0), (None, 0)]
    for pz in (800, 500):
        live('1832355', toll, pz, '1 8 3 2 3 5 5')


TARGETS = {'tandem': tandem, 'fabric': fabric, 'calls': calls, 'announce': announce, 'aline': aline, 'flood': flood, 'monitor': monitor}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        t0 = time.time()
        TARGETS[k]()
        print(f'\n  [{k}: {time.time() - t0:.0f} s]\n', flush=True)
