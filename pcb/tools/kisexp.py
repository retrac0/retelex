"""KiCad 10 S-expressions: reader/writer, symbol libraries, pin geometry, and a
reader for .kicad_sch files with a small one-sheet connectivity solver.

Promoted from pcb/out/toolcheck/kisexp.py.  Everything else in pcb/tools/
builds on this module; it has no dependency on pcbnew.

    Q                 a quoted string atom (stays quoted on output)
    parse(text)       -> nested lists
    dump(node)        -> text
    register_lib(nick, path)   make a project .kicad_sym loadable as 'nick:Sym'
    flat_symbol(lib_id)        the symbol as KiCad embeds it in lib_symbols
    sym_pins(lib_id | node)    [{unit, num, name, type, x, y, rot, len, hidden}]
    pin_xy / pin_outward       library pin -> sheet point / outward direction
    sym_bbox(lib_id, unit, rot, mirror)  body+pins extent around the origin
    SchFile(path)              symbols, labels, wires, sheets of one sheet file
"""
import math
import re
import uuid as _uuid
from pathlib import Path

SYMDIR = Path("/usr/share/kicad/symbols")
PCB_ROOT = Path(__file__).resolve().parent.parent          # /home/joel/telco/pcb

# project symbol libraries: nickname -> .kicad_sym path
LIBS = {'telco': PCB_ROOT / 'lib' / 'telco.kicad_sym'}


class Q(str):
    """A quoted string atom."""


def uid():
    return str(_uuid.uuid4())


_TOK = re.compile(r'\(|\)|"(?:\\.|[^"\\])*"|[^\s()]+')


def parse(text):
    stack = [[]]
    for m in _TOK.finditer(text):
        t = m.group(0)
        if t == '(':
            stack.append([])
        elif t == ')':
            x = stack.pop()
            stack[-1].append(x)
        elif t[0] == '"':
            stack[-1].append(Q(re.sub(r'\\(.)', lambda m: '\n' if m.group(1) == 'n' else m.group(1),
                                      t[1:-1])))
        else:
            stack[-1].append(t)
    return stack[0][0]


def _atom(a):
    if isinstance(a, Q):
        return '"' + a.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(a, float):
        s = f"{a:.4f}".rstrip('0').rstrip('.')
        return '0' if s in ('-0', '') else s
    return str(a)


def dump(node, ind=0):
    """Serialize: a list whose items are all atoms goes on one line."""
    if not isinstance(node, list):
        return _atom(node)
    if all(not isinstance(c, list) for c in node):
        return '(' + ' '.join(_atom(c) for c in node) + ')'
    pad = '\t' * (ind + 1)
    head = [c for c in node if not isinstance(c, list)]
    out = '(' + ' '.join(_atom(c) for c in head)
    for c in node:
        if isinstance(c, list):
            out += '\n' + pad + dump(c, ind + 1)
    return out + '\n' + '\t' * ind + ')'


def kids(node, head):
    return [c for c in node if isinstance(c, list) and c and c[0] == head]


def kid(node, head):
    k = kids(node, head)
    return k[0] if k else None


def val(node, head, default=None):
    k = kid(node, head)
    return k[1] if k and len(k) > 1 else default


def props(node):
    """{name: value} of a symbol's / sheet's (property ...) children."""
    return {str(p[1]): str(p[2]) for p in kids(node, 'property')}


# ---------------------------------------------------------------- libraries
_libs = {}


def register_lib(nick, path):
    """Make a project library loadable as 'nick:Sym' (overrides a stock name)."""
    LIBS[nick] = Path(path)
    _libs.pop(nick, None)


def lib_path(libname):
    if libname in LIBS:
        return Path(LIBS[libname])
    return SYMDIR / f"{libname}.kicad_sym"


def lib(libname):
    if libname not in _libs:
        p = lib_path(libname)
        if not p.exists():
            raise KeyError(f"symbol library '{libname}' not found ({p})")
        tree = parse(p.read_text())
        _libs[libname] = {str(c[1]): c for c in kids(tree, 'symbol')}
    return _libs[libname]


