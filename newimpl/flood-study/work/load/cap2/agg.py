#!/usr/bin/env python3
"""agg.py LOG... -- cluster-sighting totals across runs (cap2)."""
import sys, os, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse import parse
T = collections.Counter(); st = collections.Counter(); tk = collections.Counter(); stuck = []
for p in sys.argv[1:]:
    r = parse(p)
    o = r.get('outcome', {}); s = r.get('safety', {})
    for k in ('total', 'OK', 'WRONG', 'JOINED', 'XTALK', 'NOSPEECH', 'NODT', 'NOGO', 'BUSY', 'CUT'):
        T['calls_' + k] += int(o.get(k, 0))
    for k in ('phantom', 'wrongring', 'idlehear', 'drainring', 'stuck', 'ring_anon', 'alert_nobell'):
        T['safety_' + k] += int(s.get(k, 0))
    T['inv_fail'] += int(r.get('inv', {}).get('fail', 0)); T['inv_pass'] += int(r.get('inv', {}).get('pass', 0))
    for x, d in r['ex'].items():
        u = d.get('unit', {})
        for k in ('claims', 'att_take', 'att_refuse', 'seized_in', 'nomon', 'unhold', 'nofwd_busy', 'nofwd_empty', 'n_nofwd', 'n_glare', 'floods', 'refuse_unattributed'):
            T['unit_' + k] += int(u.get(k, 0))
        T['mon_max_max'] = max(T['mon_max_max'], int(d.get('exchange', {}).get('mon_max', 0)))
        T['res_max_max'] = max(T['res_max_max'], int(d.get('exchange', {}).get('res_max', 0)))
        for k, v in d.get('c2refst', {}).items():
            if k != 'ex': st[k] += int(v)
        for k, v in d.get('c2takest', {}).items():
            if k != 'ex': tk[k] += int(v)
        c = d.get('checks', {})
        T['un_ovf'] += int(c.get('un_ovf', 0)); T['mk_ovf'] += int(c.get('mk_ovf', 0)); T['b_clash'] += int(c.get('b_clash_ticks', 0))
    for e in r.get('events', []):
        stuck.append(os.path.basename(p) + ': ' + e)
print('runs', len(sys.argv) - 1)
for k in sorted(T): print(f'  {k} = {T[k]}')
print('  refusal marker states (c2 runs):', dict(st))
print('  take marker states (c2 runs):', dict(tk))
for e in stuck: print('  EV', e)
