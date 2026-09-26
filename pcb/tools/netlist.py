#!/usr/bin/env python3
"""Export and parse KiCad 10 netlists, and refuse the ones kicad-cli lets through.

    netlist.py export top.kicad_sch [-o top.xml]   export (kicadxml) + check; exit 1 on errors
    netlist.py check  top.xml                        the checks alone
    netlist.py show   top.xml                        components, then nets with their nodes

Library use:
    nl = netlist.export('top.kicad_sch')           # -> Netlist, checked; raises NetlistError
    nl = netlist.read('top.xml'); errs = nl.check()
    nl.comps['U1'].value / .fields / .pins / .sheet / .dnp / .xsim
    nl.nets['/C_TX'] -> [Node(ref, pin, name, type)]
    nl.net_of[('U1', '5')] -> '/C_TX'
    nl.sheets['/<uuid>/'] -> Sheet(name, tstamps, file, props (the sheet symbol's
                             fields, e.g. Sim.Macro), pins, sch (SchFile of its file))

What the checks catch that kicad-cli does not (it exits 0 on all of them):
  * a symbol whose lib_id is missing from its file's lib_symbols (KiCad exports
    its pins as one net 'Net-(U1-Pad??)' typed 'unspecified');
  * a reference used twice, across every sheet instance, power symbols
    (#PWR, #FLG) included -- the export prints 'annotation errors' and goes on;
  * an unannotated reference ('U?').
kicad-cli's kicadxml omits exclude_from_sim, so it is read from the .kicad_sch
files (a symbol's own flag, or its sheet's).
"""
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter, namedtuple
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kisexp  # noqa: E402

Node = namedtuple('Node', 'ref pin name type')


class NetlistError(Exception):
    pass


class Comp:
    def __init__(self, **kw):
        self.__dict__.update(kw)

    def __repr__(self):
        return f"Comp({self.ref} {self.value} {self.lib}:{self.part} {self.sheet})"


class Sheet:
    def __init__(self, **kw):
        self.__dict__.update(kw)


def _fn(pinfunction, pin):
    """KiCad 10.0.6 writes pinfunction as '<name>_<num>' ('D_3'); strip it."""
    if pinfunction is None:
        return ''
    suf = '_' + pin
    return pinfunction[:-len(suf)] if pinfunction.endswith(suf) else pinfunction


class Netlist:
    def __init__(self, path):
        self.path = Path(path)
        root = ET.parse(self.path).getroot()
        des = root.find('design')
        self.source = Path(des.findtext('source'))
        self.sheets = {}
        for s in des.iter('sheet'):
            tb = s.find('title_block')
            self.sheets[s.get('tstamps')] = Sheet(number=int(s.get('number')), name=s.get('names') or s.get('name'),
                                                  tstamps=s.get('tstamps'),
                                                  file=tb.findtext('source') if tb is not None else '',
                                                  props={}, pins=[], sch=None, xsim=False)
        self.comps, self.comp_list = {}, []
        for c in root.find('components'):
            ls, sp = c.find('libsource'), c.find('sheetpath')
            fields = {f.get('name'): (f.text or '') for f in c.iter('field')}
            prp = {p.get('name'): p.get('value') for p in c.iter('property')}
            comp = Comp(ref=c.get('ref'), value=c.findtext('value'), footprint=c.findtext('footprint') or '',
                        lib=ls.get('lib'), part=ls.get('part'),
                        sheet=sp.get('names') if sp is not None else '/',
                        sheet_ts=sp.get('tstamps') if sp is not None else '/',
                        uuids=(c.findtext('tstamps') or '').split(), fields=fields, props=prp,
                        dnp='dnp' in prp, xsim=False,
                        units=[[p.get('num') for p in u.iter('pin')] for u in c.iter('unit')])
            self.comp_list.append(comp)
            self.comps[comp.ref] = comp
        self.libparts = {}
        for lp in root.find('libparts'):
            self.libparts[(lp.get('lib'), lp.get('part'))] = {
                p.get('num'): (p.get('name'), p.get('type')) for p in lp.iter('pin')}
        self.nets, self.net_of = {}, {}
        for n in root.find('nets'):
            nodes = [Node(x.get('ref'), x.get('pin'), _fn(x.get('pinfunction'), x.get('pin')), x.get('pintype'))
                     for x in n.iter('node')]
            self.nets[n.get('name')] = nodes
            for x in nodes:
                self.net_of[(x.ref, x.pin)] = n.get('name')
        self._sch_loaded = False

    # ------------------------------------------------ the schematic files
    def schematic(self):
        """Read every .kicad_sch of the hierarchy: sheet symbols' fields and
        pins, exclude_from_sim flags.  Idempotent."""
        if self._sch_loaded:
            return self
        base = self.source.parent
        files = {}

        def sf(name):
            if name not in files:
                files[name] = kisexp.SchFile(base / name)
            return files[name]

        root = sf(self.source.name)
        self.files = files
        for ts, sh in sorted(self.sheets.items(), key=lambda t: t[0].count('/')):
            sh.sch = sf(sh.file) if sh.file else root
            if ts == '/':
                continue
            parent_ts = ts.rstrip('/').rsplit('/', 1)[0] + '/'
            parent = self.sheets.get(parent_ts)
            psch = parent.sch if parent else root
            u = ts.rstrip('/').rsplit('/', 1)[1]
            sym = next((s for s in psch.sheets if s['uuid'] == u), None)
            if sym is None:
                raise NetlistError(f"sheet {sh.name}: no sheet symbol {u} in {psch.path.name}")
            sh.props, sh.pins, sh.symbol = sym['props'], sym['pins'], sym
            node = next(x for x in kisexp.kids(psch.tree, 'sheet') if str(kisexp.val(x, 'uuid')) == u)
            sh.xsim = str(kisexp.val(node, 'exclude_from_sim', 'no')) == 'yes' or (parent.xsim if parent else False)
        byref = {}
        for f in files.values():
            for s in f.symbols:
                xs = str(kisexp.val(s['node'], 'exclude_from_sim', 'no')) == 'yes'
                for path, ref, unit in s['instances']:
                    byref.setdefault(ref, []).append((f, s, path, unit, xs))
        self.sym_instances = byref
        for c in self.comp_list:
            sh = self.sheets.get(c.sheet_ts)
            c.xsim = any(x[4] for x in byref.get(c.ref, [])) or bool(sh and sh.xsim)
        self._sch_loaded = True
        return self

    def symbol_of(self, sheet_ts, uuid):
        """The component ref of placed symbol `uuid` in sheet instance sheet_ts."""
        for c in self.comp_list:
            if c.sheet_ts == sheet_ts and uuid in c.uuids:
                return c.ref
        return None

    # ------------------------------------------------------------- checks
    def check(self):
        """[error strings]; empty means the netlist can be trusted."""
        err = []
        dup = [r for r, n in Counter(c.ref for c in self.comp_list).items() if n > 1]
        if dup:
            err.append(f"duplicate references in the netlist: {', '.join(sorted(dup))}")
        for c in self.comp_list:
            if c.ref.endswith('?'):
                err.append(f"{c.ref}: not annotated")
        for n, nodes in self.nets.items():
            for x in nodes:
                if x.type == 'unspecified' or 'Pad??' in n:
                    err.append(f"{x.ref} pin {x.pin} on '{n}' typed '{x.type}': symbol missing from lib_symbols?")
                    break
        try:
            self.schematic()
        except (OSError, NetlistError) as e:
            err.append(f"cannot read the schematic files: {e}")
            return err
        for f in self.files.values():
            for s in f.symbols:
                if s['lib_id'] not in f.lib_symbols:
                    refs = sorted({r for _, r, _ in s['instances']})
                    err.append(f"{f.path.name}: {s['lib_id']} ({', '.join(refs)}) is not in lib_symbols")
        seen = {}
        for ref, insts in self.sym_instances.items():
            for f, s, path, unit, _ in insts:
                k = (ref, unit)
                if k in seen and seen[k] != (path, s['uuid']):
                    err.append(f"reference {ref} unit {unit} used twice ({seen[k][0]} and {path})")
                seen.setdefault(k, (path, s['uuid']))
        return sorted(set(err))