def has_symbol(lib_id):
    libname, sym = lib_id.split(':', 1)
    try:
        return sym in lib(libname)
    except KeyError:
        return False


def flat_symbol(lib_id):
    """Return the symbol as KiCad embeds it in lib_symbols: name 'Lib:Sym',
    derived symbols ('extends') flattened onto their base, unit sub-symbols
    renamed to the derived name."""
    libname, sym = lib_id.split(':', 1)
    L = lib(libname)
    if sym not in L:
        raise KeyError(f"no symbol '{sym}' in library '{libname}'")
    s = L[sym]
    ext = kid(s, 'extends')
    if not ext:
        out = [x for x in s]
        out[1] = Q(lib_id)
        return out
    base = flat_symbol(f"{libname}:{ext[1]}")
    bname = str(ext[1])
    pr = {p[1]: p for p in kids(s, 'property')}
    out = [base[0], Q(lib_id)]
    for c in base[2:]:
        if isinstance(c, list) and c[0] == 'property' and c[1] in pr:
            out.append(pr.pop(c[1]))
        elif isinstance(c, list) and c[0] == 'symbol':
            sub = list(c)
            sub[1] = Q(re.sub('^' + re.escape(bname), sym, str(c[1])))
            out.append(sub)
        else:
            out.append(c)
    idx = next(i for i, c in enumerate(out) if isinstance(c, list) and c[0] == 'symbol')
    for p in pr.values():
        out.insert(idx, p)
        idx += 1
    return out


def _symnode(s):
    return flat_symbol(s) if isinstance(s, str) else s


def sym_pins(sym):
    """[{unit, num, name, type, x, y, rot, len, hidden}] in library coordinates
    (Y up).  unit 0 = common to all units.  De Morgan (body style 2) skipped.
    sym is a lib_id or an already-flattened / embedded symbol node."""
    s = _symnode(sym)
    out = []
    for sub in kids(s, 'symbol'):
        m = re.search(r'_(\d+)_(\d+)$', str(sub[1]))
        unit, style = int(m.group(1)), int(m.group(2))
        if style == 2:
            continue
        for p in kids(sub, 'pin'):
            at = kid(p, 'at')
            hidden = 'hide' in p or any(isinstance(c, list) and c[:2] == ['hide', 'yes'] for c in p)
            out.append(dict(unit=unit, num=str(kid(p, 'number')[1]), name=str(kid(p, 'name')[1]),
                            type=str(p[1]), x=float(at[1]), y=float(at[2]),
                            rot=float(at[3]) if len(at) > 3 else 0.0,
                            len=float(val(p, 'length', 0)), hidden=hidden))
    return out


def sym_units(sym):
    return sorted({p['unit'] for p in sym_pins(sym)} - {0}) or [1]


def is_power_symbol(sym):
    return kid(_symnode(sym), 'power') is not None


