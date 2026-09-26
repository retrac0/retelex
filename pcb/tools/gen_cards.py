#!/usr/bin/env python3
"""gen_cards.py -- the first draft of both block-stack schematics, from
pcb/lib/block-stack.json (stackdef.py), drawn with sch.py.

    python3 gen_cards.py [CARD ...]              write pcb/<card>/<card>.kicad_sch (+ sheets); the
                                                 cards are blkhdr_bus_RevA and blkhdr_logic_RevA
                                                 (and portcard, only with --force-portcard: the
                                                 port card's BOARD is pcb/portcard_RevC, by hand)
    python3 gen_cards.py --check                     hold the schematics' connectors to the JSON

THE SCHEMATICS ARE THE DESIGN once they exist.  Running this again OVERWRITES
them; it is for the first draft, and for starting over.  --check is what stays
useful afterwards: it exports each card's netlist and fails unless every stack,
bus, adapter and edge pin carries the net block-stack.json gives it, so a card
edited in KiCad cannot drift off the stack's pin contract unnoticed.

Every connection is a label on a pin end (sch.py): a net's name IS its label.
The RC networks that a digital simulator cannot run sit on sheets of their own
with a Sim.Macro field (net2v.py replaces the sheet with a cell of
pcb/models/74hc.v):

    port card   det.kicad_sch   x2  DETM (M, from a6), DETE (E)   rc_det
                cr.kicad_sch    x2  CRM (/FM's rise), CRE (/FE's) cr_rel RISE=1
    header A    rst.kicad_sch   x1  the /RESET filter              rc_filt

The jumpers carry Sim.Jumper, so one netlist serves every setting: the port
card's three lane jumpers are ganged as LANE, its POS jumper is POS; the
header A's NUMBER jumper is JUMPERED and BLOCK.  Its HC ROUTE and RBT SOURCE
jumpers are excluded from simulation: which highway a block drives is
mainboard.v's model, and rbt is an input of block.v, driven by the bench.
The lamps (LEDs, their resistors) are excluded too: a digital simulator has no
LED.  The '595s that drive them are simulated, and the stack checks them.
"""
import json
import subprocess
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
PCB = HERE.parent
sys.path.insert(0, str(HERE))
import kisexp  # noqa: E402
from sch import Project, erc  # noqa: E402

SPEC = json.loads((PCB / 'lib' / 'block-stack.json').read_text())
DATE = '2026-09-25'

# refs that live on a macro sheet, per card: sheet file -> [(instance, {role: ref}, {pin: net})]
MACROS = {
    'portcard': {
        'det': [('DETM', dict(D='D1', RF='R6', RS='R7', C='C1'), dict(IN='E_A_TX', OUT='RC_M')),
                ('DETE', dict(D='D2', RF='R8', RS='R9', C='C2'), dict(IN='E', OUT='RC_E'))],
        'cr': [('CRM', dict(C='C3', R='R10', D='D3'), dict(IN='FM_N', OUT='CR_M')),
               ('CRE', dict(C='C4', R='R11', D='D4'), dict(IN='FE_N', OUT='CR_E'))],
    },
    'blkhdr_bus_RevA': {
        'rst': [('RSTF', dict(R='R11', C='C1'), dict(A='B_RESET_N', Y='RESET_RC'))],
    },
    'blkhdr_logic_RevA': {},
}
MACRO_FIELDS = {
    'det': 'rc_det T_ARM=T_ARM T_REL=T_REL',
    'cr': 'cr_rel RISE=1 REL:OUT',
    'rst': 'rc_filt T_UP=100 T_DN=100 INIT=0',     # the board's is ~1 ms: shorter than any bench's reset
}
TITLES = {
    'blkhdr_bus_RevA': 'Block header A, the bus board -- the bottom card of a block stack',
    'blkhdr_logic_RevA': 'Block header B, the logic board -- on A, under the port cards; the lamps',
    'portcard': 'Port card -- one port circuit, eight to a block stack',
}


def spec_of(net):
    if net in ('+5V', 'GND'):
        return 'p:' + net
    if net in ('NC', None) or (net or '').startswith('SP'):
        return 'nc'                 # SPn: a spare that passes through the stack, connected to nothing here
    return net


def units_of(lib_id):
    """pin number -> unit, for a symbol."""
    return {p['num']: p['unit'] for p in kisexp.sym_pins(lib_id)}


