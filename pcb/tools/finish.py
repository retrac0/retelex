#!/usr/bin/env python3
"""finish.py -- route the last few connections the autorouter left open, one at a
time, by a maze search on a grid, then refill the pour.  Freerouting finishes a
board's first 99 %; it does not come back for the last few, and ripping up
round them measured worse (1 open became 19).

    finish.py BOARD NET [NET ...]            route each named net's open gaps
    finish.py BOARD --drop-net NET x0,y0,x1,y1   delete that net's tracks in a box
                                              first (a GND stub the pour covers)

Both copper layers on a 0.1 mm grid.  Everything of another net is an obstacle,
grown by the clearance and half the track width; the board edge keeps 0.5 mm.
The search runs from the island holding the net's first pad to any copper of
the same net in another island; a layer change costs a via.  Track 0.3 mm,
clearance 0.25 mm, via 0.8 / 0.4 mm, as route.py gives Freerouting.  DRC with
schematic parity decides whether the result stands."""
import heapq
import math
import os
import sys

import numpy as np
import pcbnew
from pcbnew import FromMM, ToMM, VECTOR2I

G = 0.1                     # grid, mm
TW, CL, VIA, DRILL = 0.3, 0.25, 0.8, 0.4
LAYERS = [pcbnew.F_Cu, pcbnew.B_Cu]


def seg_cells(x0, y0, x1, y1, r, nx, ny):
    """grid cells within r of a segment"""
    out = []
    lo_x, hi_x = min(x0, x1) - r, max(x0, x1) + r
    lo_y, hi_y = min(y0, y1) - r, max(y0, y1) + r
    dx, dy = x1 - x0, y1 - y0
    L2 = dx * dx + dy * dy
    for i in range(max(0, int(lo_x / G)), min(nx - 1, int(hi_x / G) + 1) + 1):
        for j in range(max(0, int(lo_y / G)), min(ny - 1, int(hi_y / G) + 1) + 1):
            px, py = i * G, j * G
            t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy) / L2))
            qx, qy = x0 + t * dx - px, y0 + t * dy - py
            if qx * qx + qy * qy <= r * r:
                out.append((i, j))
    return out


def box_cells(x0, y0, x1, y1, grow, nx, ny):
    return [(i, j) for i in range(max(0, int((x0 - grow) / G)), min(nx - 1, int((x1 + grow) / G) + 1) + 1)
            for j in range(max(0, int((y0 - grow) / G)), min(ny - 1, int((y1 + grow) / G) + 1) + 1)]


