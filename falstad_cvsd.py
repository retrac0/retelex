"""
CircuitJS (Falstad) prototypes of the subscriber line's voice path, built from
subcircuit modules:

    CVSD-ENC   the 64 kbps CVSD encoder, mf8-spec.md §12.1, with the Iabc drive of
               circuit-review.md §2.4 and the logic connections of its §4
    CVSD-DEC   the decoder: the same engine, taking its bit and its clock from outside
    TX-CLK     the half-bit clock HB (128 kHz) and the bit clock H, §9.1
    DM-ENC     the differential Manchester encoder, §9.2: a 74HC112 and one OR gate
    LINE       the pair as the receiver sees it: level, noise and impulses summed,
               then the §9.5 input filter
    DM-RX      the receiver of §9.4 on the two-phase timing of circuit-review.md §3:
               slicer, transition detector, dead time, interval classifier, LONG and
               MID (a 74HC109, no gate), the recovered bit clock, §9.6's carrier detect
    RECON      the 3.4 kHz reconstruction filter

and three circuits made of them:

    falstad/cvsd_link.txt    audio -> CVSD-ENC -> DM-ENC -> LINE -> DM-RX -> CVSD-DEC -> audio.
                             The decoder runs on the clock the receiver recovers.
    falstad/dm_link.txt      the line code alone, on a PRBS: fast enough to watch
    falstad/cvsd_engine.txt  the codec alone, looped back on two clock sources

    python3 falstad_cvsd.py                     writes all three
    python3 falstad_cvsd.py link -o F --noise 0.8 --level-db -20 ...   one variant
    python3 falstad_cvsd.py check run.json ...  a falstad/sim.mjs recording against the model

Every component value is derived from the codec law in mf8.params(64000) and the
line-code constants of mf8-spec.md §9, so the files follow the model.  The output
is CircuitJS's XML format.  Pin positions come from a port of CircuitJS's own
geometry, because in CircuitJS two pins connect only where their coordinates
coincide; every module and every circuit is checked, net by net, against the
netlist intended before anything is written.

`check` reads what falstad/sim.mjs recorded from falstad.com's simulator and
compares it with the Python model: the line's bit errors, the decoder against
cvsd.decode on the bits and the bit intervals it actually received, the syllabic
node against the law, the OTA against Iabc, and the tone's in-band SINAD.
falstad_cvsd.log is the committed run.
"""
import argparse, json, math, os, sys
from xml.sax.saxutils import quoteattr

import numpy as np

import cvsd, fast, mf8

RATE = 64000
LAW = mf8.params(RATE)
STEPS = 16      # time steps per bit.  The OTA's current is constant within a bit, so any
                # whole number gets a step's area right, but at 8 the encoder made runs
                # of three nine times as often as the model at -20 dB, and 32 agrees
                # with 16 (falstad_cvsd.log)

# ------------------------------------------------------------ component values

E96 = [100, 102, 105, 107, 110, 113, 115, 118, 121, 124, 127, 130, 133, 137, 140, 143,
       147, 150, 154, 158, 162, 165, 169, 174, 178, 182, 187, 191, 196, 200, 205, 210,
       215, 221, 226, 232, 237, 243, 249, 255, 261, 267, 274, 280, 287, 294, 301, 309,
       316, 324, 332, 340, 348, 357, 365, 374, 383, 392, 402, 412, 422, 432, 442, 453,
       464, 475, 487, 499, 511, 523, 536, 549, 562, 576, 590, 604, 619, 634, 649, 665,
       681, 698, 715, 732, 750, 768, 787, 806, 825, 845, 866, 887, 909, 931, 953, 976]


def e96(r):
    d = 10 ** math.floor(math.log10(r) - 2)
    return min((v * d for v in E96 + [1000]), key=lambda v: abs(math.log(v / r)))


V_A = 5.0                       # the logic rail: /coincidence swing and the source's reference
FS = 1.0                        # integrator full scale, volts about ground
C_INT = 10e-9
C_SYL = 100e-9
BETA = 100.0                    # CircuitJS's default transistor
R_INT = e96(LAW.tau_int / C_INT)
I_MAX = LAW.slew * FS * C_INT                      # the bit rate cancels
M = 10 ** (LAW.companding_db / 20)                 # I_max / I_min
R_PAR = LAW.tau_syl / C_SYL                        # R1 || R2
K = 1 - 1 / M                                      # R2 / (R1 + R2)
R1 = e96(R_PAR / K)
R2 = e96(R_PAR / (1 - K))
R_SET = V_A / (I_MAX * (BETA + 1) / BETA)          # the trimmed value, base current included
VD_SYL = V_A * R2 / (R1 + R2)                      # idle: /coincidence high all the time

# the line, mf8-spec.md §9 at the 64 kbps plug (§9.7): one cell is one CVSD bit
CELL = 1 / RATE
DEAD = 0.2                      # dead time, cells
THRESH = 0.75                   # a gap longer than this is a 1
CD_CELLS = 2.0                  # carrier-detect timeout
HYST = 0.05                     # slicer hysteresis, volts either side of zero: 5 % of a 1 V peak
F_IN = 2 * RATE                 # input filter corner: the symbol rate, 128 kHz
R_F1, C_F1 = 1.24e3, 1e-9       # two RC sections at F_IN, the second ten times the impedance
R_F2, C_F2 = 12.4e3, 100e-12
L_RING, C_RING, R_RING = 10e-3, 1.58e-9, 19.1e3    # impulse: 40 kHz, tau 60 us (phy.plant_noise)


def ring_peak():
    """Peak of the tank's response to a 1 V step through R_RING."""
    w0 = 1 / math.sqrt(L_RING * C_RING)
    a = 1 / (2 * R_RING * C_RING)
    wd = math.sqrt(w0 * w0 - a * a)
    tp = math.atan2(wd, a) / wd
    return math.exp(-a * tp) * math.sin(wd * tp) / (R_RING * C_RING * wd)


# ------------------------------------------------------------ CircuitJS geometry

def _floor(v):
    return int(math.floor(v + .48))


def interp(a, b, f, g=0.0):
    """CircuitElm.interpPoint(a, b, f, g)."""
    gx, gy = b[1] - a[1], a[0] - b[0]
    n = math.hypot(gx, gy)
    g = g / n if n else 0.0
    return (_floor(a[0] * (1 - f) + b[0] * f + g * gx),
            _floor(a[1] * (1 - f) + b[1] * f + g * gy))


def interp2(a, b, f, g):
    return interp(a, b, f, g), interp(a, b, f, -g)


def dsign(p1, p2):
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    return (1 if dx > 0 else -1) if dy == 0 else (1 if dy > 0 else -1)


