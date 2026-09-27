#!/usr/bin/env python3
"""cross.py LOG -- crossing floods at B: for each pair of B classifications from opposite
sides within 100 ms, the gap between them and what happened to the second."""
import re, sys

for path in sys.argv[1:]:
    seiz = []
    for line in open(path, errors='replace'):
        if line.startswith('TP ') and ' ex=B SEIZE ' in line:
            d = dict(re.findall(r'(\w+)=(\S+)', line))
            seiz.append((float(d['t']), d['p'], d['fwd'], d['fst'], d['rsb'], float(d['hop'])))
    print(path, 'B seizures:', len(seiz))
    rows = []
    for i in range(1, len(seiz)):
        t0, p0 = seiz[i - 1][0], seiz[i - 1][1]
        t1, p1, fwd, fst, rsb, hop = seiz[i]
        if t1 - t0 < 100.0:
            # the upstream write times: classification minus hop
            gap_cls = t1 - t0
            gap_wr = (t1 - hop) - (t0 - seiz[i - 1][5])
            rows.append((gap_wr, gap_cls, fwd, fst, rsb, p0, p1, t1))
    for r in sorted(rows):
        print('  upstream-write gap %6.2f ms  classification gap %6.2f ms  second: %-8s fst=%s rsb=%s  (%s then %s at %.1f)' % r)
    lost = sum(1 for r in rows if r[2] != 'yes')
    print('  pairs within 100 ms: %d, second lost: %d' % (len(rows), lost))
