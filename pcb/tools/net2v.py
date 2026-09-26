#!/usr/bin/env python3
"""KiCad netlist -> structural Verilog over a part-model library.

    net2v.py top.xml --top port_card --portmap ports.json --models ../models -o port_card.v
    net2v.py top.xml --top toy --ports J1 --models ../models -o toy.v

INPUT: a kicadxml netlist (netlist.py export) and the .kicad_sch files it came
from (read for sheet fields, hierarchical labels and exclude_from_sim).

MODELS (--models DIR, repeatable; default pcb/models): DIR/pinmap.json maps a
part to its model, and DIR/*.v hold the modules (their headers are read to
check ports and to learn macro cells' ports).  pinmap.json:

    { "74HC151": { "module": "hc151",                       # optional; default 74HC151 -> hc151
                   "pins": { "4": {"port": "p4", "dir": "in"},
                             "5": {"port": "p5", "dir": "out"},                  # totem pole
                             "8": {"dir": "pwr", "type": "gnd"},
                             "16": {"dir": "pwr", "type": "vcc"} } },
      "74HC125": { "pins": { "3": {"port": "p3", "dir": "out", "type": "tri"} ...} },  # + p3_oe
      "2N7002":  { "module": "nfet", "pins": { "1": {"port": "G", "dir": "in"},
                   "2": {"dir": "pwr", "type": "gnd"},                           # source on GND
                   "3": {"port": "D", "dir": "out", "type": "od"} } },           # port D_pd
      "74HCT151": "74HC151" }                                                   # an alias
  The flat form {"74HC151": {"4": {...}, ...}} (no "pins" level) is read too.
  dir: in | out | pwr | nc.   out type: totem (default) | tri (value port + <port>_oe,
  or "oe": name) | od (<port>_pd, or "pd": name).  pwr type: vcc (+5V) | gnd, or "net": name.
  A symbol field Sim.Model overrides the Value as the pinmap key.

WHAT EACH COMPONENT BECOMES
  * a part in the pinmap: one instance per PACKAGE (all units), named by its ref;
  * Device:R: to a rail = a pull; <= --series-max ohms (100) = a series link
    (the two nets are one); otherwise a WEAK DRIVER of the net that has no
    always-on driver by the value of the one that has.  Field Sim.R overrides:
    series | drop | from:1 | from:2;
  * Device:R_Network0N (pin 1 common) and R_Pack0N expand to resistors;
  * Device:C across the rails is dropped; elsewhere dropped with a warning;
  * a symbol with a Sim.Jumper field is a set of SWITCHES closed by a module
    parameter (below); any other connector is ignored unless --ports names it;
  * DNP and exclude_from_sim components are left out, and so is everything on
    a sheet whose symbol carries Sim.Macro (replaced by the cell) or
    exclude_from_sim.

JUMPERS: Sim.Jumper = "<kind>:<PARAM>[=<default>][@<col>[-<col>]] ..."
  one:LANE   column k is shunted when LANE == k (default -1: none)
  bits:FIT   column k shunted when FIT[k] is 1;  nbits:BLK  when BLK[k] is 0
  Columns are pin pairs: Conn_02xNN_Odd_Even (1,2)(3,4)..; _Top_Bottom (1,N+1)..;
  _Counter_Clockwise (1,2N)..; Jumper_2 (1,2); Jumper_3 (1,2)(2,3); or give
  Sim.Pairs = "1-2,3-4,...".  Jumpers naming one PARAM are ganged.  On a sheet
  file placed more than once, PARAM is prefixed with the sheet path (PORT0__LANE).

MACRO CELLS: Sim.Macro = "<cell> [PARAM=value ...] [cellport:PIN ...] [cellport:@simnet ...]"
  on a SHEET symbol: every component on that sheet is replaced by <cell>; cell
  ports bind to the sheet pins of the same name (or cellport:SHEETPIN); each
  sheet pin must touch a component pin inside the sheet (that is how its net
  is found).  On a COMPONENT: the component is replaced; cellport:PINNUMBER.
  cellport:@name binds a port to a simulation-only module input `name`.

MODULE PORTS: --ports J1,J2 (every net on those connectors, named after the
net) or --portmap ports.json:
    { "/C_TX": {"port": "c_tx"},  "/HC0": {"port": "hc", "index": 0},
      "/BUSY": {"port": "busy", "dir": "probe"},
      "/LANE0": {"port": "lane", "index": 0, "bundle": ["tri", "weak"]} }
  dir: in | out (checked) | probe (output of the on-card value).  A port net is
  classified from its on-card drivers:
    none                      -> input  NAME
    one always-on totem pole  -> output NAME
    anything else (a BUNDLE)  -> input NAME (the value resolved outside) plus
        output NAME_oe, NAME_o   tri-state / switched totem drivers (oe=1: drives o)
        output NAME_pd           open drains (1 = pulling low)
        output NAME_we, NAME_wo  weak drivers: pulls, resistors from another net
    The outside resolves:  NAME = |pd ? 0 : oe ? o : we ? wo : <its own pull>.

MULTI-DRIVER NETS are resolved here, never with z, wand or tri1:
    value = |pd ? 0 : oe1 ? v1 : oe2 ? v2 : ... : weak ? wv : 1'b0
  and NET__clash is 1 while two strong drivers are enabled (or a drain pulls
  against a driven 1); `wire __clash` ORs them all (--clash-port makes it an
  output).  Benches must SAMPLE __clash, never trigger on its edges.

A JSON sidecar (<out>.json) lists ports, parameters and simulation inputs.
"""
import argparse
import json
import re
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kisexp  # noqa: E402
import netlist as netlist_mod  # noqa: E402

DEFAULT_MODELS = Path(__file__).resolve().parent.parent / 'models'
RAILS = {'+5V': 1, 'VCC': 1, 'GND': 0}
CONNECTOR_LIBS = ('Connector', 'Connector_Generic', 'Connector_Generic_MountingPin',
                  'Connector_Generic_Shielded', 'Mechanical', 'Jumper', 'TestPoint')
VKEYWORDS = set('''always and assign automatic begin buf bufif0 bufif1 case casex casez cell cmos config deassign
default defparam design disable edge else end endcase endconfig endfunction endgenerate endmodule endprimitive
endspecify endtable endtask event for force forever fork function generate genvar highz0 highz1 if ifnone incdir
include initial inout input instance integer join large liblist library localparam macromodule medium module nand
negedge nmos nor noshowcancelled not notif0 notif1 or output parameter pmos posedge primitive pull0 pull1 pulldown
pullup pulsestyle_onevent pulsestyle_ondetect rcmos real realtime reg release repeat rnmos rpmos rtran rtranif0
rtranif1 scalared showcancelled signed small specify specparam strong0 strong1 supply0 supply1 table task time tran
tranif0 tranif1 tri tri0 tri1 triand trior trireg unsigned use uwire vectored wait wand weak0 weak1 while wire wor
xnor xor logic bit byte int longint shortint string type var'''.split())


ZERO, ONE = "1'b0", "1'b1"


