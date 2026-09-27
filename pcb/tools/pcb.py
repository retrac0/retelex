#!/usr/bin/env python3
"""pcb.py -- a block-stack card's board, placed from its netlist and
pcb/lib/block-stack.json, with pcbnew (KiCad 10).

    python3 pcb.py CARD ...                 -> pcb/<card>/<card>.kicad_pcb (placed, unrouted);
                                            CARD: blkhdr_bus_RevA, blkhdr_logic_RevA, portcard_RevC
    python3 pcb.py relink [card ...]        re-point footprints at their symbols after a regeneration

The netlist is pcb/out/gen/<card>.xml (sim/gen.sh makes it).  Footprints come
from each symbol's Footprint field; every footprint carries its symbol's path,
so KiCad's Update PCB from Schematic, and DRC --schematic-parity, see one design.

FIXED, from block-stack.json: what mates with something at a place -- the two
stacking headers, the header link J8, the bus and edge IDCs -- and the four
holes.  Each one's pads are checked against the JSON's own pad coordinates (the
pin contract is also a position contract: pin n of every card must sit over pin
n of the next).  Test strips, the adapter header and the jumpers are placed
with the rest (fixed: false in the JSON), beside the logic they serve.

PLACED here: every package on a grid in the free area, its 100 nF beside it,
then the rest where they fit.  A first placement for a human to improve, not a
finished layout -- and running this again overwrites the board.
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pcbnew
from pcbnew import FromMM, ToMM, VECTOR2I

HERE = Path(__file__).resolve().parent
PCB = HERE.parent
SPEC = json.loads((PCB / 'lib' / 'block-stack.json').read_text())
FPDIRS = {'telco': PCB / 'lib' / 'telco.pretty'}
STOCK = Path('/usr/share/kicad/footprints')
W = H = 100.0
CA, CB = 'blkhdr_bus_RevA', 'blkhdr_logic_RevA'
CARDS = [CA, CB, 'portcard_RevC']
LAYERS = {'portcard_RevC': 2, CA: 2, CB: 2}    # Joel: no 4-layer cards

# Package slots, in order: pin 1 at (x, y), rotation.  Six columns 0.55 in apart,
# rows far enough apart for a row of 100 nF between them.
COLS = [9.53 + 13.97 * i for i in range(6)]
SLOTS = {
    'portcard_RevC': [(x, 11.43, 0) for x in COLS] + [(x, 43.18, 0) for x in COLS],
    # A and B: a first draft only; the boards are placed by hand (place.py apply)
    CA: [(12.07 + 16.0 * i, y, 0) for y in (16.0, 45.0) for i in range(5)],
    CB: [(12.07 + 16.0 * i, y, 0) for y in (16.0, 45.0) for i in range(6)],
}

# where packages and the rest may go: (x0, y0, x1, y1) in mm, tried in order
FREE = {
    'portcard_RevC': [(8.5, 66.0, 53.5, 85.5), (8.5, 8.5, 92.0, 66.0), (53.5, 62.0, 92.0, 66.5),
                 (85.8, 62.0, 92.5, 85.5)],
    CA: [(8.5, 8.5, 92.0, 85.0)],
    CB: [(8.5, 8.5, 92.0, 88.0)],
}


def mm(x, y):
    return VECTOR2I(FromMM(x), FromMM(y))


def load_fp(fpid):
    lib, name = fpid.split(':', 1)
    d = FPDIRS.get(lib, STOCK / f"{lib}.pretty")
    fp = pcbnew.FootprintLoad(str(d), name)
    if fp is None:
        raise SystemExit(f"missing footprint {fpid}")
    fp.SetFPIDAsString(fpid)
    return fp


def netlist(path):
    root = ET.parse(path).getroot()
    comps = {}
    for c in root.find('components'):
        sp = c.find('sheetpath')
        first = c.findtext('tstamps').split()[0]
        comps[c.get('ref')] = dict(
            value=c.findtext('value'), fp=c.findtext('footprint'), path=sp.get('tstamps') + first,
            sheet=sp.get('names'),
            sheetfile=next((p.get('value') for p in c.iter('property') if p.get('name') == 'Sheetfile'), ''),
            fields={f.get('name'): f.text for f in (c.find('fields') if c.find('fields') is not None else [])})
    pads = {}
    for n in root.find('nets'):
        for x in n.iter('node'):
            pads[(x.get('ref'), x.get('pin'))] = n.get('name')
    return comps, pads


def bbox(fp, margin=0.4):
    """Courtyard (or body) extent in mm, grown by margin: (x0, y0, x1, y1)."""
    b = fp.GetCourtyard(pcbnew.F_CrtYd).BBox() if fp.GetCourtyard(pcbnew.F_CrtYd).OutlineCount() else None
    if b is None or b.GetWidth() == 0:
        b = fp.GetBoundingBox(False)
    return (ToMM(b.GetX()) - margin, ToMM(b.GetY()) - margin,
            ToMM(b.GetRight()) + margin, ToMM(b.GetBottom()) + margin)


def overlap(a, b):
    return not (a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1])


class Board:
    def __init__(self, card):
        self.card = card
        self.b = pcbnew.BOARD()
        self.b.GetDesignSettings().SetBoardThickness(FromMM(1.6))
        self.b.SetCopperLayerCount(LAYERS[card])
        self.nets = {}
        self.taken = []            # (bbox, ref, side)
        self.outline()

    def outline(self):
        pts = [(0, 0), (W, 0), (W, H), (0, H), (0, 0)]
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            s = pcbnew.PCB_SHAPE(self.b)
            s.SetShape(pcbnew.SHAPE_T_SEGMENT)
            s.SetLayer(pcbnew.Edge_Cuts)
            s.SetStart(mm(x1, y1))
            s.SetEnd(mm(x2, y2))
            s.SetWidth(FromMM(0.1))
            self.b.Add(s)

    def net(self, name):
        if name not in self.nets:
            n = pcbnew.NETINFO_ITEM(self.b, name)
            self.b.Add(n)
            self.nets[name] = self.b.FindNet(name)
        return self.nets[name]

    def add(self, ref, comp, pads, x, y, rot=0, back=False, fpid=None):
        fp = load_fp(fpid or comp['fp'])
        fp.SetParent(self.b)
        fp.SetReference(ref)
        fp.SetValue(comp['value'] if comp else ref)
        fp.SetPosition(mm(x, y))
        fp.SetOrientationDegrees(rot)
        self.b.Add(fp)
        if back:
            fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
        if comp:
            fp.SetPath(pcbnew.KIID_PATH(comp['path']))
            fp.SetSheetname(comp['sheet'].strip('/').split('/')[-1] if comp['sheet'] != '/' else '')
            fp.SetSheetfile(comp['sheetfile'])
            for pad in fp.Pads():
                n = pads.get((ref, pad.GetNumber()))
                if n:                       # an 'unconnected-(...)' net too: parity wants it
                    pad.SetNet(self.net(n))
            # the symbol's own fields ride along, hidden: parity compares them
            for k, v in (comp.get('fields') or {}).items():
                if k in ('Footprint', 'Datasheet', 'Description') or v is None:
                    continue
                fp.SetField(k, v)
                f = fp.GetField(k)
                if f is not None:
                    f.SetVisible(False)
        self.taken.append((bbox(fp), ref, 'B' if back else 'F'))
        return fp

    def fits(self, box, side='F', tht=True):
        if box[0] < 1.0 or box[1] < 1.0 or box[2] > W - 1.0 or box[3] > H - 1.0:
            return False
        for b, _, s in self.taken:
            # a through-hole part blocks both sides where its pads are
            if (s == side or tht) and overlap(box, b):
                return False
        return True


def pad_xy(fp):
    return {p.GetNumber(): (round(ToMM(p.GetPosition().x), 2), round(ToMM(p.GetPosition().y), 2))
            for p in fp.Pads()}


def fixed_parts(card):
    """[(ref, x, y, rot, back, pads_expected, fpid override)] from the JSON."""
    out = []
    for c in SPEC['stack_connectors']:
        fpid = c['footprint'][card]
        out.append((c['ref'], c['pos'], c['rotation'], c['side'] == 'bottom', c['pads'], fpid))
    for c in SPEC['connectors'] + SPEC['jumpers']:
        if c['card'] == card and c.get('fixed', False):
            out.append((c['ref'], c['pos'], c['rotation'], c['side'] == 'bottom', c['pads'], None))
    return out


def base_board(card):
    """A board with only what the contract fixes: outline, stack / bus /
    adapter / edge / test / link connectors and jumpers (each checked pad by
    pad against block-stack.json), and the four holes.
    -> (Board, comps, pads, placed refs, problems)"""
    xml = PCB / 'out' / 'gen' / f"{card}.xml"
    comps, pads = netlist(xml)
    bd = Board(card)
    placed = set()
    problems = []

    # ---- fixed: connectors and jumpers, then holes
    for ref, pos, rot, back, want, fpid in fixed_parts(card):
        comp = comps[ref]
        fp = bd.add(ref, comp, pads, pos[0], pos[1], rot, back, fpid=None)

        def off(fp):
            got = pad_xy(fp)
            return [(n, got.get(str(n)), tuple(xy)) for n, xy in want.items()
                    if got.get(str(n)) is None or
                    max(abs(got[str(n)][0] - xy[0]), abs(got[str(n)][1] - xy[1])) > 0.02]
        bad = off(fp)
        if bad and back:
            # KiCad's flip and rotation compose differently from the JSON's
            # "mirror x, then rotate": try the four quarter turns on B.Cu
            for r in (rot, -rot, 180 - rot, 180 + rot):
                fp.SetOrientationDegrees(r)
                fp.SetPosition(mm(pos[0], pos[1]))
                if not off(fp):
                    bad = []
                    # its keep-out moved with it
                    bd.taken = [t for t in bd.taken if t[1] != ref] + [(bbox(fp), ref, 'B')]
                    break
        if bad:
            problems.append(f"{ref}: {len(bad)} pads off the contract, e.g. pad {bad[0][0]} at {bad[0][1]} "
                            f"want {bad[0][2]}")
        placed.add(ref)
    for h in SPEC['mechanical']['holes']:
        fp = load_fp(SPEC['mechanical']['hole_footprint'])
        fp.SetParent(bd.b)
        fp.SetReference(h['ref'])
        fp.SetValue('M3')
        fp.SetPosition(mm(*h['xy']))
        fp.SetBoardOnly(True)
        fp.Reference().SetVisible(False)
        bd.b.Add(fp)
        bd.taken.append((bbox(fp, 1.5), h['ref'], 'F'))
    return bd, comps, pads, placed, problems


def build(card):
    bd, comps, pads, placed, problems = base_board(card)

    # ---- packages, each with its decoupling capacitor
    cd = {p['ref']: p for p in SPEC['cards'][card]['parts']}
    dec = {}
    for p in SPEC['cards'][card]['parts']:
        f = p.get('function', '')
        if f.startswith('decoupling, '):
            dec[f.split(', ')[1]] = p['ref']
    ics = sorted([r for r in comps if r.startswith('U')], key=lambda r: int(r[1:]))
    ics += sorted([r for r in comps if r.startswith('RN') and 'DIP' in (comps[r]['fp'] or '')], key=lambda r: int(r[2:]))
    slots = list(SLOTS[card])
    for ref in ics:
        ok = False
        while slots and not ok:
            x, y, r = slots.pop(0)
            ok = place_at(bd, comps, pads, ref, [(x, y, r)])
        if not ok:
            ok = place_near(bd, comps, pads, ref, FREE[card], 1.27, rot=90, pitch=(1.27, 1.27))
        if not ok:
            problems.append(f"{ref}: no room")
            continue
        placed.add(ref)
        c = dec.get(ref)
        if c and c in comps:
            fp_ic = next(f for f in bd.b.Footprints() if f.GetReference() == ref)
            bx = bbox(fp_ic, 0)
            # in the gap to the right of the package, beside its VCC pin (the last
            # pin, top right); else under it, else over it
            px, py = ToMM(fp_ic.GetPosition().x), ToMM(fp_ic.GetPosition().y)
            spot = [(px + 7.62 + 3.3, py, 90), (px + 7.62 + 3.3, py + 2.54, 90),
                    (bx[0] + 2.54, bx[3] + 1.9, 0), (bx[0] + 2.54, bx[1] - 1.9, 0)]
            if place_at(bd, comps, pads, c, spot):
                placed.add(c)

    # ---- everything else: resistors, networks, diodes, FETs, capacitors
    rest = [r for r in comps if r not in placed and not r.startswith('#') and not r.startswith('U')]
    order = {'Q': 0, 'RN': 1, 'R': 2, 'D': 3, 'C': 4}
    rest.sort(key=lambda r: (order.get(r[:2] if r.startswith('RN') else r[0], 9), len(r), r))
    for ref in rest:
        ok = False
        for rot in (0, 90):
            if place_near(bd, comps, pads, ref, FREE[card], 1.27, rot=rot, pitch=(1.27, 1.27)):
                ok = True
                break
        if ok:
            placed.add(ref)
        else:
            problems.append(f"{ref}: no room")

    out = PCB / card / f"{card}.kicad_pcb"
    bd.b.Save(str(out))
    return out, problems, len(placed), len(comps)


def place_at(bd, comps, pads, ref, spots):
    comp = comps[ref]
    for x, y, rot in spots:
        fp = load_fp(comp['fp'])
        fp.SetPosition(mm(x, y))
        fp.SetOrientationDegrees(rot)
        if bd.fits(bbox(fp)):
            bd.add(ref, comp, pads, x, y, rot)
            return True
    return False


def place_near(bd, comps, pads, ref, regions, grid, rot=0, pitch=(1.27, 1.27)):
    comp = comps[ref]
    probe = load_fp(comp['fp'])
    probe.SetOrientationDegrees(rot)
    probe.SetPosition(mm(0, 0))
    b0 = bbox(probe)
    for (x0, y0, x1, y1) in regions:
        # scan rows top to bottom, columns left to right, on the pitch
        y = y0 - b0[1]
        while y + b0[3] <= y1:
            x = x0 - b0[0]
            while x + b0[2] <= x1:
                box = (b0[0] + x, b0[1] + y, b0[2] + x, b0[3] + y)
                if bd.fits(box):
                    bd.add(ref, comp, pads, round(x / 0.635) * 0.635, round(y / 0.635) * 0.635, rot)
                    return True
                x += pitch[0]
            y += pitch[1]
    return False


def relink(card):
    """Point every footprint on an existing board at its symbol again (by
    reference), and check every pad's net against the current netlist: for a
    board placed or routed before the schematic was regenerated."""
    comps, pads = netlist(PCB / 'out' / 'gen' / f"{card}.xml")
    path = PCB / card / f"{card}.kicad_pcb"
    b = pcbnew.LoadBoard(str(path))
    moved, wrong = 0, []
    for fp in b.Footprints():
        ref = fp.GetReference()
        c = comps.get(ref)
        if c is None:
            continue
        fp.SetPath(pcbnew.KIID_PATH(c['path']))
        fp.SetSheetname(c['sheet'].strip('/').split('/')[-1] if c['sheet'] != '/' else '')
        fp.SetSheetfile(c['sheetfile'])
        moved += 1
        for k, v in (c.get('fields') or {}).items():
            if k in ('Footprint', 'Datasheet', 'Description') or v is None:
                continue
            fp.SetField(k, v)
            f = fp.GetField(k)
            if f is not None:
                f.SetVisible(False)
        for pad in fp.Pads():
            want = pads.get((ref, pad.GetNumber()))
            got = pad.GetNetname()
            if want and want.startswith('unconnected-') and got != want:
                n = b.FindNet(want)
                if n is None:
                    n = pcbnew.NETINFO_ITEM(b, want)
                    b.Add(n)
                    n = b.FindNet(want)
                pad.SetNet(n)
            elif want and got != want:
                wrong.append(f"{ref}.{pad.GetNumber()}: board {got or '(none)'}, netlist {want}")
    b.Save(str(path))
    return moved, wrong


def main(argv):
    if argv and argv[0] == 'relink':
        rc = 0
        for card in argv[1:] or [CA, CB]:
            n, wrong = relink(card)
            print(f"relinked {n} footprints on {card}; {len(wrong)} pads on a different net")
            for w in wrong[:20]:
                print('   ', w)
            rc |= bool(wrong)
        return rc
    rc = 0
    for card in argv or [CA, CB]:
        out, problems, n, total = build(card)
        print(f"wrote {out}: {n} of {total} footprints placed, {LAYERS[card]} layers")
        for p in problems:
            print('   ', p)
        rc |= bool(problems)
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
