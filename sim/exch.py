"""
The exchange of exchange/: a fabric of 8-slot highways, a marker that hunts ports
by class in fixed order, and features that are lines.

    tandem    why the fabric switches bits and not voice band: N codecs in tandem
    fabric    the highway, cell by cell: commutate, select, capture, re-time
    calls     one exchange, tick by tick: the hotline rule, the release rule,
              answers-to hunt (0 → 04), class hunt for 9, registers as a pool, and what each party hears
    announce  a recorded message as a ROM image of CVSD bits, and its two seams
    aline     digits as serial characters on the A bit, through one to seven trunk hops
    flood     the timing of a network call: the key 1, live pulses, e and b, the claim
    monitor   the trunk monitor: which rules keep a flood from ever claiming a wrong number
    timing    the fabric's circuit in nanoseconds: strobes, capture, and what a card samples;
              then the same draws at 16 and 32 slots, 74HC and a 74AC highway path
    mainboard what a ribbon between the blocks costs those margins: clock skew, the line, the edges
    confer    a conference with no codec in it: the bridge switches bits to whoever is talking
    ss0       a common signalling channel: the number as one message a link, forward only
    net       eight exchanges call by call: the flood, the monitors, the claim, the registers,
              the channels, and what bursty demand does to a caller's wait for dial tone
    topo      chains, stars, trees and rings: what each carries, by arithmetic and call by call

The fabric is modelled at the cell (one highway slot, 1.95 us): a '151 puts port
k's bit on its block's highway during cell k; every port's '151 pair picks a
highway and a slot strobe, a flip-flop captures at mid-cell and a second re-times
at the frame edge.  The exchange is modelled at the 1 kHz tick, as the marker and
the release detectors would run: ports, latches, BUSY, class marks, cards that
behave (phones, tones, registers, announcements, conference legs, a CO line).

A network call is dialled `1 e b h s`: the key opens a pulse flood, the caller's
own `e` and `b` go down every trunk live, and the exchange they name claims
(network.md 3).  Local calls are `h s` and never touch a trunk.  `net` and `topo`
run that call by call; `flood` is the timing arithmetic; `monitor` is the two
rules that keep a wrong exchange from ever claiming.

Usage:  python3 sim/exch.py            everything, ~20 min    (exch.log is the run)
        python3 sim/exch.py tandem     protocol.md  §2
        python3 sim/exch.py fabric     protocol.md  §4
        python3 sim/exch.py calls      marker.md    §§3-6, features.md, mvp.md
        python3 sim/exch.py announce   features.md  §3
        python3 sim/exch.py aline      network.md   §9
        python3 sim/exch.py flood      network.md   §§3.1, 4
        python3 sim/exch.py net        network.md   §5.1
        python3 sim/exch.py topo       topology.md
        python3 sim/exch.py monitor    monitor.md   §5
        python3 sim/exch.py timing     fabric.md    §4, big-exchange.md §2
        python3 sim/exch.py mainboard  mainboard.md §5
        python3 sim/exch.py confer     conference.md
        python3 sim/exch.py ss0        ss0.md
"""
import heapq, itertools, os, sys, time, zlib
import numpy as np
from scipy import signal

ROOT = os.path.dirname(os.path.abspath(__file__))
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

UNEQ, LINE, OPER, EXT, TRUNK, DIAL, BUSY, NOGO = range(8)
CLASS = ['unequipped', 'line', 'operator', 'external', 'trunk', 'dial tone', 'busy', 'cannot-complete']
T_FALL, T_RISE, TOL = 256, 16, 0.20          # release detector: fall, arm, RC tolerance
T_DTMF = 40                                   # MT8870 guard: tone present this long before StD
T_HIT, T_ID = 8, 128                          # register.md 2: a break is a pulse; a make ends the digit
T_NODIGIT = 10000                             # register held with nothing dialled
RING_ON, RING_OFF = 2000, 4000
# Settled port map (protocol.md 5): 01 dial, 02 busy, 03 cannot-complete; registers take no port.


class Card:
    cls = UNEQ
    name = ''
    # Card-identity options (extensions.md §2.4).  Restricted is a flag here: the
    # calls model keeps the older class numbers (no fabric.md renumber), so dialling
    # limits live on the card rather than as class 111.
    priority = False
    overflow = False          # ignored: groups.md §2 replaced the o-run
    busy_out = False
    rings = True
    restricted = False
    z_only = False
    warm = False
    local_only = False
    nail = None
    answers_to = None         # port number this plain line covers (groups.md §2)
    def __init__(self): self.M = 0; self.key = None
    def step(self, ex, p, t): pass
    def sound(self): return 'silence'


class Tone(Card):
    def __init__(self, cls, name): super().__init__(); self.cls = cls; self.name = name
    def sound(self): return self.name


def _card_opts(card, priority=False, overflow=False, busy_out=False, rings=True,
               restricted=False, z_only=False, warm=False, local_only=False, nail=None,
               answers_to=None):
    """Apply extensions.md §2.4 options plus groups.md §2 answers_to.  Bare
    restricted floors to local-only when z and L are clear and warm is clear.
    overflow is accepted but ignored (the o-run is retired)."""
    card.priority = priority
    card.overflow = overflow
    card.busy_out = busy_out
    card.rings = rings
    card.restricted = restricted
    card.z_only = z_only
    card.warm = warm
    card.local_only = local_only
    card.nail = nail
    card.answers_to = answers_to
    if restricted and not z_only and not local_only and not warm:
        card.local_only = True
    return card


class Phone(Card):
    """A subscriber.  script: [(ms, 'off' | 'on' | 'key', digit)].  answer: ms of
    being rung before the hook lifts (None: never answers).  rings=False is /ANS
    low: E is steady and the phone answers without cadence/ringback."""
    def __init__(self, script=(), answer=None, cls=LINE, keylen=80,
                 priority=False, overflow=False, busy_out=False, rings=True,
                 restricted=False, z_only=False, warm=False, local_only=False, nail=None,
                 answers_to=None):
        super().__init__(); self.cls = cls; self.script = sorted(script, key=lambda e: e[0])
        self.answer = answer; self.keylen = keylen; self.rung = 0; self.key_end = -1
        _card_opts(self, priority, overflow, busy_out, rings,
                   restricted, z_only, warm, local_only, nail, answers_to)
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
            signaled = bool(ex.E[p]) if not self.rings else ex.rung(p)
            if signaled:
                self.rung += 1
                if self.rung >= self.answer:
                    self.M = 1; self.answer = None
            else:
                self.rung = 0
    def sound(self): return 'voice'


class Announce(Card):
    """A ROM message as a line: answers when rung, plays, drops M."""
    def __init__(self, cls=LINE, answer=300, play=3000, name='announcement',
                 priority=False, overflow=False, busy_out=False, rings=True,
                 restricted=False, z_only=False, warm=False, local_only=False, nail=None,
                 answers_to=None):
        super().__init__(); self.cls = cls; self.answer = answer; self.play = play
        self.name = name; self.rung = 0; self.left = 0
        _card_opts(self, priority, overflow, busy_out, rings,
                   restricted, z_only, warm, local_only, nail, answers_to)
    def step(self, ex, p, t):
        if self.M:
            self.left -= 1
            if self.left <= 0 or not ex.E[p]:
                self.M = 0; self.rung = 0
        else:
            signaled = bool(ex.E[p]) if not self.rings else ex.rung(p)
            if signaled:
                self.rung += 1
                if self.rung >= self.answer:
                    self.M = 1; self.left = self.play
            else:
                self.rung = 0
    def sound(self): return self.name


class Leg(Announce):
    """A meet-me conference leg: /ANS low, answers at once and stays while the caller does."""
    def __init__(self):
        super().__init__(cls=LINE, answer=0, play=10 ** 9, name='conference', rings=False)


class COLine(Card):
    """An FXO card on a CO line.  ring: [(ms on, ms off)] bursts from the CO.
    hold=True is the exchange build: A_TX = ringing, stretched across the cadence
    gap, OR loop closed.  hold=False is channel-cards.md 3.5 as it stands: ringing only."""
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


class Register:
    """A register in the common pool: no port.  It reads the caller's hook and
    DTMF key as the marker's probe does (marker.md 4)."""
    def __init__(self):
        self.caller = None; self.heard = 0; self.done = False
        self.brk = self.make = self.count = 0
    def attach(self, caller):
        self.caller = caller; self.heard = 0; self.done = False
        self.brk = self.make = self.count = 0
    def clear(self):
        self.caller = None; self.heard = 0; self.done = False
        self.brk = self.make = self.count = 0
    def step(self, ex, r, t):
        a = self.caller
        if a is None:
            return
        if not ex.card[a].M:
            self.brk += 1; self.make = 0
        else:
            if self.brk >= T_HIT: self.count += 1
            self.brk = 0; self.make += 1
            if self.make == T_ID and self.count:
                ex.marker_digit(r, str(self.count % 10), t); self.count = 0
        k = ex.card[a].key
        if k is None:
            self.heard = 0; self.done = False
        else:
            self.heard += 1
            if self.heard >= T_DTMF and not self.done:
                self.done = True
                ex.marker_digit(r, k, t)


class Exchange:
    def __init__(self, cards, regs=3, seed=1, log=True, tfall=None, settle=True, ringgate=True):
        self.card = [cards.get(p, Card()) for p in range(NP)]
        self.act = [p for p in range(NP) if type(self.card[p]) is not Card]
        self.regs = [Register() for _ in range(regs)]
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
        self.calls = {}                              # register index -> [caller, digits, t of last event]
        self.t = 0
        self.log = log; self.watch = []; self.last = {}
        self.dangle = {}; self.max_dangle = 0; self.overhear = 0; self.events = []

    # -- what the hardware is
    def cls(self, p): return self.card[p].cls
    def inflight(self, p):
        """A release detector still timing out: its filter high, its input already low."""
        return self.settle and ((self.filt[p][0] and not self.card[p].M) or (self.filt[p][1] and not self.E[p]))
    def free(self, p):
        """Free for terminating / hunt: not busy, on-hook, not settling; busy-out and
        a nail both count as not free (extensions.md §2.4, §3.1)."""
        c = self.card[p]
        if c.nail is not None or c.busy_out:
            return False
        return not self.busy[p] and not c.M and not self.inflight(p)
    def rung(self, p):
        """On-hook with E high: the hotline rule's ring condition, before the cadence.
        ringgate: on-hook means the FILTERED hook too, so a phone just hung up is not rung.
        rings=False (/ANS low): never the ring condition — no cadence, no ringback."""
        if not self.card[p].rings:
            return False
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
    def busy_tone(self, a, why):
        n = self.hunt(BUSY, free=False) or self.hunt(NOGO, free=False)
        self.write(a, n or 0, 1); self.note(f'marker: {oc(a)} -> busy ({why})')
    def release_reg(self, r):
        self.regs[r].clear(); self.calls.pop(r, None)
    def request(self, p):
        c = self.card[p]
        # CO line ringing in, or warm restricted: as if dialled 0 (probe 04), no register
        if self.cls(p) == EXT or (c.restricted and c.warm):
            self._probe_or_answers(p, 0o04)
            return
        r = next((i for i, reg in enumerate(self.regs) if reg.caller is None), None)
        if r is None:
            return                                    # no dial tone yet; the scanner comes round again
        d = self.hunt(DIAL, free=False)
        self.regs[r].attach(p)
        self.write(p, d or 0, 1)
        self.calls[r] = [p, [], self.t]
        self.note(f'marker: register {r} -> {oc(p)}, dial tone from {oc(d) if d else "nowhere"}')
    def _try_terminate(self, a, q):
        """Probe one port: free LINE/OPER/EXT → connect; tone → give it; else fail (False)."""
        c = self.cls(q)
        if c == UNEQ:
            return False
        if c in (DIAL, BUSY, NOGO):
            self.write(a, q, 1); return True
        if c not in (LINE, OPER, EXT):
            return False
        if q == a or not self.free(q):
            return False
        self.connect(a, q); return True
    def _probe_or_answers(self, a, q0):
        """groups.md §2.2: probe dialled q0; else first free port with answers_to == q0."""
        if self._try_terminate(a, q0):
            return
        for p in range(NP):
            if self.card[p].answers_to == q0 and self._try_terminate(a, p):
                return
        self.nogo(a, f'no answer to {oc(q0)}')
    def marker_digit(self, r, k, t):
        if r not in self.calls: return
        a, digits, _ = self.calls[r]
        digits.append(k); self.calls[r][2] = t
        caller = self.card[a]
        if len(digits) == 1:
            self.write(a, 0, 1)                       # dial tone off at the first digit
            # Restricted dialling limits (extensions.md §2.4): z wins; else L or floor.
            if caller.restricted:
                if caller.z_only and k != '0':
                    self.nogo(a, 'restricted 0-only'); self.release_reg(r); return
                if caller.local_only and k in '19':
                    self.nogo(a, 'restricted local-only'); self.release_reg(r); return
            if k == '0':                              # groups.md §2.2: called = 04, then answers-to
                self._probe_or_answers(a, 0o04)
            elif k == '9':
                q = self.hunt(EXT)
                self.connect(a, q) if q is not None else self.nogo(a, 'no free class 3')
            elif k == '1':                            # the network's key: seize a trunk.  The flood itself is
                q = self.hunt(TRUNK)                  # exch.py net; no scenario here fits a trunk card, so the
                self.nogo(a, 'no free class 4' if q is None else 'the flood is not modelled here')
            elif k not in '234567':                   # hunt finds nothing, as on a standalone exchange
                self.nogo(a, f'first key {k}')
            else:
                return
        else:
            if k not in '01234567':
                self.nogo(a, f'second key {k}')
            else:
                self._probe_or_answers(a, int(digits[0]) * 8 + int(k))
        self.release_reg(r)

    # -- one tick
    def step(self):
        t = self.t
        for p in self.act:
            s = self.latch[p]; self.E[p] = self.card[s].M if s else 0
        for p in self.act:
            self.card[p].step(self, p, t)
        for r, reg in enumerate(self.regs):
            reg.step(self, r, t)
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
        for r, (a, digits, t0) in list(self.calls.items()):
            if not self.busy[a]:
                self.release_reg(r)                   # the caller went away and the register let go
            elif t - t0 > T_NODIGIT:
                self.nogo(a, 'nothing dialled'); self.release_reg(r)
        for _ in range(8):                            # the scanner: 8 ports a tick, 64 in 8 ms
            p = self.scan; self.scan = (self.scan + 1) % NP
            nail = self.card[p].nail
            if nail is not None and not self.busy[p]:
                # Nail before call-request (extensions.md §3.1): write latch to partner.
                self.write(p, nail, 1)
                continue
            if (self.card[p].M and not self.busy[p] and not self.latch[p] and not self.inflight(p)
                    and self.cls(p) in (LINE, OPER, EXT)):
                self.request(p)
        for p in self.act:                            # who is listening to a party that is not listening back
            s = self.latch[p]
            if s and self.cls(s) in (LINE, OPER, EXT, TRUNK) and self.latch[s] != p:
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


def layout(phones, tones=True, extra=None):
    """Cards for the settled port map: tones at 01–03 when fitted; no register ports."""
    cards = {}
    if tones:
        cards[0o01] = Tone(DIAL, 'dial tone')
        cards[0o02] = Tone(BUSY, 'busy tone')
        cards[0o03] = Tone(NOGO, 'cannot-complete tone')
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
    print('  00 idle (never fitted), 01 dial, 02 busy, 03 cannot-complete; 04 operator pilot (groups.md §2);')
    print('  registers are a pool (no ports); subscribers 20-77 (standalone may use 10-17).')
    print(f'  Release: M or E low for {T_FALL} ms (each port\'s two detectors +-{TOL:.0%}), after {T_RISE} ms high.  '
          f'Scanner: 8 ports a tick.\n')
    ok = True

    def scene(title, cards, ms, watch, regs=3, **kw):
        nonlocal ok
        print(f'  {title}')
        ok &= Exchange(cards, regs=regs, **kw).run(ms, watch)
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
    scene('4. Numbers that are not there: 26 (empty slot), 1 (the network, with no network card), 8 (spare),\n'
          '     2 then 9, and 03, which cannot be dialled at all.',
          layout({0o20: P_([(100, 'off')] + keys(900, '26') + [(2500, 'on'), (3000, 'off')] + keys(3800, '1')
                           + [(5000, 'on'), (5500, 'off')] + keys(6300, '8') + [(7500, 'on'), (8000, 'off')]
                           + keys(8800, '29') + [(10500, 'on')])}), 11500, [0o20])
    scene('5. Abandoned while ringing: the called phone must stop ringing and be free.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(4000, 'on')]), 0o21: P_()}), 5500, [0o20, 0o21])
    scene('6. Abandoned while dialling: the register must let go by itself.',
          layout({0o20: P_([(100, 'off')] + keys(900, '2') + [(1500, 'on')])}), 3000, [0o20])
    scene('7. Permanent signal: off-hook and nothing dialled.',
          layout({0o20: P_([(100, 'off'), (13000, 'on')])}), 14500, [0o20])
    scene('8. Two callers dial each other at the same instant; and a called phone that lifts 3 ms before the test.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(3000, 'on'), (4000, 'off')] + keys(4800, '23')
                           + [(7000, 'on')]),
                  0o21: P_([(100, 'off')] + keys(900, '20') + [(3000, 'on')]),
                  0o23: P_([(5087, 'off'), (7000, 'on')])}), 8500, [0o20, 0o21, 0o23])

    # 0 → pilot 04; further positions answer_to 04 (groups.md §2)
    ops = lambda first: {0o04: P_(first, answer=1500),
                         0o31: P_([(9000, 'on')], answer=1500, answers_to=0o04),
                         0o32: Announce(play=2500, name='night announcement', answers_to=0o04)}
    scene('9a. 0: the operator at 04 is free.',
          layout({0o20: P_([(100, 'off')] + keys(900, '0') + [(6000, 'on')]), **ops([(6200, 'on')])}),
          7500, [0o20, 0o04, 0o31])
    scene('9b. 0: 04 is in a call (23 dialled 0 first), so the hunt falls to the second position (answers to 04).',
          layout({0o20: P_([(3000, 'off')] + keys(3800, '0') + [(8000, 'on')]),
                  0o23: P_([(100, 'off')] + keys(900, '0') + [(9000, 'on')]), **ops([(9200, 'on')])}),
          10500, [0o20, 0o04, 0o31])
    scene('9c. 0: 04 and the second position off-hook, so the announcement (answers to 04) plays and drops.',
          layout({0o20: P_([(1000, 'off')] + keys(1800, '0') + [(8000, 'on')]),
                  0o04: P_([(100, 'off'), (8500, 'on')]),
                  0o31: P_([(100, 'off'), (8500, 'on')], answers_to=0o04),
                  0o32: Announce(play=2500, name='night announcement', answers_to=0o04)}), 9500, [0o20, 0o32])
    scene('9d. 0 with nothing at 04 and no answers-to member.',
          layout({0o20: P_([(100, 'off')] + keys(900, '0') + [(3000, 'on')])}), 4000, [0o20])

    scene('10. 9: two CO lines at 10 and 11, three callers.',
          layout({0o20: P_([(100, 'off')] + keys(900, '9') + [(7000, 'on')]),
                  0o22: P_([(1000, 'off')] + keys(1800, '9') + [(7000, 'on')]),
                  0o23: P_([(2000, 'off')] + keys(2800, '9') + [(7000, 'on')]),
                  0o10: COLine(), 0o11: COLine()}), 8500, [0o20, 0o22, 0o23])
    ring = [(500 + k * 6000, 2500 + k * 6000) for k in range(4)]
    scene('11a. A CO line rings in: routed as 0 (probe 04).  The exchange FXO build holds A_TX across the cadence gap and while the loop is closed.',
          layout({0o10: COLine(ring, hold=True), 0o04: P_([(14000, 'on')], answer=8000)}),
          16000, [0o10, 0o04])
    scene('11b. The same with channel-cards.md 3.5 as it stands (A_TX = ringing only): the call is torn down in every gap, and on answer.',
          layout({0o10: COLine(ring, hold=False), 0o04: P_([(14000, 'on')], answer=8000)}),
          16000, [0o10, 0o04])

    scene('12a. The dial-tone card is pulled; a second class-5 card at 06 serves.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(5000, 'on')]), 0o21: P_([(5200, 'on')], answer=1000),
                  0o01: Card(), 0o06: Tone(DIAL, 'dial tone (spare)')}), 6500, [0o20])
    scene('12b. No tone cards at all: silence where the tones would be, and the call still completes.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(5000, 'on')]), 0o21: P_([(5200, 'on')], answer=1000)},
                 tones=False), 6500, [0o20])
    scene('13. One register, two callers lifting together: the second waits for dial tone.',
          layout({0o20: P_([(100, 'off')] + keys(1500, '24') + [(6000, 'on')]),
                  0o22: P_([(102, 'off')] + keys(3500, '25') + [(6000, 'on')]),
                  0o24: P_([(6200, 'on')], answer=1000), 0o25: P_([(6200, 'on')], answer=1000)}),
          7500, [0o20, 0o22], regs=1)
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
            stuck += bool(left); other += bool(left)
            conn += any('<->' in e and oc(c) in e for _, e in ex.events)
            nogo += any(('cannot-complete' in e or 'busy' in e) and e.startswith(f'marker: {oc(c)}')
                        for _, e in ex.events)
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
    print()

    # ---- the minimum exchange of mvp.md, as a whole
    ev1, _ = pulses(900, '21')
    ev2, _ = pulses(8800, '20')
    tries = []
    for t0, number in ((18000, '0'), (21500, '9'), (25000, '1'), (28000, '8'), (31500, '25'), (36000, '20')):
        ev, end = pulses(t0 + 800, number)
        tries += [(t0, 'off')] + ev + [(end + 600, 'on')]
    scene('19. The minimum exchange (mvp.md): rotary phones at 20 and 21, one register, no tone cards, nothing else.\n'
          '      20 calls 21 and 21 hangs up first; 21 calls 20 and 21 hangs up first again, so 20 is left off-hook;\n'
          '      then 20 dials the four first keys that find nothing here -- 0 (no operator), 9 (no outside line),\n'
          '      1 (no network card) and 8 (spare) -- and then 25 (an empty slot) and 20 (itself).',
          layout({0o20: P_([(100, 'off')] + ev1 + [(7000, 'on'), (16500, 'on')] + tries, answer=1500),
                  0o21: P_([(6000, 'on'), (8000, 'off')] + ev2 + [(15000, 'on')], answer=1500)}, tones=False),
          40500, [0o20, 0o21], regs=1)

    # ---- card-identity options (extensions.md §2.4) and answers-to (groups.md §2)
    scene('20. Answers-to hunt group: 21 and 22 answer to 20.\n'
          '      23 dials 20 while 20 and 21 are busy → connects to 22.',
          layout({0o20: P_([(100, 'off')] + keys(900, '24') + [(12000, 'on')]),
                  0o21: P_([(200, 'off')] + keys(1000, '25') + [(12000, 'on')], answers_to=0o20),
                  0o22: P_([(13000, 'on')], answer=1500, answers_to=0o20),
                  0o23: P_([(4000, 'off')] + keys(4800, '20') + [(11000, 'on')]),
                  0o24: P_([(12200, 'on')], answer=800),
                  0o25: P_([(12200, 'on')], answer=800)}), 14500, [0o23, 0o20, 0o21, 0o22])
    scene('21. Busy-out: 21 has b set.  20 dials 21 → cannot-complete (not free, no cover); then 21 lifts and dials 20 → connects.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(3500, 'on'), (8000, 'on')], answer=1500),
                  0o21: P_([(4000, 'off')] + keys(4800, '20') + [(10000, 'on')], busy_out=True)}),
          11500, [0o20, 0o21])
    scene('22. Restricted 0-only: 20 may only dial 0.  21 → cannot-complete; 0 → operator at 04.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(2500, 'on'), (3000, 'off')] + keys(3800, '0')
                           + [(7000, 'on')], restricted=True, z_only=True),
                  0o21: P_(),
                  0o04: P_([(7200, 'on')], answer=1500)}), 8500, [0o20, 0o04])
    scene('23. Restricted local-only: 20 cannot dial 9 or 1; a local call to 21 completes.\n'
          '      Bare restricted (no z, no L) floors to local-only the same way.',
          layout({0o20: P_([(100, 'off')] + keys(900, '9') + [(2500, 'on'), (3000, 'off')] + keys(3800, '21')
                           + [(8000, 'on')], restricted=True, local_only=True),
                  0o21: P_([(8200, 'on')], answer=1500),
                  0o10: COLine(),
                  0o22: P_([(100, 'off')] + keys(900, '9') + [(2500, 'on')], restricted=True)}),
          9500, [0o20, 0o21, 0o22])
    scene('24. Restricted warm: 20 lifts and is routed as 0 (probe 04) with no register (like a CO line ringing in).',
          layout({0o20: P_([(100, 'off'), (6000, 'on')], restricted=True, warm=True, z_only=True),
                  0o04: P_([(6200, 'on')], answer=1500)}), 7500, [0o20, 0o04])
    scene('25. Rings=False (/ANS low): 21 answers at once; caller hears silence, not ringback, until answer.',
          layout({0o20: P_([(100, 'off')] + keys(900, '21') + [(5000, 'on')]),
                  0o21: P_([(5200, 'on')], answer=0, rings=False)}), 6500, [0o20, 0o21])
    scene('26. Cover: 21 answers to 20.  22 dials 20 while 20 is busy → 21 rings.',
          layout({0o20: P_([(100, 'off')] + keys(900, '23') + [(10000, 'on')]),
                  0o21: P_([(11000, 'on')], answer=1500, answers_to=0o20),
                  0o22: P_([(4000, 'off')] + keys(4800, '20') + [(9000, 'on')]),
                  0o23: P_([(10200, 'on')], answer=800)}), 12500, [0o22, 0o20, 0o21])


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
    os.makedirs(os.path.join(ROOT, 'out'), exist_ok=True)
    rom.tofile(os.path.join(ROOT, 'out', 'announce.bin'))
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
    (0.55 / 0.35 of the swing, as channel-cards.md 5 took them)."""
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
T_SCAN = 8                # a pooled monitor is given a seizure within one scan of its rise, ms
                          # (eight slots on the 8 kHz octet mark: monitor.md 3)


def count_digits(y, i0, n=1, steady=False):
    """Digits a monitor counting from sample i0 takes: breaks of T_HIT or more, ended by T_ID of
    make; stops early if the trunk releases.  steady: the old rule -- T_ID of unbroken make from
    the moment it attaches, or it is blind.  Returns a list of up to n pulse counts."""
    seg = y[i0:]
    if seg.size == 0 or (steady and not seg[0]):
        return []
    e = np.flatnonzero(np.diff(seg.astype(np.int8))) + 1
    starts = np.concatenate([[0], e]); lens = np.diff(np.concatenate([starts, [seg.size]])) / 8.0
    vals = seg[starts]
    if steady and lens[0] < T_ID:
        return []
    out, pulses = [], 0
    for v, L in zip(vals, lens):
        if not v:
            if L >= T_FALL:
                return out
            if L >= T_HIT:
                pulses += 1
        elif pulses and L >= T_ID:
            out.append(pulses)
            if len(out) >= n:
                return out
            pulses = 0
    return out


def first_digit(y, i0, steady=False):
    d = count_digits(y, i0, 1, steady)
    return d[0] if d else None


def digit_end(y, i0, which=0):
    """Sample index at which digit `which` (0-based) is recognised, or None."""
    seg = y[i0:]
    e = np.flatnonzero(np.diff(seg.astype(np.int8))) + 1
    starts = np.concatenate([[0], e]); lens = np.diff(np.concatenate([starts, [seg.size]])) / 8.0
    n, seen = 0, 0
    for st, v, L in zip(starts, seg[starts], lens):
        if not v and L >= T_HIT:
            n += 1
        elif v and n and L >= T_ID:
            if seen == which:
                return i0 + int(st) + T_ID * 8
            seen += 1; n = 0
    return None


def delayed(level, ms):
    """A carrier that is not a pair.  `ms` of one-way delay, constant, ahead of the A path: what
    distance, a mux, a vocoder or a jitter buffer put between the two ends of a trunk.  A copper
    pair and an MF8 link are under a millisecond of it (`channel-cards.md` 5); a leased circuit, a
    radio or anything with a buffer is tens.  Constant delay does not distort a break -- it
    moves the whole of the caller's hook, pulses and all, later at the far end."""
    n = int(round(ms * 8))
    if n <= 0:
        return level
    return np.concatenate([np.full(n, level[0], dtype=level.dtype), level[:-n]])