def gate_pins(p1, p2, n=2):
    """GateElm, size 2: inputs 0..n-1, then the output."""
    pins, i0 = [], -(n // 2)
    for i in range(n):
        if i0 == 0 and n % 2 == 0:
            i0 += 1
        pins.append(interp(p1, p2, 0, 16 * i0))
        i0 += 1
    return pins + [p2]


W, E, N, S = 'W', 'E', 'N', 'S'


def chip_pin(x, y, sx, sy, side, pos):
    """ChipElm.setPoints at size 2: the post of a pin at `pos` on `side`."""
    return {W: (x, y + 32 * pos), E: (x + 32 + 32 * sx, y + 32 * pos),
            N: (x + 32 + 32 * pos, y - 32), S: (x + 32 + 32 * pos, y + 32 * sy)}[side]


def dff_pins(x, y):
    """DFlipFlopElm: D, Q, /Q, CLK."""
    return [chip_pin(x, y, 2, 3, *p) for p in ((W, 0), (E, 0), (E, 2), (W, 1))]


def jk_pins(x, y):
    """JKFlipFlopElm, falling-edge as a 74HC112 is: J, CLK, K, Q, /Q."""
    return [chip_pin(x, y, 2, 3, *p) for p in ((W, 0), (W, 1), (W, 2), (E, 0), (E, 2))]


def mono_pins(x, y):
    """MonostableElm: trigger (rising edge), Q, /Q."""
    return [chip_pin(x, y, 2, 2, *p) for p in ((W, 0), (E, 0), (E, 1))]


def opamp_pins(p1, p2):
    """OpAmpElm and ComparatorElm, size 2: V- (post 0), V+ (post 1), out."""
    a, b = interp2(p1, p2, 0, 16 * dsign(p1, p2))
    return [a, b, p2]


def ota_pins(p1, p2):
    """OTAElm: +, -, diode bias, Iabc, out."""
    dn = math.dist(p1, p2)
    wtot = 32 * 2 + 2 * 19 - 8
    if dn > wtot:
        lead1, lead2, p2b = interp(p1, p2, 1 - wtot / dn), p2, p2
    else:
        lead1, lead2 = p1, interp(p1, p2, wtot / dn)
        p2b = lead2
    a, b = interp2(p1, p2b, 0, 32 * dsign(p1, p2))
    return [a, b, p1, interp(lead1, lead2, 1 - 16 / wtot, 32), p2b]


def transistor_pins(p1, p2, pnp):
    """TransistorElm: base, collector, emitter."""
    c, e = interp2(p1, p2, 1, 16 * dsign(p1, p2) * pnp)
    return [p1, c, e]


def switch2_pins(p1, p2):
    """Switch2Elm: common, throw 1 (position 0), throw 2."""
    return [p1, interp(p1, p2, 1, 16), interp(p1, p2, 1, -16)]


# ------------------------------------------------------------ a schematic

def fmt(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, float):
        return f'{v:.10g}'
    return str(v)


class Sch:
    """A drawing: elements with positions, and the net every post is meant to be on."""

    def __init__(self, steps=STEPS):
        self.steps = steps
        self.ts = CELL / steps
        self.elms = []          # (tag, p1, p2, attrs, posts, nets)
        self.extra = []         # scope and slider XML
        self.index = {}
        self.models = []
        self.nsupply = 0

    def add(self, tag, p1, p2, attrs, posts, nets, name=None):
        assert len(posts) == len(nets), (tag, posts, nets)
        if name:
            self.index[name] = len(self.elms)
        self.elms.append((tag, p1, p2, attrs, list(posts), list(nets)))
        return posts

    def r(self, p1, p2, ohms, a, b, name=None):
        return self.add('r', p1, p2, {'r': float(ohms)}, [p1, p2], [a, b], name)

    def c(self, p1, p2, farads, a, b, vd=None):
        at = {'c': float(farads)}
        if vd is not None:
            at['vd'] = float(vd)
        return self.add('c', p1, p2, at, [p1, p2], [a, b])

    def gnd(self, p):
        self.add('g', p, (p[0], p[1] + 16), {}, [p], ['GND'])

    def rail(self, p, sym, volts, net, name=None, **wave):
        at = {'wf': 0, 'maxv': float(volts)}
        at.update(wave)
        return self.add('R', p, sym, at, [p], [net], name)

    def supply(self, p, sym, volts=V_A):
        """A DC rail.  Each is its own net: two ideal sources on one node are a loop."""
        self.nsupply += 1
        net = f'+{volts:g}V.{self.nsupply}'
        self.rail(p, sym, volts, net)
        return net

    def label(self, p, end, text, name=None):
        return self.add('ln', p, end, {'te': text}, [p], [text], name)

    def gate(self, tag, p1, p2, ins, out):
        """A two-input gate.  Its inputs are symmetric, so nets are given in (x, y) order."""
        pins = gate_pins(p1, p2)
        order = sorted(range(2), key=lambda i: pins[i])
        nets = [None, None, out]
        for net, i in zip(ins, order):
            nets[i] = net
        # 1 ns: any delay under a time step makes each gate level take exactly one
        # step on both edges.  At zero delay CircuitJS propagates a change only as far
        # as the solver happens to iterate within the step, which shortened the
        # coincidence pulses by up to two steps in eight and biased the syllabic level
        self.add(tag, p1, p2, {'in': 2, 'pd': 1e-9}, pins, nets)
        return [pins[i] for i in order] + [pins[2]]

    def opamp(self, p1, p2, vm, vp, out):
        pins = opamp_pins(p1, p2)
        self.add('a', p1, p2, {'f': 8, 'ma': 12.0, 'mi': -12.0, 'ga': 100000.0},
                 pins, [vm, vp, out])
        return pins

    def dff(self, x, y, d, q, nq, clk):
        return self.add('DFlipFlop', (x, y), (x + 96, y), {}, dff_pins(x, y), [d, q, nq, clk])

    def jk(self, x, y, j, clk, k, q, nq, pos_edge=False):
        return self.add('JKFlipFlop', (x, y), (x + 96, y), {'f': 4 if pos_edge else 0},
                        jk_pins(x, y), [j, clk, k, q, nq])

    def mono(self, x, y, seconds, retrig, trig, q, nq):
        return self.add('Monostable', (x, y), (x + 96, y), {'rt': bool(retrig), 'dl': float(seconds)},
                        mono_pins(x, y), [trig, q, nq])

    def wire(self, *pts, net):
        for a, b in zip(pts, pts[1:]):
            assert (a[0] == b[0]) != (a[1] == b[1]), (a, b)
            self.add('w', a, b, {}, [a, b], [net, net])

    def text(self, p, s, size=16):
        self.add('x', p, (p[0] + 16, p[1]), {'si': size, 'te': s}, [], [])

    def inst(self, model, x, y, nets, name=None):
        """An instance of a subcircuit module; returns its posts by pin name."""
        if model not in self.models:
            self.models.append(model)
        posts = model.posts(x, y)
        self.add('cc', (x, y), (x + 32 + 32 * model.sx, y), {'mo': model.name},
                 [posts[p] for p, _, _ in model.ext], [nets.get(p) for p, _, _ in model.ext], name)
        return posts

    def scope(self, names, us_per_px, pos, title):
        e = [self.index[n] for n in names]
        sp = max(1, 2 ** round(math.log2(us_per_px * 1e-6 / self.ts)))    # steps per pixel
        s = f'<o en="{e[0]}" sp="{sp}" f="x206" p="{pos}" x={quoteattr(title)}>'
        s += ''.join(f'<p e="{i}" v="0"/>' for i in e) + '</o>'
        self.extra.append(s)

    def slider(self, name, item, lo, hi, text):
        self.extra.append(f'<adj e="{self.index[name]}" en={quoteattr(item)} mn="{lo:g}" '
                          f'mx="{hi:g}" st={quoteattr(text)}/>')

    # ---------------------------------------------------------- output
    def elm_xml(self, e, nn=None, internal=()):
        tag, p1, p2, at, posts, nets = e
        s = f'<{tag} x="{p1[0]} {p1[1]} {p2[0]} {p2[1]}"'
        if nn is not None:
            s = f'<{tag} nn="{nn}" x="{p1[0]} {p1[1]} {p2[0]} {p2[1]}"'
        if 'f' not in at:
            s += f' f="{1 if tag == "ln" and at["te"] in internal else 0}"'
        for k, v in at.items():
            s += f' {k}={quoteattr(fmt(v))}'
        return s + '/>'

    def xml(self):
        head = {'f': 64, 'ts': f'{self.ts:.10g}', 'ic': 10, 'cb': 50, 'pb': 50, 'vr': 5,
                'mts': '1e-12'}
        out = ['<cir ' + ' '.join(f'{k}="{v}"' for k, v in head.items()) + '>']
        for m in self.models:
            out += ['  ' + line for line in m.xml()]
        out += ['  ' + self.elm_xml(e) for e in self.elms]
        out += ['  ' + e for e in self.extra]
        out.append('</cir>')
        return '\n'.join(out) + '\n'

    # ---------------------------------------------------------- the check
    def check(self, ext=()):
        """Nets as CircuitJS will build them from the drawing, against the nets intended."""
        parent = {}

        def find(p):
            while parent.setdefault(p, p) != p:
                parent[p] = parent[parent[p]]
                p = parent[p]
            return p

        first, comp, errors, seen = {}, {}, [], {}
        for tag, p1, p2, at, posts, nets in self.elms:
            if tag == 'w':
                parent[find(p1)] = find(p2)
            if tag == 'ln':
                parent[find(p1)] = find(first.setdefault(at['te'], p1))
        for i, (tag, p1, p2, at, posts, nets) in enumerate(self.elms):
            for k, (pt, net) in enumerate(zip(posts, nets)):
                comp.setdefault(find(pt), []).append((net, f'{tag}#{i}.{k}', tag))
        for root, items in comp.items():
            nets = {n for n, _, _ in items if n is not None}
            if len(nets) > 1:
                errors.append(f'nets merged {sorted(nets)}: {[w for _, w, _ in items]}')
            for n in nets:
                if n in seen and seen[n] != root and n != 'GND':
                    errors.append(f'net {n} is in two pieces')
                seen.setdefault(n, root)
            real = [i for i in items if i[2] not in ('w', 'ln')]
            labelled = any(i[2] == 'ln' for i in items)          # one pin and a label: a test point
            if nets and not nets <= {'GND'} | set(ext) and \
               (not real or (len(real) == 1 and not labelled and real[0][2] not in ('g', 'R'))):
                errors.append(f'net {sorted(nets)} goes nowhere: {[w for _, w, _ in items]}')
        for pin in ext:
            if pin not in seen:
                errors.append(f'external pin {pin} is not in the drawing')
        # a post on a wire's interior looks connected on screen and is not
        ends = {pt for e in self.elms for pt in e[4]}
        for tag, a, b, *_ in self.elms:
            if tag != 'w':
                continue
            for p in ends - {a, b}:
                if (a[0] == b[0] == p[0] and min(a[1], b[1]) < p[1] < max(a[1], b[1])) or \
                   (a[1] == b[1] == p[1] and min(a[0], b[0]) < p[0] < max(a[0], b[0])):
                    errors.append(f'{p} lies on the interior of wire {a}-{b}')
        return errors


class Model:
    """A subcircuit: a drawing, and which of its nets are pins, where."""

    def __init__(self, name, sch, ext, sx):
        self.name, self.sch, self.ext, self.sx = name, sch, ext, sx
        self.sy = max(2, 1 + max(pos for _, side, pos in ext if side in (W, E)))

    def posts(self, x, y):
        return {p: chip_pin(x, y, self.sx, self.sy, side, pos) for p, side, pos in self.ext}

    def check(self):
        return [f'{self.name}: {e}' for e in self.sch.check([p for p, _, _ in self.ext])]

    def xml(self):
        """CustomCompositeModel's XML: pins, then every element with its node numbers."""
        ids = {'GND': 0}
        fresh = [0]

        def nid(net):
            if net is None:
                fresh[0] += 1
                return 10000 + fresh[0]
            return ids.setdefault(net, len(ids))

        body = []
        pins = {p for p, _, _ in self.ext}
        internal = {e[3]['te'] for e in self.sch.elms if e[0] == 'ln'} - pins
        for e in self.sch.elms:
            nn = ' '.join(str(nid(n)) for n in e[5])
            body.append('  ' + self.sch.elm_xml(e, nn, internal))
        side = {N: 0, S: 1, W: 2, E: 3}
        head = [f'<ccm nm={quoteattr(self.name)} f="1" sx="{self.sx}" sy="{self.sy}">']
        head += [f'  <ext nm={quoteattr(p)} nd="{ids[p]}" ps="{pos}" sd="{side[sd]}"/>'
                 for p, sd, pos in self.ext]
        return head + body + ['</ccm>']


# ------------------------------------------------------------ the modules

def mod_cvsd(encoder, steps=STEPS, imin=1.0, imax=1.0, probes=False):
    """One CVSD engine.  The encoder closes the loop through the comparator."""
    s = Sch(steps)
    X, Y = 448, 560
    P = lambda x, y: (X + x, Y + y)
    BITIN, Q0, NQ0 = ('CMP', 'BIT', '/BIT') if encoder else ('BIT', 'Q', '/Q')
    r2 = (R1 + R2) / imin - R1              # I_min alone: I_min / I_max = R1 / (R1 + R2)
    rset = R_SET / imax

    # run register, 74HC74: the bit, the one before, the one before that
    s.dff(*P(0, 0), BITIN, Q0, NQ0, 'CLK')
    s.dff(*P(160, 0), Q0, 'Q1', None, 'CLK')
    s.dff(*P(320, 0), 'Q1', 'Q2', None, 'CLK')
    s.wire(P(96, 0), P(128, 0), P(160, 0), net=Q0)
    s.wire(P(256, 0), P(288, 0), P(320, 0), net='Q1')
    s.wire(P(416, 0), P(448, 0), net='Q2')
    for x in (0, 160, 320):
        s.wire(P(x, 32), P(x - 16, 32), P(x - 16, 144), net='CLK')
    s.wire(P(-16, 144), P(144, 144), P(304, 144), net='CLK')
    s.label(P(-16, 144), P(-64, 144), 'CLK')
    s.label(P(128, -48), P(80, -48), Q0)
    s.label(P(96, 64), P(96, 112), NQ0)

    # coincidence: /coin = (Q0 xor Q1) + (Q1 xor Q2), 74HC86 and 74HC32
    xa = s.gate('Xor', P(208, -48), P(208, -144), [Q0, 'Q1'], 'X01')
    xb = s.gate('Xor', P(368, -48), P(368, -144), ['Q1', 'Q2'], 'X12')
    s.wire(P(128, 0), P(128, -48), xa[0], net=Q0)
    s.wire(P(288, 0), P(288, -48), net='Q1')
    s.wire(P(288, -48), xa[1], net='Q1')
    s.wire(P(288, -48), xb[0], net='Q1')
    s.wire(P(448, 0), P(448, -48), xb[1], net='Q2')
    og = s.gate('Or', P(288, -176), P(288, -272), ['X01', 'X12'], '/COIN')
    s.wire(xa[2], P(208, -176), og[0], net='X01')
    s.wire(xb[2], P(368, -176), og[1], net='X12')
    s.wire(og[2], P(288, -304), net='/COIN')

    # syllabic filter: R1 into C_syl || R2.  tau_syl = C_syl (R1 || R2); the node
    # sits at V_A R2/(R1+R2) (1 - syl), and I_max / I_min = (R1 + R2) / R1
    s.r(P(288, -304), P(416, -304), R1, '/COIN', 'SYL')
    s.c(P(416, -304), P(416, -240), C_SYL, 'SYL', 'GND', vd=VD_SYL)
    s.gnd(P(416, -240))
    s.wire(P(416, -304), P(480, -304), net='SYL')
    s.r(P(480, -304), P(480, -240), r2, 'SYL', 'GND')
    s.gnd(P(480, -240))
    s.label(P(416, -304), P(416, -352), 'SYL')

    # Iabc: the op-amp holds the emitter at the syllabic node, so
    # Iabc = (V_A - V_syl) / R_set, less the PNP's base current
    oa = s.opamp(P(688, -320), P(752, -320), 'EMIT', 'SYL', 'BASE')
    s.wire(P(480, -304), oa[1], net='SYL')
    qp = transistor_pins(P(752, -320), P(784, -320), -1)
    s.add('t', P(752, -320), P(784, -320), {'pn': -1, 'be': BETA}, qp, ['BASE', 'IABC', 'EMIT'])
    s.wire(qp[2], P(784, -368), net='EMIT')
    va = s.supply(P(784, -432), P(784, -464))
    s.r(P(784, -368), P(784, -432), rset, 'EMIT', va)
    s.wire(oa[0], P(688, -368), P(784, -368), net='EMIT')

    # the OTA, LM13700: +-224 mV from Q and /Q, so Iout = +-Iabc.  Pin 2, the diode
    # bias, is open
    ota = ota_pins(P(672, -96), P(800, -96))
    s.add('OTA', P(672, -96), P(800, -96), {'pv': 12.0, 'nv': -12.0}, ota,
          ['INP', 'INN', None, 'IABC', 'INT'])
    s.wire(qp[1], ota[3], net='IABC')
    s.wire(P(640, -128), ota[0], net='INP')
    s.r(P(640, -224), P(640, -128), 47e3, Q0, 'INP')
    s.label(P(640, -224), P(640, -256), Q0)
    s.r(P(640, -128), P(544, -128), 2.2e3, 'INP', 'GND')
    s.gnd(P(544, -128))
    s.wire(P(640, -64), ota[1], net='INN')
    s.r(P(640, 16), P(640, -64), 47e3, NQ0, 'INN')
    s.label(P(640, 16), P(640, 48), NQ0)
    s.r(P(640, -64), P(544, -64), 2.2e3, 'INN', 'GND')
    s.gnd(P(544, -64))

    # integrator, C_int || R_int, and its follower
    s.wire(ota[4], P(832, -96), P(864, -96), P(896, -96), net='INT')
    s.c(P(832, -96), P(832, -32), C_INT, 'INT', 'GND')
    s.gnd(P(832, -32))
    s.r(P(864, -96), P(864, -32), R_INT, 'INT', 'GND')
    s.gnd(P(864, -32))
    ob = s.opamp(P(896, -112), P(960, -112), 'Y', 'INT', 'Y')
    s.wire(ob[0], P(896, -160), P(976, -160), P(976, -112), net='Y')
    s.wire(ob[2], P(976, -112), net='Y')
    s.label(P(976, -112), P(1024, -112), 'Y')

    if encoder:
        # LM311: open collector, pulled up to the logic rail
        cmp_ = opamp_pins(P(-256, 0), P(-160, 0))
        s.add('Comparator', P(-256, 0), P(-160, 0), {}, cmp_, ['Y', 'AUDIO', 'CMP'])
        s.wire(cmp_[2], P(-96, 0), P(0, 0), net='CMP')
        vb = s.supply(P(-96, -64), P(-96, -96))
        s.r(P(-96, 0), P(-96, -64), 4.7e3, 'CMP', vb)
        s.wire(cmp_[0], P(-288, -16), net='Y')
        s.label(P(-288, -16), P(-336, -16), 'Y')
        s.wire(cmp_[1], P(-288, 16), net='AUDIO')
        s.label(P(-288, 16), P(-336, 16), 'AUDIO')
        s.text(P(-336, -464), 'CVSD encoder: LM311, 3 x 74HC74 (half), 74HC86, 74HC32, op-amp + PNP, LM13700')
        ext = [('AUDIO', W, 0), ('CLK', W, 1), ('BIT', E, 0), ('/BIT', E, 1), ('Y', E, 2), ('SYL', E, 3)]
    else:
        s.wire(P(-96, 0), P(0, 0), net='BIT')
        s.label(P(-96, 0), P(-144, 0), 'BIT')
        s.text(P(-336, -464), 'CVSD decoder: the same engine; BIT and CLK come from the receiver')
        ext = [('BIT', W, 0), ('CLK', W, 1), ('Y', E, 0), ('SYL', E, 1)]
    if probes:
        s.label(P(448, -48), P(496, -48), 'Q2')
        s.label(P(288, -304), P(240, -304), '/COIN')
        ext += [('Q2', E, len([1 for e in ext if e[1] == E])), ('/COIN', E, 1 + len([1 for e in ext if e[1] == E]))]
    return Model('CVSD-ENC' if encoder else 'CVSD-DEC', s, ext, 6)


def mod_recon(steps=STEPS):
    """3rd-order Butterworth at 3.4 kHz: an RC, a buffer, a Sallen-Key."""
    s = Sch(steps)
    P = lambda x, y: (x, y + 400)
    s.label(P(160, -112), P(112, -112), 'IN')
    s.r(P(160, -112), P(256, -112), 10e3, 'IN', 'F1')
    s.c(P(256, -112), P(256, -48), 4.7e-9, 'F1', 'GND')
    s.gnd(P(256, -48))
    b1 = s.opamp(P(288, -128), P(352, -128), 'F1B', 'F1', 'F1B')
    s.wire(P(256, -112), b1[1], net='F1')
    s.wire(b1[0], P(288, -176), P(368, -176), P(368, -128), net='F1B')
    s.wire(b1[2], P(368, -128), net='F1B')
    s.r(P(368, -128), P(464, -128), 10e3, 'F1B', 'F2')
    s.r(P(464, -128), P(560, -128), 10e3, 'F2', 'F3')
    s.c(P(560, -128), P(560, -64), 2.4e-9, 'F3', 'GND')
    s.gnd(P(560, -64))
    b2 = s.opamp(P(592, -144), P(656, -144), 'OUT', 'F3', 'OUT')
    s.wire(P(560, -128), b2[1], net='F3')
    s.wire(b2[0], P(592, -192), P(672, -192), P(672, -144), net='OUT')
    s.wire(b2[2], P(672, -144), P(704, -144), net='OUT')
    s.c(P(464, -128), P(464, -240), 9.1e-9, 'F2', 'OUT')
    s.wire(P(464, -240), P(704, -240), P(704, -144), net='OUT')
    s.label(P(704, -144), P(752, -144), 'OUT')
    s.text(P(112, 40), 'reconstruction low-pass, 3.4 kHz, 3rd order')
    return Model('RECON', s, [('IN', W, 0), ('OUT', E, 0)], 5)


def mod_txclk(steps=STEPS):
    """HB, the half-bit clock, and H, the bit clock: §9.1's chain, from its last divide."""
    s = Sch(steps)
    # edges fall half a time step off the grid, so rounding in t cannot move them
    s.rail((160, 232), (112, 232), 2.5, 'HB', wf=2, fr=2.0 * RATE, bias=2.5,
           phaseShift=-2 * math.pi / steps)
    s.wire((160, 232), (240, 232), (320, 232), net='HB')
    s.label((240, 232), (240, 296), 'HB')
    vp = s.supply((288, 200), (288, 152))
    s.jk(320, 200, vp, 'HB', vp, 'H', None)                      # J = K = 1: divide by two
    s.wire((320, 200), (288, 200), net=vp)
    s.wire((288, 200), (288, 264), (320, 264), net=vp)
    s.wire((416, 200), (464, 200), net='H')
    s.label((464, 200), (512, 200), 'H')
    s.text((112, 360), 'clock chain: 128 kHz half-bit clock; half a 74HC112 divides by two on its falling edge')
    return Model('TX-CLK', s, [('HB', E, 0), ('H', E, 1)], 4)


def mod_dmenc(steps=STEPS):
    """§9.2: EN = H + /bit; a JK with J = K = EN, clocked by HB, toggles when EN is high."""
    s = Sch(steps)
    og = s.gate('Or', (240, 200), (336, 200), ['H', '/D'], 'EN')     # inputs: upper, lower
    s.wire((160, 184), og[0], net='H')
    s.label((160, 184), (112, 184), 'H')
    s.wire((160, 216), og[1], net='/D')
    s.label((160, 216), (112, 216), '/D')
    s.jk(432, 168, 'EN', 'HB', 'EN', 'TXD', None)
    s.wire(og[2], (384, 200), net='EN')
    s.wire((384, 200), (384, 168), (432, 168), net='EN')
    s.wire((384, 200), (384, 232), (432, 232), net='EN')
    s.wire((432, 200), (400, 200), (400, 296), net='HB')
    s.label((400, 296), (400, 344), 'HB')
    s.wire((528, 168), (576, 168), net='TXD')
    s.label((576, 168), (624, 168), 'TXD')
    s.text((112, 400), 'differential Manchester: a transition at every cell boundary (H = 1),')
    s.text((112, 424), 'and at mid-cell (H = 0) when the bit is 0.  Half a 74HC112 and a quarter 74HC32')
    return Model('DM-ENC', s, [('/D', W, 0), ('H', W, 1), ('HB', W, 2), ('TXD', E, 0)], 5)


def mod_line(steps=STEPS):
    """The pair as the receiver's slicer sees it, signal peak = LEVEL volts."""
    s = Sch(steps)
    k_imp = 1 / (2 * ring_peak())          # a square wave of +-1 V steps 2 V: ring peak 1 V
    ex = f'(a-2.5)/2.5*b+c+{k_imp:.4g}*d'
    pins = [chip_pin(400, 168, 2, 4, *p) for p in ((W, 0), (W, 1), (W, 2), (W, 3), (E, 0), (E, 1))]
    s.add('VCVS', (400, 168), (496, 168), {'ic': 4, 'ex': ex}, pins,
          ['TX', 'LEVEL', 'NOISE', 'RING', 'SUM', 'GND'])
    for k, n in enumerate(('TX', 'LEVEL', 'NOISE')):
        y = 168 + 32 * k
        s.wire((160, y), (400, y), net=n)
        s.label((160, y), (112, y), n)
    # an impulse: each edge on IMP rings the tank, 40 kHz, tau 60 us
    s.label((160, 264), (112, 264), 'IMP')
    s.r((160, 264), (256, 264), R_RING, 'IMP', 'RING')
    s.wire((256, 264), (320, 264), (400, 264), net='RING')
    s.add('l', (256, 264), (256, 344), {'l': L_RING}, [(256, 264), (256, 344)], ['RING', 'GND'])
    s.gnd((256, 344))
    s.c((320, 264), (320, 344), C_RING, 'RING', 'GND')
    s.gnd((320, 344))
    s.gnd(pins[5])
    # §9.5: two RC sections at the symbol rate
    s.wire(pins[4], (544, 168), net='SUM')
    s.label((544, 168), (544, 120), 'SUM')
    s.r((544, 168), (640, 168), R_F1, 'SUM', 'F1')
    s.c((640, 168), (640, 232), C_F1, 'F1', 'GND')
    s.gnd((640, 232))
    s.r((640, 168), (736, 168), R_F2, 'F1', 'RX')
    s.c((736, 168), (736, 232), C_F2, 'RX', 'GND')
    s.gnd((736, 232))
    s.label((736, 168), (784, 168), 'RX')
    s.text((400, 136), 'V+ = ' + ex.replace('*', ' x '), 12)
    s.text((112, 420), 'SUM = TX as +-LEVEL volts, plus NOISE, plus the ringing each edge on IMP starts;')
    s.text((112, 444), f'then the input filter: two RC sections at {F_IN/1e3:g} kHz')
    return Model('LINE', s, [('TX', W, 0), ('LEVEL', W, 1), ('NOISE', W, 2), ('IMP', W, 3),
                             ('RX', E, 0), ('SUM', E, 1)], 5)


def rx_steps(steps):
    """The receiver's timers, in whole time steps: dead time, classifier, carrier detect."""
    n_dt = max(2, round(DEAD * steps))
    return n_dt, round(THRESH * steps) - n_dt, round(CD_CELLS * steps)


def mod_dmrx(steps=STEPS):
    """§9.4 on circuit-review.md §3's timing: sample on DT's leading edge, act on its trailing."""
    s = Sch(steps)
    ts = CELL / steps
    n_dt, n_c, n_cd = rx_steps(steps)
    t_of = lambda n: (n - 0.5) * ts           # a monostable set so is high for n steps exactly

    # slicer: the 75176's receiver half, 50 mV either side of zero
    s.label((160, 200), (112, 200), 'IN')
    s.add('Schmitt', (160, 200), (256, 200), {'lt': -HYST, 'ut': HYST}, [(160, 200), (256, 200)],
          ['IN', 'RXD'])
    s.label((256, 200), (256, 152), 'RXD')
    # transition detector, 74HC86: RXD against an RC-delayed copy; P is high for 2 steps
    s.wire((256, 200), (304, 200), (400, 200), net='RXD')
    s.r((304, 200), (304, 280), 1e3, 'RXD', 'RXDD')
    s.c((304, 280), (304, 344), 1.5 * ts / (math.log(2) * 1e3), 'RXDD', 'GND')
    s.gnd((304, 344))
    s.wire((304, 280), (368, 280), (368, 232), (400, 232), net='RXDD')
    xo = s.gate('Xor', (400, 216), (496, 216), ['RXD', 'RXDD'], 'P')
    s.wire(xo[2], (528, 216), (560, 216), net='P')
    # 74HC221 half A: dead time, not retriggerable.  DT IS the accepted transition
    s.mono(560, 216, t_of(n_dt), False, 'P', 'DT', '/DT')
    s.wire((656, 216), (704, 216), net='DT')
    s.label((704, 216), (752, 216), 'DT')
    # 74HC123 half A: the classifier, retriggered when DT ENDS, so it times 0.75 - 0.2 cell
    s.wire((656, 248), (688, 248), (688, 360), (720, 360), net='/DT')
    s.mono(720, 360, t_of(n_c), True, '/DT', 'SHORT', 'EXP')
    s.label((816, 392), (816, 440), 'EXP')
    # 74HC109, both halves, on DT's leading edge, straight off the classifier with no gate
    # between: LONG as a D (J = expired, K = not expired); MID with J = not expired, K = 1,
    # which is MID <- not expired and not MID.  (On a real '109 K is /K: EXP and ground.)
    s.jk(1008, 120, 'EXP', 'DT', 'SHORT', 'BIT', None, pos_edge=True)
    s.label((1008, 120), (960, 120), 'EXP')
    s.label((1008, 152), (960, 152), 'DT')
    s.label((1008, 184), (960, 184), 'SHORT')
    s.label((1104, 120), (1152, 120), 'BIT')
    s.wire((816, 360), (880, 360), (880, 328), (1008, 328), net='SHORT')
    s.label((880, 360), (880, 408), 'SHORT')
    vk = s.supply((976, 440), (976, 488))
    s.jk(1008, 328, 'SHORT', 'DT', vk, 'MID', None, pos_edge=True)
    s.label((1008, 360), (960, 360), 'DT')
    s.wire((1008, 392), (976, 392), (976, 440), net=vk)
    # the recovered bit clock: RXC rises when DT ends, iff that transition completed a bit --
    # which is exactly when MID is clear -- and falls at the next accepted transition.  An
    # edge-triggered decoder takes it as it is.  A trunk card's '259 is a transparent latch
    # and wants a short pulse instead: circuit-review.md 3's W, the other half of the '221
    ng = s.gate('Nor', (1200, 312), (1296, 312), ['DT', 'MID'], 'RXC')
    s.label(ng[0], (1152, 296), 'DT')
    s.wire((1104, 328), ng[1], net='MID')
    s.wire(ng[2], (1344, 312), net='RXC')
    s.label((1344, 312), (1392, 312), 'RXC')
    # 74HC123 half B: carrier detect, retriggered by every transition, 2 cells
    s.wire((528, 216), (528, 456), (560, 456), net='P')
    s.mono(560, 456, t_of(n_cd), True, 'P', 'CD', None)
    s.label((656, 456), (704, 456), 'CD')
    thr = (n_dt + n_c + 0.5) / steps
    for p, cap in (((160, 248), 'slicer, +-50 mV'), ((400, 168), "'86 + RC"), ((560, 184), "'221: dead time"),
                   ((720, 328), "'123 A: classifier"), ((560, 424), "'123 B: carrier detect"),
                   ((1008, 88), "'109 A: LONG"), ((1008, 296), "'109 B: MID"), ((1200, 264), "'02")):
        s.text(p, cap, 12)
    s.text((112, 560), f'dead time {n_dt} steps: a transition under {n_dt+1} steps ({(n_dt+1)/steps:.2f} cell) after the last '
                       f'accepted one is ignored.  Classifier {n_c} steps from its end: '
                       f'a gap of {n_dt+n_c+1} steps or more ({thr:.2f} cell) is a 1')
    s.text((112, 584), 'BIT is valid at the rising edge of RXC, the recovered clock.  Timers are whole time steps here; '
                       'mf8-spec.md 9.7 has the real values')
    return Model('DM-RX', s, [('IN', W, 0), ('BIT', E, 0), ('RXC', E, 1), ('CD', E, 2),
                              ('RXD', E, 3), ('DT', E, 4)], 5)


# ------------------------------------------------------------ the circuits

PRBS7 = []
_r = 0x7f
for _ in range(127):
    PRBS7.append(_r & 1)
    _r = (_r >> 1) | (((_r ^ (_r >> 1)) & 1) << 6)


def audio_source(s, x, y, level_db, net='AUDIO'):
    """A sine at nominal level, 0.15 of full scale rms, or an audio file; returns the post."""
    sw = switch2_pins((x + 160, y), (x + 96, y))
    s.add('S', (x + 160, y), (x + 96, y), {}, sw, [net, 'SINE', 'FILE'])
    s.rail((x + 48, sw[1][1]), (x, sw[1][1]), mf8.NOMINAL_RMS * math.sqrt(2) * FS * 10 ** (level_db / 20),
           'SINE', name='SINE', wf=1, fr=1000.0)
    s.wire((x + 48, sw[1][1]), sw[1], net='SINE')
    s.add('ain', (x + 48, sw[2][1]), (x, sw[2][1]), {'ma': FS}, [(x + 48, sw[2][1])], ['FILE'])
    s.wire((x + 48, sw[2][1]), sw[2], net='FILE')
    s.slider('SINE', 'Max Voltage', 0.0, 1.0, 'Sine level, V peak')
    s.slider('SINE', 'Frequency (Hz)', 100, 3400, 'Sine frequency, Hz')
    return sw[0]


def line_section(s, x, y, a):
    """DM-ENC at (x, y), then LINE and DM-RX, their sources and sliders.  Returns DM-RX's posts."""
    enc = s.inst(mod_dmenc(s.steps), x, y, {'/D': '/BIT', 'H': 'TX_CLK', 'HB': 'HB', 'TXD': 'TXD'})
    s.label(enc['H'], (x - 48, y + 32), 'TX_CLK')
    s.label(enc['HB'], (x - 48, y + 64), 'HB')
    lx = enc['TXD'][0] + 192
    ln = s.inst(mod_line(s.steps), lx, y, {'TX': 'TXD', 'LEVEL': 'LEVEL', 'NOISE': 'NOISE',
                                           'IMP': 'IMP', 'RX': 'RXA', 'SUM': 'LSUM'})
    s.wire(enc['TXD'], (lx - 32, y), ln['TX'], net='TXD')
    s.label((lx - 32, y), (lx - 32, y - 48), 'TXD', name='TXD')
    s.label(ln['SUM'], (ln['SUM'][0] + 48, y + 32), 'LSUM', name='LSUM')
    # the line's three sources stay outside the module: a slider cannot reach inside one
    s.wire(ln['LEVEL'], (lx - 144, y + 32), (lx - 144, y + 208), net='LEVEL')
    s.rail((lx - 144, y + 208), (lx - 192, y + 208), a.line_level, 'LEVEL', name='LEVEL')
    s.wire(ln['NOISE'], (lx - 96, y + 64), (lx - 96, y + 272), net='NOISE')
    s.rail((lx - 96, y + 272), (lx - 96, y + 320), a.noise, 'NOISE', name='NOISE', wf=6)
    s.wire(ln['IMP'], (lx - 48, y + 96), (lx - 48, y + 208), net='IMP')
    s.rail((lx - 48, y + 208), (lx, y + 208), a.impulse, 'IMP', name='IMP', wf=2,
           fr=a.impulse_hz / 2, bias=0.0)
    s.text((lx - 240, y + 176), 'level', 12)
    s.text((lx - 160, y + 304), 'noise', 12)
    s.text((lx - 16, y + 176), 'impulses', 12)
    s.slider('LEVEL', 'Voltage', 0.0, 1.5, 'Line level at the receiver, V peak')
    s.slider('NOISE', 'Max Voltage', 0.0, 3.0, 'Line noise, V (uniform, per time step)')
    s.slider('IMP', 'Max Voltage', 0.0, 6.0, 'Impulse peak, V')
    s.slider('IMP', 'Frequency (Hz)', 5, 2000, 'Impulse source, Hz (two impulses a cycle)')
    rxx = ln['RX'][0] + 160
    rx = s.inst(mod_dmrx(s.steps), rxx, y, {'IN': 'RXA', 'BIT': 'RX_BIT', 'RXC': 'RX_CLK',
                                            'CD': 'CD', 'RXD': 'RXD', 'DT': 'DT'})
    s.wire(ln['RX'], (rxx - 80, y), rx['IN'], net='RXA')
    s.label((rxx - 80, y), (rxx - 80, y - 48), 'RXA', name='RXA')
    for pin in ('CD', 'RXD', 'DT'):
        s.label(rx[pin], (rx[pin][0] + 48, rx[pin][1]), pin, name=pin)
    return rx


def clocks(s, x, y):
    ck = s.inst(mod_txclk(s.steps), x, y, {'HB': 'HB', 'H': 'TX_CLK'})
    for pin, net in (('HB', 'HB'), ('H', 'TX_CLK')):
        s.wire(ck[pin], (ck[pin][0] + 64, ck[pin][1]), net=net)
        s.label((ck[pin][0] + 64, ck[pin][1]), (ck[pin][0] + 112, ck[pin][1]), net, name=net)


def build_link(a):
    s = Sch(a.steps)
    s.text((48, 48), 'CVSD over differential Manchester, 64 kbps, 128 kBaud', 24)
    s.text((48, 80), 'mf8-spec.md 9 and 12.1, subscriber-line.md 1; values from mf8.params(64000) '
                     'by falstad_cvsd.py.  Each block is a subcircuit', 12)
    src = audio_source(s, 48, 288, a.level_db)
    enc = s.inst(mod_cvsd(True, a.steps), 320, 288, {'AUDIO': 'AUDIO', 'CLK': 'TX_CLK', 'BIT': 'C_TX',
                                                      '/BIT': '/BIT', 'Y': 'ENC_Y', 'SYL': 'ENC_SYL'})
    s.wire(src, (256, 288), enc['AUDIO'], net='AUDIO')
    s.label((256, 288), (256, 240), 'AUDIO', name='AUDIO')
    s.label(enc['CLK'], (272, 320), 'TX_CLK')
    for pin, net in (('BIT', 'C_TX'), ('Y', 'ENC_Y'), ('SYL', 'ENC_SYL')):
        s.label(enc[pin], (enc[pin][0] + 48, enc[pin][1]), net, name=net)
    clocks(s, 320, 512)
    ex = enc['/BIT'][0] + 224
    rx = line_section(s, ex, 320, a)
    s.wire(enc['/BIT'], (ex, 320), net='/BIT')
    dx = rx['BIT'][0] + 160
    dec = s.inst(mod_cvsd(False, a.steps, a.dec_imin, a.dec_imax), dx, 320,
                 {'BIT': 'RX_BIT', 'CLK': 'RX_CLK', 'Y': 'DEC_Y', 'SYL': 'DEC_SYL'})
    s.wire(rx['BIT'], (dx - 96, 320), dec['BIT'], net='RX_BIT')
    s.label((dx - 96, 320), (dx - 96, 272), 'RX_BIT', name='RX_BIT')
    s.wire(rx['RXC'], (dx - 48, 352), dec['CLK'], net='RX_CLK')
    s.label((dx - 48, 352), (dx - 48, 400), 'RX_CLK', name='RX_CLK')
    s.label(dec['SYL'], (dec['SYL'][0] + 48, dec['SYL'][1]), 'DEC_SYL', name='DEC_SYL')
    fx = dec['Y'][0] + 160
    rc = s.inst(mod_recon(a.steps), fx, 320, {'IN': 'DEC_Y', 'OUT': 'OUT'})
    s.wire(dec['Y'], (fx - 80, 320), rc['IN'], net='DEC_Y')
    s.label((fx - 80, 320), (fx - 80, 272), 'DEC_Y', name='DEC_Y')
    ox = rc['OUT'][0] + 64
    s.wire(rc['OUT'], (ox, 320), net='OUT')
    s.label((ox, 320), (ox + 48, 320), 'OUT', name='OUT')
    s.add('aout', (ox, 320), (ox, 384), {'du': 1.0, 'sa': 16000}, [(ox, 320)], ['OUT'])
    # the first voltage plot in a scope is drawn green, the second red
    s.scope(['AUDIO', 'ENC_Y'], 2, 0, 'input (green), encoder integrator (red)')
    s.scope(['LSUM', 'RXA'], 1, 1, 'the line (green), after the input filter (red)')
    s.scope(['AUDIO', 'OUT'], 16, 2, 'input (green), decoder output (red)')
    s.scope(['ENC_SYL', 'DEC_SYL'], 64, 3, 'syllabic node: encoder (green), decoder (red)')
    return s


def build_dmlink(a):
    s = Sch(a.steps)
    s.text((48, 48), 'Differential Manchester link, 64 kbps, 128 kBaud, on a PRBS', 24)
    s.text((48, 80), 'mf8-spec.md 9.2 and 9.4 with circuit-review.md 3; by falstad_cvsd.py.  '
                     'Each block is a subcircuit', 12)
    data = [sum(b << i for i, b in enumerate(PRBS7[k:k + 32])) for k in range(0, 127, 32)]
    data = [d - (1 << 32) if d >= 1 << 31 else d for d in data]          # Java ints
    sg = [chip_pin(96, 288, 2, 2, W, 0), chip_pin(96, 288, 2, 2, E, 1)]
    s.add('SeqGen', (96, 288), (192, 288), {'bc': 127, 'dt': ' '.join(map(str, data))}, sg,
          ['TX_CLK', 'PRBS'])
    s.label(sg[0], (48, 288), 'TX_CLK')
    s.dff(288, 320, 'PRBS', 'C_TX', '/BIT', 'TX_CLK')                    # registers the bit, gives /bit
    s.wire(sg[1], (288, 320), net='PRBS')
    s.label((288, 352), (240, 352), 'TX_CLK')
    s.label((384, 320), (432, 320), 'C_TX', name='C_TX')
    clocks(s, 96, 480)
    rx = line_section(s, 560, 384, a)
    s.wire((384, 384), (560, 384), net='/BIT')
    for pin, net in (('BIT', 'RX_BIT'), ('RXC', 'RX_CLK')):
        s.label(rx[pin], (rx[pin][0] + 48, rx[pin][1]), net, name=net)
    s.text((96, 256), 'PRBS7', 12)
    s.scope(['TXD'], 1, 0, 'TXD, the encoder output')
    s.scope(['LSUM', 'RXA'], 1, 1, 'the line (green), after the input filter (red)')
    s.scope(['RXD', 'DT'], 1, 2, 'slicer (green), dead time = accepted transition (red)')
    s.scope(['RX_BIT', 'RX_CLK'], 1, 3, 'recovered bit (green) and clock (red)')
    return s


def build_engine(a):
    s = Sch(a.steps)
    s.text((48, 48), 'CVSD engine, 64 kbps, looped back', 24)
    s.text((48, 80), 'mf8-spec.md 12.1 with circuit-review.md 2.4; values from mf8.params(64000) '
                     'by falstad_cvsd.py.  Each block is a subcircuit', 12)
    src = audio_source(s, 48, 288, a.level_db)
    enc = s.inst(mod_cvsd(True, a.steps, probes=a.probes), 320, 288,
                 {'AUDIO': 'AUDIO', 'CLK': 'TX_CLK', 'BIT': 'C_TX', '/BIT': None, 'Y': 'ENC_Y',
                  'SYL': 'ENC_SYL', 'Q2': 'ENC_Q2', '/COIN': 'ENC_NCOIN'})
    s.wire(src, (256, 288), enc['AUDIO'], net='AUDIO')
    s.label((256, 288), (256, 240), 'AUDIO', name='AUDIO')
    dec = s.inst(mod_cvsd(False, a.steps, a.dec_imin, a.dec_imax, probes=a.probes), 800, 288,
                 {'BIT': 'C_TX', 'CLK': 'RX_CLK', 'Y': 'DEC_Y', 'SYL': 'DEC_SYL',
                  'Q2': 'DEC_Q2', '/COIN': 'DEC_NCOIN'})
    s.wire(enc['BIT'], (672, 288), dec['BIT'], net='C_TX')
    s.label((672, 288), (672, 240), 'C_TX', name='C_TX')
    for pin, net in [('Y', 'ENC_Y'), ('SYL', 'ENC_SYL')] + ([('Q2', 'ENC_Q2'), ('/COIN', 'ENC_NCOIN')] if a.probes else []):
        s.label(enc[pin], (enc[pin][0] + 48, enc[pin][1]), net, name=net)
    for pin, net in [('SYL', 'DEC_SYL')] + ([('Q2', 'DEC_Q2'), ('/COIN', 'DEC_NCOIN')] if a.probes else []):
        s.label(dec[pin], (dec[pin][0] + 48, dec[pin][1]), net, name=net)
    # the encoder's clock, and the decoder's half a bit later, as a receiver samples.
    # Two sources, not an inverter, whose zero-delay output edge wanders by a step
    for k, (name, ph, post) in enumerate((('TX_CLK', 0.0, enc['CLK']), ('RX_CLK', math.pi, dec['CLK']))):
        y = 480 + 64 * k
        s.rail((96, y), (48, y), 2.5, name, wf=2, fr=float(RATE), bias=2.5,
               phaseShift=ph - math.pi / a.steps)
        s.wire((96, y), (160, y), net=name)
        s.label((160, y), (208, y), name, name=name)
        s.label(post, (post[0] - 48, post[1]), name)
    fx = dec['Y'][0] + 160
    rc = s.inst(mod_recon(a.steps), fx, 288, {'IN': 'DEC_Y', 'OUT': 'OUT'})
    s.wire(dec['Y'], (fx - 80, 288), rc['IN'], net='DEC_Y')
    s.label((fx - 80, 288), (fx - 80, 240), 'DEC_Y', name='DEC_Y')
    ox = rc['OUT'][0] + 64
    s.wire(rc['OUT'], (ox, 288), net='OUT')
    s.label((ox, 288), (ox + 48, 288), 'OUT', name='OUT')
    s.add('aout', (ox, 288), (ox, 352), {'du': 1.0, 'sa': 16000}, [(ox, 288)], ['OUT'])
    s.scope(['AUDIO', 'ENC_Y'], 2, 0, 'input (green), encoder integrator (red)')
    s.scope(['AUDIO', 'OUT'], 16, 1, 'input (green), decoder output (red)')
    s.scope(['ENC_SYL', 'DEC_SYL'], 64, 2, 'syllabic node: encoder (green), decoder (red)')
    return s


CIRCUITS = {'link': (build_link, 'cvsd_link.txt'), 'dmlink': (build_dmlink, 'dm_link.txt'),
            'engine': (build_engine, 'cvsd_engine.txt')}


def summary(steps=STEPS):
    n_dt, n_c, n_cd = rx_steps(steps)
    return (f'law: tau_syl {LAW.tau_syl*1e3:g} ms, tau_int {LAW.tau_int*1e3:g} ms, '
            f'{LAW.companding_db:g} dB, slew {LAW.slew:g} FS/s\n'
            f'R_int {R_INT:.4g}  R1 {R1:.4g}  R2 {R2:.4g}  ratio {(R1+R2)/R1:.2f} '
            f'({20*math.log10((R1+R2)/R1):.2f} dB)  tau_syl {C_SYL*R1*R2/(R1+R2)*1e3:.3f} ms\n'
            f'I_max {I_MAX*1e6:.1f} uA  I_min {I_MAX*R1/(R1+R2)*1e6:.2f} uA  '
            f'R_set {R_SET:.4g}  V_syl at idle {VD_SYL:.3f} V  '
            f'control at I_min {V_A*R1/(R1+R2)*1e3:.0f} mV\n'
            f'line: cell {CELL*1e6:.3f} us = {steps} steps; dead time {n_dt} steps, classifier {n_c}, '
            f'long from {n_dt+n_c+1} steps ({(n_dt+n_c+0.5)/steps:.3f} cell); carrier detect {n_cd}; '
            f'filter {1/(2*math.pi*R_F1*C_F1)/1e3:.1f} kHz x2; ring {1/(2*math.pi*math.sqrt(L_RING*C_RING))/1e3:.1f} kHz, '
            f'tau {2*R_RING*C_RING*1e6:.0f} us, peak {ring_peak():.4f} V/V')


def write(kind, a, out):
    s = CIRCUITS[kind][0](a)
    errs = [e for m in s.models for e in m.check()] + s.check()
    for e in errs:
        print('CHECK:', e, file=sys.stderr)
    if errs:
        sys.exit(1)
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    with open(out, 'w') as f:
        f.write(s.xml())
    inside = sum(len(m.sch.elms) for m in s.models)
    print(f'{kind:7s} {len(s.elms)} elements and {len(s.models)} modules ({inside} elements inside), '
          f'{a.steps} steps/bit -> {out}')


# ------------------------------------------------------------ against the model

def _edges(v):
    hi = v > 2.5
    return np.flatnonzero(hi[1:] & ~hi[:-1]) + 1


def sinad(x, f0, fs, band=(200.0, 3400.0)):
    """The tone against everything else in the band: no alignment, no filter."""
    x = np.asarray(x, float)
    X = np.abs(np.fft.rfft((x - x.mean()) * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / fs)
    tone = np.abs(f - f0) <= 2.5 * fs / len(x)
    inband = (f >= band[0]) & (f <= band[1])
    return 10 * np.log10(X[tone].sum() / X[inband & ~tone].sum())


def check(path, settle=0.008):
    d = json.load(open(path))
    meta = d.get('meta', {})
    v = {k: np.asarray(x, float) for k, x in d.items() if k not in ('info', 'meta') and isinstance(x, list)}
    t = v['t']
    ts = float(np.median(np.diff(t)))
    steps = int(round(CELL / ts))
    line, codec = 'RXA' in v, 'ENC_Y' in v
    tx, rx = _edges(v['TX_CLK']), _edges(v['RX_CLK'])
    print(f'{os.path.basename(path)}: {steps} steps/bit, {t[-1]*1e3:.1f} ms; '
          + (f"{meta['steps']} steps in {meta['wallSeconds']:.0f} s wall, "
             f"{len(meta['failures'])} solver failures" if meta else 'no meta'))
    per = np.diff(tx)
    print(f'  TX clock       period {np.median(np.diff(t[tx]))*1e6:.4f} us, spread {np.ptp(per)} steps')

    # bits sent: C_TX in the middle of each TX clock period.  Bits received: what the
    # decoder's flip-flop reads on each rising edge of its clock
    b_tx = (v['C_TX'][tx[:-1] + steps // 2] > 2.5).astype(np.uint8)
    b_rx = (v['RX_BIT' if line else 'C_TX'][rx] > 2.5).astype(np.uint8)

    if line:
        # each strobe carries the bit of the TX period a fixed latency before it
        cell = (t[rx][:, None] - t[tx][None, :1]) / CELL
        best = None
        for lat in np.arange(0.0, 4.0, 0.125):
            c = np.floor(cell[:, 0] - lat).astype(int)
            ok = (c >= 0) & (c < len(b_tx))
            agree = np.mean(b_rx[ok] == b_tx[c[ok]])
            if best is None or agree > best[0] + 1e-9:
                best = (agree, lat, c, ok)
        _, lat, c, ok = best
        # the latency is measured; centre the window a quarter cell inside its plateau
        good = [l for l in np.arange(0.0, 4.0, 0.125)
                if np.mean(b_rx[ok] == b_tx[np.clip(np.floor(cell[:, 0] - l).astype(int), 0, len(b_tx) - 1)[ok]]) >= best[0] - 1e-9]
        lat = (min(good) + max(good)) / 2
        c = np.floor(cell[:, 0] - lat).astype(int)
        ok = (c >= 0) & (c < len(b_tx))
        first, last = c[ok][0], c[ok][-1]
        sent = last - first + 1
        errs = int(np.sum(b_rx[ok] != b_tx[c[ok]]))
        counts = np.bincount(c[ok] - first, minlength=sent)
        gaps = np.diff(rx)
        print(f'  line           {sent} bits sent, {int(ok.sum())} strobes: {errs} bit errors, '
              f'{int(np.sum(counts == 0))} bits with no strobe, {int(np.sum(counts > 1))} with two; '
              f'latency {lat:.2f} cell')
        gaps = gaps[8:]                                      # after the receiver has started
        print(f'  recovered clk  period {np.median(gaps):.0f} steps, {gaps.min()} to {gaps.max()}; '
              f'carrier detect high {np.mean(v["CD"][len(t)//8:] > 2.5)*100:.1f} % of the time')
        # the receiver against the repository's own: fast.mono_decode on the slicer output it
        # was given, then bit by bit in time -- each strobe against the transition that made it
        w = (v['RXD'] > 2.5).astype(np.uint8)
        n_dt, n_c, _ = rx_steps(steps)
        ref = fast.mono_decode(w, steps, thr=(n_dt + n_c + 0.5) / steps, dead=(n_dt + 1) / steps)
        ch = np.flatnonzero(np.diff(w.astype(np.int8))) + 1
        last, mid, ev = ch[0], 0, {}
        for e in ch[1:]:
            gap = e - last
            if gap <= n_dt:
                continue
            last = e
            if gap > n_dt + n_c:
                ev[int(e)], mid = 1, 0
            elif mid:
                ev[int(e)], mid = 0, 0
            else:
                mid = 1
        lag = int(np.median([r - max(e for e in ev if e < r) for r in rx[20:60]]))
        got = {int(r) - lag: int(bb) for r, bb in zip(rx, b_rx)}
        span = [k for k in set(ev) | set(got) if 20 * steps < k < len(t) - 4 * steps]
        diff = sum(ev.get(k) != got.get(k) for k in span)
        assert abs(len(ref) - len(ev)) <= 1, (len(ref), len(ev))
        print(f'  receiver       fast.mono_decode on the same slicer output gives {len(ref)} bits; strobe by '
              f'strobe, {diff} of {len(span)} differ')
        if 'LSUM' in v:
            from scipy import signal
            bz, az = signal.bilinear([1.0], [R_F1 * C_F1 * R_F2 * C_F2,
                                             R_F1 * C_F1 + R_F2 * C_F2 + R_F1 * C_F2, 1.0], fs=1 / ts)
            yf = signal.lfilter(bz, az, v['LSUM'])
            k1 = 40 * steps
            print(f'  input filter   RXA against the same two RC sections applied to LSUM in Python: '
                  f'difference {20*math.log10(np.std(yf[k1:] - v["RXA"][k1:]) / np.std(v["RXA"][k1:])):.1f} dB')
            k0 = len(t) // 8
            print(f'  at the slicer  rms {np.std(v["RXA"][k0:]):.3f} V, peak {np.max(np.abs(v["RXA"][k0:])):.3f} V; '
                  f'on the line rms {np.std(v["LSUM"][k0:]):.3f} V, peak {np.max(np.abs(v["LSUM"][k0:])):.3f} V')
    if not codec:
        return

    n = min(len(tx) - 1, len(rx) - 1)
    x = v['AUDIO'][tx[:n]]                                   # what each decision compared
    keep = int(np.searchsorted(t[tx[:n]], settle))
    peak = np.max(np.abs(x[keep:]))
    level = round(20 * math.log10(peak / (mf8.NOMINAL_RMS * math.sqrt(2) * FS)), 1) + 0.0
    print(f'  input          1 kHz at {level:+.1f} dB re nominal')

    # the OTA: the integrator's current, mid-bit, against the Iabc the drive should make
    y, syl, q = v['ENC_Y'], v['ENC_SYL'], v['C_TX'] > 2.5
    ratio, iabc = [], []
    for e in tx[keep:n]:
        for s in range(3, steps):
            i = e + s
            iout = C_INT * (y[i] - y[i - 1]) / ts + (y[i] + y[i - 1]) / 2 / R_INT
            ia = (V_A - syl[i]) / R_SET * BETA / (BETA + 1)
            ratio.append(iout * (1 if q[i] else -1) / ia)
            iabc.append(ia)
    print(f'  OTA            Iout / Iabc {np.mean(ratio):.3f} (sd {np.std(ratio):.3f}), '
          f'Iabc {min(iabc)*1e6:.2f}-{max(iabc)*1e6:.2f} uA')

    # the decoder against cvsd.decode on the bits it received, each for as long as it
    # actually lasted: the interval to the next edge of the recovered clock
    rk = int(np.searchsorted(t[rx], settle))
    dt = np.diff(t[rx])
    ym = cvsd.decode(b_rx[:-1], LAW, dt=dt)
    yd = v['DEC_Y'][rx[1:]]                                  # the state after each bit
    a, b = ym[rk:], yd[rk:]
    g = np.dot(a, b) / np.dot(b, b)
    res = 20 * math.log10(np.std(a - g * b) / np.std(a))
    print(f'  decoder        against cvsd.decode on the bits and intervals it received: gain {g:.3f}, '
          f'difference {res:.1f} dB re signal')

    # the syllabic node against the law, from the same bits and intervals
    tau = C_SYL * R1 * R2 / (R1 + R2)
    sm, sv, hist = 0.0, np.zeros(len(dt)), 0
    for i, bb in enumerate(b_rx[:-1]):
        hist = ((hist << 1) | int(bb)) & 7
        sm += ((1.0 if hist in (0, 7) else 0.0) - sm) * (1 - math.exp(-dt[i] / tau))
        sv[i] = sm
    vm = V_A * R2 / (R1 + R2) * (1 - sv[rk:])
    vc = v['DEC_SYL'][rx[1:]][rk:]
    print(f'  syllabic node  decoder {vc.mean():.3f} V, law {vm.mean():.3f} V from the same bits; '
          f'rms difference {np.std(vc - vm)*1e3:.1f} mV')

    # the encoder: its bits against cvsd.encode on the same input samples
    be = cvsd.encode(x, LAW)
    run3 = lambda z: np.mean((z[2:] == z[1:-1]) & (z[1:-1] == z[:-2]))
    print(f'  encoder        runs of three in {run3(b_tx[keep:n]):.3f} of bits; '
          f'cvsd.encode on the same input {run3(be[keep:n]):.3f}')

    # the tone at the decoder's integrator, sampled on the transmit clock's uniform grid
    s_c = sinad(v['DEC_Y'][tx[keep:n]], 1000.0, RATE)
    s_m = sinad(cvsd.decode(be, LAW)[keep:n], 1000.0, RATE)
    print(f'  SINAD, 1 kHz   circuit {s_c:.1f} dB; cvsd.encode and cvsd.decode on the same '
          f'input {s_m:.1f} dB (in band, 200-3400 Hz)')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'check':
        for pth in sys.argv[2:]:
            check(pth)
        sys.exit(0)
    ap = argparse.ArgumentParser()
    ap.add_argument('circuit', nargs='?', default='all', choices=['all'] + list(CIRCUITS))
    ap.add_argument('-o', help='output file (one circuit), or directory (all); default falstad/')
    ap.add_argument('--steps', type=int, default=STEPS, help='time steps per bit')
    ap.add_argument('--level-db', type=float, default=0.0, help='sine level re nominal')
    ap.add_argument('--line-level', type=float, default=1.0, help='signal peak at the receiver, V')
    ap.add_argument('--noise', type=float, default=0.0, help='line noise source, V (uniform +-V per step)')
    ap.add_argument('--impulse', type=float, default=0.0, help='impulse peak on the line, V')
    ap.add_argument('--impulse-hz', type=float, default=517.0, help='impulses a second')
    ap.add_argument('--dec-imin', type=float, default=1.0, help="scale the decoder's I_min alone")
    ap.add_argument('--dec-imax', type=float, default=1.0, help="scale the decoder's I_max and I_min")
    ap.add_argument('--probes', action='store_true', help='engine: bring Q2 and /COIN out as pins')
    a = ap.parse_args()
    if a.circuit == 'all':
        print(summary(a.steps))
        for kind, (_, name) in CIRCUITS.items():
            write(kind, a, os.path.join(a.o or 'falstad', name))
    else:
        write(a.circuit, a, a.o or os.path.join('falstad', CIRCUITS[a.circuit][1]))