def read(path):
    return Netlist(path)


def export(sch, xml=None, check=True):
    """kicad-cli sch export netlist --format kicadxml, then check.  Raises
    NetlistError on a failed export, 'annotation errors', or a failed check."""
    sch = Path(sch)
    xml = Path(xml) if xml else sch.with_suffix('.xml')
    r = subprocess.run(['kicad-cli', 'sch', 'export', 'netlist', '--format', 'kicadxml', '-o', str(xml), str(sch)],
                       capture_output=True, text=True)
    out = r.stdout + r.stderr
    if r.returncode != 0 or not xml.exists():
        raise NetlistError(f"netlist export failed ({r.returncode}): {out.strip()}")
    errs = []
    if re.search(r'annotation', out, re.I):          # exit status is 0 regardless
        errs.append("kicad-cli: " + ' '.join(out.split())[:400])
    nl = Netlist(xml)
    if check:
        errs += nl.check()
    if errs:
        raise NetlistError('\n'.join(errs))
    return nl


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    a = sub.add_parser('export')
    a.add_argument('sch')
    a.add_argument('-o', default=None)
    b = sub.add_parser('check')
    b.add_argument('xml')
    c = sub.add_parser('show')
    c.add_argument('xml')
    args = ap.parse_args(argv)
    try:
        if args.cmd == 'export':
            nl = export(args.sch, args.o)
            print(f"wrote {nl.path}: {len(nl.comps)} components, {len(nl.nets)} nets, checks clean")
            return 0
        nl = read(args.xml)
        if args.cmd == 'check':
            errs = nl.check()
            for e in errs:
                print("error:", e)
            print(f"{args.xml}: {'clean' if not errs else f'{len(errs)} error(s)'}")
            return 1 if errs else 0
        nl.schematic()
        for r, c in sorted(nl.comps.items()):
            flags = ' '.join(f for f, on in (('DNP', c.dnp), ('XSIM', c.xsim)) if on)
            extra = ' '.join(f"{k}={v!r}" for k, v in c.fields.items() if k.startswith('Sim.'))
            print(f"{r:6} {c.value:12} {c.lib}:{c.part:26} {c.sheet:12} {flags} {extra}")
        for n, nodes in nl.nets.items():
            print(f"{n:32} " + ' '.join(f"{x.ref}.{x.pin}{'(' + x.name + ')' if x.name else ''}:{x.type}"
                                        for x in nodes))
        return 0
    except NetlistError as e:
        print("error:", e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