def monitor():
    rng = np.random.default_rng(11)
    H, N, NS = 7, 1500, 1000
    print('MONITOR -- which rules keep a live flood from ever claiming a wrong number.')
    print(f'  A chain: an origin and {H} exchanges whose codes are 11..1{H} (shared e, distinct b).  A dial at')
    print('  10 pps +-10 %, 60/40; the key (1), then e and b (1-7, or ten pulses for a code that is not')
    print('  there), and one more.  A monitor compares BOTH digits (network.md 3, monitor.md 2).')
    print("  The origin seizes 130 ms after the key's last pulse; each exchange patches the seizure onward")
    print('  3-10 ms after its M rises; A crosses every hop through the trunk\'s A path (aline 1).  A claim')
    print(f'  cuts the onward patch.  {N} calls a row.  FALSE = an exchange other than the one dialled claimed.\n')

    def dial(t, n, per):
        ev = []
        for _ in range(n):
            ev.append((t, t + 0.6 * per)); t += per
        return ev, ev[-1][1]

    def trial(pause_lo, pause_hi, rise_seen, origin_guard, ber, carrier=0.0,
              guard_ms=G_ORIGIN, wander=0.0):
        per = 100.0 * (1 + 0.1 * (2 * rng.random() - 1))
        # key 1, then e and b (1-7 or ten), then a filler digit
        e = int(rng.integers(1, 9)); e = 10 if e == 8 else e
        b = int(rng.integers(1, 9)); b = 10 if b == 8 else b
        brk, end = dial(1000.0, 1, per)                        # the key: one pulse
        t_sz = end + T_ID + T_MARK
        p1, p2, p3 = rng.uniform(pause_lo, pause_hi, 3)
        be, end_e = dial(end + p1, e, per)
        bb, end_b = dial(end_e + p2, b, per)
        bf, end_f = dial(end_b + p3, int(rng.integers(2, 8)), per)
        n = int((end_f + 600) * 8)
        m = np.ones(n, np.uint8)
        for a, c in brk + be + bb + bf:
            m[int(a * 8):int(c * 8)] = 0
        x = m.copy(); x[:int(t_sz * 8)] = 0
        abandoned = origin_guard and be[0][0] - t_sz < guard_ms
        if abandoned:
            x[int(be[0][0] * 8):] = 0                          # the origin abandons: the trunk falls
        claimers = []
        for j in range(1, H + 1):
            y = a_path(delayed(x, carrier), 1, ber, rng)
            up = np.flatnonzero(y)
            if up.size == 0:
                break
            rise = int(up[0])
            own_e, own_b = 1, j                               # codes 11..1H
            if rise_seen:
                late = rng.uniform(0, 600) if rng.random() < 0.2 else rng.uniform(0, T_SCAN)
                got = count_digits(y, rise, 2) if late <= T_SCAN else []
            else:
                got = count_digits(y, rise + int(rng.uniform(0, 600) * 8), 2, steady=True)
            # The marker's own forwarding, and any delay the carrier LOSES between the
            # seizure and the next digit: both move the onward rise later against
            # a signal that is otherwise riding with it.
            x = y.copy(); x[:rise + int((rng.uniform(3, 10) + wander) * 8)] = 0
            if len(got) >= 2 and got[0] == own_e and got[1] == own_b:
                claimers.append(j)
                k = digit_end(y, rise, 1)                     # b recognised: clear the onward patch
                if k:
                    x[k + int(T_MARK * 8):] = 0
        target = b if e == 1 and b <= H else None
        if any(c != target for c in claimers):
            return 'false', abandoned
        if target and not claimers:
            return 'none', abandoned
        return 'right', abandoned

    print(f'  {"a monitor counts":44s} {"origin guard":>13s} {"pause between digits":>21s} {"line BER":>9s} | '
          f'{"right %":>8s} {"no claim %":>11s} {"FALSE":>6s}')
    rows = [(False, False), (True, False), (False, True), (True, True)]
    for rise_seen, guard in rows:
        for lo, hi in ((140, 900), (450, 900)):
            for ber in (0.0, 1e-2):
                if ber and not (rise_seen and guard):
                    continue
                r = [trial(lo, hi, rise_seen, guard, ber)[0] for _ in range(N)]
                name = 'only a seizure whose rise it saw' if rise_seen else 'from whenever it attaches, after 128 ms of make'
                print(f'  {name:44s} {"128 ms" if guard else "none":>13s} {f"{lo}-{hi} ms":>21s} {ber:9.0e} | '
                      f'{100 * r.count("right") / N:8.1f} {100 * r.count("none") / N:11.1f} {r.count("false"):6d}', flush=True)
    print('\n  "No claim" is the safe failure: the origin times out and returns cannot-complete.  In the rows where a')
    print('  monitor must have seen the rise, one monitor in five was busy at the seizure; with the origin guard, a caller')
    print('  whose next digit began within 258 ms of the last is abandoned too.  140 ms is the shortest pause ANY pulse')
    print('  register can read (register.md 3.2): below it two digits run together, flood or no flood.')
    print('  A second compared digit does not add a new way of attaching late -- the monitor is attached by then --')
    print('  but it does reject a partial count that landed on the wrong e before b is ever read.')

    # ---- a carrier that is not a pair -----------------------------------
    print('\n  A CARRIER THAT IS NOT A PAIR.  network.md 1.1 allows a carrier "about 2 ms of A path')
    print('  a hop".  A copper pair and an MF8 link are inside it; a leased circuit, a radio, a mux or a')
    print('  jitter buffer are tens of milliseconds.  The question rule 2 has to answer is whether that')
    print(f"  eats the origin's guard.  Both rules on, a pause of 140-900 ms, 128 ms guard, {NS} calls a row.")
    print(f'\n  {"carrier a hop":>14s} {"the flood is up at":>19s} | {"right %":>9s} {"no claim %":>11s} {"FALSE":>6s}')
    for carrier in (0, 5, 10, 20, 40, 80, 160):
        r = [trial(140, 900, True, True, 0.0, carrier) for _ in range(NS)]
        o = [v[0] for v in r]
        print(f'  {carrier:11d} ms {H * (6.5 + carrier):16.0f} ms | {100 * o.count("right") / NS:9.1f} '
              f'{100 * o.count("none") / NS:11.1f} {o.count("false"):6d}', flush=True)
    print("\n  IT DOES NOT.  A constant delay moves the whole of the caller's hook -- the seizure that")
    print('  opens the flood AND the pulses that follow it -- by the same amount, because they are the')
    print('  same wire.  An exchange seven hops out is patched in 600 ms later in absolute time and')
    print('  still sees the rise before the first break of `e`, because the break is 600 ms later too.')
    print('  **The two delays cancel exactly, and the guard never sees the carrier at all.**')

    print('\n  What DOES eat the guard is delay the carrier LOSES between the seizure and the next')
    print('  digit -- a buffer draining, a link re-timing -- because that moves the pulses forward')
    print('  against a rise that has already gone by.  A millisecond of it costs a millisecond of')
    print("  guard, exactly as the marker's own forwarding does.  Per hop, on top of the marker:")
    print(f'\n  {"wander a hop":>14s} {"spread":>8s} | {"guard 128 ms":^30s} | {"guard matched to the spread":^40s}')
    print(f'  {"":>14s} {f"over {H}":>8s} | {"right %":>9s} {"no claim %":>11s} {"FALSE":>6s} | '
          f'{"tap":>6s} {"a dial of 140-900":>18s} {"of 720-900":>17s}')
    print(f'  {"":>14s} {"":>8s} | {"":>9s} {"":>11s} {"":>6s} | {"":>6s} '
          f'{"FALSE":>6s} {"abandoned":>11s} {"FALSE":>6s} {"abandoned":>10s}')
    taps = (128, 256, 512, 1024)
    for w in (0, 2, 5, 10, 20, 40):
        sp = H * (6.5 + w)
        tap = next((t for t in taps if t >= sp), taps[-1])
        a = [trial(140, 900, True, True, 0.0, 0.0, G_ORIGIN, w) for _ in range(NS)]
        b = [trial(140, 900, True, True, 0.0, 0.0, tap, w) for _ in range(NS)]
        c = [trial(720, 900, True, True, 0.0, 0.0, tap, w) for _ in range(NS)]
        oa = [v[0] for v in a]; ob = [v[0] for v in b]; oc = [v[0] for v in c]
        print(f'  {w:11d} ms {sp:5.0f} ms | {100 * oa.count("right") / NS:9.1f} '
              f'{100 * oa.count("none") / NS:11.1f} {oa.count("false"):6d} | {tap:4d} ms '
              f'{ob.count("false"):6d} {100 * sum(v[1] for v in b) / NS:7.0f} % '
              f'{oc.count("false"):6d} {100 * sum(v[1] for v in c) / NS:7.0f} %', flush=True)
    print('\n  The guard must be at least the spread or it is not a guarantee, and no more than the')
    print(f"  caller's own pause less the {T_ID + T_MARK:.0f} ms the digit and the seizure take.  A phone to")
    print(f'  ES 201 187 gives at least 720 ms (register.md 2), so the guard may go to {720 - T_ID - T_MARK:.0f} ms -- the')
    print(f'  512 ms tap, four taps up from 128 on the counter it already has.  At {H} hops that is')
    print(f"  {512 / H - 6.5:.0f} ms a hop of wander against the present tap's {128 / H - 6.5:.0f}.  It is free in parts and it costs")
    print('  the callers who dial faster than the tap allows: every one of those gets cannot-complete.')

    print('\n  How many monitors a trunk block needs (monitor.md 4): held ~1.5 s if e is not ours, ~2.7 s if it is.')
    print(f'  {"calls an hour reaching the block":>34s} {"erlang @ 2.7 s":>14s} | ' + ' '.join(f'{f"{k} busy %":>9s}' for k in (1, 2, 3, 4)))
    for calls in (150, 576, 1500, 3000):
        a = calls * 2.7 / 3600
        busy = [1.0]
        for k in range(1, 5):
            busy.append(a * busy[-1] / (k + a * busy[-1]))
        print(f'  {calls:34d} {a:14.3f} | ' + ' '.join(f'{100 * v:9.2f}' for v in busy[1:]))


# ------------------------------------------------------------------ confer

WIN = 1024                    # a window of 16 ms at 64 kbps: TICK / 16


def run3(bits):
    """Runs of three equal bits: what drives a CVSD decoder's syllabic filter, so a measure of level
    that needs no decoder.  Three flip-flops and two gates; counted per window."""
    b = bits.astype(np.int8)
    e = np.concatenate([[0, 0], ((b[2:] == b[1:-1]) & (b[1:-1] == b[:-2])).astype(np.int32)])
    nw = len(e) // WIN
    return e[:nw * WIN].reshape(nw, WIN).sum(1)


def floor_run(spoke, hang):
    """The bridge, a window at a time.  spoke[k][w] = leg k's count reached the threshold in window w.
    A leg is silent once `hang` windows have gone by since it last spoke.  The holder keeps the floor
    until it is silent AND another leg asks; the first asker in slot order takes it.  No holder yet:
    the first leg to speak takes it."""
    L, nw = spoke.shape
    since = np.full(L, 10 ** 6)
    holder, out = -1, np.full(nw, -1, np.int8)
    for w in range(nw):
        since = np.where(spoke[:, w], 0, since + 1)
        ask = [k for k in range(L) if k != holder and spoke[k, w]]
        if ask and (holder < 0 or since[holder] >= hang):
            holder = ask[0]
        out[w] = holder
    return out


