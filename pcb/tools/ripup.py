#!/usr/bin/env python3
"""ripup.py -- clear room on a routed board so the router can finish it.

    ripup.py BOARD [--rect x0,y0,x1,y1 ...] [--net NAME ...]

Every net with a track or via inside a rectangle loses ALL its tracks and
vias, as does every named net: a net cut part-way leaves stubs the router does
not join up (measured: 1 open became 9).  GND keeps what lies outside the
rectangles, since the pour joins it; the pour is left (route.py replaces it).
Then route.py routes the board again with that room, the rest of the routing
held as it was.  Coordinates are the board's, in mm."""
import os
import sys

import pcbnew
from pcbnew import ToMM


def main(argv):
    path = argv[0]
    rects, nets = [], set()
    i = 1
    while i < len(argv):
        if argv[i] == '--rect':
            rects.append(tuple(float(v) for v in argv[i + 1].split(',')))
            i += 2
        elif argv[i] == '--net':
            nets.add(argv[i + 1].lstrip('/'))
            i += 2
        else:
            raise SystemExit(f"unknown argument {argv[i]}")
    b = pcbnew.LoadBoard(path)

    def inside(p):
        x, y = ToMM(p.x), ToMM(p.y)
        return any(r[0] <= x <= r[2] and r[1] <= y <= r[3] for r in rects)
    tr = b.Tracks()
    items = [tr[k] for k in range(len(tr))]

    def hit(t):
        if t.GetClass() == 'PCB_VIA':
            return inside(t.GetPosition())
        return inside(t.GetStart()) or inside(t.GetEnd())
    whole = set(nets) | {t.GetNetname().lstrip('/') for t in items if hit(t)}
    whole.discard('GND')
    gone = [t for t in items if t.GetNetname().lstrip('/') in whole
            or (t.GetNetname().lstrip('/') == 'GND' and hit(t))]
    for t in gone:
        b.Delete(t)
    b.Save(path)
    print(f"{os.path.basename(path)}: {len(gone)} tracks and vias removed, {len(whole)} nets cleared")
    sys.stdout.flush()
    os._exit(0)          # skip pcbnew's teardown (a double free at exit)


if __name__ == '__main__':
    main(sys.argv[1:])