def place(sheet, part, fields=None, exclude_from_sim=False, pins_override=None, card=None):
    exclude_from_sim = exclude_from_sim or part.get('sim') is False
    lib_id, ref, value = part['lib_id'], part['ref'], part['value']
    pins = pins_override or part['pins']
    fields = dict(fields or {})
    fields.update(SIM_FIELDS.get((card, ref), {}))
    if part.get('rtl') and part['rtl'] != '-':
        fields['RTL'] = part['rtl']
    if part.get('function'):
        fields['Function'] = part['function']
    umap = units_of(lib_id)
    by_unit = defaultdict(OrderedDict)
    for num, net in pins.items():
        u = umap.get(str(num))
        if u is None:
            if net in ('NC', None):
                continue            # a package NC pin the symbol does not draw (the 4002's 6 and 8)
            raise SystemExit(f"{ref}: {lib_id} has no pin {num}")
        by_unit[u][str(num)] = spec_of(net)
    # every unit's every pin: an unlisted pin is a no-connect
    for num, u in umap.items():
        by_unit[u].setdefault(num, 'nc')
    for u in sorted(by_unit):
        sheet.part(lib_id, ref, value, pins=by_unit[u], unit=u, footprint=part.get('footprint'),
                   fields=fields, exclude_from_sim=exclude_from_sim)


def conn_lib(n_pins, rows):
    if rows == 1:
        return f"Connector_Generic:Conn_01x{n_pins:02d}"
    return f"Connector_Generic:Conn_02x{n_pins // 2:02d}_Odd_Even"


def connectors_of(card):
    """Every connector and jumper on a card, as parts: stack, bus, adapter, edge, test, jumpers."""
    out = []
    for c in SPEC['stack_connectors']:
        fp = c['footprint'][card] if isinstance(c['footprint'], dict) else c['footprint']
        out.append(dict(ref=c['ref'], value=f"STACK {c['edge'].upper()}", lib_id=conn_lib(len(c['pins']), 2),
                        footprint=fp, function=c['role'], pins=c['pins'], kind='stack'))
    for c in SPEC['connectors']:
        if c['card'] != card:
            continue
        n = len(c['pins'])
        rows = 1 if 'test' in c['role'] else 2
        fp = c['footprint']
        if ' or ' in fp:
            fp = fp.split(' or ')[0].split(' (')[0]
        if fp.startswith('telco:'):
            fp = fp.split(' ')[0]       # 'telco:Bus_2x25_P2.54mm_Mirror (note)' -> the footprint
        out.append(dict(ref=c['ref'], value=c['role'].split(',')[0].split(' (')[0].upper(),
                        lib_id=conn_lib(n, rows), footprint=fp, function=c['role'], pins=c['pins'],
                        kind='conn'))
    for j in SPEC['jumpers']:
        if j['card'] != card:
            continue
        n = len(j['pins'])
        out.append(dict(ref=j['ref'], value=j['label'], lib_id=conn_lib(n, 2), footprint=j['footprint'],
                        function=j.get('missing', ''), pins=j['pins'], kind='jumper', label=j['label']))
    return out


# Per-part simulation fields.  RN1 on the header: the eight lane pulls are driven
# FROM FILL_R (pin 1, the common), which net2v cannot tell by itself because
# FILL_R comes off a '244 (a tri-state part) and the lanes from outside the card.
SIM_FIELDS = {
    ('blkhdr_bus_RevA', 'RN1'): {'Sim.R': 'from:1'},
    ('portcard', 'R5'): {'Sim.R': 'from:2'},      # E_FILL -> a pulled card's C_TX
}

JUMPER_SIM = {
    ('portcard', 'POS'): 'nbits:POS',
    ('portcard', 'WR'): 'one:LANE',
    ('portcard', 'C_TX'): 'one:LANE',
    ('portcard', 'WORD'): 'one:LANE',
    ('blkhdr_bus_RevA', 'NUMBER'): 'bits:JUMPERED@0 nbits:BLOCK@1-3',
}


