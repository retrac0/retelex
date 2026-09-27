#!/usr/bin/env python3
"""runs_json.py -- one JSON object a run for the final report."""
import sys, re, json
TOPO = {'tb_load2': 'tb_load2: A 2 2 - B 2 3, 8-ch local trunk, 48 lines each',
        'tb_load3': 'tb_load3: chain A 2 2 - B 2 3 - C 2 4, two 8-ch local trunks, 48/40/48 lines'}
out = []
for name, offered in [l.split('|', 1) for l in open(sys.argv[1]).read().strip().split('\n')]:
    p = f'{name}.log'
    knobs = {}; o = {}; wall = sim = calls = None; inv = None; safety = {}; build = ''
    for l in open(p, errors='replace'):
        if l.startswith('KNOB '):
            k = l.split()[1]
            if k.startswith('scale='):
                build = 'scale=' + k.split('=')[1]
            elif '=' in k: knobs[k.split('=')[0]] = k.split('=', 1)[1]
        if l.startswith('SUMMARY outcome total'):
            o = dict(x.split('=') for x in l.split()[2:])
        if l.startswith('SUMMARY run'):
            d = dict(x.split('=') for x in l.split()[2:] if '=' in x); sim = int(d['sim_ms']) / 1000; calls = int(d['calls'])
        if l.startswith('SUMMARY safety'):
            safety = dict(x.split('=') for x in l.split()[2:])
        m = re.search(r'walltime ([\d.]+)', l)
        if m: wall = float(m.group(1))
        if l.startswith('INVARIANT TOTAL'): inv = l.split()[2:]
    top = 'tb_load3' if 'l3' in name else 'tb_load2'
    keys = ['seed', 'dur_ms', 'idle_ms', 'switch_ms', 'idle2_ms', 'switch_redraw', 'pnet', 'dest_mode', 'hot', 'bad_e', 'bad_b', 'abandon', 'ab_dt',
            'trunc_pm', 'trunc_nd', 'own_pm', 'netlines', 'net_hi', 'netidle_ms', 'burst_ms', 'burst_every_ms', 'dt_ms']
    dflt = {'switch_ms': '0', 'switch_redraw': '0', 'dest_mode': '0', 'hot': '-', 'bad_e': '2', 'bad_b': '7', 'abandon': '0', 'ab_dt': '0', 'trunc_pm': '0',
            'trunc_nd': '1', 'own_pm': '0', 'netlines': '-1', 'net_hi': '0', 'netidle_ms': '-1', 'burst_ms': '0', 'burst_every_ms': '0', 'idle2_ms': None}
    ks = ' '.join(f'+{k}={knobs[k]}' for k in keys if k in knobs and knobs[k] != dflt.get(k, '#') and not (k == 'idle2_ms' and knobs.get('switch_ms', '0') == '0'))
    other = ' '.join(f'{k}={v}' for k, v in o.items() if k not in ('OK', 'BUSY', 'NOGO', 'ABANDON', 'WRONG') and v != '0')
    out.append(dict(name=name, topology=TOPO[top] + (' (SCALE1 real timers)' if 'scale=1' in build else ' (scale 8)'),
                    knobs=f'{build} NMON=2 NRES=2 ' + ks, offered=offered.strip(), attempts=calls,
                    connected=int(o.get('OK', 0)), wrong_number=int(o.get('WRONG', 0)) + int(o.get('JOINED', 0)) + int(o.get('XTALK', 0)),
                    stuck_at_end=0 if inv and inv[1] == 'fail=0' else -1, log=f'/home/joel/telco/newimpl/build/flood/work/load/overload/{p}',
                    abandoned=int(o.get('ABANDON', 0)), busy=int(o.get('BUSY', 0)), cannot_complete=int(o.get('NOGO', 0)),
                    other=other + f"; invariants {' '.join(inv or [])}; phantom={safety.get('phantom')} wrongring={safety.get('wrongring')} idlehear={safety.get('idlehear')}",
                    sim_s=sim, wall_s=wall))
json.dump(out, open('runs.json', 'w'), indent=1)
print(len(out), 'runs')