def confer():
    rng = np.random.default_rng(4)
    print('CONFER -- a conference bridge with no codec in it.  CVSD bits cannot be added, but they can be switched:')
    print('  each leg watches its caller\'s bits for speech, one leg holds the floor, and every other leg sends its')
    print('  caller the floor-holder\'s bits as they stand; the holder\'s own caller hears FILL.')
    print(f'  Speech detector: runs of three equal bits counted over a 16 ms window ({WIN} bits); "spoke" = the count')
    print('  reached a threshold.  No decoder, no RC: a shift register, two gates, a counter.\n')

    def noise(n, db):
        r = audio.bandlimit(rng.normal(0, 1, n), RATE)
        return r / r.std() * mf8.NOMINAL_RMS * 10 ** (db / 20)

    # 1 -- where to set the threshold
    SECS = 12.0
    n = int(SECS * RATE)
    print(f'  1. Windows reaching the threshold, % of all 16 ms windows.  Speech: talkers 1-4, {SECS:.0f} s each with')
    print('     their own pauses, plus room noise 45 dB below nominal speech; for speech the % of windows in which the')
    print('     talker\'s own 16 ms rms is within 30 dB of nominal is given alongside, as what "talking" means.')
    TH = (4, 8, 16, 32)
    print(f'     {"source":38s} ' + ' '.join(f'{f"{t} or more":>11s}' for t in TH) + f' {"talking":>9s}')
    for db in (0, -10, -20, -30):
        cnt, talk = [], []
        for j in range(1, 5):
            sp = talker(j, SECS) * 10 ** (db / 20)
            cnt.append(run3(cvsd.encode(sp + noise(n, -45), P)))
            e = sp[:len(cnt[-1]) * WIN].reshape(-1, WIN).std(1)
            talk.append(e > mf8.NOMINAL_RMS * 10 ** (-30 / 20))
        c, tk = np.concatenate(cnt), np.concatenate(talk)
        print(f'     {f"speech {db:+d} dB re nominal":38s} ' + ' '.join(f'{100 * np.mean(c >= t):11.1f}' for t in TH)
              + f' {100 * tk.mean():9.1f}')
    for db in (-20, -30, -40):
        c = run3(cvsd.encode(noise(4 * n, db), P))
        print(f'     {f"room noise alone, {db} dB":38s} ' + ' '.join(f'{100 * np.mean(c >= t):11.2f}' for t in TH))
    c = run3(fill(n * 2))
    print(f'     {"FILL (an idle leg)":38s} ' + ' '.join(f'{100 * np.mean(c >= t):11.2f}' for t in TH))
    TH0 = 8
    print(f'     -> threshold {TH0}: a counter\'s Q3.  Room noise 30 dB down reaches it once in a thousand windows, 40 dB')
    print('        down never; speech 20 dB down reaches it in a window in five, which the hangover (2) holds between.\n')

    # 2 -- a conversation
    SECS = 14.0
    n = int(SECS * RATE); nw = n // WIN; n = nw * WIN
    plan = {'A': (1, [(0.5, 4.5), (10.5, 12.0)]), 'B': (3, [(2.6, 3.0), (4.6, 8.5)]), 'C': (5, [(9.0, 13.0)])}
    names = list(plan)
    print(f'  2. Three callers, {SECS:.0f} s, room noise 45 dB down in every microphone.  A speaks 0.5-4.5 s; B says "mm-hm"')
    print('     at 2.6-3.0 s while A talks, then answers at 4.6 s, 100 ms after A stops, until 8.5 s; C speaks')
    print('     9.0-13.0 s, and A talks over C from 10.5 to 12.0 s.  Legs in slot order A, B, C.')
    bits, own, src, spoke = {}, {}, {}, []
    ramp = int(0.01 * RATE)
    for k in names:
        j, spans = plan[k]
        sp = talker(j, SECS)
        g = np.zeros(n)
        for a, b in spans:
            i0, i1 = int(a * RATE), int(b * RATE)
            g[i0:i1] = 1; g[i0:i0 + ramp] = np.linspace(0, 1, ramp); g[i1 - ramp:i1] = np.linspace(1, 0, ramp)
        src[k] = sp[:n] * g
        bits[k] = cvsd.encode(src[k] + noise(n, -45), P)
        own[k] = audio.reconstruct(cvsd.decode(bits[k], P), RATE)
        spoke.append(run3(bits[k]) >= TH0)
    spoke = np.array(spoke)

    def heard_by_others(fl):
        f = np.repeat(fl, WIN)
        f = np.concatenate([[-1], f[:-1]])                   # the decision at a window's end acts on the next bit
        mouth = fill(n)
        for q, k in enumerate(names):
            mouth = np.where(f == q, bits[k], mouth)
        return f, audio.reconstruct(cvsd.decode(mouth.astype(np.uint8), P), RATE)

    def carried(f, k, a, b):
        m = np.zeros(n, bool); m[int(a * RATE):int(b * RATE)] = True
        return 100 * (m & (f == names.index(k))).sum() / m.sum()

    def onset(k, a):
        i0 = int(a * RATE)
        return i0 + int(np.argmax(np.abs(src[k][i0:i0 + RATE]) > mf8.NOMINAL_RMS * 10 ** (-20 / 20)))

    print('\n     "switched" is the change of floor against the word\'s onset, the first sample within 20 dB of nominal:')
    print('     negative is before it.')
    print(f'     {"hangover":>9s} {"B\'s mm-hm heard":>16s} {"B\'s answer: switched":>22s} {"C\'s start: switched":>21s} '
          f'{"A over C heard":>15s} {"floor changes":>14s}')
    for hang in (4, 8, 16, 32):
        f, _ = heard_by_others(floor_run(spoke, hang))
        sw = np.flatnonzero(np.diff(f)) + 1
        def lost(k, a):
            got = sw[(f[sw] == names.index(k)) & (sw >= int(a * RATE) - RATE // 10)]
            return f'{(got[0] - onset(k, a)) / RATE * 1000:.0f} ms' if got.size else 'never'
        print(f'     {hang * 16:6d} ms {carried(f, "B", 2.6, 3.0):15.0f}% {lost("B", 4.6):>22s} {lost("C", 9.0):>21s} '
              f'{carried(f, "A", 10.5, 12.0):14.0f}% {len(sw):14d}')

    HANG = 8
    fl = floor_run(spoke, HANG)
    f, heard = heard_by_others(fl)
    sw = np.flatnonzero(np.diff(f)) + 1
    print(f'\n     At {HANG * 16} ms, every change of floor.  The listener\'s decoder was following the old holder (or FILL); from')
    print('     the switch it follows the new one.  Compared with the new holder\'s bits decoded all along:')
    print(f'     {"at":>8s} {"floor":>7s} {"switched":>12s} {"peak, heard / all along":>24s} {"error below -30 dB after":>25s}')
    for i in sw:
        q = f[i]
        k = names[q]
        a = max(a for a, b in plan[k][1] if a * RATE <= i + RATE // 10)
        rms = src[k][src[k] != 0].std()
        w = slice(i, i + int(0.02 * RATE))
        err = np.abs(heard[w] - own[k][w])
        over = np.flatnonzero(20 * np.log10(err / rms + 1e-30) > -30)
        print(f'     {i / RATE:7.3f}s {f"{names[f[i - 1]] if f[i - 1] >= 0 else chr(45)} -> {k}":>7s} '
              f'{(i - onset(k, a)) / RATE * 1000:9.0f} ms {20 * np.log10(np.abs(heard[w]).max() / np.abs(own[k][w]).max()):21.1f} dB '
              f'{(over[-1] + 1) / RATE * 1000 if over.size else 0:22.1f} ms')
    print()
    for q, k in enumerate(names):
        m = (f == q)
        for i in sw: m[i:i + int(0.02 * RATE)] = False
        e = heard[m] - own[k][m]
        tot = sum(b - a for a, b in plan[k][1])
        got = sum(carried(f, k, a, b) * (b - a) for a, b in plan[k][1]) / tot
        print(f'     {k}: {got:5.1f} % of its speech carried; what the others heard against its own decode, 20 ms clear of a '
              f'switch: {10 * np.log10(np.sum(own[k][m] ** 2) / max(np.sum(e ** 2), 1e-30)):5.1f} dB')
    os.makedirs(os.path.join(ROOT, 'out'), exist_ok=True)
    audio.write_wav(os.path.join(ROOT, 'out', 'confer_heard.wav'), audio.resample_to(heard, RATE, 8000) * 3, 8000)
    print('     sim/out/confer_heard.wav is what a caller who does not hold the floor hears.\n')

    # 3 -- two at once, over every pair of talkers
    SECS = 12.0
    n = int(SECS * RATE)
    tb = {j: cvsd.encode(talker(j, SECS) + noise(n, -45), P) for j in range(1, 8)}
    sp = {j: run3(tb[j]) >= TH0 for j in range(1, 8)}
    W = int(round(RATE / WIN))                                # windows a second, 62.5 -> 62
    print('  3. Two at once.  The holder talks for 5 s; from 1 s to 4 s another caller talks over it.  Every ordered pair')
    print('     of talkers 1-7, the interrupter\'s speech taken from 0, 3 and 6 s into its recording: 126 cases.')
    print('     Counted over the 3 s of double talk, from the detector\'s windows alone (the bits pass as in 2).')
    print(f'     {"hangover":>9s} {"floor changes, mean":>20s} {"most":>5s} {"interrupter carried":>20s} {"holder cut off":>15s}')
    for hang in (4, 8, 16, 32):
        ch, got, cut = [], [], []
        for i in range(1, 8):
            for j in range(1, 8):
                if i == j: continue
                for o in (0, 3, 6):
                    a = np.zeros(5 * W, bool); a[:] = sp[i][:5 * W]
                    b = np.zeros(5 * W, bool); b[W:4 * W] = sp[j][o * W:o * W + 3 * W]
                    fl = floor_run(np.array([a, b]), hang)[W:4 * W]
                    ch.append(np.count_nonzero(np.diff(fl)))
                    bb, aa = b[W:4 * W], a[W:4 * W]
                    got.append(100 * np.mean(fl[bb] == 1) if bb.any() else 0)
                    cut.append(100 * np.mean(fl[aa] == 1) if aa.any() else 0)
        print(f'     {hang * 16:6d} ms {np.mean(ch):20.1f} {max(ch):5d} {np.mean(got):19.0f}% {np.mean(cut):14.0f}%')

    # 4 -- the switch itself
    rng2 = np.random.default_rng(9)
    H = int(0.05 * RATE)
    print(f'\n  4. The switch itself.  The listener\'s decoder has followed the old holder and is switched, at a window\'s')
    print('     end, to the new one\'s bits; against the new holder decoded all along.  400 switches of talkers 1-7 each way:')
    print('       as the bridge does it   the old holder\'s detector silent for the 128 ms before; the new holder spoke')
    print('       if it did not wait      both spoke in the window that ends at the switch')
    print(f'     {"":24s} {"":34s} {"median":>8s} {"95 %":>8s} {"worst":>8s}')
    for how in ('as the bridge does it', 'if it did not wait'):
        settle, pk, er, tries = [], [], [], 0
        while len(settle) < 400 and tries < 10 ** 6:
            tries += 1
            i, j = rng2.choice(np.arange(1, 8), 2, replace=False)
            w = int(rng2.integers(12, len(sp[i]) - 4))
            if not sp[j][w - 1]: continue
            if how[0] == 'a' and sp[i][w - 8:w].any(): continue
            if how[0] == 'i' and not sp[i][w - 1]: continue
            t = w * WIN
            heard = audio.reconstruct(cvsd.decode(np.concatenate([tb[i][t - H:t], tb[j][t:t + H]]), P), RATE)[H:]
            ref = audio.reconstruct(cvsd.decode(tb[j][t - H:t + H], P), RATE)[H:]
            e = 20 * np.log10(np.abs(heard - ref) / mf8.NOMINAL_RMS + 1e-30)
            over = np.flatnonzero(e > -30)
            settle.append((over[-1] + 1) / RATE * 1000 if over.size else 0.0)
            er.append(e.max())
            m = int(0.02 * RATE)
            pk.append(20 * np.log10(np.abs(heard[:m]).max() / np.abs(ref[:m]).max()))
        for lab, v, u in (('error below -30 dB re nominal after', settle, 'ms'), ('largest error, re nominal', er, 'dB'),
                          ('peak in 20 ms, heard / all along', pk, 'dB')):
            print(f'     {how if lab[0] == "e" and lab[1] == "r" else "":24s} {lab:34s} '
                  + ' '.join(f'{x:5.1f} {u:2s}' for x in np.percentile(v, [50, 95, 100])))


# ------------------------------------------------------------------ timing

CELL = 1e9 / 512e3            # 1953.1 ns; HCLK is high for the first half of a cell
HC = {                        # 74HC at 4.5 V: (typical, maximum over -40..85 C), ns, from the data sheets' tables
    '163 clk-Q': (18, 43), '175 clk-Q': (17, 43), '138 A-Y': (15, 40), '138 E-Y': (17, 45),
    '151 S-Y': (25, 63), '151 I-Y': (19, 47), '151 I-W': (21, 50), '157 I-Y': (13, 31), '157 S-Y': (15, 38),
    '244': (10, 28), '74 clk-Q': (16, 44), 'card clk-C_TX': (20, 50), 'wire': (2, 12),
    '32 I-Y': (9, 22)}        # extra OR on a 16:1 or 32:1 built from '151s
T_SU, T_H = 20.0, 5.0         # a 74HC74's set-up and hold, worst case
# 74AC at 5.0 V ± 0.5 V, −40..85 C, 50 pF (Fairchild / ON / ST, same parts as HC).
# Channel cards stay 74HC: 'card clk-C_TX' is never taken from this table.
AC = {
    '163 clk-Q': (6.5, 11), '175 clk-Q': (6.0, 9.5), '138 A-Y': (6.5, 10.5), '138 E-Y': (6.5, 11.5),
    '151 S-Y': (8.5, 12.5), '151 I-Y': (6.0, 10.0), '151 I-W': (6.5, 10.5),
    '157 I-Y': (5.0, 9.0), '157 S-Y': (5.5, 9.5),
    '244': (4.0, 8.0), '74 clk-Q': (5.0, 10.0), '32 I-Y': (3.5, 7.5), 'wire': (2, 12)}
T_SU_AC, T_H_AC = 3.0, 1.0    # a 74AC74's set-up and hold, worst case


def timing():
    rng = np.random.default_rng(2)
    N = 400000
    def d(name):               # every part in every trial is its own draw, from a third of typical to the maximum
        t, m = HC[name]
        return rng.uniform(0.35 * t, m, N)
    print('TIMING -- the fabric in nanoseconds.  512 kbps: a cell is 1953 ns, HCLK high for its first half.')
    print('  Every delay in every trial drawn on its own between 0.35 x typical and the data-sheet maximum')
    print(f'  (74HC, 4.5 V, -40..85 C); {N} trials; the figure is the WORST seen.  Times from the start of the cell.\n')

    # data onto a listener's capture flip-flop: two ways a highway bit can change
    clkX, clkY = d('244'), d('244')                   # each block buffers the clocks it is given
    via_card = clkX + d('card clk-C_TX') + d('157 I-Y') + d('151 I-Y') + d('244') + d('wire') + d('244') + d('151 I-Y')
    via_count = d('163 clk-Q') + d('wire') + clkX + d('151 S-Y') + d('244') + d('wire') + d('244') + d('151 I-Y')
    valid = np.maximum(via_card, via_count)
    first_change = np.minimum(via_card, via_count)
    print('  1. A highway bit at a listener\'s capture flip-flop: card or RBT mux -> commutator -> driver -> mainboard')
    print('     -> the listening block\'s receiver -> the port\'s highway select.')
    print(f'       valid by {valid.max():6.0f} ns        (typical {np.median(valid):.0f})')

    # the strobe: '138 enabled while HCLK is low, its address the slot count delayed a quarter cell
    addr = CELL / 4 + d('175 clk-Q') + d('wire') + d('244') + d('138 A-Y')
    en = CELL / 2 + clkY + d('138 E-Y')
    cap = en + d('151 I-W')                           # the port's strobe select; W is the capture clock
    print('\n  2. The capture clock: a \'138 enabled while HCLK is low, addressed by the slot count DELAYED A QUARTER')
    print('     CELL, so its address only ever moves while it is disabled; the port\'s \'151 picks one line, W clocks.')
    print(f'       address settled {(CELL / 2 - addr).min():6.0f} ns before the enable, and moves {(CELL / 4 - (clkY + d("138 E-Y") - 0)).min():6.0f} ns after the disable')
    print(f'       capture clock rises at {cap.min():6.0f} - {cap.max():.0f} ns')
    print(f'       set-up at the flip-flop {(cap - valid - T_SU).min():6.0f} ns;  hold {(CELL + first_change - cap - T_H).min():6.0f} ns')

    # the same decoder addressed by the undelayed count: does the next line glitch as the cell turns over?
    new_addr = d('163 clk-Q') + d('wire') + d('244') + d('138 A-Y')
    off = clkY + d('138 E-Y')
    g = off - new_addr
    print('\n  3. The same decoder addressed by the count as it stands: at the turn of the cell the new address can')
    print('     arrive before the disable does, and the NEXT port\'s line pulses low with nothing settled.')
    print(f'       in {100 * (g > 0).mean():.1f} % of trials; wider than 8 ns in {100 * (g > 8).mean():.1f} %; worst {g.max():.0f} ns.'
          f'  Typical parts: {HC["244"][0] + HC["138 E-Y"][0] - (HC["163 clk-Q"][0] + HC["wire"][0] + HC["244"][0] + HC["138 A-Y"][0])} ns, no pulse.')
    print('       It is only a hazard across the spread, which is exactly the kind not to build on.')

    # what the card sees: it samples C_RX at the frame edge; captures are all at mid-cell
    q = cap + d('74 clk-Q')
    cardclk = clkY + d('wire')
    print('\n  4. No re-timing flip-flop.  Every capture is at the middle of some cell, so nothing a card is given')
    print('     changes within half a cell of the frame edge, where every card samples (RX_CLK = TX_CLK here).')
    print(f'       a source in slot 7: C_RX settled {(CELL + cardclk - q - T_SU).min():6.0f} ns before the card samples')
    print(f'       a source in slot 0: C_RX moves   {(cap + 0.35 * HC["74 clk-Q"][0] - cardclk - T_H).min():6.0f} ns after it')
    print('     A bit sent in frame f is sampled at the edge that begins f+1 whatever the two slots: one frame,')
    print('     as `fabric` 1 measured, which already models the card as sampling at that edge.')

    # the economy: C in the first half of the cell and A in the second, on one wire
    mux = CELL / 2 + clkX + d('157 S-Y') + d('151 I-Y') + d('244') + d('wire') + d('244') + d('151 I-Y')
    capC = CELL / 4 + clkY + d('138 E-Y') + d('151 I-W')      # strobe high for the middle half of the cell
    capA = 3 * CELL / 4 + clkY + d('138 E-Y') + d('151 I-Y')
    swap = CELL / 2 + 0.35 * (HC['244'][0] + HC['157 S-Y'][0] + HC['151 I-Y'][0] + 2 * HC['244'][0] + HC['wire'][0] + HC['151 I-Y'][0])
    print('\n  5. The economy form: C in the first half of the cell and A in the second on ONE highway wire, captured')
    print('     on the two edges of a strobe that is high for the middle half (the \'151 gives both senses).')
    print(f'       C: set-up {(capC - valid - T_SU).min():6.0f} ns, hold {(swap - capC - T_H).min():6.0f} ns;   '
          f'A: set-up {(capA - mux - T_SU).min():6.0f} ns, hold {(CELL + first_change - capA - T_H).min():6.0f} ns')

    timing_scale()


def timing_scale():
    """The same draws as timing 1–5, at 16 highways and at 16/32 slots, 74HC and a 74AC highway path.

    Gate delays do not scale with the cell.  A 16:1 is two '151s and a '32; a 32:1 is
    two of those and another '32.  Channel cards stay 74HC even when the highway is AC.
    """
    N = 400000
    print('\n  6. The same circuit at 16 highways (still 512 kbps, a cell of 1 953 ns), 16 slots (1.024 Mbps, 977 ns)')
    print('     and 32 slots (2.048 Mbps, 488 ns).  Gate delays do not scale.  16:1 is two \'151s and a \'32;')
    print('     32:1 is two of those and another \'32.')
    print('     Channel cards stay 74HC.  AC, where used, is the highway path only (commutator, driver, select, capture).')
    print('     extra_data is a \'32 after a 16:1 commutator and/or a 16:1 highway select;')
    print('     extra_strobe is a \'32 on a 16:1 slot select.  8 × 8 is timing 1–5.\n')

    def one(label, cell, fam, t_su, t_h, extra_data=0, extra_strobe=0, loss=0.0):
        rng = np.random.default_rng(2)
        def d(name, table=fam):
            if name == 'card clk-C_TX':
                t, m = HC[name]
            else:
                t, m = table[name]
            return rng.uniform(0.35 * t, m, N)
        clkX, clkY = d('244'), d('244')
        via_card = (clkX + d('card clk-C_TX') + d('157 I-Y') + d('151 I-Y') + d('244')
                    + d('wire') + d('244') + d('151 I-Y'))
        via_count = d('163 clk-Q') + d('wire') + clkX + d('151 S-Y') + d('244') + d('wire') + d('244') + d('151 I-Y')
        for _ in range(extra_data):
            g = d('32 I-Y')
            via_card, via_count = via_card + g, via_count + g
        valid = np.maximum(via_card, via_count)
        first_change = np.minimum(via_card, via_count)
        addr = cell / 4 + d('175 clk-Q') + d('wire') + d('244') + d('138 A-Y')
        en = cell / 2 + clkY + d('138 E-Y')
        cap = en + d('151 I-W')
        for _ in range(extra_strobe):
            cap = cap + d('32 I-Y')
        q = cap + d('74 clk-Q')
        cardclk = clkY + d('wire')
        mux = cell / 2 + clkX + d('157 S-Y') + d('151 I-Y') + d('244') + d('wire') + d('244') + d('151 I-Y')
        for _ in range(extra_data):
            mux = mux + d('32 I-Y')
        capC = cell / 4 + clkY + d('138 E-Y') + d('151 I-W')
        capA = 3 * cell / 4 + clkY + d('138 E-Y') + d('151 I-Y')
        for _ in range(extra_strobe):
            capC, capA = capC + d('32 I-Y'), capA + d('32 I-Y')
        swap = cell / 2 + 0.35 * (fam['244'][0] + fam['157 S-Y'][0] + fam['151 I-Y'][0]
                                  + 2 * fam['244'][0] + fam['wire'][0] + fam['151 I-Y'][0])
        su = (cap - valid - t_su - loss).min()
        hd = (cell + first_change - cap - t_h + loss).min()
        before = (cell / 2 - addr).min()
        after = (cell / 4 - (clkY + d('138 E-Y'))).min()
        suC = (capC - valid - t_su - loss).min()
        hdC = (swap - capC - t_h).min()
        suA = (capA - mux - t_su - loss).min()
        hdA = (cell + first_change - capA - t_h + loss).min()
        slot7 = (cell + cardclk - q - t_su).min()
        print(f'     {label}')
        print(f'       highway bit valid by {valid.max():.0f} ns (typical {np.median(valid):.0f})'
              f'{f"; cable costs {loss:.0f} ns of set-up" if loss else ""}')
        print(f'       SLOTQ settled {before:6.0f} ns before enable, moves {after:6.0f} ns after disable')
        print(f'       capture {cap.min():.0f}–{cap.max():.0f} ns;  set-up {su:6.0f} ns;  hold {hd:6.0f} ns')
        print(f'       economy C: set-up {suC:6.0f} ns, hold {hdC:6.0f} ns;   '
              f'A: set-up {suA:6.0f} ns, hold {hdA:6.0f} ns')
        print(f'       slot-last C_RX settled {slot7:6.0f} ns before the card samples')
        return su, before, suC

    one('8 × 16,  74HC: 16:1 commutator, highways still 8:1, 16:1 slots',
        1e9 / 1.024e6, HC, T_SU, T_H, extra_data=1, extra_strobe=1)
    one('8 × 16,  74HC, eight blocks on 2 m (clock at one end)',
        1e9 / 1.024e6, HC, T_SU, T_H, extra_data=1, extra_strobe=1, loss=skew(-RIB_X, n=8)[0])
    one('16 × 16, 74HC: 16:1 commutator and highway select, 16:1 slots',
        1e9 / 1.024e6, HC, T_SU, T_H, extra_data=2, extra_strobe=1)
    one('16 × 16, 74HC, 16 blocks on 4 m (clock at one end)',
        1e9 / 1.024e6, HC, T_SU, T_H, extra_data=2, extra_strobe=1, loss=skew(-RIB_X, n=16)[0])
    one('16 × 8,  74HC: 16:1 highway select, slots still 8:1',
        1e9 / 512e3, HC, T_SU, T_H, extra_data=1)
    one('16 × 8,  74HC, 16 blocks on 2 m (clock at one end)',
        1e9 / 512e3, HC, T_SU, T_H, extra_data=1, loss=skew(-RIB_X, n=16)[0])
    one('32 × 8,  74HC, 32:1 highways, slots still 8:1', 1e9 / 512e3, HC, T_SU, T_H, extra_data=2)
    one('8 × 32,  74HC, highways still 8:1, 32:1 slots', 1e9 / 2.048e6, HC, T_SU, T_H, extra_strobe=2)
    one('8 × 16,  74AC highway / 74HC cards',
        1e9 / 1.024e6, AC, T_SU_AC, T_H_AC, extra_data=1, extra_strobe=1)
    one('16 × 16, 74AC highway / 74HC cards',
        1e9 / 1.024e6, AC, T_SU_AC, T_H_AC, extra_data=2, extra_strobe=1)
    one('8 × 32,  74AC highway / 74HC cards, 32:1 slots',
        1e9 / 2.048e6, AC, T_SU_AC, T_H_AC, extra_strobe=2)
    print('\n     A negative set-up is a miss across the spread: that geometry is not 74HC.')
    print('     SLOTQ still uses a quarter-cell tap (2.048 MHz at 16 slots, 4.096 MHz at 32).')


# -------------------------------------------------------------- mainboard

RIB_V = 5.1                   # ns/m down a 0.05" ribbon with a ground between every pair: Z0 ~ 105 ohm, 49 pF/m
RIB_Z = 105.0
RIB_X = 0.25                  # a block every quarter metre along the cable
RIB_TAP = 12.0                # pF a tap: the IDC connector, the mainboard stub and one '244 input


def skew(xc, n=8):
    """The clock reaches block k late by |x_k - x_c|; the worst (driver, listener) pair and what it costs."""
    x = RIB_X * np.arange(n)
    dly = RIB_V * np.abs(x - xc)
    pairs = [(dly[a] + RIB_V * abs(x[b] - x[a]) - dly[b], a, b) for a in range(n) for b in range(n)]
    return max(pairs)


def mainboard():
    rng = np.random.default_rng(3)
    N = 400000
    def d(name):
        t, m = HC[name]
        return rng.uniform(0.35 * t, m, N)
    print('MAINBOARD -- what a ribbon costs the fabric.  Eight blocks a quarter metre apart on one cable;')
    print(f'  {RIB_V:.1f} ns/m, {RIB_Z:.0f} ohm, {1000 * RIB_V / RIB_Z:.0f} pF/m.  The same 400000 draws as `timing`, with the clock\'s own flight added.\n')

    print('  1. The clock travels down the same cable as the data, so most of the flight cancels.')
    print('     Data reaches listener b at  dly(a) + flight(a,b); b\'s strobe at  dly(b).  The loss is the difference,')
    print('     and it is ZERO whenever the driver is nearer the clock card than the listener.')
    for label, xc in (('at one end', -RIB_X), ('in the middle', RIB_X * 3.5), ('at the far end', RIB_X * 8)):
        loss, a, b = skew(xc)
        print(f'       clock card {label:16s} worst loss {loss:5.1f} ns   (block {a} driving, block {b} listening)')
    print('     Hold is never worse than with no cable at all: the same term that shortens set-up lengthens hold.')

    # the worst placement, folded into fabric.md 4's own margins
    loss, _, _ = skew(-RIB_X)
    clkX, clkY = d('244'), d('244')
    via_card = clkX + d('card clk-C_TX') + d('157 I-Y') + d('151 I-Y') + d('244') + d('wire') + d('244') + d('151 I-Y')
    via_count = d('163 clk-Q') + d('wire') + clkX + d('151 S-Y') + d('244') + d('wire') + d('244') + d('151 I-Y')
    valid, first_change = np.maximum(via_card, via_count), np.minimum(via_card, via_count)
    cap = CELL / 2 + clkY + d('138 E-Y') + d('151 I-W')
    print(f'\n  2. The worst pair on the worst placement ({loss:.0f} ns), against `timing` 4\'s figures:')
    print(f'       set-up at the capture flip-flop {(cap - valid - T_SU - loss).min():6.0f} ns   (no cable: {(cap - valid - T_SU).min():.0f})')
    print(f'       hold                            {(CELL + first_change - cap - T_H + loss).min():6.0f} ns   (no cable: {(CELL + first_change - cap - T_H).min():.0f})')
    print(f'     The data\'s own flight is already inside the {HC["wire"][1]:.0f} ns `wire` term of §4; the clock\'s was not.')

    # the strobe hazard: HCLK and SLOTQ go down the same cable, so their skew is conductor-to-conductor only
    addr = CELL / 4 + d('175 clk-Q') + d('wire') + d('244') + d('138 A-Y')
    print(f'\n  3. The §3.2 hazard is untouched.  HCLK and SLOTQ leave the clock card together and arrive together:')
    print(f'     their skew is conductor to conductor in one ribbon, under 0.1 ns/m, not the {RIB_V:.0f} ns/m of the cable.')
    print(f'       address settled {(CELL / 2 - addr).min():6.0f} ns before the enable, as it was')

    # the line itself
    print('\n  4. The line itself, and why the cure for an edge is to slow it down.')
    for L, n in ((2.0, 8), (4.0, 8)):
        C = 1000 * RIB_V / RIB_Z * L + n * RIB_TAP
        print(f'     {L:.0f} m, {n} taps: {C:.0f} pF, one way {RIB_V * L:.1f} ns, round trip {2 * RIB_V * L:.1f} ns.'
              f'  A \'244 alone gives a {2.2 * 40 * C * 1e-3:.0f} ns edge,')
        for Rs in (33, 100, 220):
            print(f'         {Rs:3d} ohm in series: edge {2.2 * (Rs + 40) * C * 1e-3:4.0f} ns, {100 * 2.2 * (Rs + 40) * C * 1e-3 / CELL:4.1f} % of a cell'
                  f'{"   <- slower than the round trip: no ringing to settle" if 2.2 * (Rs + 40) * C * 1e-3 > 2 * RIB_V * L else ""}')
        print(f'         a clock line draws C.V.f = {C * 5 * 512e-6:.2f} mA at 512 kHz, {C * 5 * 1024e-6:.2f} mA at 1.024 MHz')
    print('\n  Nothing here is near a limit.  The cure for the edges is to SLOW them: the budget is three quarters')
    print('  of a microsecond and the line is ten nanoseconds long, so a series resistor spends what it likes.')


# ------------------------------------------------------------------ flood

HOP = 7.0                 # a seizure crossing one exchange: A path 2 ms, scan of the trunk ports, marker
A_FALL, A_RISE = 2.0, 1.5 # the trunk's A path, per hop: channel-cards.md 5, and `aline` 1
A_PATH = 2.0              # what network.md 1.1 allows a CARRIER a hop, one way, and what
                          # HOP's 7 ms has in it.  A copper pair or an MF8 link is under it; a
                          # leased circuit, a radio or anything with a buffer is not
T_MARK = 2.0              # a marker action


def npulses(d):
    return int(d) or 10


def caller(digits, pause=800.0, t0=1000.0):
    """When the origin's register has each digit.  Rotary at 10 pps 60/40, `pause` ms from the last
    break to the next first break.  Returns [(start, end of signalling, recognised)]."""
    out, t = [], t0
    for d in digits:
        end = t + (npulses(d) - 1) * 100 + 60
        out.append((t, end, end + T_ID)); t = end + pause
    return out


def flood_call(number, own, chain, pause=800.0):
    """Live pulse flood of network.md 3.  `number` is the full dialled string: `hs` local, or
    `1ebhs` for a network call.  `own` is the origin's code; `chain` is exchange codes from the
    origin onward.  Trunks listen to the caller; monitors read e and b.  Returns events and the
    figures of merit."""
    dg = caller(number, pause)
    spaced = ' '.join(number)
    ev = [(0.0, 'lifts'), (10.0, 'register attached; dial tone'), (dg[0][0], f'dials {spaced}')]
    r = [x[2] for x in dg]

    # local: h s, never a trunk
    if len(number) == 2:
        t = r[-1] + T_MARK
        ev.append((t, 'local: connected'))
        return ev, dict(pdd=t - dg[-1][1], held={}, mon={}, reg=t - 10.0)

    assert number[0] == '1' and len(number) == 5, 'network number is 1 e b h s'
    code = number[1:3]
    # the key is in: seize a trunk in every direction, listening to the caller
    t_sz = r[0] + T_MARK
    ev.append((t_sz, 'the first digit is in, and is 1: seize a trunk in every direction, listening to the caller'))
    ev.append((t_sz + G_ORIGIN, "the origin's guard ends: a break before this would have abandoned the call"))
    J = chain.index(code) if code in chain else None
    nh = len(chain) - 1
    for j in range(1, nh + 1):
        tip = '; nowhere to forward' if j == nh else '; patched onward'
        ev.append((t_sz + HOP * j, f'  {chain[j]}: M rises{tip}; monitor on'))

    # subsequent digits as the caller dials them
    for i, d in enumerate(number[1:], 1):
        ev.append((dg[i][0], f'dials {d}'))

    # own code dialled as 1 e b h s: release the trunks and finish locally
    if code == own:
        t = r[2] + T_MARK
        ev.append((t, 'own code: the origin claims its own call and releases the trunks'))
        rel = t + T_FALL
        ev.append((rel, 'every flooded port has released itself'))
        t_loc = r[4] + T_MARK
        ev.append((t_loc, 'connected locally'))
        held = {f'{chain[j - 1]}-{chain[j]}': rel - (t_sz + HOP * (j - 1)) for j in range(1, nh + 1)}
        mon = {chain[j]: rel - (t_sz + HOP * j) for j in range(1, nh + 1)}
        return ev, dict(pdd=t_loc - dg[4][1], held=held, mon=mon, reg=t_loc - 10.0)

    # digit arrival at hop j: A rise along the path, then ID
    seen = lambda i, j: dg[i][1] + A_RISE * j + T_ID
    mon = {}
    # e: every monitor whose e matches reads on; the rest let go
    e_hit = [j for j in range(1, nh + 1) if chain[j][0] == code[0]]
    e_miss = [j for j in range(1, nh + 1) if chain[j][0] != code[0]]
    for j in e_miss:
        ev.append((seen(1, j), f'  {chain[j]}: e is not mine; monitor lets go'))
        mon[chain[j]] = seen(1, j) - (t_sz + HOP * j)
    if e_hit:
        ev.append((seen(1, e_hit[0]), f'  e={code[0]}: monitors at '
                   + ', '.join(chain[j] for j in e_hit) + ' read on'))
    for j in e_hit:
        if j != J:
            ev.append((seen(2, j), f'  {chain[j]}: b is not mine; monitor lets go; the patch stays'))
            mon[chain[j]] = seen(2, j) - (t_sz + HOP * j)
        else:
            mon[chain[j]] = seen(2, j) - (t_sz + HOP * j)

    if J is None:
        t = r[2] + 2000
        ev.append((t, 'no claim in 2 s: cannot-complete tone'))
        return ev, dict(pdd=t - dg[4][1], held={}, mon=mon)

    t_claim = seen(2, J) + T_MARK
    ev.append((t_claim, f'  {chain[J]}: CLAIM; onward patch cleared; backward A = 1'))
    ev.append((t_claim + A_RISE * J, 'origin: backward A rises on the trunk'))
    if J < nh:
        ev.append((t_claim + A_FALL + T_FALL, f'  beyond {chain[J]}: ports have released themselves'))
    # last digits travel the claimed path: recognised at the owner after A rise
    t_conn = seen(4, J) + T_MARK
    ev.append((t_conn, f'  {chain[J]}: has {number[3]} {number[4]}; trunk <-> line; the phone rings, RBT goes back'))
    t_cut = max(t_claim + A_RISE * J, dg[4][1] + A_RISE * J + T_ID) + T_MARK
    ev.append((t_cut, 'origin: caller <-> trunk; register freed'))
    heard = max(t_cut, t_conn)
    ev.append((heard, 'caller hears ringback'))
    held = {}
    for j in range(1, nh + 1):
        if j > J:
            held[f'{chain[j - 1]}-{chain[j]}'] = t_claim + A_FALL + T_FALL - (t_sz + HOP * (j - 1))
        else:
            held[f'{chain[j - 1]}-{chain[j]}'] = t_claim + A_RISE * J + T_MARK - (t_sz + HOP * (j - 1))
    flood_legs = {k: v for k, v in held.items() if chain.index(k.split('-')[1]) > J}
    return ev, dict(pdd=heard - dg[4][1], held=held, flood_legs=flood_legs, mon=mon, reg=t_cut - 10.0)


def flood():
    # network.md 3.1: line 44 of 22 dials 1 2 4 5 5 on 22 = 23 = 24 = 25
    chain = ['22', '23', '24', '25']
    print('FLOOD -- the timing of a network call under the pulse flood (network.md 3, 4).')
    print('  Arithmetic from measured constants, not a simulation of the gates:')
    print(f'    register windows HIT {T_HIT} / ID {T_ID} ms (register.md 2); A path per hop: a fall')
    print(f'    {A_FALL} ms, a rise {A_RISE} ms (aline 1); a seizure crosses an exchange in {HOP:.0f} ms; marker action {T_MARK:.0f} ms;')
    print(f'    origin guard {G_ORIGIN:.0f} ms (monitor.md 3); release {T_FALL} ms.  No sender: trunks listen to the caller.')
    print('    The caller starts dialling 1 s after dial tone; 800 ms between digits.\n')

    print('  1. Line 44 of exchange 22 dials 1 2 4 5 5 on 22 = 23 = 24 = 25 (network.md 3.1).')
    ev, m = flood_call('12455', '22', chain)
    for t, e in sorted(ev, key=lambda x: x[0]):
        print(f'     {t:8.0f}  {e}')
    print(f"     post-dial delay, caller's last pulse to ringback: {m['pdd']:.0f} ms\n")

    print('  2. The same call from the middle: a line of 23 dials 1 2 5 5 5.  Seizes toward 22 and toward 24;')
    print('     25 claims; the origin keeps that leg and releases the other.')
    mid = ['23', '22']  # one side only for the arithmetic of the claim path; both ways noted
    ev2, m2 = flood_call('12555', '23', ['23', '24', '25'])
    for t, e in sorted(ev2, key=lambda x: x[0]):
        print(f'     {t:8.0f}  {e}')
    fl = m2.get('flood_legs') or m2['held']
    print(f"     post-dial delay: {m2['pdd']:.0f} ms;  flood legs past the owner held "
          f"{(max(fl.values()) if fl else 0):.0f} ms\n")

    print('  3. A LOCAL call, 2244 dials 4 7: no trunk is touched.')
    ev, m = flood_call('47', '22', chain)
    for t, e in sorted(ev, key=lambda x: x[0]):
        print(f'     {t:8.0f}  {e}')
    print(f'     post-dial delay: {m["pdd"]:.0f} ms\n')

    print("  4. Own code from inside: 2244 dials 1 2 2 5 5.  Floods, then the origin's register sees its own")
    print('     e b, releases the trunks and carries on locally.')
    ev, m = flood_call('12255', '22', chain)
    for t, e in sorted(ev, key=lambda x: x[0]):
        print(f'     {t:8.0f}  {e}')
    held = max(m['held'].values()) if m['held'] else 0
    print(f'     every link held {held:.0f} ms; post-dial delay {m["pdd"]:.0f} ms\n')

    print('  5. The load of the flood itself.  4 exchanges x 48 lines x 3 calls an hour; a fraction leave,')
    print('     spread evenly; erlangs of pure signalling on a link the call does not keep (beyond the owner),')
    print('     and of monitor time at an exchange the call passes (taken as 23).')
    print(f'     {"leaving":>8s} {"link waste E":>13s} {"monitor at 23 E":>16s} {"flood held, code 24 s":>22s}')
    for leave in (0.2, 0.3, 0.5):
        _, mn = flood_call('12455', '22', chain)
        calls = 4 * 48 * 3
        # a network call holds the beyond-owner link until claim+release; local holds nothing
        beyond = mn.get('flood_legs') or {k: v for k, v in mn['held'].items() if k == '24-25'}
        waste_ms = max(beyond.values()) if beyond else 0
        link_e = calls * leave * waste_ms / 3.6e6
        # monitors: at 23, e matches so it holds until b
        mon_e = calls * leave * mn['mon'].get('23', 0) / 3.6e6
        print(f'     {leave:8.0%} {link_e:13.3f} {mon_e:16.3f} {waste_ms / 1000:22.2f}')

    print('\n  6. What must hold: the flood is up before the caller\'s next digit.  The origin makes sure:')
    print(f'     it abandons a call whose next break comes within {G_ORIGIN:.0f} ms of its seizure (monitor.md 3).')
    ready = T_ID + T_MARK + G_ORIGIN
    print(f'     Ready {ready:.0f} ms after his last pulse = digit recognised {T_ID} + seizure {T_MARK:.0f} + guard {G_ORIGIN}, whatever the hop count.')
    print(f'     {"hops":>5s} {"the flood itself takes, ms":>27s} {"at a slow marker, 12 ms a hop":>30s} {"inside the guard":>17s}')
    for hops in (1, 3, 7, 10):
        print(f'     {hops:5d} {HOP * hops:27.0f} {(12 + A_FALL) * hops:30.0f} {str((12 + A_FALL) * hops < G_ORIGIN):>17s}')
    print(f'     Margin for a dial: {500 - ready:.0f} ms at 500 ms between digits, {800 - ready:.0f} ms at 800.  A caller who beats it is')
    print('     abandoned to cannot-complete: a failed call, never a wrong number.')
    print(f'     Post-dial delay: {T_ID + T_MARK + A_RISE * 2:.0f} ms after the last pulse, whatever the hop count')
    print('     (133 ms here to the third exchange); a register-sender would have cost 0.49 s (network.md 9).\n')

    def live(number, domains, pause, label):
        """Live digits.  domains[i] = (who acts on this digit, hops the NEXT flood must cross) or (None, 0)."""
        dg = caller(number, pause, t0=1000.0)
        print(f'     {label}, {pause:.0f} ms between digits')
        print(f'     {"digit":>6s} {"its last pulse":>15s} {"acted on by":28s} {"next flood ready":>17s} {"next digit begins":>18s} {"margin ms":>10s}')
        worst = 1e9
        for i, d in enumerate(number):
            who, hops = domains[i]
            if who is None:
                print(f'     {d:>6s} {dg[i][1]:15.0f} {"-":28s}')
                continue
            ready_t = dg[i][1] + T_ID + T_MARK + G_ORIGIN
            nxt = dg[i + 1][0] if i + 1 < len(number) else None
            margin = nxt - ready_t if nxt is not None else None
            if margin is not None:
                worst = min(worst, margin)
            print(f'     {d:>6s} {dg[i][1]:15.0f} {who:28s} {ready_t:17.0f} {nxt if nxt else 0:18.0f} {margin if margin is not None else 0:10.0f}')
        heard = dg[-1][1] + A_RISE * 2 + T_ID + T_MARK
        print(f'     the far phone rings {heard - dg[-1][1]:.0f} ms after the last pulse;  smallest margin {worst:.0f} ms\n')

    print('  7. Live margins on 1 2 4 5 5.  The origin acts on the key; exchange 24 claims on b.')
    for pz in (800, 500):
        live('12455', [('origin 22: seize the flood', 3), (None, 0), ('exchange 24: claim', 0), (None, 0), (None, 0)],
             pz, '1 2 4 5 5')

    print('  8. Out of the network: 1 8 / 1 9 are reserved (network.md 6).  One way considered, not adopted:')
    print('     each digit claimed by one level in turn, with the same guard.  8 and 9 can never be e or b,')
    print('     so a monitor knows such a call by the first digit it hears and lets go.')
    other = [('origin 22: seize', 3), ("gateway: claim, onto next flood", 7),
             ("far gateway: claim, into its ties", 3), ('exchange 31: claim', 0), (None, 0), (None, 0)]
    for pz in (800, 500):
        live('183147', other, pz, '1 8 3 1 4 7  (reserved path, worked as successive claims)')
    live('1953147',
         [('origin 22: seize', 3), ("gateway: claim, onto next flood", 7),
          ("area gateway: claim", 7), ("far gateway: claim", 3),
          ('exchange 31: claim', 0), (None, 0), (None, 0)],
         800, '1 9 5 3 1 4 7')


# ------------------------------------------------------------------ ss0

SS0_BITS = 18             # a message: start, 16 data bits, stop
SS0_BAUD = 1.0            # bits a ms: the clock card's 1 kHz TICK.  The S lane's x bit is 8 kbps: 8 samples a bit
T_MSG = SS0_BITS / SS0_BAUD
T_ALIGN = 1.0             # a message waits for the next TICK to begin
T_HUNT = HOP - A_FALL     # a hunt of the trunk ports and the marker's decision: a flood hop less its A path
SS0_HOP = T_ALIGN + T_MSG + T_HUNT + T_MARK     # a SEIZE received, a trunk hunted onward, the next SEIZE loaded


def erlang_b(E, N):
    b = 1.0
    for k in range(1, N + 1):
        b = E * b / (k + E * b)
    return b


def erlang_cap(N, gos=0.01):
    lo, hi = 0.0, float(N)
    for _ in range(60):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if erlang_b(mid, N) < gos else (lo, mid)
    return lo


def waste(chain, net, calls_h=48 * 3):
    """Erlangs of trunk held on each link of a chain by calls that do not use that link.  Every
    exchange originates calls_h calls an hour, a fraction net of them spread evenly over the others.
    Live flood: a local call holds nothing; a network call (1 e b h s) seizes every direction at the
    key and releases unused legs when the owner claims on b.  SS0: nothing until the last digit; a
    SEIZE relayed hop by hop; the far way seized only from a middle exchange, until the claim.
    Returns {link: [flood local calls, flood network calls, SS0]}."""
    n = len(chain)
    links = [f'{chain[i]}-{chain[i + 1]}' for i in range(n - 1)]
    out = {L: [0.0, 0.0, 0.0] for L in links}
    for o in range(n):
        sides = [[links[i] for i in range(o - 1, -1, -1)], [links[i] for i in range(o, n - 1)]]
        # local calls: no flood (column 0 stays 0)
        for d in range(n):
            if d == o:
                continue
            S, J = (0, o - d) if d < o else (1, d - o)
            dg = caller('1' + chain[d] + '55'); r = [x[2] for x in dg]
            per = calls_h * net / (n - 1) / 3.6e6
            t_sz = r[0] + T_MARK
            t_claim = dg[2][1] + A_RISE * J + T_ID + T_MARK         # b recognised at the owner
            t_drop = t_claim + A_RISE * J + T_MARK                   # the origin lets the other way go
            for s, side in enumerate(sides):
                for j, L in enumerate(side, 1):
                    if s == S and j <= J:
                        continue                                   # the call's own path
                    down = (t_claim + A_FALL * (j - J)) if s == S else (t_drop + A_FALL * j)
                    out[L][1] += per * (down + T_FALL - (t_sz + HOP * (j - 1)))
            t0 = r[4] + T_MARK                                      # after h s under 1 e b h s
            t_drop = t0 + J * SS0_HOP + A_RISE * J + T_MARK
            for j, L in enumerate(sides[1 - S], 1):
                up = t0 + (j - 1) * SS0_HOP
                if up >= t_drop + A_FALL * (j - 1):               # the fall overtook the relay: never seized
                    break
                out[L][2] += per * (t_drop + A_FALL * j + T_FALL - up)
    return out


def ss0():
    from math import comb
    print('SS0 -- the number on a common channel: one SEIZE a link, forward only; A carries everything else.')
    print('  Arithmetic from the constants of `flood`, not a simulation of the gates:')
    print(f'    a message is {SS0_BITS} bits at {SS0_BAUD * 1000:.0f} baud, {T_MSG:.0f} ms, and waits up to {T_ALIGN:.0f} ms for the TICK;')
    print(f'    a hop hunts onward in {T_HUNT:.0f} ms (a flood hop, {HOP:.0f} ms, less its A path) and writes in {T_MARK:.0f} ms:')
    print(f'    {SS0_HOP:.0f} ms a hop.  Register ID {T_ID} ms; A rise {A_RISE} ms and fall {A_FALL} ms a hop; release {T_FALL} ms.\n')

    print('  1. Post-dial delay, the caller\'s last pulse to ringback, by hops from the origin to the owner.')
    print(f'     {"hops":>5s} {"live flood ms":>14s} {"SS0 ms":>8s}')
    for J in range(1, 8):
        live = T_ID + T_MARK + A_RISE * J
        pdd = T_ID + T_MARK + J * SS0_HOP + A_RISE * J + T_MARK
        print(f'     {J:5d} {live:14.0f} {pdd:8.0f}')

    print('\n  2. Trunk held by calls that do not use it, erlangs on each link of 21 = 22 = 23 = 24.  Every exchange')
    print('     48 lines x 3 calls an hour, the network share spread evenly over the other three, rotary dials.')
    print('     Local calls hold nothing under the pulse flood; a network call wastes the legs past the owner.')
    for net in (0.2, 0.5):
        w = waste(['21', '22', '23', '24'], net)
        print(f'     {net:.0%} of calls leave')
        print(f'     {"link":>8s} {"flood: local calls":>19s} {"network calls":>14s} {"total":>7s} {"SS0":>7s}')
        for L, (a, b, c) in w.items():
            print(f'     {L:>8s} {a:19.3f} {b:14.3f} {a + b:7.3f} {c:7.3f}')

    print('\n  3. A message against line errors.  Each x sample (one line bit a superframe) wrong with probability p,')
    print('     independently.  A data bit is the majority of the middle 1, 3 or 5 of its 8 samples; odd parity')
    print('     over the 16 data bits; a bad stop bit discards.  Per million messages: LOST, discarded, so the call')
    print('     fails; WRONG, an even number of data bits wrong and accepted -- an upper bound on a wrong number.')
    print(f'     {"line p":>8s} {"samples":>8s} {"bit error":>10s} {"lost / 1e6":>11s} {"wrong / 1e6":>12s}')
    for p in (1e-4, 1e-3, 1e-2, 3e-2):
        for m in (1, 3, 5):
            q = sum(comb(m, k) * p ** k * (1 - p) ** (m - k) for k in range(m // 2 + 1, m + 1))
            odd = sum(comb(16, k) * q ** k * (1 - q) ** (16 - k) for k in range(1, 17, 2))
            even = sum(comb(16, k) * q ** k * (1 - q) ** (16 - k) for k in range(2, 17, 2))
            lost = odd + (1 - odd) * q
            wrong = even * (1 - q)
            print(f'     {p:8.0e} {m:8d} {q:10.1e} {lost * 1e6:11.1f} {wrong * 1e6:12.4f}')

    print('\n  4. The bearer.  Erlangs a direction carries at 1 % blocking (Erlang B), by voice channels left:')
    print(f'     {"channels":>9s} {"erlang":>7s}')
    for N in (5, 6, 10, 12):
        print(f'     {N:9d} {erlang_cap(N):7.2f}')
    print('     The S lane\'s x bit costs no channel.  Channel 6 given over costs 6 -> 5 a link, 12 -> 10 a doubled direction.')



# ------------------------------------------------------------------ net

NET_SCAN = 8.0            # the marker's scanner comes round to a port this often, ms
NET_HUB = 4.0             # a hub's extra writes when it fans a seizure out (network.md 3.2)
NET_REPOINT = NET_SCAN / 2 + T_MARK     # a hub re-points its incoming trunk when the claim comes back
FLOOD_TIMEOUT = 5000.0    # the origin releases its trunks if b is not in by then (network.md 4)
NO_CLAIM = 2000.0         # no claim this long after the last digit -> cannot-complete
HOLD_MEAN = 48000.0       # 0.08 E a line at 3 calls an hour, a line being one of two in each call
STOPS = 0.01              # callers who dial the key and then stop: the 5 s rule of network.md 4


def pulses_of(d):
    return 10 if d == 0 else d


def code_hold(code):
    """seconds a flood is held for a call to this code: from the key until e and b are in
    (network.md 4).  2.0 s for code 11, 0.1 s a pulse of e or b, 2.7 s mean over all 64."""
    return 2.0 + 0.1 * (pulses_of(int(code[0])) - 1) + 0.1 * (pulses_of(int(code[1])) - 1)


class Tempo:
    """The clock a call's own timing is made on.

    LIFE is the exchange as it is built.  FAST is what verilog's system testbenches run --
    `make stress`, `make traffic` -- where the dial and the register's three windows are eight
    times life, so a call costs a second and a half of simulation instead of twelve and an hour
    of offered traffic is minutes rather than a day.

    WHAT DOES NOT MOVE is everything the marker's scanner sets: the 8 ms scan, the 7 ms hop, a
    marker action, the A path.  Those are the same milliseconds in both, which is what lets the
    two runs be read against each other -- and it makes the fast one HARDER on the common
    control than life is, because in a call's own terms the scan is eight times as long."""

    def __init__(self, name, pulse, brk, idw, gap, dt_pause, answer, busy, no_claim,
                 timeout, fall, hold, guard):
        self.name, self.pulse, self.brk, self.idw = name, pulse, brk, idw
        self.gap, self.dt_pause, self.answer, self.busy = gap, dt_pause, answer, busy
        self.no_claim, self.timeout, self.fall, self.hold = no_claim, timeout, fall, hold
        self.guard = guard                 # the origin's guard (monitor.md 3, rule 2)


# The exchange as built: 10 pps 60/40, register.md 2's 8/128/256 ms windows, 0.5-0.9 s between
# digits, network.md 4's 5 s rule, a 256 ms release detector, a 48 s call.
LIFE = Tempo('life', pulse=100.0, brk=60.0, idw=T_ID, gap=(500.0, 900.0),
             dt_pause=(300.0, 1000.0), answer=(0.0, 0.0), busy=3000.0,
             no_claim=NO_CLAIM, timeout=FLOOD_TIMEOUT, fall=T_FALL, hold=HOLD_MEAN,
             guard=G_ORIGIN)
# verilog's system testbenches: every one of those eight times faster, and the conversation cut
# to half a second.  The marker's scan, its hop and its actions are NOT in this table.
FAST = Tempo('x8', pulse=20.0, brk=12.0, idw=16.0, gap=(60.0, 120.0),
             dt_pause=(10.0, 40.0), answer=(16.0, 216.0), busy=375.0,
             no_claim=250.0, timeout=625.0, fall=32.0, hold=500.0, guard=G_ORIGIN / 8)


class Pool:
    """n of something, with the time it spends busy and the calls it turns away."""

    def __init__(self, n):
        self.n, self.used, self.busy, self.last, self.refused, self.taken = n, 0, 0.0, 0.0, 0, 0
        self.hi = 0                        # the high-water mark, for reading against the RTL
        self.t0 = 0.0                      # what a warm-up has forgotten

    def _mark(self, t):
        self.busy += self.used * (t - self.last); self.last = t

    def take(self, t):
        self._mark(t)
        if self.used >= self.n:
            self.refused += 1; return False
        self.used += 1; self.taken += 1
        if self.used > self.hi:
            self.hi = self.used
        return True

    def give(self, t):
        self._mark(t); self.used -= 1

    def reset(self, t):
        """forget everything before t and keep what is held: a warm-up."""
        self._mark(t)
        self.busy, self.t0, self.refused, self.taken, self.hi = 0.0, t, 0, 0, self.used

    def erlang(self, t):
        self._mark(t); d = t - self.t0
        return self.busy / d if d else 0.0


class Net:
    """A network of exchanges: the flood, the monitors, the claim and the registers, in milliseconds.

    Every exchange has registers, a trunk block a direction with monitors on it, and, where it
    faces more than two directions, fan-out resolvers.  Every link has channels.  A call is
    dialled digit by digit at 10 pps; the key opens the flood, e and b go down it live, and the
    exchange whose code they are claims (network.md 3)."""

    def __init__(self, links, lines, regs=3, mons=3, resolvers=3, leave=0.3, seed=1, strapped=(),
                 tempo=None, idle=None, holds='exp', dt_wait=None, burst=None, ports=None,
                 link_ms=A_PATH, guard=None):
        self.rng = np.random.default_rng(seed)
        self.t, self.q, self.seq, self.t0 = 0.0, [], 0, 0.0
        self.lines, self.leave = lines, leave
        # The clock the dial is on, and whether a caller is a LINE or a Poisson stream.
        # idle = None is the arrival process of network.md 5.1: calls come from nowhere at
        # a fixed rate whatever the exchange is doing.  idle = a number makes every line a
        # source, which is what the RTL bench has -- a line is a state machine there and there
        # is no other kind of caller -- so the offered load falls as the exchange fills.
        self.tp = tempo or LIFE
        self.idle, self.finite = idle, idle is not None
        self.holds, self.dt_wait, self.burst = holds, dt_wait, burst
        self.ports = ports                     # the (h, s) a line may be, or None for any
        # What the CARRIER costs a hop, one way, and the origin's guard against it.
        # network.md 1.1 allows a carrier about 2 ms of A path a hop, which is what
        # NET_HOP's 7 ms has in it; a leased circuit, a radio or anything with a buffer
        # has tens.  `guard` is monitor.md 3's rule 2, which is what that budget is
        # for: a break inside it and the origin abandons rather than risk a wrong number.
        self.link_ms = link_ms
        self.guard = self.tp.guard if guard is None else guard
        self.is_hot = False
        self.onhook = dict(lines)
        self.cancel = {x: 0 for x in lines}
        self.strapped = {frozenset(l) for l in strapped}          # links whose words carry n (network.md 3.3)
        self.codes = list(lines)
        self.dirs = {x: [] for x in lines}                       # exchange -> the exchanges it faces
        self.chan = {}
        for (u, v), n in links.items():
            self.dirs[u].append(v); self.dirs[v].append(u)
            self.chan[frozenset((u, v))] = Pool(n)
        self.reg = {x: Pool(regs) for x in lines}
        self.mon = {(x, d): Pool(mons) for x in lines for d in self.dirs[x]}
        self.res = {x: Pool(resolvers) for x in lines if len(self.dirs[x]) > 2}
        self.busy_lines = {x: 0 for x in lines}
        self.stat = {k: 0 for k in ('calls', 'local', 'net', 'no_register', 'waited', 'no_trunk',
                                    'no_monitor', 'no_resolver', 'called_busy', 'no_claim',
                                    'timed_out', 'done', 'no_dialtone', 'herds',
                                    'guarded', 'late', 'wrong', 'lost_owner')}
        self.dialtone, self.complete_local, self.complete_net, self.hops = [], [], [], []
        self.flood_held, self.stopped_held = [], []

    # --- event queue -------------------------------------------------
    def free(self, pool):
        pool.give(self.t)

    def at(self, t, fn, *a):
        self.seq += 1; heapq.heappush(self.q, (t, self.seq, fn, a))

    def run(self, until):
        while self.q and self.q[0][0] < until:
            self.t, _, fn, a = heapq.heappop(self.q); fn(*a)
        self.t = until

    # --- lines as sources ---------------------------------------------
    # A line is a source only in the finite model.  The book to keep is that the number of wake
    # events outstanding is the number of lines on hook: a wake takes a line, and the line puts
    # one back when it is done with.  A herd lifts lines EARLY, so it cancels as many wakes as
    # it forces, or the network would quietly gain callers.
    def draw_idle(self):
        mean = self.idle
        if self.burst:
            # The same mean in bursts.  A share s = up/(up+down) of the time the rate is x
            # times what it is the rest of the time, so the cold RATE is the mean over
            # (1-s) + x*s -- and an idle is one over a rate, so the cold IDLE is that much
            # longer than the mean, and the hot idle is x times shorter again.
            up, down, x = self.burst
            mean = self.idle * (down + up * x) / (up + down)
            if self.is_hot:
                mean /= x
        return float(self.rng.exponential(mean))

    def draw_hold(self):
        if self.holds == 'flat':
            return self.tp.hold
        if self.holds == 'two':             # nine short calls to one ten times as long
            return self.tp.hold * (5.5 if self.rng.random() < 0.1 else 0.5)
        return float(self.rng.exponential(self.tp.hold))

    def wake(self, x, dst=None, forced=False):
        if not forced and self.cancel[x] > 0:
            self.cancel[x] -= 1             # this line was lifted early by a herd
            return
        if self.onhook[x] <= 0:
            self.at(self.t + self.draw_idle(), self.wake, x)
            return
        self.onhook[x] -= 1
        self.busy_lines[x] += 1
        self.arrive(x, dst)

    def finish(self, x):
        """a line back on hook.  Nothing to do in the Poisson model: a caller is not a line there."""
        if not self.finite:
            return
        self.busy_lines[x] -= 1
        self.onhook[x] += 1
        self.at(self.t + self.draw_idle(), self.wake, x)

    def go_hot(self, up, down):
        self.is_hot = not self.is_hot
        self.at(self.t + float(self.rng.exponential(up if self.is_hot else down)), self.go_hot, up, down)

    def a_herd(self, pc, spread, every):
        """a flash crowd: a share of every line in the network lifts inside `spread`, and they all
        dial the SAME exchange.  It is where the calls go, not only when they come."""
        self.stat['herds'] += 1
        dst = self.codes[int(self.rng.integers(0, len(self.codes)))]
        for x in self.lines:
            # a share of EVERY line, as tb_traffic's herd is -- capped at the lines
            # actually on hook, because the book to keep is one wake a line on hook
            k = min(int(self.lines[x] * pc), self.onhook[x])
            self.cancel[x] += k
            for _ in range(k):
                self.at(self.t + float(self.rng.uniform(0, spread)), self.wake, x,
                        None if dst == x else dst, True)
        self.at(self.t + float(self.rng.exponential(every)), self.a_herd, pc, spread, every)

    def forget(self):
        """a warm-up: what the network did while it was filling is not what it does."""
        for p in (list(self.chan.values()) + list(self.reg.values())
                  + list(self.mon.values()) + list(self.res.values())):
            p.reset(self.t)
        for k in self.stat:
            self.stat[k] = 0
        for l in (self.dialtone, self.complete_local, self.complete_net, self.hops,
                  self.flood_held, self.stopped_held):
            del l[:]
        self.t0 = self.t

    def start_lines(self):
        # spread flat over one idle, which is what the RTL bench does at the top of a phase: a
        # phase begins with every line on hook, and how they are spread decides the transient
        for x in self.lines:
            for _ in range(self.lines[x]):
                self.at(float(self.rng.uniform(0, self.idle)), self.wake, x)

    # --- the topology ------------------------------------------------
    def hop(self, u, v):
        return (NET_HOP - A_PATH + self.link_ms
                + (NET_HUB if len(self.dirs[u]) > 2 else 0.0))

    # --- calls -------------------------------------------------------
    def digits(self, dst=None):
        """when the register has each digit, from the first digit's first break.  A local number is
        h s, h 2-7 and s 0-7.  A network number is 1 e b h s, with e b the code of the exchange called;
        a 0 is ten pulses"""
        if self.ports:
            h, sl = self.ports[int(self.rng.integers(0, len(self.ports)))]
        else:
            h, sl = int(self.rng.integers(2, 8)), int(self.rng.integers(0, 8))
        number = [h, sl] if dst is None else [1, int(dst[0]), int(dst[1]), h, sl]
        t, out, start = 0.0, [], []
        for d in number:
            start.append(t)                                  # this digit's first break
            t += (pulses_of(d) - 1) * self.tp.pulse + self.tp.brk
            out.append(t + self.tp.idw)                      # and when it is recognised
            t += float(self.rng.uniform(*self.tp.gap))
        self.starts = start
        return out

    def arrive(self, x, want=None):
        self.stat['calls'] += 1
        if want is not None:
            dst = want
        else:
            remote = self.rng.random() < self.leave and len(self.lines) > 1
            dst = x
            if remote:
                dst = self.codes[int(self.rng.integers(0, len(self.codes)))]
                while dst == x:
                    dst = self.codes[int(self.rng.integers(0, len(self.codes)))]
        self.at(self.t + float(self.rng.uniform(0, NET_SCAN)) + T_MARK, self.seize_register, x, dst, self.t)

    def seize_register(self, x, dst, lifted):
        if not self.reg[x].take(self.t):
            self.stat['no_register'] += 1
            if self.t - lifted < NET_SCAN * 1.5:
                self.stat['waited'] += 1          # the first time this caller was turned away
            if self.dt_wait is not None and self.t - lifted > self.dt_wait:
                self.stat['no_dialtone'] += 1           # the caller gave up on dial tone
                self.finish(x); return
            self.at(self.t + NET_SCAN, self.seize_register, x, dst, lifted)   # the scanner comes round again
            return
        self.dialtone.append(self.t - lifted)
        start = self.t + float(self.rng.uniform(*self.tp.dt_pause))
        if dst == x:
            self.stat['local'] += 1
            d = self.digits()
            self.at(start + d[-1] + T_MARK, self.local_call, x, lifted)
        else:
            self.stat['net'] += 1
            d = self.digits(dst)                     # 1 e b h s
            stopped = self.rng.random() < STOPS
            self.at(start + d[0] + T_MARK, self.open_flood, x, dst, lifted,
                    start + d[1], start + d[2], start + d[4], stopped,
                    start + self.starts[1])          # and when `e`'s first break is

    def local_call(self, x, lifted):
        self.reg[x].give(self.t)
        if self.rng.random() < self.busy_lines[x] / self.lines[x] or self.onhook[x] <= 0:
            self.stat['called_busy'] += 1; self.finish(x); return
        self.complete_local.append(self.t - lifted)
        self.connect(x, x, [], lifted)

    # --- the flood ---------------------------------------------------
    def open_flood(self, x, dst, lifted, t_e, t_b, t_last, stopped, t_break=None):
        legs, seized = [], []
        for d in self.dirs[x]:
            ch = self.chan[frozenset((x, d))]
            if ch.take(self.t):
                legs.append(d); seized.append(frozenset((x, d)))
        if not legs:
            self.stat['no_trunk'] += 1; self.reg[x].give(self.t); self.finish(x); return
        call = dict(origin=x, dst=dst, lifted=lifted, t_e=t_e, t_b=t_b, t_last=t_last,
                    held=seized, seized_at=self.t, claimed=False, stopped=stopped,
                    t_break=t_break if t_break is not None else self.t + 1e9)
        # monitor.md 3, rule 2: the origin sees both its own seizure and the caller's
        # next break, and abandons if the break is inside the guard -- because it cannot
        # know how far the flood has got, and a monitor patched in mid-digit counts short.
        if call['t_break'] < self.t + self.guard:
            self.stat['guarded'] += 1
            self.at(call['t_break'], self.guard_drop, call)
        for d in legs:
            self.at(self.t + self.hop(x, d), self.reaches, call, x, d, [frozenset((x, d))])
        if stopped:
            self.at(self.t + self.tp.timeout, self.give_up, call, True)    # the 5 s rule
        else:
            self.at(t_b + self.tp.no_claim, self.give_up, call, False)

    def guard_drop(self, call):
        """a break inside the guard: release the trunks and give cannot-complete."""
        if call['claimed']:
            return
        call['claimed'] = True
        self.reg[call['origin']].give(self.t)
        for l in call['held']:
            self.at(self.t + self.tp.fall, self.free, self.chan[l])
        call['held'] = []
        self.finish(call['origin'])

    def read_e(self, call):
        """What `e` a monitor patched in at this instant will count under `1 e b h s`.
        It saw the rise, so it counts from there -- and every pulse of `e` that has
        already gone by is one it never sees.  Returns the digit it will compare
        with its own `e` jumper, or None if the whole of `e` went by before it was
        patched in (when it would count `b` as `e` and miss the owner).  A match on
        `e` is not a claim: the monitor then reads `b` and claims only on both."""
        late = self.t - call['t_break']
        if late <= 0:
            return int(call['dst'][0])
        gone = int(late / self.tp.pulse) + 1          # the break in progress is gone too
        seen = pulses_of(int(call['dst'][0])) - gone
        return None if seen <= 0 else (0 if seen >= 10 else seen)

    def reaches(self, call, frm, x, path):
        """a seizure arrives at x from frm, having come by path: a monitor listens, and a transit
        forwards it on -- never into a strapped link, and never onward from one.
        Claim needs both code digits: e then b (`monitor.md` 2)."""
        mon = self.mon[(x, frm)]
        watched = mon.take(self.t)
        if not watched and x == call['dst'] and not call['stopped']:
            self.stat['no_monitor'] += 1
        # Has this exchange been patched in before the caller's next break?  If not, its
        # monitor counts a digit short, and what that costs depends on whose code it lands on.
        e_seen = self.read_e(call) if watched else int(call['dst'][0])
        if watched and e_seen != int(call['dst'][0]):
            self.stat['late'] += 1
            if x == call['dst']:
                self.stat['lost_owner'] += 1          # the owner reads its own code wrong
            elif e_seen is not None and x[0] == str(e_seen) and x[1] == call['dst'][1]:
                self.stat['wrong'] += 1               # wrong e that still fits another exchange's code
        if watched and call['stopped']:
            # no digit ever comes: the monitor holds until the origin's 5 s rule releases the trunk
            self.at(call['seized_at'] + self.tp.timeout + self.tp.fall, self.free, mon)
        elif watched:
            # let go after e if e is not ours; after b if it is (then claim on a full match)
            same_e = x[0] == call['dst'][0]
            self.at(max(self.t, call['t_b'] if same_e else call['t_e']), self.free, mon)
            if x == call['dst'] and e_seen == int(call['dst'][0]):
                self.at(call['t_b'] + T_MARK, self.claim, call, path)
        if call['claimed'] or path[-1] in self.strapped:
            return
        onward = [d for d in self.dirs[x] if d != frm and frozenset((x, d)) not in self.strapped]
        if not onward:
            return
        if len(onward) > 1:
            if not self.res[x].take(self.t):
                self.stat['no_resolver'] += 1
                onward = onward[:1]                              # patch into the first direction only
            else:
                self.at(call['t_b'] + T_MARK + NET_REPOINT, self.free, self.res[x])
        for d in onward:
            ch = self.chan[frozenset((x, d))]
            if ch.take(self.t):
                call['held'].append(frozenset((x, d)))
                self.at(self.t + self.hop(x, d), self.reaches, call, x, d, path + [frozenset((x, d))])

    def claim(self, call, path):
        """the first copy of the flood to be claimed is the call; every other leg lets go"""
        if call['claimed']:
            return
        call['claimed'] = True
        hops = len(path)
        back = hops * A_RISE + hops * NET_REPOINT
        keep, rest = list(path), list(call['held'])
        for l in keep:
            rest.remove(l)
        for l in rest:
            self.at(self.t + back + self.tp.fall, self.free, self.chan[l])
            self.flood_held.append(self.t + back + self.tp.fall - call['seized_at'])
        call['held'] = keep
        self.hops.append(hops)
        self.at(max(self.t + back, call['t_last'] + T_MARK), self.answered, call, keep)

    def answered(self, call, keep):
        x, dst = call['origin'], call['dst']
        self.reg[x].give(self.t)
        if self.rng.random() < self.busy_lines[dst] / self.lines[dst] or self.onhook[dst] <= 0:
            self.stat['called_busy'] += 1
            for l in keep:
                self.at(self.t + self.tp.busy, self.free, self.chan[l])
            self.finish(x)
            return
        self.complete_net.append(self.t - call['lifted'])
        self.connect(x, dst, keep, call['lifted'])

    def give_up(self, call, timed_out=False):
        if call['claimed']:
            return
        call['claimed'] = True
        self.stat['timed_out' if timed_out else 'no_claim'] += 1
        if timed_out:
            self.stopped_held.append(self.t + T_FALL - call['seized_at'])
        self.reg[call['origin']].give(self.t)
        for l in call['held']:
            self.at(self.t + self.tp.fall, self.free, self.chan[l])
        call['held'] = []
        self.finish(call['origin'])

    def connect(self, x, dst, keep, lifted):
        self.stat['done'] += 1
        if self.finite:
            # The called line answers.  It is taken off hook WITHOUT a wake of its own being
            # spent, so one of its own is cancelled: the book to keep is that the wakes
            # outstanding at an exchange are the lines on hook there, and a call that is
            # answered would otherwise leave the network one caller richer every time.
            self.busy_lines[dst] += 1; self.onhook[dst] -= 1; self.cancel[dst] += 1
        else:
            self.busy_lines[x] += 1; self.busy_lines[dst] += 1
        wait = float(self.rng.uniform(*self.tp.answer)) if self.tp.answer[1] else 0.0
        hold = wait + self.draw_hold()          # the called line is rung, then answers
        self.at(self.t + hold, self.release, x, dst, keep)

    def release(self, x, dst, keep):
        if self.finite:
            self.finish(x); self.finish(dst)
        else:
            self.busy_lines[x] -= 1; self.busy_lines[dst] -= 1
        for l in keep:
            self.at(self.t + self.tp.fall, self.free, self.chan[l])


NET_HOP = 7.0             # a seizure crossing one exchange (network.md 4)


def net_topology():
    """two hubs of four directions, three leaves each (network.md 5).  Codes share e by side."""
    hubs = ('11', '12')                      # backbone codes, by convention
    leaves = {'21': '11', '22': '11', '23': '11', '31': '12', '32': '12', '33': '12'}
    links = {(v, h): 6 for v, h in leaves.items()}
    links[hubs] = 12
    lines = {h: 24 for h in hubs}
    lines.update({v: 48 for v in leaves})
    return links, lines


BURST_UP, BURST_DOWN, BURST_X = 30e3, 300e3, 8.0   # 30 s of it, every 5 minutes, eight times the rate


def net_arrivals(sim, hours, spiky, calls_h=3.0):
    """calls a line makes: 3 an hour.  Smooth is Poisson.  Bursty is the same mean in bursts -- an
    office where a meeting ends, a shift changes, a switchboard is thrown open: 30 s at eight times
    the rate, once every 5 minutes.  The two differ in when the calls come, not how many."""
    rng, end = sim.rng, hours * 3600e3
    for x, n in sim.lines.items():
        mean = n * calls_h / 3600e3               # calls a millisecond
        if not spiky:
            t = 0.0
            while t < end:
                t += float(rng.exponential(1 / mean))
                if t < end:
                    sim.at(t, sim.arrive, x)
            continue
        share = BURST_UP / (BURST_UP + BURST_DOWN)
        quiet = mean / (1 - share + BURST_X * share)
        t, hot = 0.0, False
        while t < end:
            span = float(rng.exponential(BURST_UP if hot else BURST_DOWN))
            rate = quiet * (BURST_X if hot else 1.0)
            u = t
            while True:
                u += float(rng.exponential(1 / rate))
                if u >= t + span or u >= end:
                    break
                sim.at(u, sim.arrive, x)
            t += span; hot = not hot


def net():
    print('NET -- a network of eight exchanges, in milliseconds: the flood, the monitors, the claim,')
    print('  the registers and the channels.  Two hubs of four directions, three leaves each; 12 channels')
    print('  between the hubs and 6 to every leaf; 24 lines at a hub, 48 at a leaf, 336 in all.')
    print('  A line makes 3 calls an hour and holds one 48 s.  Dial 10 pps, 0.5-0.9 s between digits.')
    print('  Local calls are h s and touch no trunk; the rest are 1 e b h s and open a flood.')
    print(f'  Bursty is the same mean in bursts: {BURST_UP / 1000:.0f} s at {BURST_X:.0f}x the rate, every '
          f'{BURST_DOWN / 1000:.0f} s, an office at a shift change.')
    links, lines = net_topology()
    cases = (('smooth, 30 % leaving', 0.3, False, 3), ('bursty, 30 % leaving', 0.3, True, 3),
             ('bursty, 50 % leaving', 0.5, True, 3), ('bursty, 30 %, 2 registers', 0.3, True, 2),
             ('bursty, 30 %, 1 register', 0.3, True, 1))
    rows, hours = [], 12
    for label, leave, spiky, regs in cases:
        sim = Net(links, lines, regs=regs, leave=leave, seed=3)
        net_arrivals(sim, hours, spiky)
        sim.run(hours * 3600e3)
        rows.append((label, sim))

    print('\n  1. What a caller waits for.  Dial tone is the register; ringback is everything.')
    print(f'  {"":27s} {"calls":>6s} {"waited for":>11s} {"dial tone, ms":>26s} {"lift to ringback, s":>26s}')
    print(f'  {"":27s} {"an hr":>6s} {"a register":>11s} {"mean":>7s} {"95 %":>7s} {"99 %":>7s} {"worst":>7s}'
          f' {"local":>8s} {"network":>8s} {"worst":>8s}')
    for label, sim in rows:
        dt = np.array(sim.dialtone); loc = np.array(sim.complete_local) / 1000
        nw = np.array(sim.complete_net) / 1000
        print(f'  {label:27s} {sim.stat["calls"] / hours:6.0f} {100 * sim.stat["waited"] / sim.stat["calls"]:10.1f} %'
              f' {dt.mean():7.1f} {np.percentile(dt, 95):7.1f} {np.percentile(dt, 99):7.1f} {dt.max():7.0f}'
              f' {loc.mean():8.2f} {nw.mean():8.2f} {max(loc.max(), nw.max()):8.2f}')

    print('\n  2. What failed, per 1 000 calls.  A caller turned away waits a scan and asks again, so')
    print('     only the last five columns are calls that did not go through.')
    print(f'  {"":27s} {"no trunk":>9s} {"no monitor":>11s} {"no resolver":>12s} {"no claim":>9s} {"called busy":>12s}')
    for label, sim in rows:
        k, c = sim.stat, sim.stat['calls'] / 1000
        print(f'  {label:27s} {k["no_trunk"] / c:9.1f} {k["no_monitor"] / c:11.1f} '
              f'{k["no_resolver"] / c:12.1f} {k["no_claim"] / c:9.1f} {k["called_busy"] / c:12.1f}')

    print('\n  3. The links: erlangs, and the calls that found no free channel.')
    print(f'  {"":27s} {"a leaf link, 6 ch":>22s} {"hub to hub, 12 ch":>22s} {"flood held for nothing":>24s}')
    for label, sim in rows:
        t = hours * 3600e3
        leaf, hub = sim.chan[frozenset(('21', '11'))], sim.chan[frozenset(('11', '12'))]
        fh = np.array(sim.flood_held) / 1000
        print(f'  {label:27s} {leaf.erlang(t):9.2f} E {100 * leaf.refused / max(leaf.taken, 1):7.2f} %'
              f' {hub.erlang(t):9.2f} E {100 * hub.refused / max(hub.taken, 1):7.2f} %'
              f' {fh.mean():13.2f} s a leg')

    print('\n  4. The pools, erlangs and the % of the calls that wanted one and found none free.')
    print(f'  {"":27s} {"hub resolvers":>17s} {"hub registers":>12s} {"leaf registers":>15s} {"leaf monitors":>17s}')
    print('     A register turned away is a caller waiting a scan, counted in 1; the others are calls lost.')
    for label, sim in rows:
        t = hours * 3600e3
        f = lambda p: f'{p.erlang(t):6.2f} E {100 * p.refused / max(p.taken + p.refused, 1):5.1f} %'
        print(f'  {label:27s} {f(sim.res["11"]):>17s} {sim.reg["11"].erlang(t):10.2f} E'
              f' {sim.reg["21"].erlang(t):13.2f} E {f(sim.mon[("21", "11")]):>17s}')

    print(f'\n  5. The 5 s rule (network.md 4).  {100 * STOPS:.0f} % of network callers dial the key and stop.')
    print(f'  {"":27s} {"they were":>10s} {"trunks held, s":>15s} {"without the rule":>18s}')
    for label, sim in rows:
        if sim.stopped_held:
            sh = np.array(sim.stopped_held) / 1000
            print(f'  {label:27s} {sim.stat["timed_out"]:10d} {sh.mean():15.2f} {10 + T_FALL / 1000:18.2f}')

    p = predict(links, lines, (), 0.3)
    print(f'\n  6. Against the arithmetic of network.md 5, with these codes\' own floods ({p["flood"]:.2f} E a link):')
    print(f'     at 30 % leaving a leaf link is predicted {p["worst_e"]:.2f} E and {100 * p["worst_b"]:.2f} % blocking.  **Bursts leave')
    print('     the erlangs alone and fall on the registers**: the same calls, arriving together, wait for dial tone.')


# ------------------------------------------------------------------ topo

FLOOD_S = sum(code_hold(f'{e}{b}') for e in range(8) for b in range(8)) / 64     # over all 64 codes
ORIG_E = 3 * HOLD_MEAN / 3600e3           # erlangs a line originates: 3 calls an hour of 48 s
SLOW_HOP, SLOW_HUB = 12.0, 4.0            # a slow marker's hop, and a hub's extra (monitor.md 3)
SS0_HOLD = 0.4                            # SS0: a seizure held till the claim, a few hops out and back, and released


def lines_for(groups):
    """lines left at an exchange with this many trunk groups: the first sits in
    block 1, which holds no lines; each one more takes eight line slots
    (protocol.md 5, mf8-unit.md 7). Block 0 is never an MF8 group."""
    return max(0, 48 - 8 * max(0, groups - 1))


BACKBONE = [f'{e}{b}' for e in (1, 0) for b in (1, 2, 3, 4, 5, 6, 7, 0)]            # 00-17, by convention
ORDINARY = [f'{e}{b}' for e in (2, 3, 4, 5, 6, 7) for b in (1, 2, 3, 4, 5, 6, 7, 0)]   # 20-77, fewest pulses first


def shape(links, straps=()):
    """a network from its links {(u, v): channels}: lines by the groups each exchange fits, and codes by
    the convention of network.md 2 -- an exchange of three or four directions takes a backbone
    code, 00-17, the rest 20-77, and either kind spills into the other's when its own run out"""
    names = sorted({x for l in links for x in l}, key=lambda n: (len(n), n))
    assert len(names) <= 64, 'more than 64 exchanges'
    degree = {n: sum(n in l for l in links) for n in names}
    spare = {True: list(BACKBONE), False: list(ORDINARY)}
    code = {}
    for n in names:
        kind = degree[n] > 2
        code[n] = (spare[kind] or spare[not kind]).pop(0)
    groups = {n: 0 for n in names}
    for (u, v), ch in links.items():
        groups[u] += -(-ch // 8); groups[v] += -(-ch // 8)
    lk = {(code[u], code[v]): ch for (u, v), ch in links.items()}
    ln = {code[n]: lines_for(groups[n]) for n in names}
    assert max(groups.values()) <= 7, 'more than seven trunk groups'
    return lk, ln, [(code[u], code[v]) for u, v in straps], code


def predict(links, lines, straps=(), leave=0.3, hold=None):
    """Erlang arithmetic for a tree, or a tree with strapped links across it (network.md 3.3, 5).
    hold: seconds a call that leaves holds a channel on every link it is offered to.  None is the
    pulse flood, each code its own; a number is SS0, where the seizure lasts only till the claim"""
    strapped = {frozenset(l) for l in straps}
    tree = {x: [] for x in lines}
    for u, v in links:
        if frozenset((u, v)) not in strapped:
            tree[u].append(v); tree[v].append(u)
    assert max(len(tree[x]) + sum(x in l for l in strapped) for x in lines) <= 4, 'more than four directions'

    reach = {}

    def path(u, v):
        if frozenset((u, v)) in strapped:
            return [u, v]
        seen = reach.get(u)
        if seen is None:
            seen, front = {u: [u]}, [u]
            while front:
                nxt = []
                for x in front:
                    for y in tree[x]:
                        if y not in seen:
                            seen[y] = seen[x] + [y]; nxt.append(y)
                front = nxt
            reach[u] = seen
        return seen[v]

    n, total = len(lines), sum(lines.values())
    load = {frozenset(l): 0.0 for l in links}
    paths = {}
    for u in lines:
        for v in lines:
            if u != v:
                p = path(u, v); paths[(u, v)] = p
                for a, b in zip(p, p[1:]):
                    load[frozenset((a, b))] += lines[u] * ORIG_E * leave / (n - 1)
    rate = 3 / 3600 * leave * (hold if hold else sum(code_hold(c) for c in lines) / n)
    chans = {frozenset(l): c for l, c in links.items()}
    flood = {l: (sum(lines[x] for x in l) if l in strapped else total) * rate for l in load}
    block = {l: erlang_b(load[l] + flood[l], chans[l]) for l in load}
    worst = max(block, key=block.get)
    lost = {}
    for (u, v), p in paths.items():
        ok = 1.0
        for a, b in zip(p, p[1:]):
            ok *= 1 - block[frozenset((a, b))]
        lost[(u, v)] = 1 - ok
    w = {k: lines[k[0]] for k in lost}
    need = lambda a: next(m for m in range(1, 40) if erlang_b(a, m) <= 0.005)
    hubs = [x for x in lines if len(tree[x]) > 2]
    far = max(total - lines[x] for x in lines)                 # the worst block hears every flood but its own
    spread = max(sum(SLOW_HOP + (SLOW_HUB if len(tree[x]) > 2 else 0) for x in p[1:]) for p in paths.values())
    return dict(n=n, lines=total, flood=total * rate, worst=worst, worst_e=load[worst] + flood[worst],
                worst_ch=chans[worst], worst_b=block[worst], pair=max(lost.values()),
                mean=sum(lost[k] * w[k] for k in lost) / sum(w.values()),
                hops=sum((len(paths[k]) - 1) * w[k] for k in lost) / sum(w.values()),
                diameter=max(len(p) - 1 for p in paths.values()), spread=spread,
                monitors=need(far * rate), resolvers=need(max((total - lines[h]) * rate for h in hubs)) if hubs else 0)


def chain_links(n, ch, end=None):
    return {(f'x{i:02d}', f'x{i + 1:02d}'): (end if end and i in (0, n - 2) else ch) for i in range(n - 1)}


def star_links(spokes, ch, k=1, inner=None, outer=None):
    """a hub with chains of k exchanges on each spoke: inner channels next the hub, outer on the last link"""
    out = {}
    for s in range(spokes):
        prev = 'hub'
        for i in range(k):
            out[(prev, f's{s}{i}')] = (outer or ch) if (i == k - 1 and k > 1) else (inner or ch)
            prev = f's{s}{i}'
    return out


def tree_links(m=12, up=12, down=6):
    """a tandem of four directions, a sub-hub on each, three chains on each sub-hub: m leaves dealt
    round the twelve chains.  A link with an exchange beyond it is 12 channels; the last is `down`"""
    depth = [m // 12 + (1 if c < m % 12 else 0) for c in range(12)]
    out = {}
    for h in range(4):
        out[('t', f'h{h}')] = up
        for c in range(3):
            prev = f'h{h}'
            for i in range(depth[h * 3 + c]):
                out[(prev, f'l{h}{c}{i}')] = down if i == depth[h * 3 + c] - 1 else 12
                prev = f'l{h}{c}{i}'
    return out


def core_links(m, core=18):
    """three tandems in a chain, five 12-channel branches off them (two, one, two), a sub-hub on each
    branch with three chains: m leaves dealt round the fifteen chains, every link 12 channels"""
    out = {('r0', 'r1'): core, ('r1', 'r2'): core}
    depth = [m // 15 + (1 if c < m % 15 else 0) for c in range(15)]
    for b, root in enumerate(('r0', 'r0', 'r1', 'r2', 'r2')):
        out[(root, f'h{b}')] = 12
        for c in range(3):
            prev = f'h{b}'
            for i in range(depth[b * 3 + c]):
                out[(prev, f'l{b}{c}{i}')] = 12
                prev = f'l{b}{c}{i}'
    return out


def two_hubs(bypass=False):
    out = {('h0', 'h1'): 12}
    for h in range(2):
        for c in range(3):
            out[(f'h{h}', f'l{h}{c}')] = 6
    if bypass:
        out[('l00', 'l10')] = 6            # a loop through both hubs: a leaf on each side joined directly
    return out


def ring_links(n, ch):
    out = chain_links(n, ch)
    out[(f'x{n - 1:02d}', 'x00')] = ch
    return out


def topo():
    print('TOPO -- what shapes of network the protocol carries, and how large.  A line makes 3 calls an hour of')
    print(f'  48 s; every call that leaves floods every link for 2.0 to 3.8 s by the code it calls, {FLOOD_S:.2f} s over all 64')
    print('  (network.md 4); each shape is worked with its own codes, the backbone\'s from 00-17.  An exchange')
    print('  faces four directions at most and fits eight trunk groups at most; it keeps 48 lines with two')
    print('  groups and gives up six for each one more.  Arithmetic is Erlang B on a tree, as network.md 5')
    print('  and `net` agree it may be; "pair" is the worst end-to-end loss between two exchanges, "lost" the mean.')

    head = (f'  {"":34s} {"exch":>4s} {"lines":>6s} {"flood":>6s} {"worst link":>24s} {"pair":>7s} {"lost":>7s} '
            f'{"hops":>5s} {"across":>7s} {"spread":>7s} {"mon":>4s} {"res":>4s}')

    def row(label, links, straps=(), leave=0.3):
        lk, ln, st, code = shape(links, straps)
        p = predict(lk, ln, st, leave)
        print(f'  {label:34s} {p["n"]:4d} {p["lines"]:6d} {p["flood"]:5.2f}E {p["worst_e"]:6.2f} E on {p["worst_ch"]:2d} ch '
              f'{100 * p["worst_b"]:6.2f}% {100 * p["pair"]:6.2f}% {100 * p["mean"]:6.2f}% {p["hops"]:5.2f} '
              f'{p["diameter"]:4d} hp {p["spread"]:4.0f} ms {p["monitors"]:4d} {p["resolvers"]:4d}')
        return p

    print('\n  1. Chains, 30 % of calls leaving.  "spread" is the flood crossing the network at a slow marker,')
    print('     against the origin\'s 128 ms guard; mon and res are the monitors a block and resolvers a hub for 0.5 %.')
    print(head)
    for ch in (6, 12):
        for n in (2, 3, 4, 5, 6, 8, 10, 11, 12):
            row(f'chain of {n}, {ch} channels', chain_links(n, ch))
    print('     A chain of 12 is 11 hops: 132 ms at a slow marker, outside the guard.')

    print('\n  2. Hubs.  A hub faces four directions; a tandem gives all eight groups to trunks and keeps 6 lines.')
    print(head)
    row('star: hub and 4 spokes, 6 ch', star_links(4, 6))
    row('star: tandem and 4 spokes, 12 ch', star_links(4, 12))
    row('two hubs, six leaves (net)', two_hubs())
    for k in (2, 3, 4, 5):
        row(f'tandem, 4 chains of {k}, 12 ch', star_links(4, 12, k, outer=6))
    for k in (4, 5, 6, 8):
        row(f'tandem, 4 chains of {k}, 12 ch all', star_links(4, 12, k))
    row('tree: tandem, 4 sub-hubs, 12 leaves', tree_links(12))
    row('  the same, 12 ch to every leaf', tree_links(12, 12, 12))
    row('tree: ... and 24 leaves (29)', tree_links(24))
    row('  the same, 12 ch to every leaf', tree_links(24, 12, 12))
    row('tree: ... and 31 leaves (36)', tree_links(31, 12, 12))
    row('three tandems, 5 branches, 18 lv', core_links(18))
    row('three tandems, 5 branches, 28 lv', core_links(28))

    print('\n  3. The same shapes as fewer or more calls leave home.')
    print(head)
    for leave in (0.2, 0.5):
        print(f'     {100 * leave:.0f} % leaving')
        row('chain of 5, 6 channels', chain_links(5, 6), leave=leave)
        row('chain of 8, 12 channels', chain_links(8, 12), leave=leave)
        row('two hubs, six leaves (net)', two_hubs(), leave=leave)
        row('tandem, 4 chains of 5, 12 ch all', star_links(4, 12, 5), leave=leave)
        row('tree: tandem, 4 sub-hubs, 12 leaves', tree_links(12), leave=leave)
        row('  the same, 12 ch to every leaf', tree_links(12, 12, 12), leave=leave)

    print('\n  4. The largest of each family with no link over 1 %, inside the 64 codes and the 128 ms guard.')
    print(head)
    fams = (('chain, 6 ch', lambda n: chain_links(n, 6), range(2, 13)),
            ('chain, 12 ch', lambda n: chain_links(n, 12), range(2, 13)),
            ('star, 6 ch', lambda n: star_links(n, 6), range(2, 5)),
            ('tandem, 4 chains, 12 ch', lambda k: star_links(4, 12, k), range(1, 9)),
            ('tree, 12 ch, leaves', lambda m: tree_links(m, 12, 12), range(1, 60)),
            ('three tandems, leaves', lambda m: core_links(m), range(1, 57)))
    for leave in (0.2, 0.3, 0.5):
        print(f'     {100 * leave:.0f} % leaving')
        for label, make, sizes in fams:
            best = None
            for z in sizes:
                lk, ln, st, _ = shape(make(z))
                p = predict(lk, ln, st, leave)
                if p['worst_b'] <= 0.01 and p['spread'] <= G_ORIGIN:
                    best = z
            if best:
                row(f'{label}: {best}', make(best), leave=leave)
            else:
                print(f'  {label}: none')

    print('\n  5. Rings.  A link strapped with n carries calls between its own two ends only (network.md 3.3).')
    print(head)
    for n in (4, 6, 8):
        row(f'chain of {n}, 6 channels', chain_links(n, 6))
        row(f'ring of {n}, one link strapped', ring_links(n, 6), [(f'x{n - 1:02d}', 'x00')])
    row('two hubs, six leaves (net)', two_hubs())
    row('  and a strapped leaf-to-leaf link', two_hubs(True), [('l00', 'l10')])

    print(f'\n  6. The same families under SS0 (ss0.md), whose seizure lasts only until the claim,')
    print(f'     taken as {SS0_HOLD:.1f} s against the pulse flood\'s 2.0-3.8 s, and which needs no monitor and no guard.')
    print(f'  {"":34s} {"pulse flood":>28s} {"SS0":>28s}')
    print(f'  {"":34s} {"exch":>5s} {"lines":>6s} {"worst":>7s} {"across":>8s} {"exch":>5s} {"lines":>6s} {"worst":>7s} {"PDD":>8s}')
    for label, make, sizes in fams:
        best = {}
        for h in (None, SS0_HOLD):
            for z in sizes:
                lk, ln, st, _ = shape(make(z))
                p = predict(lk, ln, st, 0.3, h)
                if p['worst_b'] <= 0.01 and (h or p['spread'] <= G_ORIGIN):
                    best[h] = (z, p)
        if None in best and SS0_HOLD in best:
            (z1, p1), (z2, p2) = best[None], best[SS0_HOLD]
            print(f'  {label:34s} {p1["n"]:5d} {p1["lines"]:6d} {100 * p1["worst_b"]:6.2f}% {p1["spread"]:5.0f} ms '
                  f'{p2["n"]:5d} {p2["lines"]:6d} {100 * p2["worst_b"]:6.2f}% {T_ID + T_MARK + p2["diameter"] * (SS0_HOP + A_RISE) + T_MARK:5.0f} ms')
    print('     SS0\'s "across" is post-dial delay, the caller\'s last pulse to ringback at the far end:')
    print(f'     {T_ID:.0f} ms to recognise the digit and {SS0_HOP + A_RISE:.0f} ms a hop, against the flood\'s 133 ms whatever the distance.')

    print('\n  7. Run call by call, 12 hours, smooth demand, 30 % leaving, three registers; monitors a block and')
    print('     resolvers a hub three of each unless the row says.  The worst link is the one that refused most.')
    print(f'  {"":34s} {"calls":>6s} {"worst link":>22s} {"network calls lost / 1 000":>28s} {"hops":>5s} '
          f'{"flood held":>11s} {"ringback":>9s}')
    print(f'  {"":34s} {"an hr":>6s} {"":>22s} {"no trunk":>9s} {"no claim":>9s} {"pools":>8s} {"":>5s} {"a leg":>11s} {"network":>9s}')
    runs = (('chain of 6, 6 channels', chain_links(6, 6), (), 3),
            ('star: hub and 4 spokes, 6 ch', star_links(4, 6), (), 3),
            ('two hubs, six leaves (net)', two_hubs(), (), 3),
            ('  and a strapped leaf-to-leaf link', two_hubs(True), [('l00', 'l10')], 3),
            ('tree: tandem, 4 sub-hubs, 12 leaves', tree_links(12), (), 3),
            ('  the same, four of each pool', tree_links(12), (), 4),
            ('tree, 24 leaves, 12 ch, five', tree_links(24, 12, 12), (), 5),
            ('three tandems, 28 leaves, five', core_links(28), (), 5),
            ('ring of 6, one link strapped', ring_links(6, 6), [('x05', 'x00')], 3),
            ('ring of 6, NO strap', ring_links(6, 6), (), 3),
            ('ring of 4, NO strap', ring_links(4, 6), (), 3))
    for label, links, straps, pools in runs:
        lk, ln, st, _ = shape(links, straps)
        sim = Net(lk, ln, mons=pools, resolvers=pools, leave=0.3, seed=5, strapped=st)
        hours = 12
        net_arrivals(sim, hours, False)
        sim.run(hours * 3600e3)
        t = hours * 3600e3
        w = max(sim.chan, key=lambda l: (sim.chan[l].refused / max(sim.chan[l].taken + sim.chan[l].refused, 1),
                                         sim.chan[l].erlang(t) / sim.chan[l].n))
        c = sim.chan[w]
        k, nc = sim.stat, max(sim.stat['net'], 1) / 1000
        print(f'  {label:34s} {k["calls"] / hours:6.0f} {c.erlang(t):6.2f} E on {c.n:2d} ch {100 * c.refused / max(c.taken + c.refused, 1):6.2f}%'
              f' {k["no_trunk"] / nc:9.1f} {k["no_claim"] / nc:9.1f} {(k["no_monitor"] + k["no_resolver"]) / nc:8.1f}'
              f' {np.mean(sim.hops):5.2f} {np.mean(sim.flood_held) / 1000:9.2f} s {np.mean(sim.complete_net) / 1000:7.2f} s')
    print('\n  8. One call, alone, on a ring of six: channels seized 1.5 s after the handset is lifted.')
    for label, straps in (('one link strapped', [('x05', 'x00')]), ('NO strap', ())):
        lk, ln, st, code = shape(ring_links(6, 6), straps)
        sim = Net(lk, ln, leave=1.0, seed=2, strapped=st)
        sim.at(0.0, sim.arrive, code['x00'])
        sim.run(1500.0)
        print(f'     {label:20s} {sum(p.used for p in sim.chan.values()):3d} of {sum(p.n for p in sim.chan.values())}')
    print('     An unstrapped ring sends every flood round and round until the links are full, and holds them')
    print('     until the code is dialled: about two seconds of a whole ring for every call that leaves.')


# ------------------------------------------------------------------ traffic

# The bursts and the herds, in the FAST clock `make traffic` runs on.  `net`'s figures are life:
# 30 s of burst every 5 minutes.  Eight times faster that is 3.8 s every 38 s, which a 25 s run
# would see once; these are the same duty cycle on a shorter turn, so a run sees a dozen.
T_UP, T_DOWN, T_X = 1000.0, 5000.0, 8.0          # hot one second in six, at eight times the rate
H_EVERY, H_PC, H_SPREAD = 6000.0, 0.33, 300.0    # a flash crowd: a third of the network, in 300 ms

# `make traffic`: two hubs on one link, three leaves on each, six channels everywhere, twelve
# lines an exchange.  The codes are the bench's own -- e from 2, b from 1, so that no exchange's
# code costs ten pulses -- and the ports are the slots it fits lines in, blocks 2 and 5.
RTL_LINES = 12
RTL_PORTS = [(2, s) for s in range(8)] + [(5, s) for s in range(4)]


def rtl_code(i):
    return f'{2 + i // 7}{1 + i % 7}'


def rtl_net(nhub=2, spoke=3, slen=1, ch=6, nline=RTL_LINES):
    """the topology tb_traffic builds from the same three numbers: a chain of hubs, spokes on
    each, each spoke a chain"""
    links = {}
    for h in range(nhub - 1):
        links[(rtl_code(h), rtl_code(h + 1))] = ch
    for h in range(nhub):
        for sp in range(spoke):
            prev = h
            for p in range(slen):
                idx = nhub + (h * spoke + sp) * slen + p
                links[(rtl_code(prev), rtl_code(idx))] = ch
                prev = idx
    lines = {rtl_code(i): nline for i in range(nhub + nhub * spoke * slen)}
    return links, lines


def phase(links, lines, idle, secs, model='smooth', holds='exp', leave=0.3, seed=1,
          regs=3, mons=3, res=3, tempo=None, ports=RTL_PORTS, dt_wait=1200.0, warm=4000.0):
    """one phase of demand on a fresh network: every line a source, arriving by `model`.  The
    first `warm` ms are run and then forgotten, as tb_traffic's own phases are."""
    sim = Net(links, lines, regs=regs, mons=mons, resolvers=res, leave=leave, seed=seed,
              tempo=tempo or FAST, idle=idle, holds=holds, dt_wait=dt_wait, ports=ports,
              burst=(T_UP, T_DOWN, T_X) if model == 'bursty' else None)
    sim.start_lines()
    if model == 'bursty':
        sim.at(float(sim.rng.exponential(T_DOWN)), sim.go_hot, T_UP, T_DOWN)
    if model == 'herd':
        sim.at(float(sim.rng.exponential(H_EVERY)), sim.a_herd, H_PC, H_SPREAD, H_EVERY)
    sim.run(warm)
    sim.forget()
    sim.run(warm + secs * 1000.0)
    return sim


def per_s(sim, n):
    """a rate over the measured part of a run, which is what is left after the warm-up"""
    return 1000.0 * n / max(sim.t - sim.t0, 1.0)


def link_stat(sim, u, v):
    p = sim.chan[frozenset((u, v))]
    return p.erlang(sim.t), 100 * p.refused / max(p.taken + p.refused, 1), p.hi


def pooled(sim, what):
    """the mean over every exchange of a pool's erlangs, and what it turned away"""
    ps = list(what.values())
    e = sum(p.erlang(sim.t) for p in ps) / len(ps)
    ref = sum(p.refused for p in ps)
    tk = sum(p.taken + p.refused for p in ps)
    return e, 100 * ref / max(tk, 1)


# What `make traffic-net` and `make traffic-deep` measured -- the same networks, the same
# clock, the same two phases, in eight and ten whole exchanges of RTL.  `verilog/README.md`
# carries the runs.  A pool is quoted the way the bench quotes it: a register pool an
# exchange, a monitor pool a trunk block, a resolver pool at every exchange that forwards.
RTL_RUN = {
    'off peak':      dict(calls=20.9, done=114, hub_e=2.48, sp=(2.33, 2.47, 2.81),
                          reg=1.50, mon=0.30, res=0.85, dt=32.6, all_e=20.04),
    'peak':          dict(calls=33.1, done=121, hub_e=3.10, sp=(2.77, 3.17, 3.66),
                          reg=2.05, mon=0.33, res=1.24, dt=68.6, all_e=26.41),
    'deep off peak': dict(calls=26.0, done=110, hub_e=3.97, near=(3.69, 4.26), far=4.10,
                          reg=1.58, res=1.34, dt=39.1, all_e=35.59),
    'deep peak':     dict(calls=39.2, done=144, hub_e=3.76, near=(3.59, 4.11), far=3.78,
                          reg=2.04, res=1.26, dt=70.9, all_e=34.59),
}


def traffic():
    print('TRAFFIC -- demand that is not smooth, and the same network at peak and off peak.')
    print('  Every line is a SOURCE here, not a Poisson stream: it hangs up, waits, and lifts again,')
    print('  so the offered load falls as the exchange fills.  That is what `make traffic-net` has in the')
    print('  gates -- a line is a state machine there and there is no other kind of caller -- and this')
    print('  runs on the same clock as the RTL bench: the dial and the register\'s three windows eight')
    print('  times life, the marker\'s 8 ms scan and its 7 ms hop untouched.')
    links, lines = rtl_net()
    tot = sum(lines.values())
    print(f'\n  The network: 8 exchanges, two hubs on one link with three leaves each, six channels')
    print(f'  every link, {RTL_LINES} lines an exchange, {tot} in all.  Three registers, three monitor cells a')
    print('  block, three resolvers.  30 % of calls leave home; a conversation averages 0.5 s.')

    SECS, OP, PK, WARM = 10, 3000, 1500, 6000.0
    LONG = SECS_2 = 240             # sections 2-4 are not tied to the RTL's run length
    print(f'  Phase 1 is {SECS} s, measured after {WARM / 1000:.0f} s of warm-up -- a phase begins with every')
    print('  line on hook, which is not a state the network is ever in otherwise, and the warm-up is')
    print('  twice the longer idle so that what is measured is a network in its stride.  Off peak a line')
    print(f'  waits {OP} ms between calls and at peak {PK} ms.  `make traffic-net` runs the same two')
    print(f'  phases in the gates.  2 to 4 are not tied to that and run {LONG} s, because a 1 % loss is')
    print('  not a measurement over a few hundred seizures.')

    # ---- 1. against the RTL --------------------------------------------
    print('\n  1. The same network in the gates and here.  `make traffic-net` is the RTL column.')
    rows = []
    for name, idle in (('off peak', OP), ('peak', PK)):
        rows.append((name, phase(links, lines, idle, SECS, seed=7, warm=WARM)))
    print(f'  {"":16s} {"calls/s":>8s} {"talked":>7s} {"hub link":>9s} {"the 3 spoke links":>19s} '
          f'{"registers":>10s} {"monitors":>9s} {"resolvers":>10s} {"dial tone":>10s}')
    print(f'  {"":16s} {"offered":>8s} {"":>7s} {"E":>9s} {"E, lowest to highest":>19s} '
          f'{"mean E":>10s} {"mean E":>9s} {"mean E":>10s} {"mean, ms":>10s}')
    for name, sim in rows:
        he, _, _ = link_stat(sim, '21', '22')
        sp = sorted(link_stat(sim, '21', v)[0] for v in ('23', '24', '25'))
        re_, _ = pooled(sim, sim.reg)
        mo, _ = pooled(sim, sim.mon)
        rs, _ = pooled(sim, sim.res)
        dt = np.array(sim.dialtone)
        print(f'  {name:16s} {per_s(sim, sim.stat["calls"]):8.1f} {sim.stat["done"]:7d} '
              f'{he:9.2f} {sp[0]:6.2f} {sp[1]:6.2f} {sp[2]:6.2f} {re_:10.2f} {mo:9.2f} '
              f'{rs:10.2f} {dt.mean():10.1f}')
        if name in RTL_RUN:
            r = RTL_RUN[name]
            print(f'  {"  in the gates":16s} {r["calls"]:8.1f} {r["done"]:7d} '
                  f'{r["hub_e"]:9.2f} {r["sp"][0]:6.2f} {r["sp"][1]:6.2f} {r["sp"][2]:6.2f} '
                  f'{r["reg"]:10.2f} {r["mon"]:9.2f} {r["res"]:10.2f} {r["dt"]:10.1f}')
    for name, sim in rows:
        tot = sum(p.erlang(sim.t) for p in sim.chan.values())
        rate = per_s(sim, sim.stat['calls'])
        line = (f'     {name:8s}: every link taken together is {tot:5.2f} E here'
                f' -- {tot / rate:.3f} E for each call a second offered')
        if name in RTL_RUN:
            r = RTL_RUN[name]
            line += f', and {r["all_e"]:5.2f} E / {r["all_e"] / r["calls"]:.3f} in the gates'
        print(line)
    print('     Erlangs are what both models measure the same way: a channel-millisecond is a')
    print('     channel-millisecond.  Loss is not -- the RTL counts the marker\'s own "every trunk')
    print('     this way is busy" event, which is raised when an ORIGIN hunts and finds none, and')
    print('     `Pool.refused` here is every seizure turned away, a transit\'s forward included.')

    # ---- 1b. ten exchanges, spokes two deep ----------------------------
    print('\n     And the same again at TEN exchanges: the two hubs with two spokes each, and each')
    print('     spoke two deep, so that every spoke has a TRANSIT on it and the link next the hub')
    print('     carries the whole spoke past it.  `make traffic-deep` is the RTL column.')
    dlinks, dlines = rtl_net(2, 2, 2)
    drows = []
    for name, idle in (('off peak', OP), ('peak', PK)):
        # 8 s, which is what the ten-exchange RTL run is: it costs a quarter more
        # than the eight and the phase was cut to keep it inside the afternoon
        drows.append((name, phase(dlinks, dlines, idle, 8, seed=7, warm=WARM)))
    print(f'  {"":16s} {"calls/s":>8s} {"talked":>7s} {"hub link":>9s} {"next the hub":>13s} '
          f'{"the far link":>13s} {"registers":>10s} {"resolvers":>10s} {"dial tone":>10s}')
    for name, sim in drows:
        he, _, _ = link_stat(sim, '21', '22')
        near = sorted(link_stat(sim, '21', v)[0] for v in ('23', '25'))
        far = link_stat(sim, '23', '24')[0]          # the link beyond the transit
        re_, _ = pooled(sim, sim.reg)
        rs, _ = pooled(sim, sim.res)
        dt = np.array(sim.dialtone)
        print(f'  {name:16s} {per_s(sim, sim.stat["calls"]):8.1f} {sim.stat["done"]:7d} '
              f'{he:9.2f} {near[0]:6.2f} {near[1]:6.2f} {far:13.2f} {re_:10.2f} {rs:10.2f} '
              f'{dt.mean():10.1f}')
        if ('deep ' + name) in RTL_RUN:
            r = RTL_RUN['deep ' + name]
            print(f'  {"  in the gates":16s} {r["calls"]:8.1f} {r["done"]:7d} '
                  f'{r["hub_e"]:9.2f} {r["near"][0]:6.2f} {r["near"][1]:6.2f} {r["far"]:13.2f} '
                  f'{r["reg"]:10.2f} {r["res"]:10.2f} {r["dt"]:10.1f}')
    for name, sim in drows:
        tot = sum(p.erlang(sim.t) for p in sim.chan.values())
        rate = per_s(sim, sim.stat['calls'])
        line = (f'     {name:8s}: every link taken together is {tot:5.2f} E here'
                f' -- {tot / rate:.3f} E for each call a second offered')
        if ('deep ' + name) in RTL_RUN:
            r = RTL_RUN['deep ' + name]
            line += f', and {r["all_e"]:5.2f} E / {r["all_e"] / r["calls"]:.3f} in the gates'
        print(line)
    print('     A spoke\'s two links are the one next the hub, which carries the transit\'s own lines')
    print('     AND the exchange behind it, and the one beyond, which carries one exchange.')

    print(f'\n     Every link of the eight, both phases.  Erlang B is on the erlangs the run carried.')
    print(f'  {"link":10s} {"phase":10s} {"erlang":>7s} {"high":>5s} {"Erlang B":>9s} {"refused":>9s}')
    for u, v in sorted({tuple(sorted(l)) for l in ((a, b) for a, b in links)}):
        for name, sim in rows:
            e, b, hi = link_stat(sim, u, v)
            print(f'  {u} = {v}  {name:10s} {e:7.2f} {hi:5d} {100 * erlang_b(e, 6):8.2f} % {b:8.2f} %')

    # ---- 2. the traffic models -----------------------------------------
    print('\n  2. Four ways the same mean can arrive.  Smooth is Poisson.  Bursty is the network')
    print(f'     going hot and cold together -- {T_UP / 1000:.0f} s at {T_X:.0f}x the rate in every {(T_UP + T_DOWN) / 1000:.0f} s.  Herd is a flash')
    print(f'     crowd: {100 * H_PC:.0f} % of every line in the network lifts inside {H_SPREAD:.0f} ms, and they all dial')
    print('     the SAME exchange -- not only when the calls come but where they go.')
    print(f'  {"arrivals":12s} {"phase":9s} {"calls/s":>8s} {"busiest link":>26s} {"registers":>18s} '
          f'{"dial tone, ms":>24s}')
    print(f'  {"":12s} {"":9s} {"offered":>8s} {"E":>7s} {"E a call/s":>10s} {"blocked":>7s} {"mean E":>8s} {"waited":>9s} '
          f'{"mean":>8s} {"95 %":>7s} {"worst":>7s}')
    mrows = []
    # Off peak here is the 6 000 ms of `net`'s own line, not the 3 000 that phase 1
    # uses: nothing ties 2 to 4 to the RTL's phase, and a light hour is where a
    # herd shows.  The warm-up is twice the idle throughout.
    for model in ('smooth', 'bursty', 'herd'):
        for nm, idle in (('off peak', 6000), ('peak', PK)):
            sim = phase(links, lines, idle, SECS_2, model=model, seed=11,
                        warm=2.0 * idle)
            if nm == 'peak':
                mrows.append((model, sim))
            w = max(sim.chan.values(), key=lambda p: p.erlang(sim.t))
            re_, rw = pooled(sim, sim.reg)
            dt = np.array(sim.dialtone)
            rate = per_s(sim, sim.stat['calls'])
            print(f'  {model:12s} {nm:9s} {rate:8.1f} {w.erlang(sim.t):7.2f} {w.erlang(sim.t) / rate:10.3f} '
                  f'{100 * w.refused / max(w.taken + w.refused, 1):6.2f} % {re_:8.2f} {rw:8.1f} % '
                  f'{dt.mean():8.1f} {np.percentile(dt, 95):7.1f} {dt.max():7.0f}')
    print('     "waited" is the share of callers the scanner had to come back to, which is dial tone')
    print(f'     late and not a call lost (marker.md 6).  {mrows[2][1].stat["herds"]} herds were let loose.')
    print('')
    print('     A BURST DOES NOT OFFER THE SAME CALLS, and that is not the model being wrong.  The')
    print('     cold rate is set so the mean over the cycle is the smooth one, which is exact for')
    print(f'     arrivals out of nowhere; but a line that is off hook cannot lift, and at {T_X:.0f}x the rate the')
    print('     hot idle is shorter than a call, so the lines themselves are the limit.  `net`, whose')
    print('     callers arrive from nowhere, cannot show this: it is what makes a line a source.')
    print('     "E a call/s" is the link\'s erlangs divided by the calls a second that produced them,')
    print('     so the three may be read against each other at the load each one managed to offer.')

    print('\n     Where each model falls.  The flood is on every link whatever the shape of the demand;')
    print('     what moves is which link, and how long a caller waits for a register.')
    print(f'  {"arrivals":12s} {"busiest link":>24s} {"every link":>12s} {"monitors":>18s} {"resolvers":>18s}')
    for model, sim in mrows:
        w = max(sim.chan, key=lambda l: sim.chan[l].erlang(sim.t))
        tot_e = sum(p.erlang(sim.t) for p in sim.chan.values())
        me, mb = pooled(sim, sim.mon)
        se, sb = pooled(sim, sim.res)
        u, v = sorted(w)
        print(f'  {model:12s} {u} = {v}{"":>8s} {sim.chan[w].erlang(sim.t):7.2f} E {tot_e:10.2f} E '
              f'{me:10.2f} E {mb:5.1f} % {se:10.2f} E {sb:5.1f} %')

    # ---- 3. the holding-time law ----------------------------------------
    print('\n  3. The same arrivals, three holding-time laws of the same mean.  Erlang B is insensitive')
    print('     to the law in theory; nothing in this exchange has read Erlang.')
    print(f'  {"holding":14s} {"sd/mean":>8s} {"calls/s":>8s} {"worst link":>18s} {"Erlang B":>10s} '
          f'{"every link":>12s}')
    for holds, label, cv in (('exp', 'exponential', 1.00), ('flat', 'constant', 0.00),
                             ('two', 'two-class 9:1', 1.55)):
        sim = phase(links, lines, PK, LONG, holds=holds, seed=13, warm=2.0 * PK)
        w = max(sim.chan.values(), key=lambda p: p.erlang(sim.t))
        wb = max(sim.chan.values(), key=lambda p: p.refused / max(p.taken + p.refused, 1))
        tot_e = sum(p.erlang(sim.t) for p in sim.chan.values())
        print(f'  {label:14s} {cv:8.2f} {per_s(sim, sim.stat["calls"]):8.1f} {w.erlang(sim.t):7.2f} E '
              f'{100 * wb.refused / max(wb.taken + wb.refused, 1):6.2f} % {100 * erlang_b(w.erlang(sim.t), 6):9.2f} % '
              f'{tot_e:10.2f} E')

    # ---- 4. peak against off peak ---------------------------------------
    print('\n  4. Peak against off peak, as a sweep: the same network, the idle between a line\'s calls')
    print('     cut step by step.  "offered" is what the lines managed to offer, not what was asked.')
    print(f'  {"idle, ms":>9s} {"calls/s":>8s} {"worst link":>18s} {"Erlang B":>10s} {"lost":>10s} '
          f'{"no trunk":>9s} {"registers":>18s} {"talked":>7s}')
    print(f'  {"":>9s} {"":>8s} {"E":>9s} {"refused":>8s} {"":>10s} {"a call":>10s} {"/1000 net":>9s} '
          f'{"mean E":>8s} {"waited":>9s} {"":>7s}')
    for idle in (12000, 8000, 6000, 4000, 3000, 2000, 1500, 1000, 700):
        sim = phase(links, lines, idle, LONG, seed=17, warm=2.0 * idle)
        we = max(sim.chan.values(), key=lambda p: p.erlang(sim.t))
        re_, rw = pooled(sim, sim.reg)
        nc = max(sim.stat['net'], 1) / 1000
        lost = 1 - sim.stat['done'] / max(sim.stat['calls'], 1)
        print(f'  {idle:9d} {per_s(sim, sim.stat["calls"]):8.1f} {we.erlang(sim.t):9.2f} '
              f'{100 * we.refused / max(we.taken + we.refused, 1):7.2f} % {100 * erlang_b(we.erlang(sim.t), 6):9.2f} % '
              f'{100 * lost:9.1f} % {sim.stat["no_trunk"] / nc:9.1f} {re_:8.2f} {rw:8.1f} % {sim.stat["done"]:7d}')
    print('     "lost a call" counts every caller who did not talk -- the called line busy, no trunk,')
    print('     no claim, dial tone given up on -- so most of it is the called line, not the network.')


# ------------------------------------------------------------------ big

def backbone(core_k, core_ch, levels, mid=None):
    """A backbone of `core_k` tandems in a chain, `core_ch` channels between them, and on each
    tandem a tree of `levels` = [(branch, channels), ...] read outward.  A branch of 1 is a
    chain, which is what a long spoke is.  `mid` caps the spokes of a tandem with backbone on
    BOTH sides: it has one direction fewer to spare and two trunk groups more already spent."""
    out = {}
    for h in range(core_k - 1):
        out[(f't{h}', f't{h + 1}')] = core_ch

    def grow(parent, tag, depth, first):
        if depth >= len(levels):
            return
        b, ch = levels[depth]
        if depth == 0 and mid is not None and not first:
            b = mid
        for j in range(b):
            kid = f'{tag}.{j}'
            out[(parent, kid)] = ch
            grow(kid, kid, depth + 1, first)
    for h in range(core_k):
        grow(f't{h}', f'n{h}', 0, h == 0 or h == core_k - 1)
    return out


def mesh_core(k, core_ch, levels, mid=None):
    """The same, with the k tandems FULLY CONNECTED instead of chained.  The flood must see a
    tree, so only the k-1 links of the chain may carry it and every other core link is strapped
    (network.md 3.3).  Returns the links and the straps."""
    out = backbone(k, core_ch, levels, mid)
    straps = []
    for a in range(k):
        for b in range(a + 2, k):
            out[(f't{a}', f't{b}')] = core_ch
            straps.append((f't{a}', f't{b}'))
    return out, straps


def sized(links, straps=(), cap=48, leave=0.3):
    """what a shape costs, with every exchange capped at `cap` lines"""
    try:
        lk, ln, st, code = shape(links, straps)
    except AssertionError as e:
        return None, str(e)
    ln = {k: min(cap, v) for k, v in ln.items()}
    try:
        return predict(lk, ln, st, leave), None
    except AssertionError as e:
        return None, str(e)


def n_of(links):
    return len({x for l in links for x in l})


# The families section 6 searches.  Channels go down as a link goes outward, never up, and a
# tandem with backbone on both sides is given `mid` spokes: these are the rules of shape, not a
# preference, and they cut a search of half a million shapes to a few thousand.
BIG_CH = (6, 12, 18, 24)


def big_family():
    for k in (1, 2, 3, 4, 5):
        for cch in ((12,) if k == 1 else BIG_CH):
            for b0 in (2, 3, 4):
                for mid in (None if k <= 2 else 1, 2):
                    if mid is not None and mid > b0:
                        continue
                    for depth in (1, 2, 3):
                        for b in itertools.product((1, 2, 3), repeat=depth - 1):
                            for ch in itertools.product((6, 12), repeat=depth):
                                if any(ch[i] > ch[i - 1] for i in range(1, depth)):
                                    continue
                                lv = [(b0, ch[0])] + [(b[i - 1], ch[i]) for i in range(1, depth)]
                                yield k, cch, lv, mid


def big():
    print('BIG -- how near sixty-four exchanges the pulse flood will go, and what shape gets there.')
    print('  The rules are topology.md 1: four directions an exchange, eight trunk groups, the flood')
    print('  sees a tree, sixty-four codes, and the whole flood inside the origin\'s 128 ms guard at a')
    print(f'  slow marker ({SLOW_HOP:.0f} ms a hop and {SLOW_HUB:.0f} more at a hub).  Erlang B on a tree throughout,')
    print(f'  3 calls an hour of {HOLD_MEAN / 1000:.0f} s a line, and every call that leaves floods every link for')
    print(f'  {FLOOD_S:.2f} s on average over the sixty-four codes.  "lines" is what the shape is worked at, after')
    print('  the trunk groups have taken their slots and the cap in the label has taken the rest.')

    head = (f'  {"":38s} {"exch":>4s} {"lines":>6s} {"a/ex":>5s} {"flood":>6s} {"worst link":>21s} '
            f'{"pair":>7s} {"hops":>5s} {"spread":>7s} {"mon":>4s} {"res":>4s}')
    keep = []

    def row(label, links, straps=(), cap=48, leave=0.3, note=None):
        p, why = sized(links, straps, cap, leave)
        if p is None:
            print(f'  {label:38s}  {n_of(links):3d} exchanges -- {why}')
            return None
        print(f'  {label:38s} {p["n"]:4d} {p["lines"]:6d} {p["lines"] // p["n"]:5d} {p["flood"]:5.2f}E '
              f'{p["worst_e"]:6.2f} E on {p["worst_ch"]:2d} {100 * p["worst_b"]:5.2f}% {100 * p["pair"]:6.2f}% '
              f'{p["diameter"]:4d} hp {p["spread"]:4.0f} ms {p["monitors"]:4d} {p["resolvers"]:4d}')
        if note:
            keep.append((note, links, straps, cap, leave))
        return p

    # ---- 1. a tandem chain with spokes ---------------------------------
    print('\n  1. A tandem-chain backbone with spokes on it.  A tandem in the MIDDLE of the chain has')
    print('     two directions left after the backbone and two trunk groups, so it carries two spokes')
    print('     of six channels or one of twelve; an end of the chain has three directions and four')
    print('     groups.  That asymmetry is the whole of what a backbone costs.')
    print(head)
    for k in (2, 3, 4, 5):
        row(f'{k} tandems, 3 spokes (2 in the middle)', backbone(k, 12, [(3, 12)], mid=2))
    for k in (3, 4, 5):
        row(f'{k} tandems, 18 ch backbone, 3 and 1', backbone(k, 18, [(3, 12)], mid=1))
    print('     A chain of tandems is four hops across and spends nothing on depth.  What it cannot do')
    print('     is grow: each tandem carries two or three exchanges and there is no room for more.')

    # ---- 2. long spokes -------------------------------------------------
    print('\n  2. LONG SPOKES: a branch of 1 after the first level is a chain hanging off the tandem.')
    print('     Depth is free in trunks and dear in hops, and the link next the tandem carries the')
    print('     whole spoke past it.')
    print(head)
    for k in (2, 3):
        for deep in (2, 3, 4, 5):
            row(f'{k} tandems, 3 spokes {deep} deep',
                backbone(k, 12, [(3, 12)] + [(1, 12)] * (deep - 1), mid=2))
    print('     Ten hops is the guard, and a chain of that length on one link is its own bottleneck.')

    # ---- 3. branching spokes -------------------------------------------
    print('\n  3. Spokes that BRANCH: a sub-hub on each spoke and leaves on that, and a level more')
    print('     under those.  The same exchanges in half the hops, and the traffic divided over more')
    print('     links next the tandem.  48-line exchanges first, to show where that stops.')
    print(head)
    row('1 tandem, 4 x 3', backbone(1, 12, [(4, 12), (3, 6)]))
    row('1 tandem, 4 x 3 x 3', backbone(1, 12, [(4, 12), (3, 12), (3, 6)]))
    row('2 tandems, 3 x 3', backbone(2, 12, [(3, 12), (3, 6)]))
    row('2 tandems, 3 x 3 x 2', backbone(2, 12, [(3, 12), (3, 12), (2, 6)]))
    row('3 tandems, 3 and 2, x 3 x 2', backbone(3, 12, [(3, 12), (3, 12), (2, 6)], mid=2))

    # ---- 4. what a fully connected core buys ----------------------------
    print('\n  4. FULLY CONNECTED tandems.  Of the k(k-1)/2 links between k tandems only the k-1 of a')
    print('     chain may carry the flood, because the flood must see a tree; every other one is')
    print('     STRAPPED, and a strapped link carries calls between its own two ends only')
    print('     (network.md 3.3).  A tandem has twelve lines.  So this is what they are worth:')
    print('     Read the pairs: each is the SAME eight trunk groups at each tandem, spent on a chain')
    print('     of wide links or on a mesh of narrow ones.')
    print(head)
    row('3 tandems chained, 12 ch, 2 spokes', backbone(3, 12, [(2, 12)]))
    lk, st = mesh_core(3, 6, [(2, 12)])
    row('  fully connected, 6 ch, 2 spokes', lk, st)
    lk, st = mesh_core(3, 12, [(2, 12)])
    row('  fully connected, 12 ch: 2 groups more', lk, st)
    row('4 tandems chained, 12 ch, 1 spoke', backbone(4, 12, [(1, 12)]))
    lk, st = mesh_core(4, 6, [(1, 12)])
    row('  fully connected, 6 ch, 1 spoke', lk, st)
    row('5 tandems chained, 12 ch, no spokes', backbone(5, 12, []))
    lk, st = mesh_core(5, 6, [])
    row('  fully connected, 6 ch, no spokes', lk, st)
    lk, st = mesh_core(6, 6, [])
    row('6 tandems fully connected, 6 ch', lk, st)
    print('     Wherever there is anything BEHIND a hub, the mesh spends directions and trunk groups')
    print('     and moves no traffic worth the name: the only calls a strapped tandem-to-tandem link')
    print('     can carry are the twelve lines at one end calling the twelve at the other.  Capacity')
    print('     between hubs is bought in CHANNELS on the tree, not in links off it.')
    print('     The last pair is the exception that shows why.  With NOTHING behind them, the hubs')
    print('     ARE the traffic, every pair has a direct link and no call is ever forwarded -- and')
    print('     the mesh is better than the chain by a factor of five.  Five is also where it stops:')
    print('     a sixth exchange would want a fifth direction, and any exchange hung off one of the')
    print('     five turns every one of those links back into a strap that nothing may cross.')

    # ---- 5. smaller exchanges -------------------------------------------
    print('\n  5. What actually reaches sixty-four codes: SMALLER EXCHANGES.  Both the traffic and the')
    print('     flood on every link are proportional to the LINES in the network and not to the')
    print('     exchanges, so the way to sixty-four is exchanges that are not full.')
    print(head)
    for cap in (48, 36, 24, 18, 12, 8):
        row(f'2 tandems, 3 x 3 x 2, {cap:2d} lines an ex',
            backbone(2, 12, [(3, 12), (3, 12), (2, 6)]), cap=cap)

    # ---- 6. the search --------------------------------------------------
    print('\n  6. The largest network with no link over 1 %, inside the guard and the sixty-four codes,')
    print('     searched over backbones of 1-5 tandems, trees of up to three levels, and line caps.')
    print(head)
    # Biggest first, and stop as soon as the exchanges stop going up: the count of
    # exchanges does not depend on the line cap, so a shape smaller than one that
    # has already passed can never win and need not be worked at all.  That is the
    # difference between half an hour and a few seconds.
    cands = []
    for k, cch, lv, mid in big_family():
        links = backbone(k, cch, lv, mid)
        n = n_of(links)
        if 4 <= n <= 64:
            cands.append((-n, k, cch, lv, mid, links))
    cands.sort(key=lambda c: c[0])

    def largest(leave, guard):
        best, bcap, bdesc = None, None, None
        for nn, k, cch, lv, mid, links in cands:
            if best is not None and -nn < best['n']:
                break
            for cap in (48, 36, 30, 24, 18, 12, 10, 8):    # the largest that fits wins
                p, _ = sized(links, (), cap, leave)
                if p is None:
                    break                                  # the shape is illegal at any cap
                if p['worst_b'] > 0.01 or p['spread'] > guard:
                    continue
                if best is None or (p['n'], p['lines']) > (best['n'], best['lines']):
                    best, bcap, bdesc = p, cap, (k, cch, lv, mid)
                break
        return best, bcap, bdesc

    for leave in (0.2, 0.3, 0.5):
        best, bcap, bdesc = largest(leave, G_ORIGIN)
        if best is None:
            print(f'     {100 * leave:.0f} % leaving: none')
            continue
        k, cch, lv, mid = bdesc
        shp = ' x '.join(str(b) for b, _ in lv)
        row(f'{100 * leave:.0f} %: {k} tandem{"s" if k > 1 else ""} {cch} ch, {shp}, {bcap} lines',
            backbone(k, cch, lv, mid), (), bcap, leave,
            note=f'{100 * leave:.0f} % leaving, {bcap} lines an exchange')
    print('     The count of exchanges is what is maximised, and the lines only break a tie, so these')
    print('     are the shapes that fill the numbering plan rather than the ones that carry the most.')

    # ---- 7. the guard's tap ----------------------------------------------
    print(f"\n  7. What the GUARD'S TAP buys.  The flood has to cross the network inside the origin's")
    print(f"     guard (monitor.md 3, rule 2), which is one tap on a counter -- {G_ORIGIN:.0f} ms today, and")
    print(f"     {SLOW_HOP:.0f} ms a hop at a slow marker with {SLOW_HUB:.0f} more at a hub.  It may go as far as the caller's")
    print(f"     own pause less the {T_ID + T_MARK:.0f} ms the digit and the seizure take: a phone to ES 201 187 gives")
    print(f"     720 ms (register.md 2), so {720 - T_ID - T_MARK:.0f} ms, and 512 is the last tap under it.  A carrier's own")
    print("     delay is NOT in this budget (monitor.md 5.1); wander is.")
    print(f'\n  {"tap":>7s} {"a chain of 12 ch":>28s} | {"the largest network at 30 % leaving":>44s}')
    print(f'  {"":>7s} {"hops":>6s} {"exchanges":>10s} {"what stops it":>11s} | {"exch":>5s} {"lines":>6s} '
          f'{"a/ex":>5s} {"worst link":>17s} {"hops":>5s} {"spread":>7s}')
    for tap in (128, 256, 512):
        hops = 0
        for n in range(2, 65):
            p, _ = sized(chain_links(n, 12), (), 48, 0.3)
            if p is None or p['spread'] > tap:
                break
            hops = p['diameter']
            stop = 'traffic' if p['worst_b'] > 0.01 else ''
        # the longest chain the tap allows, ignoring what it would carry
        long_p, _ = sized(chain_links(min(hops + 1, 64), 12), (), 48, 0.3)
        best, bcap, bdesc = largest(0.3, tap)
        why = 'the codes' if hops + 1 >= 64 else 'the guard'
        line = f'  {tap:5.0f}ms {hops:6d} {hops + 1:10d} {why:>11s} |'
        if best is None:
            print(line + '   none')
            continue
        print(line + f' {best["n"]:5d} {best["lines"]:6d} {best["lines"] // best["n"]:5d} '
              f'{best["worst_e"]:6.2f} E on {best["worst_ch"]:2d} {100 * best["worst_b"]:5.2f}% '
              f'{best["diameter"]:4d} hp {best["spread"]:4.0f} ms')
    print('     "hops" is the longest chain whose flood fits the tap, whatever it would carry -- the')
    print('     timer alone.  The network beside it has both constraints on, and past 128 ms the guard')
    print('     stops being the one that binds: what stops the search then is the traffic on the')
    print('     centre and the four directions an exchange has, neither of which is a timer.')

    # ---- 8. call by call -------------------------------------------------
    print('\n  8. Those run call by call with `net`\'s engine -- the flood, the monitors, the claim, the')
    print('     resolvers and the registers -- five monitor cells a block and five resolvers a hub,')
    print('     at the busy hour of 3 calls a line and then at TWICE it, which is a network built for')
    print('     one community and given two.  6 hours of each.')
    print(f'  {"":30s} {"calls/h":>8s} {"calls":>6s} {"worst link":>21s} {"lost / 1 000 network calls":>26s} {"hops":>5s} {"ringback":>9s}')
    print(f'  {"":30s} {"a line":>8s} {"an hr":>6s} {"":>21s} {"no trunk":>9s} {"no claim":>9s} {"pools":>7s} {"":>5s} {"network":>9s}')
    for label, links, straps, cap, leave in keep:
      for calls_h in (3.0, 6.0):
        lk, ln, st, _ = shape(links, straps)
        ln = {a: min(cap, b) for a, b in ln.items()}
        sim = Net(lk, ln, mons=5, resolvers=5, leave=leave, seed=5, strapped=st)
        hours = 6
        net_arrivals(sim, hours, False, calls_h)
        sim.run(hours * 3600e3)
        t = hours * 3600e3
        w = max(sim.chan, key=lambda l: (sim.chan[l].refused / max(sim.chan[l].taken + sim.chan[l].refused, 1),
                                         sim.chan[l].erlang(t) / sim.chan[l].n))
        c = sim.chan[w]
        k, nc = sim.stat, max(sim.stat['net'], 1) / 1000
        print(f'  {label:30s} {calls_h:8.0f} {k["calls"] / hours:6.0f} {c.erlang(t):6.2f} E on {c.n:2d} ch '
              f'{100 * c.refused / max(c.taken + c.refused, 1):5.2f}% {k["no_trunk"] / nc:9.1f} '
              f'{k["no_claim"] / nc:9.1f} {(k["no_monitor"] + k["no_resolver"]) / nc:7.1f} '
              f'{np.mean(sim.hops):5.2f} {np.mean(sim.complete_net) / 1000:7.2f} s')



TARGETS = {'tandem': tandem, 'fabric': fabric, 'calls': calls, 'announce': announce, 'aline': aline,
           'flood': flood, 'monitor': monitor, 'timing': timing, 'mainboard': mainboard,
           'confer': confer, 'ss0': ss0, 'net': net, 'topo': topo, 'traffic': traffic,
           'big': big}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        t0 = time.time()
        TARGETS[k]()
        print(f'\n  [{k}: {time.time() - t0:.0f} s]\n', flush=True)