class GenError(Exception):
    pass


def vname(net):
    s = net
    m = re.fullmatch(r'Net-\((.*)\)', s)
    if m:
        s = 'net_' + m.group(1)
    s = s.lstrip('/')
    s = re.sub(r'~\{([^}]*)\}', r'\1_n', s)
    s = s.replace('/', '__').replace('+', 'p').replace('-', '_')
    s = re.sub(r'[^A-Za-z0-9_]', '_', s)
    if not s or s[0].isdigit():
        s = 'n_' + s
    return s + '_' if s in VKEYWORDS else s


def ohms(v):
    s = (v or '').strip().upper().replace('Ω', '').replace('OHM', '').replace(' ', '')
    mult = {'R': 1, '': 1, 'K': 1e3, 'M': 1e6}
    m = re.fullmatch(r'(\d+)([RKM])(\d+)', s)
    if m:
        return float(f"{m.group(1)}.{m.group(3)}") * mult[m.group(2)]
    m = re.fullmatch(r'(\d+(?:\.\d+)?)([RKM]?)', s)
    if m:
        return float(m.group(1)) * mult[m.group(2)]
    return None


# ------------------------------------------------------------------ models
def parse_verilog_headers(text):
    """{module: {'ports': {name: 'input'|'output'|'inout'}, 'params': [names]}}"""
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    mods = {}
    for m in re.finditer(r'\bmodule\s+(\w+)', text):
        name, i = m.group(1), m.end()

        def balanced(i):
            depth, j = 0, i
            while j < len(text):
                if text[j] == '(':
                    depth += 1
                elif text[j] == ')':
                    depth -= 1
                    if depth == 0:
                        return text[i + 1:j], j + 1
                j += 1
            return '', j
        rest = text[i:].lstrip()
        i = len(text) - len(rest)
        params = []
        if rest.startswith('#'):
            k = text.index('(', i)
            pbody, i = balanced(k)
            params = re.findall(r'\bparameter\b[^=,;]*?(\w+)\s*=', pbody)
            params += re.findall(r',\s*(\w+)\s*=', pbody)
        k = text.find('(', i)
        semi = text.find(';', i)
        ports = {}
        body_end = text.find('endmodule', i)
        if k != -1 and (semi == -1 or k < semi):
            plist, i = balanced(k)
            cur = None
            for item in plist.split(','):
                d = re.match(r'\s*(input|output|inout)\b', item)
                if d:
                    cur = d.group(1)
                ids = re.findall(r'(\w+)\s*$', item.strip())
                if ids and cur:
                    ports[ids[0]] = cur
            if not any(True for _ in ports):
                body = text[i:body_end]
                for d, rest_ in re.findall(r'\b(input|output|inout)\b([^;]*);', body):
                    for n in re.findall(r'(\w+)\s*(?:,|$)', re.sub(r'\[[^]]*\]', '', rest_)):
                        if n not in ('wire', 'reg', 'logic', 'signed'):
                            ports[n] = d
        body = text[i:body_end]
        params += re.findall(r'\bparameter\b[^=;]*?(\w+)\s*=', body)
        mods[name] = dict(ports=ports, params=params)
    return mods


def default_module(key):
    k = key.lower()
    m = re.fullmatch(r'74([a-z]+)(\d+[a-z]*)', k)
    if m:
        return m.group(1) + m.group(2)
    s = re.sub(r'[^a-z0-9_]', '_', k)
    return ('m_' + s) if s[:1].isdigit() else s


_DIRS = {'in': 'in', 'input': 'in', 'out': 'out', 'output': 'out', 'pwr': 'pwr', 'power': 'pwr',
         'nc': 'nc', 'inout': 'inout', 'bidir': 'inout'}
_OUTT = {'': 'totem', 'totem': 'totem', 'pp': 'totem', 'push-pull': 'totem', 'out': 'totem', 'output': 'totem',
         'tri': 'tri', 'tristate': 'tri', 'tri_state': 'tri', '3state': 'tri',
         'od': 'od', 'oc': 'od', 'open_drain': 'od', 'open_collector': 'od'}


class Models:
    def __init__(self, dirs):
        self.pinmap, self.alias, self.vmods, self.files, self.macros = {}, {}, {}, [], {}
        for d in dirs:
            d = Path(d)
            if d.is_file():
                self._file(d)
                continue
            for f in sorted(d.glob('*.v')) + sorted(d.glob('*.sv')):
                self._file(f)
            pm = d / 'pinmap.json'
            if pm.exists():
                self._pinmap(pm)

    def _file(self, f):
        f = Path(f)
        if f.suffix == '.json':
            self._pinmap(f)
            return
        self.files.append(f)
        self.vmods.update(parse_verilog_headers(f.read_text()))

    def _pinmap(self, path):
        raw = json.loads(Path(path).read_text())
        self.alias.update(raw.get('_values', {}))              # schematic Value -> part
        for cell, m in raw.get('_macros', {}).items():
            self.macros[cell] = m
        for key, e in raw.items():
            if key.startswith('_'):
                continue
            if isinstance(e, str):
                self.alias[key] = e
                continue
            if 'alias' in e:
                self.alias[key] = e['alias']
                continue
            pins = e.get('pins')
            if pins is None:
                pins = {k: v for k, v in e.items() if not k.startswith('_') and isinstance(v, dict)}
            module = e.get('module') or e.get('_module') or default_module(key)
            norm = {}
            for num, p in pins.items():
                if isinstance(p, str):
                    p = {'port': p, 'dir': 'in'}
                t = str(p.get('type', '') or '').lower()
                d = 'nc' if t == 'nc' else _DIRS.get(str(p.get('dir', 'in')).lower())
                if d is None:
                    raise GenError(f"pinmap {key} pin {num}: dir '{p.get('dir')}'")
                q = dict(port=p.get('port'), dir=d, type=t, net=p.get('rail') or p.get('net'),
                         oe=p.get('oe'), pd=p.get('pd'))
                if d == 'out':
                    t = _OUTT.get(q['type'])
                    if t is None:
                        raise GenError(f"pinmap {key} pin {num}: output type '{q['type']}'")
                    q['type'] = t
                    if t == 'tri':
                        q['oe'] = q['oe'] or f"{q['port']}_oe"
                    if t == 'od':                   # the port itself is 1 while pulling low
                        q['pd'] = q['pd'] or q['port']
                if d == 'pwr' and not q['net']:
                    q['net'] = {'gnd': 'GND', 'vss': 'GND', 'ground': 'GND'}.get(q['type'], '+5V')
                norm[str(num)] = q
            self.pinmap[key] = dict(module=module, pins=norm, params=e.get('params', {}))

    def entry(self, key):
        seen = set()
        while key in self.alias and key not in seen:
            seen.add(key)
            key = self.alias[key]
        return self.pinmap.get(key)

    def cell_ports(self, cell):
        """Macro cell ports: {signal: (kind, {role: verilog port}, sim)}, kind in
        in|out|tri|od.  From the Verilog header (X + X_oe = tri, X_pd = od) and
        pinmap.json's _macros (type, and sim = a simulation-only input)."""
        if cell not in self.vmods:
            raise GenError(f"macro cell '{cell}' not found in the model files")
        ports = self.vmods[cell]['ports']
        meta = self.macros.get(cell, {}).get('ports', {})
        out = {}
        for n, d in ports.items():
            if d == 'input':
                out[n] = ('in', {'v': n}, bool(meta.get(n, {}).get('sim')))
        for n, d in ports.items():
            if d != 'output':
                continue
            t = str(meta.get(n, {}).get('type', '')).lower()
            if n.endswith('_oe') and ports.get(n[:-3]) == 'output':
                continue
            if t == 'od':
                out[n] = ('od', {'pd': n}, False)
            elif n.endswith('_pd'):
                out[n[:-3]] = ('od', {'pd': n}, False)
            elif ports.get(n + '_oe') == 'output':
                out[n] = ('tri', {'v': n, 'oe': n + '_oe'}, False)
            else:
                out[n] = ('out', {'v': n}, False)
        return out


