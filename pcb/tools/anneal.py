#!/usr/bin/env python3
"""anneal.py -- a first placement for a block-stack board by simulated annealing,
for place.py apply to write and Freerouting to route.

    anneal.py CARD PINS.json OUT.json [--seed N] [--iters N] [--T0 T] [--channel K] [--from PLACEMENT.json]

PINS.json holds the parts a person places: {ref: [x, y, rot] or [x, y, rot, "edge"]}
(the edge connectors, the lamps), and "_keepout": [[x0, y0, x1, y1], ...], areas no
moved part may use (header B keeps off the 9 mm bus IDC shroud of header A below it).  Everything else not fixed by the contract
(pcb.py base_board) is moved, on a 1.27 mm grid in quarter turns, to minimise

    sum over signal nets of the half-perimeter of the pads  (GND and +5V left out)
  + each 100 nF held beside its package's VCC pin
  + a heavy price on any overlap, off-board or keep-out

where a package's courtyard is grown by CHANNEL on every side, so that the
routing channels between packages are part of the placement.  The result is a
draft: a person looks at it, and the router decides.  OUT.json is the pinned
parts plus the moved ones, in place.py apply's form.
"""
import json
import math
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pcb as P  # noqa: E402

GRID = 1.27
CHANNEL = {'U': 1.4, 'RN': 0.6, 'JP': 0.8, 'J': 0.8}     # courtyard growth by ref prefix, mm
MARGIN = 0.4                                            # place.py's own courtyard margin


def prefix(ref):
    for p in ('RN', 'JP', 'U', 'J', 'R', 'C', 'D', 'Q'):
        if ref.startswith(p):
            return p
    return ref[0]


class Part:
    def __init__(self, ref, fpid):
        self.ref = ref
        self.rots = {}
        for rot in (0, 90, 180, 270):
            fp = P.load_fp(fpid)
            fp.SetOrientationDegrees(rot)
            fp.SetPosition(P.mm(0, 0))
            b = P.bbox(fp, 0.0)
            self.rots[rot] = (b, P.pad_xy(fp))
        self.grow = CHANNEL.get(prefix(ref), 0.0) + MARGIN


