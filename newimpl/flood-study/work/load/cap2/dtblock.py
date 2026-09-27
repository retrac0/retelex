#!/usr/bin/env python3
"""dtblock.py LOG... -- dial-tone delay (dt - lift) and NODT by the caller's block (20-27 = block 2 ...)."""
import sys, collections
tot = collections.defaultdict(list); nodt = collections.Counter(); att = collections.Counter()
for p in sys.argv[1:]:
    for line in open(p, errors='replace'):
        if not line.startswith('CALL '): continue
        d = dict(t.split('=', 1) for t in line.split()[1:] if '=' in t)
        fr = d['from']; blk = fr[0] + fr[1]
        att[blk] += 1
        if d.get('out') == 'NODT': nodt[blk] += 1
        if d.get('dt', '-') != '-' and d.get('lift', '-') != '-':
            tot[blk].append(int(d['dt']) - int(d['lift']))
for b in sorted(att):
    xs = sorted(tot[b])
    m = sum(xs) / len(xs) if xs else 0
    p90 = xs[int(len(xs) * .9)] if xs else 0
    print(f"{b}: att={att[b]:4d} served={len(xs):4d} nodt={nodt[b]:3d} ({100*nodt[b]/att[b]:4.1f}%) dt_mean={m:7.1f} p90={p90}")
