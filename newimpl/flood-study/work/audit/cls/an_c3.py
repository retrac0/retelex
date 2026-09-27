#!/usr/bin/env python3
"""an_c3.py -- aggregate tb_cls3 sc10 load logs (SZ / LC / SUMMARY / HIST lines).

usage: an_c3.py LOG [LOG ...]
Per log: seizures, rise->hold percentiles overall and by group (W = ports 10-17,
low; E = 40-47, high), late pickups (hold after the first break), cells armed
after the first break, re-classifications, unholds of live seizures, wrong
claims, and the exposure of the 3 2 callers by first-break time.
"""
import sys, re, collections

def pct(xs, p):
    if not xs: return float('nan')
    xs = sorted(xs); k = min(len(xs) - 1, max(0, int(round(p / 100.0 * (len(xs) - 1)))))
    return xs[k]

for path in sys.argv[1:]:
    sz = []
    lc = []
    other = []
    for line in open(path, errors='replace'):
        if line.startswith('SZ '):
            d = dict(kv.split('=', 1) for kv in line.split()[1:] if '=' in kv)
            for k in list(d):
                try: d[k] = float(d[k])
                except ValueError: pass
            sz.append(d)
        elif line.startswith('LC '):
            d = dict(kv.split('=', 1) for kv in line.split()[1:] if '=' in kv)
            lc.append(d)
        elif line.startswith(('SUMMARY', 'HIST', '  WATCHDOG')) or 'WRONG' in line or 'RECLASS' in line \
                or 'TAKES TRUNK' in line or 'ORIGIN takes' in line or 'RESOLVER' in line or 'FAIL' in line:
            other.append(line.rstrip())
    print('=' * 100)
    print(path, ' seizures', len(sz), ' lifts', len(lc))
    held = [d for d in sz if d['hold'] >= 0]
    rh = [d['hold'] for d in held]
    for name, grp in (('all', held), ('W', [d for d in held if d['dir'] == 'W']), ('E', [d for d in held if d['dir'] == 'E'])):
        xs = [d['hold'] for d in grp]
        if xs:
            print('  rise->hold %-3s n=%4d  p50 %6.1f  p90 %6.1f  p99 %6.1f  max %6.1f  >19ms %4d  >40ms %4d  >100ms %4d' % (
                name, len(xs), pct(xs, 50), pct(xs, 90), pct(xs, 99), max(xs),
                sum(1 for x in xs if x > 19), sum(1 for x in xs if x > 40), sum(1 for x in xs if x > 100)))
    nh = [d for d in sz if d['hold'] < 0]
    print('  never held %d (of which dialled: %d)' % (len(nh), sum(1 for d in nh if d['e'] > 0)))
    late = [d for d in held if d['hold'] > d['t1']]
    print('  held after the first break: %d   cells armed after the first break: %d' % (
        len(late), sum(int(d['nlate']) for d in sz)))
    print('  re-held (nhold>1): %d   unholds of live seizures: %d   claims %d   WRONG %d' % (
        sum(1 for d in sz if d['nhold'] > 1), sum(int(d['nunhlive']) for d in sz),
        sum(int(d['claim']) for d in sz), sum(int(d['wrong']) for d in sz)))
    # exposure: the 3 2 callers by first-break time
    ex = [d for d in sz if d['e'] == 3 and d['b'] == 2]
    bins = [(0, 100), (100, 150), (150, 200), (200, 300), (300, 500), (500, 10000)]
    for lo, hi in bins:
        g = [d for d in ex if lo <= d['t1'] < hi]
        if g:
            print('  3 2 callers t1 %4d-%-5d n=%3d  held-late %2d  emin<3 %2d  wrong %2d' % (
                lo, hi, len(g), sum(1 for d in g if d['hold'] > d['t1']),
                sum(1 for d in g if 0 <= d['emin'] < 3), sum(int(d['wrong']) for d in g)))
    # backlog at rise vs hold delay
    bk = collections.defaultdict(list)
    for d in held: bk[int(d['back'])].append(d['hold'])
    print('  backlog at rise -> mean hold delay: ' + '  '.join('%d:%.1f(n%d)' % (b, sum(v)/len(v), len(v)) for b, v in sorted(bk.items())))
    # by port
    bp = collections.defaultdict(list)
    for d in held: bp[d['q']].append(d['hold'])
    print('  by port mean hold delay: ' + '  '.join('%s:%.1f' % (q, sum(v)/len(v)) for q, v in sorted(bp.items())))
    dts = [float(d['dt']) for d in lc if float(d['dt']) >= 0]
    if dts:
        print('  dial tone n=%d  p50 %.1f  p90 %.1f  p99 %.1f  max %.1f  none %d' % (
            len(dts), pct(dts, 50), pct(dts, 90), pct(dts, 99), max(dts), sum(1 for d in lc if float(d['dt']) < 0)))
    for o in other: print('  | ' + o)