# ------------------------------------------------------------- the design
class Drv:
    """One driver on a net.  kind: totem (v) | tri (oe, v) | od (pd) |
    weak (v = constant or ('net', name)) | ext (port input, conditional)."""

    def __init__(self, kind, v=None, oe=None, pd=None, desc='', cond=(), home=None, did=None):
        self.kind, self.v, self.oe, self.pd, self.desc = kind, v, oe, pd, desc
        self.cond, self.home, self.did = tuple(cond), home, did

    def gated(self, cond):
        return Drv(self.kind, self.v, self.oe, self.pd, self.desc, self.cond + tuple(cond), self.home, self.did)


def _and(*terms):
    t = [x for x in terms if x not in ('1', "1'b1", '')]
    if not t:
        return "1'b1"
    return ' && '.join(f"({x})" if ('?' in x or '||' in x) else x for x in t)


class Gen:
    def __init__(self, nl, top, models, port_refs=(), portmap=None, series_max=100.0, rails=None,
                 clash_port=False, strict=False, extra_params=None):
        self.nl, self.top, self.models = nl, top, models
        self.extra_params = OrderedDict(extra_params or {})   # --param NAME=DEFAULT
        self.port_refs, self.portmap = set(port_refs), portmap
        self.series_max, self.clash_port, self.strict = series_max, clash_port, strict
        self.rails = dict(RAILS, **(rails or {}))
        self.err, self.warn = [], []
        self.own = defaultdict(list)          # net -> [Drv] physically on that net
        self.switch = defaultdict(list)       # net -> [(other net, cond str, desc)]
        self.weak_r = []                      # (ref, net a, net b, value, how)
        self.insts = []                       # (sheet, ref, module, params, [(port, expr-key, kind)], comment)
        self.params = OrderedDict()           # name -> (kind, width, default, [refs])
        self.sim_inputs = OrderedDict()       # name -> comment
        self.loads = defaultdict(list)        # net -> [(ref, port)]
        self.dseq = 0

    # ---------------------------------------------------------- helpers
    def net(self, ref, pin):
        n = self.nl.net_of.get((ref, pin))
        if n is None or n.startswith('unconnected-'):
            return None
        return n

    def new_drv(self, net, kind, **kw):
        self.dseq += 1
        d = Drv(kind, home=net, did=self.dseq, **kw)
        self.own[net].append(d)
        return d

    def param(self, name, kind, width, default, ref):
        if name in self.params:
            k, w, dflt, refs = self.params[name]
            if k != kind:
                self.err.append(f"parameter {name}: {ref} uses it as '{kind}', {refs[0]} as '{k}'")
            self.params[name] = (k, max(w, width), dflt, refs + [ref])
        else:
            self.params[name] = (kind, width, default, [ref])

    # ----------------------------------------------------------- build
    def build(self):
        nl = self.nl
        nl.schematic()
        # sheets replaced by a macro cell (outermost wins) or excluded
        macro_sheets = []
        for ts, sh in sorted(nl.sheets.items(), key=lambda t: len(t[0])):
            if ts == '/' or 'Sim.Macro' not in sh.props:
                continue
            if any(ts.startswith(m) for m, _ in macro_sheets):
                continue
            macro_sheets.append((ts, sh))
        self.macro_sheets = macro_sheets
        file_uses = defaultdict(int)
        for sh in nl.sheets.values():
            file_uses[sh.file] += 1
        self.file_uses = file_uses

        for c in sorted(nl.comp_list, key=lambda c: (c.sheet, _refkey(c.ref))):
            if c.dnp or c.xsim:
                continue
            if any(c.sheet_ts.startswith(ts) for ts, _ in macro_sheets):
                continue
            if c.ref in self.port_refs:
                continue
            if not c.units or not any(c.units):
                continue                                   # mounting holes, logos
            if 'Sim.Jumper' in c.fields and c.fields['Sim.Jumper'].strip():
                self.jumper(c)
            elif 'Sim.Macro' in c.fields and c.fields['Sim.Macro'].strip():
                self.macro(c.fields['Sim.Macro'], c.sheet, c.ref, comp=c)
            elif c.lib == 'Device' and re.fullmatch(r'R(_Small|_US|_Small_US)?', c.part):
                self.resistor(c, c.ref, '1', '2')
            elif c.lib == 'Device' and re.fullmatch(r'R_(Network|Pack)(\d\d)(_.*)?', c.part):
                m = re.fullmatch(r'R_(Network|Pack)(\d\d)(_.*)?', c.part)
                k = int(m.group(2))
                if m.group(1) == 'Network':
                    pairs = [('1', str(i + 2)) for i in range(k)]            # pin 1 common
                elif m.group(3) == '_SIP':
                    pairs = [(str(2 * i + 1), str(2 * i + 2)) for i in range(k)]   # side by side
                else:
                    pairs = [(str(i + 1), str(2 * k - i)) for i in range(k)]      # DIP: across
                for a, b in pairs:
                    self.resistor(c, f"{c.ref}.{b}", a, b)
            elif c.lib == 'Device' and re.fullmatch(r'C(_Small|_Polarized|_Polarized_Small)?|CP(_Small)?', c.part):
                a, b = self.net(c.ref, '1'), self.net(c.ref, '2')
                if not (a in self.rails and b in self.rails):
                    msg = f"{c.ref}: capacitor {a}-{b} off the rails dropped (put RC timing in a Sim.Macro)"
                    (self.err if self.strict else self.warn).append(msg)
            elif c.lib in CONNECTOR_LIBS or c.lib.startswith('Connector'):
                if self.portmap is None:
                    self.warn.append(f"{c.ref}: connector {c.lib}:{c.part} ignored (not in --ports)")
            elif c.lib == 'Device' and re.match(r'(D|LED)', c.part):
                self.err.append(f"{c.ref}: {c.lib}:{c.part} has no model: put it in a Sim.Macro sheet "
                                f"or mark it exclude_from_sim")
            else:
                self.part(c)
        for ts, sh in macro_sheets:
            self.macro(sh.props['Sim.Macro'], sh.name, sh.name.strip('/').replace('/', '_') or 'MACRO',
                       sheet=(ts, sh))
        self.ports()
        self.weak()
        return self

    def part(self, c):
        key = c.fields.get('Sim.Model') or c.value
        e = self.models.entry(key)
        if e is None:
            self.err.append(f"{c.ref}: no model for '{key}' ({c.lib}:{c.part}) in pinmap.json")
            return
        mod = e['module']
        vm = self.models.vmods.get(mod)
        if self.models.vmods and vm is None:
            self.err.append(f"{c.ref}: module '{mod}' for '{key}' not found in the model files")
        pins = self.nl.libparts.get((c.lib, c.part), {})
        conns = []
        for num, (pname, ptype) in sorted(pins.items(), key=lambda t: _refkey(t[0])):
            q = e['pins'].get(num)
            if q is None:
                self.err.append(f"{c.ref}: pinmap '{key}' has no pin {num} ({pname})")
                continue
            net = self.nl.net_of.get((c.ref, num))
            nc = net is None or net.startswith('unconnected-')
            if q['dir'] == 'pwr':
                if net != q['net']:
                    self.err.append(f"{c.ref} pin {num} {pname}: on {net}, the model wants {q['net']}")
                continue
            if q['dir'] == 'nc':
                continue
            if q['dir'] == 'inout':
                self.err.append(f"{c.ref} pin {num}: 'inout' pins are not modelled; use a directional model")
                continue
            if vm is not None:
                need = [q['port']] if q['dir'] == 'in' or q['type'] == 'totem' else \
                    ([q['port'], q['oe']] if q['type'] == 'tri' else [q['pd']])
                for pn in need:
                    if pn not in vm['ports']:
                        self.err.append(f"{c.ref}: module {mod} has no port '{pn}' (pin {num})")
            if q['dir'] == 'in':
                if nc:
                    self.err.append(f"{c.ref} pin {num} ({pname}): input not connected")
                    continue
                conns.append((q['port'], 'in', net))
                self.loads[net].append((c.ref, num))
                continue
            if nc:
                conns.append((q['port'], 'nc-' + q['type'], (q.get('oe'), q.get('pd'))))
                continue
            desc = f"{c.ref}.{num} {q['type']}"
            if q['type'] == 'totem':
                d = self.new_drv(net, 'totem', v=f"{c.ref}_{q['port']}", desc=desc)
                conns.append((q['port'], 'totem', d))
            elif q['type'] == 'tri':
                w = f"{c.ref}_{q['port']}"
                d = self.new_drv(net, 'tri', v=w, oe=f"{w}_oe", desc=desc)
                conns.append((q['port'], 'tri', (d, q['oe'])))
            else:
                w = f"{c.ref}_{q['pd']}"
                d = self.new_drv(net, 'od', pd=w, desc=desc)
                conns.append((q['pd'], 'od', d))
        extra = set(e['pins']) - set(pins)
        if extra and pins:
            self.warn.append(f"{c.ref}: pinmap '{key}' pins {sorted(extra, key=_refkey)} not on the symbol")
        params = e.get('params') or {}
        self.insts.append((c.sheet, c.ref, mod, params, conns, f"{c.value} {c.lib}:{c.part}"))

    def resistor(self, c, name, pa, pb):
        a, b = self.net(c.ref, pa), self.net(c.ref, pb)
        how = c.fields.get('Sim.R', '').strip().lower()
        if how == 'drop' or a is None or b is None or a == b:
            return
        if a in self.rails and b in self.rails:
            return
        r = ohms(c.value)
        if how == 'series' or (not how and r is not None and r <= self.series_max and
                               a not in self.rails and b not in self.rails):
            self.switch[a].append((b, "1'b1", f"{name} {c.value}"))
            self.switch[b].append((a, "1'b1", f"{name} {c.value}"))
            return
        if r is None and not how:
            self.warn.append(f"{name}: value '{c.value}' not understood; taken as a weak resistor")
        self.weak_r.append((name, a, b, c.value, how))

    def jumper(self, c):
        spec = c.fields['Sim.Jumper']
        pairs = c.fields.get('Sim.Pairs', '').strip()
        if pairs:
            cols = [tuple(p.strip().split('-')) for p in pairs.split(',')]
        else:
            cols = _jumper_pairs(c.part)
            if cols is None:
                self.err.append(f"{c.ref}: cannot tell the columns of {c.lib}:{c.part}: give Sim.Pairs")
                return
        prefix = ''
        if c.sheet != '/' and self.file_uses[self.nl.sheets[c.sheet_ts].file] > 1:
            prefix = vname(c.sheet.strip('/')) + '__'
        for tok in spec.split():
            m = re.fullmatch(r'(one|bits|nbits):(\w+)(?:=(-?\w+))?(?:@(\d+)(?:-(\d+))?)?', tok)
            if not m:
                self.err.append(f"{c.ref}: Sim.Jumper token '{tok}' (want one|bits|nbits:PARAM[=d][@a-b])")
                continue
            kind, pname, dflt, a, b = m.groups()
            idx = list(range(len(cols)))
            if a is not None:
                idx = list(range(int(a), int(b if b is not None else a) + 1))
            if any(i >= len(cols) for i in idx):
                self.err.append(f"{c.ref}: Sim.Jumper '{tok}' names a column past {len(cols) - 1}")
                continue
            pname = prefix + pname
            if kind == 'one':
                self.param(pname, 'one', 32, dflt if dflt is not None else '-1', c.ref)
            else:
                self.param(pname, 'bits', len(idx), dflt if dflt is not None else '0', c.ref)
            for k, ci in enumerate(idx):
                pa, pb = cols[ci]
                na, nb = self.net(c.ref, pa), self.net(c.ref, pb)
                if na is None or nb is None or na == nb:
                    continue
                cond = {'one': f"{pname} == {k}", 'bits': f"{pname}[{k}]", 'nbits': f"!{pname}[{k}]"}[kind]
                desc = f"{c.ref} {pa}-{pb}"
                # A shunt to a RAIL (a strap: POS, the block number) drives the
                # other side to the rail's value while it is fitted.  reach()
                # never walks into a rail, so it cannot be a switch: before this
                # every strap to GND was silently open and read its pull-up.
                ra, rb = na in self.rails, nb in self.rails
                if ra and rb:
                    continue
                if ra or rb:
                    sig, rail = (nb, na) if ra else (na, nb)
                    self.new_drv(sig, 'totem', v=(ONE if self.rails[rail] else ZERO), cond=(cond,),
                                 desc=f"{desc} to {rail}")
                    continue
                self.switch[na].append((nb, cond, desc))
                self.switch[nb].append((na, cond, desc))

    def macro(self, spec, sheet_name, inst, comp=None, sheet=None):
        toks = spec.split()
        cell, params, binds = toks[0], OrderedDict(), {}
        for t in toks[1:]:
            if '=' in t and (':' not in t or t.index('=') < t.index(':')):
                k, v = t.split('=', 1)
                params[k] = v
            elif ':' in t:
                k, v = t.split(':', 1)
                binds[k] = v
            else:
                self.err.append(f"{inst}: Sim.Macro token '{t}'")
        try:
            cports = self.models.cell_ports(cell)
        except GenError as e:
            self.err.append(f"{inst}: {e}")
            return
        # where each sheet pin / component pin lands
        where = {}
        if sheet is not None:
            ts, sh = sheet
            for p in sh.pins:
                hits = sh.sch.label_pins(p['name'])
                nets = set()
                for u, num in hits:
                    ref = self.nl.symbol_of(ts, u)
                    if ref is not None:
                        n = self.nl.net_of.get((ref, num))
                        if n:
                            nets.add(n)
                if len(nets) != 1:
                    self.err.append(f"macro sheet {sh.name}: pin {p['name']} reaches "
                                    f"{sorted(nets) or 'no component pin'} inside {sh.file}")
                    continue
                where[p['name']] = nets.pop()
        else:
            for u in comp.units:
                for num in u:
                    n = self.nl.net_of.get((comp.ref, num))
                    where[num] = n
            lp = self.nl.libparts.get((comp.lib, comp.part), {})
            for num, (pname, _) in lp.items():
                if pname and pname not in where:
                    where[pname] = where.get(num)
        conns, used = [], set()
        for cp, (kind, roles, sim) in cports.items():
            src = binds.get(cp)
            if src is None:
                src = cp if cp in where else next((k for k in where if k.lower() == cp.lower()), None)
            if src is None and sim:
                src = '@' + cp                  # a simulation-only port binds to a module input of its name
            if src is not None and src.startswith('@'):
                nm = src[1:]
                self.sim_inputs.setdefault(nm, f"simulation only: {cell} {inst}")
                if kind != 'in':
                    self.err.append(f"{inst}: {cell}.{cp} is an output; '@{nm}' binds inputs only")
                conns.append((cp, 'sim', nm))
                continue
            if src is None or src not in where:
                if kind == 'in':
                    self.err.append(f"{inst}: {cell} input '{cp}' is not bound (sheet pin, pin or @simnet)")
                else:
                    conns.append((cp, 'nc-' + ('totem' if kind == 'out' else kind), (roles.get('oe'), roles.get('pd'))))
                continue
            used.add(src)
            net = where[src]
            if net is None or net.startswith('unconnected-'):
                if kind == 'in':
                    self.err.append(f"{inst}: {cell} input '{cp}' is on an unconnected pin")
                continue
            if kind == 'in':
                conns.append((cp, 'in', net))
                self.loads[net].append((inst, cp))
            elif kind == 'out':
                d = self.new_drv(net, 'totem', v=f"{inst}_{cp}", desc=f"{inst}.{cp} ({cell})")
                conns.append((cp, 'totem', d))
            elif kind == 'tri':
                w = f"{inst}_{cp}"
                d = self.new_drv(net, 'tri', v=w, oe=f"{w}_oe", desc=f"{inst}.{cp} ({cell})")
                conns.append((cp, 'tri', (d, roles['oe'])))
            else:
                w = f"{inst}_{roles['pd']}"
                d = self.new_drv(net, 'od', pd=w, desc=f"{inst}.{cp} ({cell})")
                conns.append((roles['pd'], 'od', d))
        if sheet is not None:
            spare = [p['name'] for p in sheet[1].pins if p['name'] not in used and p['name'] in where]
            if spare:
                self.err.append(f"macro sheet {sheet[1].name}: pins {spare} bind to no port of {cell}")
        vp = self.models.vmods.get(cell, {}).get('params', [])
        for k in params:
            if vp and k not in vp:
                self.err.append(f"{inst}: {cell} has no parameter {k}")
        self.insts.append((sheet_name, inst, cell, params, conns, f"macro cell {cell}"))

    # ------------------------------------------------------------- ports
    def ports(self):
        """self.pnet: net -> (port name, index or None, dir, forced bundle kinds)."""
        self.pnet = OrderedDict()
        if self.portmap is not None:
            for net, e in self.portmap.items():
                if net.startswith('_'):
                    continue
                if isinstance(e, str):
                    e = {'port': e}
                cand = [net, '/' + net.lstrip('/'), net.lstrip('/')]
                real = next((n for n in cand if n in self.nl.nets), None)
                if real is None:
                    self.err.append(f"portmap: net '{net}' is not in the netlist")
                    continue
                self.pnet[real] = (e['port'], e.get('index'), e.get('dir', 'auto'), e.get('bundle'))
        for ref in sorted(self.port_refs):
            if ref not in self.nl.comps:
                self.err.append(f"--ports: no component {ref}")
                continue
            for u in self.nl.comps[ref].units:
                for num in u:
                    n = self.nl.net_of.get((ref, num))
                    if n and not n.startswith('unconnected-') and n not in self.rails and n not in self.pnet:
                        self.pnet[n] = (vname(n), None, 'auto', None)

    # --------------------------------------------------------- resolution
    def reach(self, net):
        """[(net, (cond, ...))] joined to net through switches, net itself first."""
        out, seen, todo = [(net, ())], {net}, [(net, ())]
        while todo:
            n, c = todo.pop(0)
            for m, cond, _ in self.switch.get(n, []):
                if m in seen or m in self.rails:
                    continue
                cc = c if cond == "1'b1" else c + (cond,)
                seen.add(m)
                out.append((m, cc))
                todo.append((m, cc))
        return out

    def eff(self, net, weak=True):
        ds = []
        for m, c in self.reach(net):
            for d in self.own.get(m, []):
                if d.kind == 'weak' and not weak:
                    continue
                ds.append(d.gated(c))
        return ds

    def always(self, net):
        """The ungated totem-pole driver of a net (via series links), or None."""
        t = [d for d in self.eff(net, weak=False) if d.kind == 'totem' and not d.cond]
        return t[0] if len(t) == 1 else (t if t else None)

    def _sourced(self, net):
        """Something that always has a value: an always-on totem pole, or a
        port with no strong driver on this card (the outside drives it)."""
        a = self.always(net)
        if a is not None:
            return a
        if net in self.pnet and self.pnet[net][2] != 'probe' and \
                not any(d.kind != 'weak' for d in self.eff(net, weak=False)):
            return 'port'
        return None

    def weak(self):
        for name, a, b, value, how in self.weak_r:
            src = None
            if how.startswith('from:'):
                pin = how[5:]
                src = (a, b) if pin == '1' else (b, a)
            elif a in self.rails:
                src = (a, b)
            elif b in self.rails:
                src = (b, a)
            else:
                ta, tb = self._sourced(a), self._sourced(b)
                if ta is not None and tb is None:
                    src = (a, b)
                elif tb is not None and ta is None:
                    src = (b, a)
                elif ta is not None and tb is not None:
                    self.warn.append(f"{name} {value}: between two always-driven nets {a}, {b}: ignored")
                    continue
                else:
                    self.err.append(f"{name} {value}: between {a} and {b}, neither always driven: "
                                    f"say which drives with Sim.R = from:1 | from:2 | series")
                    continue
            s, t = src
            v = f"1'b{self.rails[s]}" if s in self.rails else ('net', s)
            self.new_drv(t, 'weak', v=v, desc=f"{name} {value} from {s}")

    # --------------------------------------------------------- emission
    def emit(self):
        nl = self.nl
        names = set(self.params) | set(self.sim_inputs)
        out_ports = []          # (decl, comment)
        # ---- port classification
        groups = OrderedDict()                      # port name -> {index: net}
        for net, (pn, idx, d, forced) in self.pnet.items():
            g = groups.setdefault(pn, dict(bits={}, dir=d, forced=set(), vector=idx is not None))
            key = idx if idx is not None else 0
            if key in g['bits']:
                self.err.append(f"port {pn}[{key}]: nets {g['bits'][key]} and {net}")
            g['bits'][key] = net
            if forced:
                g['forced'] |= set(forced)
            if (idx is not None) != g['vector']:
                self.err.append(f"port {pn}: mixes indexed and plain nets")
        self.val = {}               # net -> verilog expression of its resolved value
        self.direct = {}            # driver id -> the name its model output connects to
        pclass = {}
        for pn, g in groups.items():
            if g['dir'] == 'probe':
                continue
            classes = {}
            for i, net in g['bits'].items():
                ds = self.eff(net)
                strong = [x for x in ds if x.kind != 'weak']
                if not ds:
                    classes[i] = 'in'
                elif len(strong) == 1 and strong[0].kind == 'totem' and not strong[0].cond and \
                        all(x.kind == 'weak' for x in ds if x is not strong[0]):
                    classes[i] = 'out'
                else:
                    classes[i] = 'bundle'
            cls = set(classes.values())
            if g['forced'] or len(cls) > 1 or 'bundle' in cls:
                c = 'bundle'
            else:
                c = cls.pop() if cls else 'in'
            if g['dir'] in ('in', 'out') and c != g['dir']:
                self.err.append(f"port {pn}: declared '{g['dir']}' but its on-card drivers make it '{c}'")
            pclass[pn] = c
        for pn, g in groups.items():
            n = max(g['bits']) + 1
            if g['vector'] and len(g['bits']) != n:
                self.warn.append(f"port {pn}: bits {sorted(set(range(n)) - set(g['bits']))} have no net")
            g['width'] = n
            names.add(pn)
            for i, net in g['bits'].items():
                ref = f"{pn}[{i}]" if g['vector'] else pn
                if g['dir'] == 'probe':
                    continue
                self.val[net] = ref
        # ---- internal nets: value expressions
        signal_nets = [n for n in nl.nets if n not in self.rails and not n.startswith('unconnected-')]
        wires = OrderedDict()
        wname = {}
        taken = set(names) | {i[1] for i in self.insts}

        def uniq(s):
            base, k = s, 1
            while s in taken:
                s = f"{base}_{k}"
                k += 1
            taken.add(s)
            return s
        port_of = {net: pn for net, (pn, _, d, _) in self.pnet.items() if d != 'probe'}
        for n in signal_nets:
            if n in self.val:
                continue
            if not self.own.get(n) and not self.loads.get(n) and not self.switch.get(n) and n not in self.pnet:
                continue
            wname[n] = uniq(vname(n))
            self.val[n] = wname[n]
        # pure-output port bits: the driver connects straight to the port
        for pn, g in groups.items():
            if pclass.get(pn) == 'out':
                for i, net in g['bits'].items():
                    d = [x for x in self.eff(net) if x.kind == 'totem'][0]
                    if d.home == net:
                        self.direct[d.did] = self.val[net]
        body = []
        clashes = []
        for n in signal_nets:                     # pass 1: always-driven nets own their driver
            a = self.always(n) if n in wname else None
            if a is not None and not isinstance(a, list) and a.home == n and a.did not in self.direct:
                self.direct[a.did] = wname[n]
        for pn, g in groups.items():              # output ports fed through a series link
            if pclass.get(pn) == 'out':
                for i, net in g['bits'].items():
                    d = [x for x in self.eff(net) if x.kind == 'totem'][0]
                    if d.home != net:
                        body.append(f"    assign {self.val[net]} = {self._dval(d)};   // {d.desc}")
        for n in signal_nets:
            if n not in wname:
                continue
            ds = self.eff(n)
            reach = self.reach(n)
            portsr = [(m, c) for m, c in reach if m != n and m in port_of]
            a = self.always(n)
            if isinstance(a, list):
                self.err.append(f"{n}: {len(a)} always-on totem-pole outputs: " + ', '.join(x.desc for x in a))
                continue
            if a is not None:
                if self.direct.get(a.did) != wname[n]:
                    body.append(f"    assign {wname[n]} = {self._dval(a)};   // {a.desc}")
                others = [x for x in ds if x.kind != 'weak' and x.did != a.did]
                if others and any(x.home == n for x in [a] + others):
                    clashes.append((wname[n], self._clash_expr([a] + others)))
                continue
            uncond = [m for m, c in portsr if not c]
            if uncond:
                body.append(f"    assign {wname[n]} = {self.val[uncond[0]]};   // joined to port {uncond[0]}")
                continue
            expr, comment, cl = self._resolve(n, ds)
            for m, c in reversed(portsr):
                expr = f"{_and(*c)} ? {self.val[m]} : {expr}"
                comment.append(f"{m} when {_and(*c)}")
            if not ds and not portsr:
                if self.loads.get(n):
                    self.err.append(f"{n}: read by {self.loads[n][:4]} but nothing drives it")
                continue
            body.append(f"    assign {wname[n]} = {expr};")
            if comment:
                body[-1] += "   // " + '; '.join(comment)
            if cl is not None and any(d.home == n for d in ds if d.kind != 'weak'):
                clashes.append((wname[n], cl))
        # ---- port bundles
        port_decl = []
        for pn, g in groups.items():
            w = g['width']
            rng = f"[{w - 1}:0] " if g['vector'] else ''
            if g['dir'] == 'probe':
                for i, net in g['bits'].items():
                    ref = f"{pn}[{i}]" if g['vector'] else pn
                    v = self.val.get(net)
                    if v is None:
                        self.err.append(f"probe {pn}: net {net} has no value on this card")
                        continue
                    body.append(f"    assign {ref} = {v};   // probe {net}")
                port_decl.append((f"output wire {rng}{pn}", f"probe: {self._nets(g)}"))
                continue
            c = pclass[pn]
            if c == 'in':
                port_decl.append((f"input  wire {rng}{pn}", self._nets(g)))
                continue
            if c == 'out':
                port_decl.append((f"output wire {rng}{pn}", self._nets(g)))
                continue
            kinds = set(g['forced'])
            per = {}
            for i, net in g['bits'].items():
                ds = self.eff(net)
                tri = [x for x in ds if x.kind in ('totem', 'tri')]
                od = [x for x in ds if x.kind == 'od']
                wk = [x for x in ds if x.kind == 'weak']
                per[i] = (tri, od, wk)
                if tri:
                    kinds.add('tri')
                if od:
                    kinds.add('od')
                if wk:
                    kinds.add('weak')
            port_decl.append((f"input  wire {rng}{pn}", f"resolved outside; {self._nets(g)}"))
            sfx = []
            if 'tri' in kinds:
                sfx += ['_oe', '_o']
            if 'od' in kinds:
                sfx += ['_pd']
            if 'weak' in kinds:
                sfx += ['_we', '_wo']
            for s in sfx:
                port_decl.append((f"output wire {rng}{pn}{s}", ''))
                names.add(pn + s)
            for i in range(w):
                ref = (lambda s: f"{pn}{s}[{i}]") if g['vector'] else (lambda s: f"{pn}{s}")
                tri, od, wk = per.get(i, ([], [], []))
                net = g['bits'].get(i, '(none)')
                if 'tri' in kinds:
                    oes = [self._oe(d) for d in tri]
                    body.append(f"    assign {ref('_oe')} = {' || '.join(oes) or ZERO};"
                                f"   // {net}: " + (', '.join(d.desc for d in tri) or 'no strong driver'))
                    body.append(f"    assign {ref('_o')} = {self._mux(tri)};")
                if 'od' in kinds:
                    pds = [_and(*(d.cond + (d.pd,))) for d in od]
                    body.append(f"    assign {ref('_pd')} = {' || '.join(pds) or ZERO};"
                                f"   // {net}: " + (', '.join(d.desc for d in od) or 'no drain'))
                if 'weak' in kinds:
                    wes = [_and(*d.cond) for d in wk]
                    body.append(f"    assign {ref('_we')} = {' || '.join(wes) or ZERO};"
                                f"   // {net}: " + (', '.join(d.desc for d in wk) or 'no weak driver'))
                    body.append(f"    assign {ref('_wo')} = {self._weak_chain(wk) if wk else ZERO};")
                if len(tri + od) > 1:
                    clashes.append((f"{pn}_{i}" if g['vector'] else pn, self._clash_expr(tri + od)))
        for nm in self.sim_inputs:
            port_decl.insert(0, (f"input  wire {nm}", self.sim_inputs[nm]))
        # ---- instances
        inst_lines, driver_wires = [], []
        cur = None
        for sheet, ref, mod, params, conns, comment in sorted(self.insts, key=lambda t: (t[0], _refkey(t[1]))):
            if sheet != cur:
                inst_lines.append(f"\n    // ---- sheet {sheet}")
                cur = sheet
            cs = []
            for port, kind, x in conns:
                if kind == 'in':
                    cs.append(f".{port}({self._vin(x)})")
                elif kind == 'sim':
                    cs.append(f".{port}({x})")
                elif kind.startswith('nc-'):
                    t = kind[3:]
                    oe, pd = x
                    if t == 'tri':
                        cs.append(f".{port}(), .{oe}()")
                    elif t == 'od':
                        cs.append(f".{pd}()")
                    else:
                        cs.append(f".{port}()")
                elif kind == 'totem':
                    tgt = self.direct.get(x.did)
                    if tgt is None:
                        tgt = x.v
                        driver_wires.append(x.v)
                    cs.append(f".{port}({tgt})")
                elif kind == 'tri':
                    d, oeport = x
                    driver_wires += [d.v, d.oe]
                    cs.append(f".{port}({d.v}), .{oeport}({d.oe})")
                elif kind == 'od':
                    driver_wires.append(x.pd)
                    cs.append(f".{port}({x.pd})")
            ps = ''
            if params:
                ps = ' #(' + ', '.join(f".{k}({v})" for k, v in params.items()) + ')'
            inst_lines.append(f"    {mod}{ps} {ref} (   // {comment}\n        " +
                              ',\n        '.join(cs) + ");")
        for dw in driver_wires:
            if dw in taken:
                self.err.append(f"driver wire {dw} collides with a net or port name")
            taken.add(dw)
        # ---- assemble
        L = ["// GENERATED by pcb/tools/net2v.py -- do not edit.",
             f"// netlist: {nl.path}",
             f"// schematic: {nl.source}",
             "// Nets keep their schematic names; multi-driver nets are resolved below with no z.",
             "`timescale 1ns/1ps",
             f"module {self.top}"]
        if self.params or self.extra_params:
            L[-1] += " #("
            ps = [(f"parameter {pn} = {dflt}", "--param: for macro cells to inherit")
                  for pn, dflt in self.extra_params.items()]
            for pn, (k, w, dflt, refs) in self.params.items():
                decl = f"parameter integer {pn} = {dflt}" if k == 'one' else f"parameter [{w - 1}:0] {pn} = {dflt}"
                ps.append((decl, f"jumper {' '.join(sorted(set(refs), key=_refkey))}"))
            L += [f"    {d}{',' if i < len(ps) - 1 else ''}   // {c}" for i, (d, c) in enumerate(ps)]
            L.append(") (")
        else:
            L[-1] += " ("
        if self.clash_port:
            port_decl.append(("output wire __clash", "two strong drivers enabled on one net"))
        L += [f"    {d}{',' if i < len(port_decl) - 1 else ''}" + (f"   // {c}" if c else '')
              for i, (d, c) in enumerate(port_decl)]
        L.append(");")
        if wires or wname:
            L.append("    // ---- nets")
            for n, w in wname.items():
                L.append(f"    wire {w};   // {n}")
        if driver_wires:
            L.append("    // ---- driver outputs, one per strong driver that shares its net")
            for dw in driver_wires:
                L.append(f"    wire {dw};")
        L += inst_lines
        L.append("\n    // ---- resolution")
        L += body
        L.append("\n    // ---- contention monitors: SAMPLE these, never trigger on their edges")
        for w, cl in clashes:
            L.append(f"    wire {w}__clash = {cl};")
        allc = ' | '.join(f"{w}__clash" for w, _ in clashes) or "1'b0"
        L.append(f"    {'assign' if self.clash_port else 'wire'} __clash = {allc};")
        L += ["endmodule", ""]
        self.sidecar = dict(
            top=self.top, netlist=str(nl.path),
            params={k: dict(kind=v[0], width=v[1], default=v[2], jumpers=v[3]) for k, v in self.params.items()},
            sim_inputs=list(self.sim_inputs),
            ports={pn: dict(cls=pclass.get(pn, 'probe' if g['dir'] == 'probe' else '?'),
                            width=g['width'] if g['vector'] else None,
                            nets={str(i): n for i, n in g['bits'].items()},
                            bundle=[s for s in ('_oe', '_o', '_pd', '_we', '_wo') if pn + s in names])
                   for pn, g in groups.items()},
            clashes=[w for w, _ in clashes])
        return '\n'.join(L)

    # ---- small emitters
    def _nets(self, g):
        b = g['bits']
        if len(b) == 1:
            return next(iter(b.values()))
        ks = sorted(b)
        return f"{b[ks[0]]} .. {b[ks[-1]]}"

    def _vin(self, net):
        return self.val.get(net) or self._const(net)

    def _const(self, net):
        return f"1'b{self.rails[net]}" if net in self.rails else vname(net)

    def _dval(self, d):
        return self.direct.get(d.did, d.v) if d.kind == 'totem' else d.v

    def _wval(self, d):
        return self.val.get(d.v[1], vname(d.v[1])) if isinstance(d.v, tuple) else d.v

    def _oe(self, d):
        return _and(*(d.cond + ((d.oe,) if d.kind == 'tri' else ())))

    def _mux(self, tri, default=ZERO):
        """The value the strong drivers put out: the first enabled one."""
        if len(tri) == 1:
            return self._dval(tri[0])
        chain = default
        for d in reversed(tri):
            chain = f"{self._oe(d)} ? {self._dval(d)} : {chain}"
        return chain

    def _weak_chain(self, wk, default=ZERO):
        unc = [d for d in wk if not d.cond]
        chain = self._wval(unc[0]) if unc else default
        for d in reversed([d for d in wk if d.cond]):
            chain = f"{_and(*d.cond)} ? {self._wval(d)} : {chain}"
        return chain

    def _clash_expr(self, strong):
        terms = []
        drv = [d for d in strong if d.kind in ('totem', 'tri')]
        oes = [self._oe(d) for d in drv]
        pds = [_and(*(d.cond + (d.pd,))) for d in strong if d.kind == 'od']
        if len(oes) > 1:
            terms.append('(' + ' + '.join("8'd1" if o == ONE else f"{{7'd0, {o}}}" for o in oes) + ") > 8'd1")
        if oes and pds:
            vals = [self._dval(d) if o == ONE else f"({o} && {self._dval(d)})" for d, o in zip(drv, oes)]
            terms.append(f"({' || '.join(pds)}) && ({' || '.join(vals)})")
        return ' || '.join(terms) if terms else ZERO

    def _resolve(self, n, ds):
        strong = [d for d in ds if d.kind in ('totem', 'tri')]
        od = [d for d in ds if d.kind == 'od']
        wk = [d for d in ds if d.kind == 'weak']
        comment = [d.desc + (f" when {_and(*d.cond)}" if d.cond else '') for d in ds]
        unc = [d for d in wk if not d.cond]
        if len({str(d.v) for d in unc}) > 1:
            self.err.append(f"{n}: conflicting weak drivers: {', '.join(d.desc for d in unc)}")
        if not unc:
            if od and not strong and not wk:
                self.err.append(f"{n}: open drain ({', '.join(d.desc for d in od)}) with no pull-up")
            elif strong or od:
                self.warn.append(f"{n}: floats when every driver lets go; reads 0 then")
        chain = self._weak_chain(wk)
        expr = chain
        for d in reversed(strong):
            expr = f"{self._oe(d)} ? {self._dval(d)} : {expr}"
        if od:
            pds = ' || '.join(_and(*(d.cond + (d.pd,))) for d in od)
            expr = f"!({pds})" if (not strong and chain == ONE) else f"({pds}) ? {ZERO} : {expr}"
        cl = self._clash_expr(strong + od) if len(strong + od) > 1 else None
        return expr, comment, cl


