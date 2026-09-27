#!/usr/bin/env python3
"""regshare.py T0 T1 LOG... -- share of ORIGIN register time (dial tone -> connect/tone/hang-up) by outcome,
for callers given dial tone in [T0,T1).  Far-register time for taken claims is not included."""
import sys, collections
t0, t1 = int(sys.argv[1]), int(sys.argv[2])
for p in sys.argv[3:]:
    acc = collections.Counter(); n = collections.Counter()
    for line in open(p, errors='replace'):
        if not line.startswith('CALL '): continue
        d = dict(x.split('=', 1) for x in line.split()[1:] if '=' in x)
        if d['dt'] == '-': continue
        dt = int(d['dt'])
        if not (t0 <= dt < t1): continue
        ends = [int(d[k]) for k in ('tone', 'alert', 'rel') if d.get(k, '-') != '-']
        e = min(ends) if ends else dt
        k = f"{d['kind']}-{d['out']}"
        acc[k] += e - dt; n[k] += 1
    tot = sum(acc.values())
    print(f'== {p} dial tone in [{t0},{t1}): register-ms {tot}')
    for k, v in acc.most_common():
        print(f'   {k:12s} n={n[k]:3d} share={100*v/tot:5.1f}% mean_hold={v/n[k]:6.0f} ms')
