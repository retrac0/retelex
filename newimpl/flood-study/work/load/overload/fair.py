#!/usr/bin/env python3
"""fair.py -- dial-tone fairness by port block over a lift-time window.
usage: fair.py T0 T1 LOG [LOG ...]   (calls lifted in [T0,T1) ms; CUT calls skipped)
Per block of eight ports (2x..7x), both exchanges pooled: attempts, got dial tone,
NODT share, mean wait of those served, and OK share."""
import sys, collections
t0, t1 = int(sys.argv[1]), int(sys.argv[2])
blk = collections.defaultdict(lambda: [0, 0, 0, 0, []])
for p in sys.argv[3:]:
    for line in open(p, errors='replace'):
        if not line.startswith('CALL '): continue
        d = dict(x.split('=', 1) for x in line.split()[1:] if '=' in x)
        try: lift = int(d['lift'])
        except ValueError: continue
        if not (t0 <= lift < t1) or d['out'] == 'CUT': continue
        b = blk[d['from'][1]]
        b[0] += 1
        if d['dt'] != '-': b[1] += 1; b[4].append(int(d['dt']) - lift)
        if d['out'] == 'NODT': b[2] += 1
        if d['out'] == 'OK': b[3] += 1
tot = [0, 0, 0, 0]
print(f'window {t0}-{t1} ms  logs: {" ".join(sys.argv[3:])}')
print('  block  att  served  NODT%  wait_mean  OK%')
for k in sorted(blk):
    a, s, n, o, w = blk[k]
    for i, v in enumerate((a, s, n, o)): tot[i] += v
    print(f'  {k}x    {a:4d}  {s:5d}  {100*n/a:5.0f}  {sum(w)/len(w) if w else 0:8.0f}  {100*o/a:4.0f}')
a, s, n, o = tot
print(f'  all    {a:4d}  {s:5d}  {100*n/max(1,a):5.0f}  {"":8s}  {100*o/max(1,a):4.0f}')