def _refkey(r):
    m = re.match(r'([^\d]*)(\d+)(.*)', str(r))
    return (m.group(1), int(m.group(2)), m.group(3)) if m else (str(r), 0, '')


def _jumper_pairs(part):
    m = re.fullmatch(r'Conn_02x(\d\d)_(Odd_Even|Top_Bottom|Counter_Clockwise)(_.*)?', part)
    if m:
        n = int(m.group(1))
        if m.group(2) == 'Odd_Even':
            return [(str(2 * k + 1), str(2 * k + 2)) for k in range(n)]
        if m.group(2) == 'Top_Bottom':
            return [(str(k + 1), str(n + k + 1)) for k in range(n)]
        return [(str(k + 1), str(2 * n - k)) for k in range(n)]
    if re.match(r'(Solder)?Jumper_2_', part) or re.fullmatch(r'Conn_01x02(_.*)?', part):
        return [('1', '2')]
    if re.match(r'(Solder)?Jumper_3_', part):
        return [('1', '2'), ('2', '3')]
    return None


def generate(nl, top, models, **kw):
    """-> (verilog text, sidecar dict, errors, warnings)"""
    g = Gen(nl, top, models, **kw)
    try:
        g.build()
        text = g.emit() if not g.err else ''
    except GenError as e:
        g.err.append(str(e))
        text = ''
    return text, getattr(g, 'sidecar', {}), g.err, g.warn


