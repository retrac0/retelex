#!/usr/bin/env python3
"""runs_json.py LOG... -- the StructuredOutput 'runs' entries (cap2)."""
import sys, json, os
sys.path.insert(0, os.path.dirname(__file__))
from parse import parse
out = []
for p in sys.argv[1:]:
    r = parse(p); k = r['knobs']; run = r.get('run', {}); o = r.get('outcome', {})
    T = int(run.get('traffic_ms', 1)) / 1000.0
    topo = 'tb_load2 (A 2 2 = B 2 3, 8-ch local trunk, 48 lines each)' if 'l2b' not in r['name'] else 'tb_load2b (two baseband ties 11,12; 48 lines each)'
    if r['name'].startswith('s1'): topo += ', SCALE1 real timers'
    if r['name'].startswith('cac'): topo += ', FIX connect-at-claim (cap2/fix_cac/net_unit.v)'
    ex = r['ex']
    att = {x: float(d.get('attempts', {}).get('per_s', 0)) for x, d in ex.items()}
    cl = {x: (int(d.get('unit', {}).get('claims', 0)), int(d.get('unit', {}).get('att_take', 0)), int(d.get('unit', {}).get('att_refuse', 0))) for x, d in ex.items()}
    reg = {x: d.get('exchange', {}).get('reg_occ') for x, d in ex.items()}
    link = {x: d.get('link', {}).get('busy_mean') for x, d in ex.items()}
    oN = r.get('outcome_N', {}); oL = r.get('outcome_L', {})
    okx = {x: int(d.get('attempts', {}).get('OK', 0)) for x, d in ex.items()}
    other = (f"NODT={o.get('NODT')} CUT={o.get('CUT')} NOANS={o.get('NOANS')} JOINED={o.get('JOINED')} NOSPEECH={o.get('NOSPEECH')} "
             f"| N: {' '.join(a+'='+b for a,b in oN.items() if b!='0' and a!='kind')} | L: {' '.join(a+'='+b for a,b in oL.items() if b!='0' and a!='kind')} "
             f"| why {' '.join(a+'='+b for a,b in r.get('why',{}).items())} "
             f"| OK/min/ex {' '.join(f'{x}={okx[x]/T*60:.1f}' for x in sorted(okx))} "
             f"| claims(take/refuse) {' '.join(f'{x}={cl[x][0]}({cl[x][1]}/{cl[x][2]})' for x in sorted(cl))} "
             f"| reg_occ {' '.join(f'{x}={reg[x]}' for x in sorted(reg))} | trunks busy_mean {' '.join(f'{x}={link[x]}' for x in sorted(link))} "
             f"| carried {r.get('carried',{}).get('erlangs')} E | dt mean {r.get('dialtone_delay',{}).get('mean')} p99 {r.get('dialtone_delay',{}).get('p99')} ms "
             f"| inv {r.get('inv',{}).get('pass')}/{int(r.get('inv',{}).get('pass',0))+int(r.get('inv',{}).get('fail',0))} PASS")
    sf = r.get('safety', {})
    if int(sf.get('stuck', 0)): other += f" | {sf.get('stuck')} watchdog STUCK line (marker never idle 7.5 s at overload), ended by STUCK-END"
    if int(o.get('NOSPEECH', 0)): other += " | NOSPEECH = harness artefact (talk 14-18 ms)"
    s = r.get('safety', {})
    out.append(dict(name=r['name'], topology=topo,
        knobs=' '.join(f'+{a}={k[a]}' for a in ('seed','dur_ms','idle_ms','pnet','dest_mode','orig_x') if a in k) + (' scale=' + str(run.get('scale'))),
        offered=f"idle {k.get('idle_ms')} ms mean on 48 lines/ex, pnet {int(k.get('pnet',0))/10:.0f}%: attempts/s " + ' '.join(f'{x}={att[x]:.2f}' for x in sorted(att)),
        attempts=int(o.get('total', 0)), connected=int(o.get('OK', 0)), wrong_number=int(o.get('WRONG', 0)) + int(s.get('wrongring', 0)),
        stuck_at_end=int(r.get('inv', {}).get('fail', 0)), log=os.path.abspath(p),
        abandoned=int(o.get('ABANDON', 0)), busy=int(o.get('BUSY', 0)), cannot_complete=int(o.get('NOGO', 0)),
        sim_s=int(run.get('sim_ms', 0)) / 1000.0, wall_s=round(r.get('walltime') or 0), other=other))
print(json.dumps(out, indent=1))
