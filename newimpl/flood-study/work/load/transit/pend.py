#!/usr/bin/env python3
"""pend.py LOG -- with the pending-forward fix: for each B seizure that was not forwarded at once,
was it forwarded later (a FWD with in=that port within 60 ms), and how late?"""
import re, sys

for path in sys.argv[1:]:
    ev = []
    for line in open(path, errors='replace'):
        if line.startswith('TP ') and ' ex=B ' in line and (' SEIZE ' in line or ' FWD ' in line):
            d = dict(re.findall(r'(\w+)=(\S+)', line))
            d['ev'] = line.split()[4]
            d['t'] = float(d['t'])
            ev.append(d)
    n = late = never = 0
    delays = []
    for i, e in enumerate(ev):
        if e['ev'] == 'SEIZE' and e['fwd'] != 'yes':
            n += 1
            f = next((g for g in ev[i + 1:] if g['ev'] == 'FWD' and g['in'] == e['p'] and g['t'] - e['t'] < 60.0), None)
            if f is None:
                never += 1
                print('  NEVER forwarded: %s at %.1f (%s)' % (e['p'], e['t'], e['fwd']))
            else:
                late += 1
                delays.append(f['t'] - e['t'])
    print('%s: B seizures not forwarded at once: %d; forwarded late: %d (after %s ms); never: %d'
          % (path, n, late, ', '.join('%.1f' % x for x in delays), never))