def main(argv=None):
    ap = argparse.ArgumentParser(description='KiCad kicadxml netlist -> structural Verilog')
    ap.add_argument('xml')
    ap.add_argument('--top', required=True, help='module name')
    ap.add_argument('--ports', default='', help='comma-separated connector refs whose nets are the ports')
    ap.add_argument('--portmap', help='JSON: net -> {port, index, dir, bundle}')
    ap.add_argument('--models', action='append', help=f'model dir or file (default {DEFAULT_MODELS})')
    ap.add_argument('--series-max', type=float, default=100.0, help='ohms at or below which R is a link')
    ap.add_argument('--rail', action='append', default=[], help='NET=0|1, another constant rail')
    ap.add_argument('--clash-port', action='store_true', help='make __clash a module output')
    ap.add_argument('--param', action='append', default=[],
                    help="NAME=DEFAULT: declare a module parameter (a Sim.Macro may pass NAME through)")
    ap.add_argument('--strict', action='store_true', help='off-rail capacitors are errors')
    ap.add_argument('-o', required=True)
    a = ap.parse_args(argv)
    nl = netlist_mod.read(a.xml)
    errs = nl.check()
    if errs:
        for e in errs:
            print("error:", e, file=sys.stderr)
        return 1
    models = Models(a.models or [DEFAULT_MODELS])
    if not models.pinmap:
        print(f"error: no pinmap.json in {a.models or [DEFAULT_MODELS]}", file=sys.stderr)
        return 1
    pm = json.loads(Path(a.portmap).read_text()) if a.portmap else None
    rails = {k: int(v) for k, v in (r.split('=') for r in a.rail)}
    text, side, err, warn = generate(nl, a.top, models, port_refs=[p for p in a.ports.split(',') if p],
                                     portmap=pm, series_max=a.series_max, rails=rails,
                                     clash_port=a.clash_port, strict=a.strict,
                                     extra_params=[p.split('=', 1) for p in a.param])
    for w in warn:
        print("warning:", w, file=sys.stderr)
    if err:
        for e in err:
            print("error:", e, file=sys.stderr)
        return 1
    Path(a.o).write_text(text)
    Path(a.o).with_suffix('.json').write_text(json.dumps(side, indent=1) + '\n')
    print(f"wrote {a.o} ({len(side['ports'])} ports, {len(side['params'])} parameters, "
          f"{len(side['clashes'])} contention monitors)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