def build(card):
    cd = SPEC['cards'][card]
    out = PCB / card
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob('*.kicad_sch'):
        old.unlink()
    # A header board passes stack nets it never uses (the other board's, the
    # port cards'): a label on one pin is the design there, not an omission.
    prj = Project(card, out, fp_libs={'telco': PCB / 'lib' / 'telco.pretty'},
                  erc_ignore=('isolated_pin_label',) if card.startswith('blkhdr') else ())
    top = prj.root
    top.title(TITLES[card], rev='A', date=DATE, company='telco',
              comments=['First draft generated by pcb/tools/gen_cards.py from pcb/lib/block-stack.json',
                        'Spec: exchange/block-stack.md.  Reference RTL: newimpl/rtl/block.v, port.v, frame_decode.v',
                        'Checked by: make -C pcb netcheck (netlist -> Verilog -> the newimpl benches, lockstep vs block.v)']
              + (['Stack nets this board does not use pass straight through: ERC isolated_pin_label is off here']
                 if card.startswith('blkhdr') else []))

    macro_refs = {r for insts in MACROS[card].values() for _, roles, _ in insts for r in roles.values()}
    parts = {p['ref']: p for p in cd['parts']}

    # ---- connectors and jumpers, first column(s)
    conns = connectors_of(card)
    flag_done = set()
    for c in conns:
        pins = OrderedDict()
        for num, net in sorted(c['pins'].items(), key=lambda kv: int(kv[0])):
            s = spec_of(net)
            if net in ('+5V', 'GND') and net not in flag_done and c['kind'] == 'stack':
                s = [s, 'p:PWR_FLAG']
                flag_done.add(net)
            pins[str(num)] = s
        fields = {}
        if c['kind'] == 'jumper':
            sim = JUMPER_SIM.get((card, c['label']))
            if sim:
                fields['Sim.Jumper'] = sim
        top.part(c['lib_id'], c['ref'], c['value'], pins=pins, footprint=c['footprint'],
                 fields=dict(fields, Function=c['function']) if c['function'] else fields,
                 exclude_from_sim=(c['kind'] == 'jumper' and c['label'] in ('HC ROUTE', 'RBT SOURCE')))
        top.newcol()

    # ---- packages, in the order stackdef.py lists them (roughly the signal flow)
    ics = [p for p in cd['parts'] if p['lib_id'].startswith(('74xx:', '4xxx:'))]
    for i, p in enumerate(ics):
        place(top, p, card=card)
        if i % 3 == 2:
            top.newcol()
    top.newcol()
    rest = [p for p in cd['parts'] if not p['lib_id'].startswith(('74xx:', '4xxx:'))
            and p['ref'] not in macro_refs and not p['ref'].startswith(('C', 'J'))]
    for i, p in enumerate(rest):
        place(top, p, card=card)
        if i % 8 == 7:
            top.newcol()
    top.newcol()
    caps = [p for p in cd['parts'] if p['ref'].startswith('C') and p['ref'] not in macro_refs]
    for i, p in enumerate(caps):
        place(top, p, card=card)
        if i % 12 == 11:
            top.newcol()
    top.newcol()

    # ---- macro sheets
    for file, insts in MACROS[card].items():
        sh = prj.sheet(f"{file}.kicad_sch")
        roles0 = insts[0][1]
        refs = {role: [inst[1][role] for inst in insts] for role in roles0}
        pr = {role: parts[refs[role][0]] for role in roles0}
        if file == 'det':
            sh.title('rc_det: the supervision detector -- fast up through D and RF, slow down through RS',
                     comments=['Sim.Macro on each sheet symbol: net2v.py replaces this sheet with pcb/models rc_det',
                               'port.v:134-136, 175-188; fabric.md 5.2'])
            sh.part('Device:D', refs['D'], pr['D']['value'], pins={'1': 'DET', '2': 'h:IN/input'},
                    footprint=pr['D']['footprint'])
            sh.part('Device:R', refs['RF'], pr['RF']['value'], pins={'1': 'DET', '2': 'h:OUT/output'},
                    footprint=pr['RF']['footprint'])
            sh.part('Device:R', refs['RS'], pr['RS']['value'], pins={'1': 'h:IN/input', '2': 'h:OUT/output'},
                    footprint=pr['RS']['footprint'])
            sh.part('Device:C', refs['C'], pr['C']['value'], pins={'1': 'h:OUT/output', '2': 'p:GND'},
                    footprint=pr['C']['footprint'])
        elif file == 'cr':
            sh.title("cr_rel: a detector's fall, differentiated into the '273's /CLR",
                     comments=["IN is the '14 output /FM or /FE: its RISE is the detector's fall (port.v:180, 186, 190-194)",
                               'Sim.Macro: cr_rel RISE=1'])
            sh.part('Device:C', refs['C'], pr['C']['value'], pins={'1': 'h:IN/input', '2': 'h:OUT/output'},
                    footprint=pr['C']['footprint'])
            sh.part('Device:R', refs['R'], pr['R']['value'], pins={'1': 'h:OUT/output', '2': 'p:GND'},
                    footprint=pr['R']['footprint'])
            sh.part('Device:D', refs['D'], pr['D']['value'], pins={'1': 'h:OUT/output', '2': 'p:GND'},
                    footprint=pr['D']['footprint'])
        elif file == 'rst':
            sh.title('rc_filt: the /RESET filter, 10k into 100n, about 1 ms (bus.md 6.2)',
                     comments=['Sim.Macro: rc_filt, shortened to 100 ns in simulation: block.v has no filter, and tb_ctl resets for 1 us',
                               "port.v:38: 'also /RESET, filtered at the block'"])
            sh.part('Device:R', refs['R'], pr['R']['value'], pins={'1': 'h:A/input', '2': 'h:Y/output'},
                    footprint=pr['R']['footprint'])
            sh.part('Device:C', refs['C'], pr['C']['value'], pins={'1': 'h:Y/output', '2': 'p:GND'},
                    footprint=pr['C']['footprint'])
        for inst, roles, pins in insts:
            top.place_sheet(sh, inst, pins={k: spec_of(v) for k, v in pins.items()},
                            fields={'Sim.Macro': MACRO_FIELDS[file]})
    return prj.write()