def route_net(b, netname):
    bb = b.GetBoardEdgesBoundingBox()
    W, H = ToMM(bb.GetRight()), ToMM(bb.GetBottom())
    nx, ny = int(W / G) + 1, int(H / G) + 1
    grow = CL + TW / 2
    block = [bytearray(nx * ny) for _ in LAYERS]
    mine = [bytearray(nx * ny) for _ in LAYERS]       # this net's copper
    code = b.FindNet(netname).GetNetCode()

    def mark(arr, cells):
        for i, j in cells:
            arr[j * nx + i] = 1
    tr = b.Tracks()
    for t in [tr[k] for k in range(len(tr))]:
        own = t.GetNetCode() == code
        if t.GetClass() == 'PCB_VIA':
            x, y = ToMM(t.GetPosition().x), ToMM(t.GetPosition().y)
            r = ToMM(t.GetBoundingBox().GetWidth()) / 2      # a via is handed back as a PCB_TRACK
            for li in range(2):
                mark(mine[li] if own else block[li], seg_cells(x, y, x, y, (r if own else r + grow), nx, ny))
        else:
            li = LAYERS.index(t.GetLayer()) if t.GetLayer() in LAYERS else None
            if li is None:
                continue
            w = ToMM(t.GetWidth()) / 2
            mark(mine[li] if own else block[li],
                 seg_cells(ToMM(t.GetStart().x), ToMM(t.GetStart().y), ToMM(t.GetEnd().x), ToMM(t.GetEnd().y),
                           (w if own else w + grow), nx, ny))
    pads_of_net = []
    for fp in b.Footprints():
        for p in fp.Pads():
            pb = p.GetBoundingBox()
            x0, y0, x1, y1 = ToMM(pb.GetX()), ToMM(pb.GetY()), ToMM(pb.GetRight()), ToMM(pb.GetBottom())
            own = p.GetNetCode() == code
            layers = [li for li, L in enumerate(LAYERS) if p.IsOnLayer(L)]
            if p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH:
                layers = [0, 1]
            for li in layers:
                if own:     # the disc inside the pad: a track ending there is on copper
                    r = min(x1 - x0, y1 - y0) / 2 * 0.8
                    mark(mine[li], seg_cells((x0 + x1) / 2, (y0 + y1) / 2, (x0 + x1) / 2, (y0 + y1) / 2, r, nx, ny))
                else:
                    mark(block[li], box_cells(x0, y0, x1, y1, grow, nx, ny))
            if own:
                pads_of_net.append(((x0 + x1) / 2, (y0 + y1) / 2))
    # the board edge
    e = int((0.5 + TW / 2) / G) + 1
    for li in range(2):
        for i in range(nx):
            for j in list(range(e)) + list(range(ny - e, ny)):
                block[li][j * nx + i] = 1
        for j in range(ny):
            for i in list(range(e)) + list(range(nx - e, nx)):
                block[li][j * nx + i] = 1
    # islands of this net: flood over its copper, joined through the layers at pads/vias
    comp = [[-1] * (nx * ny) for _ in LAYERS]

    def flood(si, sj, sl, c):
        st = [(si, sj, sl)]
        comp[sl][sj * nx + si] = c
        while st:
            i, j, l = st.pop()
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                a, bq = i + di, j + dj
                if 0 <= a < nx and 0 <= bq < ny and mine[l][bq * nx + a] and comp[l][bq * nx + a] < 0:
                    comp[l][bq * nx + a] = c
                    st.append((a, bq, l))
            o = 1 - l
            if mine[o][j * nx + i] and comp[o][j * nx + i] < 0 and mine[l][j * nx + i] and _joined(i, j):
                comp[o][j * nx + i] = c
                st.append((i, j, o))
    joins = set()
    for p in pads_of_net:
        joins.add((int(round(p[0] / G)), int(round(p[1] / G))))
    for t in [tr[k] for k in range(len(tr))]:
        if t.GetNetCode() == code and t.GetClass() == 'PCB_VIA':
            joins.add((int(round(ToMM(t.GetPosition().x) / G)), int(round(ToMM(t.GetPosition().y) / G))))

    def _joined(i, j):
        return any(abs(i - a) <= 8 and abs(j - c) <= 8 for a, c in joins)
    c = 0
    for l in range(2):
        for idx in range(nx * ny):
            if mine[l][idx] and comp[l][idx] < 0:
                flood(idx % nx, idx // nx, l, c)
                c += 1
    if c <= 1:
        return None, 'already connected'
    # start: the island of the first pad; goal: any other island
    p0 = pads_of_net[0]
    s0 = (int(round(p0[0] / G)), int(round(p0[1] / G)))
    start_c = comp[0][s0[1] * nx + s0[0]]
    if start_c < 0:
        start_c = comp[1][s0[1] * nx + s0[0]]
    # multi-source A*-less Dijkstra from every cell of the start island
    vr = int(math.ceil((VIA / 2 + CL - TW / 2) / G))
    dist = {}
    prev = {}
    pq = []
    for l in range(2):
        for idx in range(nx * ny):
            if comp[l][idx] == start_c:
                k = (idx % nx, idx // nx, l)
                dist[k] = 0.0
                heapq.heappush(pq, (0.0, k))
    via_cost = 6.0
    goal = None
    bad = np.zeros((ny, nx), dtype=bool)
    for L in (0, 1):
        bad |= (np.frombuffer(bytes(block[L]), dtype=np.uint8).reshape(ny, nx) == 1) & \
               (np.frombuffer(bytes(mine[L]), dtype=np.uint8).reshape(ny, nx) == 0)
    viaok = np.ones((ny, nx), dtype=bool)
    for di in range(-vr, vr + 1):
        for dj in range(-vr, vr + 1):
            if di * di + dj * dj > vr * vr:
                continue
            sh = np.zeros_like(bad)
            ys = slice(max(0, dj), ny + min(0, dj)); yd = slice(max(0, -dj), ny + min(0, -dj))
            xs = slice(max(0, di), nx + min(0, di)); xd = slice(max(0, -di), nx + min(0, -di))
            sh[yd, xd] = bad[ys, xs]
            viaok &= ~sh
    viaok = viaok.ravel().tolist()
    steps = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
             (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)]
    while pq:
        d, (i, j, l) = heapq.heappop(pq)
        if d > dist.get((i, j, l), 1e18):
            continue
        cc = comp[l][j * nx + i]
        if cc >= 0 and cc != start_c:
            goal = (i, j, l)
            break
        for di, dj, w in steps:
            a, bq = i + di, j + dj
            if not (0 <= a < nx and 0 <= bq < ny):
                continue
            idx = bq * nx + a
            if block[l][idx] and not mine[l][idx]:
                continue
            k = (a, bq, l)
            nd = d + w
            if nd < dist.get(k, 1e18):
                dist[k] = nd
                prev[k] = (i, j, l)
                heapq.heappush(pq, (nd, k))
        # a via: both layers clear over the via's size
        o = 1 - l
        if viaok[j * nx + i]:
            k = (i, j, o)
            nd = d + via_cost
            if nd < dist.get(k, 1e18):
                dist[k] = nd
                prev[k] = (i, j, l)
                heapq.heappush(pq, (nd, k))
    if goal is None:
        return None, 'no path'
    path = [goal]
    while path[-1] in prev:
        path.append(prev[path[-1]])
    path.reverse()
    # to tracks: merge straight runs, a via at each layer change
    net = b.FindNet(netname)
    added = 0
    run = [path[0]]
    for k in path[1:] + [None]:
        if k is not None and k[2] == run[-1][2] and (len(run) < 2 or
                (k[0] - run[-1][0], k[1] - run[-1][1]) == (run[-1][0] - run[-2][0], run[-1][1] - run[-2][1])):
            run.append(k)
            continue
        if len(run) >= 2:
            t = pcbnew.PCB_TRACK(b)
            t.SetStart(VECTOR2I(FromMM(run[0][0] * G), FromMM(run[0][1] * G)))
            t.SetEnd(VECTOR2I(FromMM(run[-1][0] * G), FromMM(run[-1][1] * G)))
            t.SetWidth(FromMM(TW))
            t.SetLayer(LAYERS[run[0][2]])
            t.SetNet(net)
            b.Add(t)
            added += 1
        if k is None:
            break
        if k[2] != run[-1][2]:
            v = pcbnew.PCB_VIA(b)
            v.SetPosition(VECTOR2I(FromMM(k[0] * G), FromMM(k[1] * G)))
            v.SetWidth(FromMM(VIA))
            v.SetDrill(FromMM(DRILL))
            v.SetNet(net)
            b.Add(v)
            added += 1
        run = [run[-1], k] if k[2] == run[-1][2] else [k]
    return added, f"{len(path)} cells"


def main(argv):
    path = argv[0]
    b = pcbnew.LoadBoard(path)
    args = argv[1:]
    i = 0
    while i < len(args):
        if args[i] == '--drop-net':
            name, box = args[i + 1], [float(v) for v in args[i + 2].split(',')]
            tr = b.Tracks()
            gone = 0
            for t in [tr[k] for k in range(len(tr))]:
                if t.GetNetname().lstrip('/') != name.lstrip('/') or t.GetClass() == 'PCB_VIA':
                    continue
                pts = [(ToMM(t.GetStart().x), ToMM(t.GetStart().y)), (ToMM(t.GetEnd().x), ToMM(t.GetEnd().y))]
                if all(box[0] <= x <= box[2] and box[1] <= y <= box[3] for x, y in pts):
                    b.Delete(t)
                    gone += 1
            print(f"  {name}: {gone} tracks dropped in {box}")
            i += 3
            continue
        name = args[i] if args[i].startswith('/') or b.FindNet(args[i]) else '/' + args[i]
        if b.FindNet(name) is None:
            name = args[i]
        added, how = route_net(b, name)
        print(f"  {name}: {'routed, ' + str(added) + ' items' if added else how} ({how})")
        i += 1
    filler = pcbnew.ZONE_FILLER(b)
    filler.Fill(b.Zones())
    b.Save(path)
    sys.stdout.flush()
    os._exit(0)


if __name__ == '__main__':
    main(sys.argv[1:])