# ------------------------------------------------------------ pin geometry
def xform(rot, mirror, px, py):
    """Library point (Y up) -> offset on the sheet (Y down), KiCad's order:
    Y flip, rotate CCW on screen in 90 degree steps, then mirror."""
    x, y = px, -py
    for _ in range((int(rot) % 360) // 90):     # CCW on screen with Y down: (x,y)->(y,-x)
        x, y = y, -x
    if mirror == 'x':                           # mirror about the X axis: y -> -y
        y = -y
    elif mirror == 'y':                         # mirror about the Y axis: x -> -x
        x = -x
    return x, y


def pin_xy(sx, sy, rot, mirror, px, py):
    """Library pin point -> schematic sheet point for a symbol at (sx, sy)."""
    x, y = xform(rot, mirror, px, py)
    return round(sx + x, 4), round(sy + y, 4)


def pin_outward(rot, mirror, prot):
    """Unit vector pointing away from the body at a pin (sheet coords)."""
    a = math.radians(prot)
    dx, dy = -round(math.cos(a)), -round(math.sin(a))   # pin points into the body
    x, y = xform(rot, mirror, dx, dy)
    return int(x), int(y)


def sym_bbox(sym, unit=1, rot=0, mirror=None):
    """(x0, y0, x1, y1) sheet-offset extent of a unit's body and pins."""
    s = _symnode(sym)
    pts = []
    for sub in kids(s, 'symbol'):
        m = re.search(r'_(\d+)_(\d+)$', str(sub[1]))
        u, style = int(m.group(1)), int(m.group(2))
        if style == 2 or u not in (0, unit):
            continue
        for g in sub:
            if not isinstance(g, list):
                continue
            if g[0] == 'rectangle':
                for k in ('start', 'end'):
                    a = kid(g, k)
                    pts.append((float(a[1]), float(a[2])))
            elif g[0] in ('polyline', 'bezier'):
                for xy in kids(kid(g, 'pts') or [], 'xy'):
                    pts.append((float(xy[1]), float(xy[2])))
            elif g[0] == 'circle':
                c, r = kid(g, 'center'), float(val(g, 'radius', 0))
                pts += [(float(c[1]) - r, float(c[2]) - r), (float(c[1]) + r, float(c[2]) + r)]
            elif g[0] == 'arc':
                for k in ('start', 'mid', 'end'):
                    a = kid(g, k)
                    if a:
                        pts.append((float(a[1]), float(a[2])))
            elif g[0] == 'pin':
                at = kid(g, 'at')
                x, y, r = float(at[1]), float(at[2]), float(at[3]) if len(at) > 3 else 0
                ln = float(val(g, 'length', 0))
                pts += [(x, y), (x + ln * math.cos(math.radians(r)), y + ln * math.sin(math.radians(r)))]
    if not pts:
        return (-1.27, -1.27, 1.27, 1.27)
    tp = [xform(rot, mirror, x, y) for x, y in pts]
    xs, ys = [p[0] for p in tp], [p[1] for p in tp]
    return min(xs), min(ys), max(xs), max(ys)


# ------------------------------------------------------ schematic file reader
class SchFile:
    """One .kicad_sch file: embedded lib_symbols, placed symbols, labels,
    wires, junctions, no-connects and sheet symbols, plus a union-find over
    connection points so a label can be traced to the symbol pins it touches.

    Connectivity rules implemented (enough for scripted and hand-drawn cells):
    wire endpoints join; a point lying on a wire joins it; labels join the
    point they sit on; local and hierarchical labels of the same text join.
    Global labels and power symbols are not followed (they leave the sheet).
    """

    def __init__(self, path):
        self.path = Path(path)
        self.tree = parse(self.path.read_text())
        self.uuid = str(val(self.tree, 'uuid', ''))
        ls = kid(self.tree, 'lib_symbols') or []
        self.lib_symbols = {str(s[1]): s for s in kids(ls, 'symbol')}
        self.symbols = []
        for s in kids(self.tree, 'symbol'):
            at = kid(s, 'at')
            insts = []
            for pr in kids(kid(s, 'instances') or [], 'project'):
                for pa in kids(pr, 'path'):
                    insts.append((str(pa[1]), str(val(pa, 'reference', '')), int(val(pa, 'unit', 1))))
            self.symbols.append(dict(
                lib_id=str(val(s, 'lib_id')), uuid=str(val(s, 'uuid')),
                x=float(at[1]), y=float(at[2]), rot=float(at[3]) if len(at) > 3 else 0.0,
                mirror=val(s, 'mirror'), unit=int(val(s, 'unit', 1)), props=props(s),
                instances=insts, node=s))
        self.labels = []           # (kind, text, x, y)
        for kind, head in (('local', 'label'), ('global', 'global_label'), ('hier', 'hierarchical_label')):
            for lb in kids(self.tree, head):
                at = kid(lb, 'at')
                self.labels.append((kind, str(lb[1]), float(at[1]), float(at[2])))
        self.wires = []
        for w in kids(self.tree, 'wire'):
            self.wires.append([(float(p[1]), float(p[2])) for p in kids(kid(w, 'pts'), 'xy')])
        self.junctions = [(float(kid(j, 'at')[1]), float(kid(j, 'at')[2])) for j in kids(self.tree, 'junction')]
        self.no_connects = [(float(kid(j, 'at')[1]), float(kid(j, 'at')[2])) for j in kids(self.tree, 'no_connect')]
        self.sheets = []
        for sh in kids(self.tree, 'sheet'):
            pins = []
            for p in kids(sh, 'pin'):
                at = kid(p, 'at')
                pins.append(dict(name=str(p[1]), shape=str(p[2]), x=float(at[1]), y=float(at[2])))
            insts = []
            for pr in kids(kid(sh, 'instances') or [], 'project'):
                for pa in kids(pr, 'path'):
                    insts.append((str(pa[1]), str(val(pa, 'page', ''))))
            pr_ = props(sh)
            self.sheets.append(dict(uuid=str(val(sh, 'uuid')), name=pr_.get('Sheetname', ''),
                                    file=pr_.get('Sheetfile', ''), props=pr_, pins=pins,
                                    instances=insts))

    def symbol_pins(self, s):
        """[(pin dict, sheet x, sheet y)] for one placed symbol, from the
        file's own embedded lib_symbols (what KiCad itself uses)."""
        node = self.lib_symbols.get(s['lib_id'])
        if node is None:
            return []
        out = []
        for p in sym_pins(node):
            if p['unit'] in (0, s['unit']):
                out.append((p,) + pin_xy(s['x'], s['y'], s['rot'], s['mirror'], p['x'], p['y']))
        return out

    def connectivity(self):
        """Union-find over points.  Returns (find, pin_points) where
        pin_points = [(symbol uuid, pin number, (x, y))]."""
        parent = {}

        def key(x, y):
            return (round(x, 3), round(y, 3))

        def find(k):
            parent.setdefault(k, k)
            while parent[k] != k:
                parent[k] = parent[parent[k]]
                k = parent[k]
            return k

        def union(a, b):
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb

        pin_points = []
        for s in self.symbols:
            if s['lib_id'].startswith('power:'):
                continue
            for p, x, y in self.symbol_pins(s):
                pin_points.append((s['uuid'], p['num'], key(x, y)))
                find(key(x, y))
        pts = set(parent) | {key(x, y) for _, _, x, y in self.labels}
        for w in self.wires:
            for a, b in zip(w, w[1:]):
                union(key(*a), key(*b))
                pts |= {key(*a), key(*b)}
        # T-connections: any point that lies inside a wire segment joins it
        for w in self.wires:
            for (x1, y1), (x2, y2) in zip(w, w[1:]):
                for (px, py) in list(pts):
                    if min(x1, x2) - 1e-3 <= px <= max(x1, x2) + 1e-3 and \
                       min(y1, y2) - 1e-3 <= py <= max(y1, y2) + 1e-3 and \
                       abs((x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)) < 1e-3:
                        union((px, py), key(x1, y1))
        byname = {}
        for kind, text, x, y in self.labels:
            find(key(x, y))
            if kind in ('local', 'hier'):
                if text in byname:
                    union(key(x, y), byname[text])
                byname[text] = key(x, y)
        return find, pin_points

    def label_pins(self, text, kinds=('hier',)):
        """Symbol pins [(symbol uuid, pin number)] connected to the label(s)
        named text of the given kinds on this sheet."""
        find, pin_points = self.connectivity()
        roots = {find((round(x, 3), round(y, 3))) for k, t, x, y in self.labels if t == text and k in kinds}
        return [(u, n) for u, n, k in pin_points if find(k) in roots]