# ------------------------------------------------------------------ check
def check(card):
    """Every connector pin on the card carries the JSON's net."""
    sys.path.insert(0, str(HERE))
    import netlist
    nl = netlist.export(PCB / card / f"{card}.kicad_sch", PCB / 'out' / card / f"{card}.xml")
    bad = []
    for c in connectors_of(card):
        for num, want in c['pins'].items():
            got = nl.net_of.get((c['ref'], str(num)))
            got_n = (got or '').lstrip('/')
            if want in ('NC', None) or want.startswith('SP'):
                if got and not got_n.startswith('unconnected-'):
                    bad.append(f"{c['ref']}.{num}: want no connection, got {got}")
                continue
            if got_n != want:
                bad.append(f"{c['ref']}.{num}: want {want}, got {got}")
    return bad


def main(argv):
    if '--check' in argv:
        cards = [a for a in argv if not a.startswith('-')] or ['blkhdr_bus_RevA', 'blkhdr_logic_RevA', 'portcard']
        fail = 0
        for card in cards:
            (PCB / 'out' / card).mkdir(parents=True, exist_ok=True)
            bad = check(card)
            print(f"  {card}: {'pin contract holds' if not bad else f'{len(bad)} pins off contract'}")
            for b in bad[:40]:
                print('    ' + b)
            fail |= bool(bad)
        return fail
    cards = [a for a in argv if not a.startswith('-')] or ['blkhdr_bus_RevA', 'blkhdr_logic_RevA']
    # The port card's board is maintained by hand in KiCad (pcb/portcard_RevC,
    # with the port-state LEDs, Joel 2026-09-26); pcb/portcard is the generated
    # schematic the netlist check runs.  Never draw it unless asked for by name
    # AND with --force-portcard.
    if 'portcard' in cards and '--force-portcard' not in argv:
        print("refusing to regenerate the port card: its board is hand-maintained "
              "(pcb/portcard_RevC); pass --force-portcard to draw pcb/portcard afresh")
        cards = [c for c in cards if c != 'portcard']
    rc = 0
    for card in cards:
        path = build(card)
        ok, vio = erc(path, out=PCB / 'out' / card / 'erc.json') if (PCB / 'out' / card).mkdir(
            parents=True, exist_ok=True) is None else (None, None)
        print(f"wrote {path}: ERC {'clean' if ok else f'{len(vio)} violations'}")
        for v in (vio or [])[:30]:
            print('   ', v[0], v[1], v[2], '|', '; '.join(v[3])[:160])
        rc |= not ok
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
