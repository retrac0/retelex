#!/usr/bin/env python3
"""parse.py LOG... -- the compact result of a hub run: outcome, why, safety,
unit and link lines, HUBSUM, and counts of the HUB event kinds."""
import sys, re, collections
for fn in sys.argv[1:]:
    L = open(fn, errors='replace').read().splitlines()
    print('=====', fn)
    ev = collections.Counter(); flags = collections.Counter()
    for l in L:
        if l.startswith('HUB '):
            m = re.match(r'HUB t=\S+ ex=(\S) (\S+)', l)
            if m: ev[m.group(1) + ':' + m.group(2)] += 1
            for f in ('PHANTOMSEIZE', 'NOCLAIM', 'SUSPECT', 'LATE', 'BUSY-FWDR', 'BUSY-NORES', 'GONE', 'HERE'):
                if f in l: flags[f] += 1
            m = re.search(r'by=(\S+)', l)
            if m: flags['by=' + m.group(1)] += 1
    for l in L:
        if l.startswith(('SUMMARY run', 'SUMMARY outcome', 'SUMMARY why', 'SUMMARY safety', 'SUMMARY carried',
                         'SUMMARY dialtone', 'SUMMARY postdial', 'SUMMARY exchange', 'SUMMARY link', 'SUMMARY unit',
                         'SUMMARY nogo_written', 'SUMMARY attempts', 'INVARIANT FAIL', 'INVARIANT TOTAL', 'HUBSUM',
                         'STUCK', 'WRONGRING', 'PHANTOM ', 'IDLEHEAR', 'DRAINRING', 'TIMEOUT', 'WARN', '%Error', 'START', 'END')):
            print(l[:600])
    print('HUB events:', dict(sorted(ev.items())))
    print('HUB flags :', dict(sorted(flags.items())))
    c = collections.Counter()
    for l in L:
        if l.startswith('CALL '):
            m = re.search(r'kind=(\S+).*out=(\S+) why=(\S+)', l)
            if m: c[(m.group(1), m.group(2), m.group(3))] += 1
    print('CALL kind/out/why:', dict(sorted(c.items())))
