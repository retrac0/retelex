#!/usr/bin/env python3
"""win.py T0 T1 LOG -- traffic in a time window: attempts lifted, OK by END time (completions/s),
carried erlangs (answered talk overlapping the window), network claims seen (N calls with key in window)."""
import sys
t0, t1, p = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
lift = okend = 0; talk = 0; kinds = {}
for line in open(p, errors='replace'):
    if not line.startswith('CALL '): continue
    d = dict(x.split('=', 1) for x in line.split()[1:] if '=' in x)
    n = lambda k: int(d[k]) if d.get(k, '-') not in ('-', '') else None
    if n('lift') is not None and t0 <= n('lift') < t1:
        lift += 1; kinds[(d['kind'], d['out'])] = kinds.get((d['kind'], d['out']), 0) + 1
    if d['out'] in ('OK', 'CUT') and n('ans') is not None and t0 <= n('alert') < t1: okend += 1
    if n('ans') is not None and n('end') is not None:
        a, e = max(n('ans'), t0), min(n('end'), t1)
        if e > a: talk += e - a
T = (t1 - t0) / 1000
print(f'{p} [{t0},{t1}) ms: lifts {lift} ({lift/T/2:.2f}/s/exch), connected+answered {okend} ({okend/T:.2f}/s both, by alert time), carried {talk/(t1-t0):.2f} E')
print('   by lift:', ' '.join(f'{k}{o}={v}' for (k, o), v in sorted(kinds.items())))
