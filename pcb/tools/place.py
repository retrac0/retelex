#!/usr/bin/env python3
"""place.py -- try a placement of a block-stack board, and score it.

    place.py info  CARD                     what is fixed, what is free, every part to place
                                            (size at 0 deg, nets) -- JSON on stdout
    place.py apply CARD PLACEMENT.json OUT  write OUT/CARD/CARD.kicad_pcb: the contract's fixed
                                            parts, then PLACEMENT = {ref: [x, y, rot]}; fails on
                                            an overlap, a part off the board, or a part left out.
                                            [x, y, rot, "edge"]: a right-angle part at an edge,
                                            whose body may reach past the outline
    place.py hpwl  BOARD                    half-perimeter wirelength of every net, in mm, and the
                                            worst nets -- a fast proxy, no routing
    place.py score BOARD [PASSES]           route BOARD in place (route.py, Freerouting, routing
                                            only), GND pour, then DRC with schematic parity ->
                                            JSON: unconnected, copper violations, tracks, vias

Coordinates are KiCad's: mm, +x right, +y toward the FRONT edge, origin at the
back-left corner of the 100 x 100 outline.  (x, y) is the footprint's origin --
pad 1 for a DIP, a header or a SIP -- and rot is degrees counter-clockwise as
KiCad shows it.  Every part goes on the top side.  A part's courtyard, grown by
0.4 mm, must not touch another's, a hole's 1.5 mm keep-out, or the board edge.

A variant directory carries copies of the card's schematic, so KiCad's DRC can
check the board against it (--schematic-parity), and it never touches pcb/CARD/.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PCB = HERE.parent
sys.path.insert(0, str(HERE))
import pcb as P  # noqa: E402
import pcbnew  # noqa: E402
from pcbnew import ToMM  # noqa: E402

COPPER = {'clearance', 'tracks_crossing', 'shorting_items', 'hole_clearance', 'copper_edge_clearance',
          'via_dangling', 'track_dangling', 'hole_to_hole', 'courtyards_overlap', 'unconnected_items',
          'solder_mask_bridge', 'annular_width', 'drill_out_of_range', 'items_not_allowed'}


def info(card):
    bd, comps, pads, placed, problems = P.base_board(card)
    fixed = []
    for b, ref, side in bd.taken:
        fixed.append(dict(ref=ref, side=side, bbox=[round(v, 2) for v in b]))
    nets_of = {}
    for (ref, pin), n in pads.items():
        nets_of.setdefault(ref, set()).add(n)
    parts = []
    for ref, c in sorted(comps.items(), key=lambda kv: P._refkey(kv[0]) if hasattr(P, '_refkey') else kv[0]):
        if ref in placed or ref.startswith('#'):
            continue
        fp = P.load_fp(c['fp'])
        fp.SetPosition(P.mm(0, 0))
        b = P.bbox(fp, 0.0)
        parts.append(dict(ref=ref, value=c['value'], footprint=c['fp'],
                          bbox_at_origin_rot0=[round(v, 2) for v in b],
                          size=[round(b[2] - b[0], 2), round(b[3] - b[1], 2)],
                          function=(c.get('fields') or {}).get('Function', ''),
                          nets=sorted(n for n in nets_of.get(ref, ()) if not n.startswith('unconnected-'))))
    fixed_nets = {}
    for ref in placed:
        fixed_nets[ref] = sorted(n for n in nets_of.get(ref, ()) if not n.startswith('unconnected-'))
    return dict(card=card, outline=[P.W, P.H], layers=P.LAYERS[card], margin_courtyard=0.4,
                hole_keepout=1.5, fixed=fixed, fixed_nets=fixed_nets, to_place=parts,
                contract_problems=problems)


def apply(card, placement, out):
    bd, comps, pads, placed, problems = P.base_board(card)
    placement = {k: v for k, v in placement.items() if not k.startswith('_')}
    want = [r for r in comps if r not in placed and not r.startswith('#')]
    missing = [r for r in want if r not in placement]
    if missing:
        problems.append(f"not placed: {missing}")
    for ref, xyr in placement.items():
        if ref not in comps or ref in placed:
            problems.append(f"{ref}: not a part to place on {card}")
            continue
        x, y, rot = (list(xyr) + [0])[:3]
        edge = len(xyr) > 3 and xyr[3] == 'edge'
        fp = P.load_fp(comps[ref]['fp'])
        fp.SetOrientationDegrees(rot)
        fp.SetPosition(P.mm(x, y))
        box = P.bbox(fp)
        if edge:
            box = (max(box[0], 1.0), max(box[1], 1.0), min(box[2], P.W - 1.0), min(box[3], P.H - 1.0))
        if not bd.fits(box):
            hit = [r for b, r, s in bd.taken if P.overlap(box, b)]
            problems.append(f"{ref} at ({x}, {y}, {rot}): "
                            + (f"overlaps {hit}" if hit else "off the board"))
        bd.add(ref, comps[ref], pads, x, y, rot)
    d = Path(out) / card
    d.mkdir(parents=True, exist_ok=True)
    src = PCB / card
    for f in src.glob('*.kicad_sch'):
        shutil.copy(f, d / f.name)
    shutil.copy(src / f"{card}.kicad_pro", d / f"{card}.kicad_pro")
    (d / 'fp-lib-table').write_text(
        f'(fp_lib_table\n\t(version 7)\n\t(lib (name "telco") (type "KiCad") '
        f'(uri "{PCB / "lib" / "telco.pretty"}") (options "") (descr ""))\n)\n')
    path = d / f"{card}.kicad_pcb"
    bd.b.Save(str(path))
    return path, problems


def hpwl(board_path):
    b = pcbnew.LoadBoard(str(board_path))
    pts = {}
    for fp in b.Footprints():
        for p in fp.Pads():
            n = p.GetNetname()
            if not n or n.startswith('unconnected-'):
                continue
            pts.setdefault(n, []).append((ToMM(p.GetPosition().x), ToMM(p.GetPosition().y)))
    per = {}
    for n, ps in pts.items():
        if len(ps) < 2:
            continue
        xs, ys = [p[0] for p in ps], [p[1] for p in ps]
        per[n] = (max(xs) - min(xs)) + (max(ys) - min(ys))
    sig = {n: v for n, v in per.items() if n.lstrip('/') not in ('GND', '+5V')}
    worst = sorted(sig.items(), key=lambda kv: -kv[1])[:12]
    return dict(total_mm=round(sum(sig.values()), 1), nets=len(sig),
                worst=[[n, round(v, 1)] for n, v in worst])


def score(board_path, passes=12):
    board_path = Path(board_path)
    env = dict(os.environ)
    env.setdefault('FREEROUTING_TIMEOUT', '3600')
    r = subprocess.run([sys.executable, str(HERE / 'route.py'), str(board_path), str(board_path), str(passes)],
                       capture_output=True, text=True, env=env)
    routed = r.returncode == 0
    out = board_path.with_suffix('.drc.json')
    subprocess.run(['kicad-cli', 'pcb', 'drc', '--format', 'json', '--severity-error', '--severity-warning',
                    '--schematic-parity', '-o', str(out), str(board_path)], capture_output=True, text=True)
    d = json.loads(out.read_text()) if out.exists() else {}
    viol = {}
    for v in d.get('violations', []):
        viol[v['type']] = viol.get(v['type'], 0) + 1
    copper = {k: v for k, v in viol.items() if k in COPPER}
    b = pcbnew.LoadBoard(str(board_path))
    tr = b.Tracks()
    items = [tr[i] for i in range(len(tr))]
    log = board_path.with_suffix('.freerouting.log')
    fr = ''
    if log.exists():
        lines = [l for l in log.read_text(errors='replace').splitlines() if 'unrouted' in l]
        fr = lines[-1][-200:] if lines else ''
    return dict(board=str(board_path), routed=routed,
                route_tail=(r.stdout + r.stderr).strip().splitlines()[-1:] if not routed else [],
                unconnected=len(d.get('unconnected_items', [])), copper_violations=copper,
                parity=len(d.get('schematic_parity', [])),
                tracks=sum(1 for t in items if t.GetClass() == 'PCB_TRACK'),
                vias=sum(1 for t in items if t.GetClass() == 'PCB_VIA'),
                freerouting_last=fr)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    if cmd == 'info':
        print(json.dumps(info(argv[1]), indent=1))
    elif cmd == 'apply':
        path, problems = apply(argv[1], json.loads(Path(argv[2]).read_text()), argv[3])
        print(json.dumps(dict(board=str(path), problems=problems), indent=1))
        return 1 if problems else 0
    elif cmd == 'hpwl':
        print(json.dumps(hpwl(argv[1]), indent=1))
    elif cmd == 'score':
        print(json.dumps(score(argv[1], int(argv[2]) if len(argv) > 2 else 12), indent=1))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