def main(argv):
    card, pins_path, out_path = argv[:3]
    seed = int(argv[argv.index('--seed') + 1]) if '--seed' in argv else 1
    iters = int(argv[argv.index('--iters') + 1]) if '--iters' in argv else 60000
    start = json.loads(Path(argv[argv.index('--from') + 1]).read_text()) if '--from' in argv else {}
    rng = random.Random(seed)
    if '--channel' in argv:             # scale the routing channels, for a crowded board
        k = float(argv[argv.index('--channel') + 1])
        for key in CHANNEL:
            CHANNEL[key] *= k
    pinned = json.loads(Path(pins_path).read_text())
    keepout = [tuple(k) for k in pinned.pop('_keepout', [])]
    T0 = float(argv[argv.index('--T0') + 1]) if '--T0' in argv else 40.0
    bd, comps, pads, placed, problems = P.base_board(card)
    if problems:
        print('contract problems:', problems)
    # obstacles: fixed parts and holes, as base_board left them (margin included)
    obst = [b for b, r, s in bd.taken] + keepout
    fixed_pad = {}
    for fp in bd.b.Footprints():
        for num, xy in P.pad_xy(fp).items():
            fixed_pad[(fp.GetReference(), num)] = xy
    refs = [r for r in comps if r not in placed and not r.startswith('#')]
    parts = {r: Part(r, comps[r]['fp']) for r in refs}
    for r, v in pinned.items():
        b, pd = parts[r].rots[v[2]]
        edge = len(v) > 3
        box = (b[0] + v[0] - MARGIN, b[1] + v[1] - MARGIN, b[2] + v[0] + MARGIN, b[3] + v[1] + MARGIN)
        if edge:
            box = (max(box[0], 1.0), max(box[1], 1.0), min(box[2], 99.0), min(box[3], 99.0))
        obst.append(box)
        for num, xy in pd.items():
            fixed_pad[(r, num)] = (xy[0] + v[0], xy[1] + v[1])
    movers = [r for r in refs if r not in pinned]

    # nets: signal nets, plus a stiff tie from each 100 nF to its package's VCC pin
    nets = {}
    for (ref, pin), n in pads.items():
        if n.startswith('unconnected-') or n.lstrip('/') in ('GND', '+5V'):
            continue
        nets.setdefault(n, []).append((ref, pin))
    weight = {n: 1.0 for n in nets}
    spec = {p['ref']: p for p in P.SPEC['cards'][card]['parts']}
    for r, p in spec.items():
        f = p.get('function', '')
        if r in parts and f.startswith('decoupling, '):
            u = f.split(', ')[1]
            vcc = next(pin for (ref, pin), n in pads.items() if ref == u and n.lstrip('/') == '+5V')
            nets[f'__dec_{r}'] = [(r, '1'), (u, vcc)]
            weight[f'__dec_{r}'] = 6.0
    of_part = {}
    for n, members in nets.items():
        for ref, _ in members:
            of_part.setdefault(ref, set()).add(n)

    # state
    st = {}
    cols = [x for x in range(8, 93, 5)]
    for r in movers:
        if r in start:
            st[r] = list(start[r][:3])
        else:
            st[r] = [rng.choice(cols) * 1.0, rng.uniform(15, 80), rng.choice((0, 90, 180, 270))]
            if prefix(r) == 'U':
                st[r][2] = rng.choice((0, 180))

    def pad_at(ref, pin):
        if ref in st:
            x, y, rot = st[ref]
            px, py = parts[ref].rots[rot][1][pin]
            return px + x, py + y
        return fixed_pad.get((ref, pin))

    def net_cost(n):
        xs, ys = [], []
        for ref, pin in nets[n]:
            p = pad_at(ref, pin)
            if p is None:
                continue
            xs.append(p[0]); ys.append(p[1])
        if len(xs) < 2:
            return 0.0
        return weight[n] * ((max(xs) - min(xs)) + (max(ys) - min(ys)))

    def box(ref):
        x, y, rot = st[ref]
        b = parts[ref].rots[rot][0]
        g = parts[ref].grow
        return (b[0] + x - g, b[1] + y - g, b[2] + x + g, b[3] + y + g)

    def ov(a, b):
        w = min(a[2], b[2]) - max(a[0], b[0])
        h = min(a[3], b[3]) - max(a[1], b[1])
        return w * h if w > 0 and h > 0 else 0.0

    def part_pen(ref, others=True):
        b = box(ref)
        pen = 0.0
        # off board (the outline less 1 mm)
        pen += max(0, 1.0 - b[0]) * 20 + max(0, 1.0 - b[1]) * 20 + max(0, b[2] - 99.0) * 20 + max(0, b[3] - 99.0) * 20
        for o in obst:
            pen += ov(b, o)
        if others:
            for r2 in movers:
                if r2 != ref:
                    pen += ov(b, box(r2))
        return pen

    def total():
        c = sum(net_cost(n) for n in nets)
        pen = sum(part_pen(r, False) for r in movers)
        for i, a in enumerate(movers):
            ba = box(a)
            for b2 in movers[i + 1:]:
                pen += ov(ba, box(b2))
        return c, pen

    lam = 20.0
    c, pen = total()
    cost = c + lam * pen
    T1 = 0.05
    for it in range(iters):
        T = T0 * (T1 / T0) ** (it / iters)
        r = rng.choice(movers)
        old = list(st[r])
        span = max(GRID, 30.0 * T / T0 + 2.0)
        mv = rng.random()
        if mv < 0.75:
            st[r][0] = round((old[0] + rng.uniform(-span, span)) / GRID) * GRID
            st[r][1] = round((old[1] + rng.uniform(-span, span)) / GRID) * GRID
        elif mv < 0.9:
            st[r][2] = rng.choice((0, 180)) if prefix(r) == 'U' else rng.choice((0, 90, 180, 270))
        else:
            r2 = rng.choice(movers)
            if r2 == r:
                continue
            old2 = list(st[r2])
            st[r][0], st[r][1], st[r2][0], st[r2][1] = old2[0], old2[1], old[0], old[1]
        touched = {r} | ({r2} if mv >= 0.9 else set())
        ns = set().union(*(of_part.get(t, set()) for t in touched))
        # delta, recomputing only what moved
        st_new = {t: list(st[t]) for t in touched}
        for t in touched:
            st[t] = old if t == r else old2
        before = sum(net_cost(n) for n in ns) + lam * sum(part_pen(t) for t in touched)
        for t in touched:
            st[t] = st_new[t]
        after = sum(net_cost(n) for n in ns) + lam * sum(part_pen(t) for t in touched)
        d = after - before
        if d <= 0 or rng.random() < math.exp(-d / T):
            cost += d
        else:
            st[r] = old
            if mv >= 0.9:
                st[r2] = old2
        if it % 2000 == 0:
            # the price of overlap climbs from 20 to 4000: early on parts pass
            # through each other to find their places, at the end nothing may touch
            nl = 20.0 * 200.0 ** (it / iters)
            cost += (nl - lam) * sum(part_pen(t, False) for t in movers)
            lam = nl
    c, pen = total()
    out = dict(pinned)
    if keepout:
        out['_keepout'] = [list(k) for k in keepout]
    for r in movers:
        out[r] = [round(st[r][0], 3), round(st[r][1], 3), int(st[r][2])]
    Path(out_path).write_text(json.dumps(out, indent=0))
    print(f"{card}: wirelength {c:.0f} mm (with decoupling ties), overlap {pen:.2f} mm2, {len(movers)} parts moved")
    return 0 if pen < 1e-6 else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
