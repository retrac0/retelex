#!/usr/bin/env python3
"""jam.py T0 T1 LOG... -- local-only lines (ports 50-77, line index >= 24) vs network-capable lines
(20-47) over calls lifted in [T0,T1): attempts, served, NODT%, dial-tone wait mean/p90 of the served,
OK% (CUT excluded), by kind."""
import sys, collections
t0, t1 = int(sys.argv[1]), int(sys.argv[2])
for p in sys.argv[3:]:
    g = collections.defaultdict(lambda: [0, 0, 0, 0, []])
    for line in open(p, errors='replace'):
        if not line.startswith('CALL '): continue
        d = dict(x.split('=', 1) for x in line.split()[1:] if '=' in x)
        lift = int(d['lift'])
        if not (t0 <= lift < t1) or d['out'] == 'CUT': continue
        cls = 'loc-lines(50-77)' if d['from'][1] in '567' else 'net-lines(20-47)'
        k = (cls, d['kind'])
        r = g[k]; r[0] += 1
        if d['dt'] != '-': r[1] += 1; r[4].append(int(d['dt']) - lift)
        if d['out'] == 'NODT': r[2] += 1
        if d['out'] == 'OK': r[3] += 1
    print(f'== {p} lifts in [{t0},{t1})')
    for k in sorted(g):
        a, s, n, o, w = g[k]; w.sort()
        print(f'   {k[0]:17s} kind={k[1]:3s} att={a:3d} served={s:3d} NODT={100*n/a:3.0f}% '
              f'dt_mean={sum(w)/len(w) if w else 0:6.0f} dt_p90={w[int(0.9*(len(w)-1))] if w else 0:5d} OK={100*o/a:3.0f}%')
