#!/usr/bin/env python3
"""compare.py LOG... -- each RTL run beside regmodel at the same knobs (long run, scale of the log)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse import parse
from regmodel import M
print(f"{'run':20s} | {'att/s/ex':>9s} | {'OK/min/ex':>10s} | {'N ok%':>6s} | {'refuse%':>8s} | {'reg':>9s} | {'NODT%':>6s} | {'notrunk':>7s} | carried E")
for p in sys.argv[1:]:
    r = parse(p); k = r['knobs']; run = r.get('run', {})
    T = int(run.get('traffic_ms', 1)) / 1000.0
    ex = r['ex']; o = r.get('outcome', {}); oN = r.get('outcome_N', {})
    att = sum(float(d.get('attempts', {}).get('per_s', 0)) for d in ex.values()) / 2
    ok = int(o.get('OK', 0)) / T * 60 / 2
    nt = int(oN.get('total', 0)); nok = int(oN.get('OK', 0)); ncut = int(oN.get('CUT', 0))
    cl = sum(int(d.get('unit', {}).get('claims', 0)) for d in ex.values())
    rf = sum(int(d.get('unit', {}).get('att_refuse', 0)) for d in ex.values())
    reg = '/'.join(d.get('exchange', {}).get('reg_occ', '?') for x, d in sorted(ex.items()))
    nodt = int(o.get('NODT', 0)) / max(int(o.get('total', 1)), 1)
    notr = sum(int(d.get('nogo_written', {}).get('N_NOTRUNK', 0)) for d in ex.values())
    ch = 2 if 'l2b' in r['name'] else 8
    scale = int(run.get('scale', 8))
    kw = dict(scale=scale, idle=int(k['idle_ms']), pnet=int(k['pnet']), CH=ch,
              mode=int(k.get('dest_mode', 0)), orig='A' if k.get('orig_x') == '1' else 'AB',
              T=(2000000 if scale == 8 else 12000000), warm=(20000 if scale == 8 else 200000))
    if r['name'].startswith('cac'): kw['connect_at_claim'] = 1
    m = M(**kw).run().summary()
    print(f"{r['name']:20s} | {att:4.2f} {m['att_s_ex']:4.2f} | {ok:5.1f} {m['ok_min_ex']:4.1f} | {100*nok/max(nt-ncut,1):3.0f} {100*m['N_ok']:3.0f}"
          f" | {100*rf/max(cl,1):3.0f} {100*m['refuse']:3.0f}  | {reg} {m['reg']:.2f} | {100*nodt:3.0f} {100*m['nodt']:3.0f}"
          f" | {notr:2d} {100*m['notrunk']:3.0f}% | {r.get('carried',{}).get('erlangs')} {m['carried_E']:.2f}"
          f"   (RTL: {int(o.get('total',0))} calls, {cl} claims, T={T:.0f}s)")
