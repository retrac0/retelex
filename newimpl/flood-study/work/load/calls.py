#!/usr/bin/env python3
"""calls.py -- aggregate the load harness's CALL / SUMMARY / INVARIANT lines.

usage: calls.py LOG [LOG ...]          one block per log, then a total
       calls.py -c 'out=WRONG' LOG     print the CALL lines matching key=value(s)

Per log: outcome counts by kind (L, N, BAD), the reasons seen (why=), dial-tone
and post-dial delay percentiles recomputed from the CALL lines, the safety
lines (WRONGRING, PHANTOM, DRAINRING, STUCK) and every INVARIANT FAIL.
"""
import sys, re, collections

def calls(path):
    for line in open(path, errors='replace'):
        if line.startswith('CALL '):
            d = dict(kv.split('=', 1) for kv in line.split()[1:] if '=' in kv)
            yield d

def num(v):
    try: return int(v)
    except (TypeError, ValueError): return None

def pct(xs, p):
    if not xs: return '-'
    xs = sorted(xs); return xs[min(len(xs) - 1, (len(xs) * p + 99) // 100 - 1)]

def report(paths, title):
    by = collections.Counter(); why = collections.Counter()
    dt, pdd, pdn = [], [], []
    n = 0
    for p in paths:
        for c in calls(p):
            n += 1
            by[(c.get('kind'), c.get('out'))] += 1
            if c.get('out') not in ('OK', None) and c.get('why', '-') != '-':
                why[c['why']] += 1
            lift, t_dt, last = num(c.get('lift')), num(c.get('dt')), num(c.get('last'))
            alert, tone = num(c.get('alert')), num(c.get('tone'))
            if lift is not None and t_dt is not None: dt.append(t_dt - lift)
            if last is not None and alert is not None and alert >= last: pdd.append(alert - last)
            if last is not None and tone is not None and c.get('out') in ('NOGO', 'BUSY'):
                pdn.append(max(0, tone - last))
    print(f'== {title}: {n} calls')
    kinds = sorted({k for k, _ in by})
    outs = sorted({o for _, o in by})
    for k in kinds:
        print(f'   {k:4s}', ' '.join(f'{o}={by[(k, o)]}' for o in outs if by[(k, o)]))
    if why: print('   why ', ' '.join(f'{w}={c}' for w, c in why.most_common()))
    for name, xs in (('dialtone', dt), ('pdd_alert', pdd), ('pdd_nogo', pdn)):
        if xs:
            print(f'   {name:9s} n={len(xs)} mean={sum(xs)/len(xs):.1f} p50={pct(xs,50)} '
                  f'p99={pct(xs,99)} max={max(xs)}')

def events(path):
    for line in open(path, errors='replace'):
        if re.match(r'(WRONGRING|PHANTOM|DRAINRING|STUCK|INVARIANT FAIL|SELFTEST FAIL|TIMEOUT|WARN|%Error|%Warning)', line):
            print('   ' + line.rstrip())

def main(argv):
    if len(argv) > 2 and argv[1] == '-c':
        want = dict(kv.split('=', 1) for kv in argv[2].split(','))
        for p in argv[3:]:
            for line in open(p, errors='replace'):
                if line.startswith('CALL '):
                    d = dict(kv.split('=', 1) for kv in line.split()[1:] if '=' in kv)
                    if all(d.get(k) == v for k, v in want.items()):
                        print(line.rstrip())
        return
    for p in argv[1:]:
        report([p], p)
        events(p)
    if len(argv) > 2:
        report(argv[1:], 'TOTAL')

if __name__ == '__main__':
    main(sys.argv)
