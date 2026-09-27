#!/usr/bin/env python3
# summ.py run_X.log ... -- one line a trial that is not plain OK, plus totals
import sys, re
for fn in sys.argv[1:]:
    try: L = open(fn).read().splitlines()
    except Exception as e: print(fn, e); continue
    print('==', fn)
    for i, l in enumerate(L):
        if l.startswith('  REF') or l.startswith('  --') or 'trials:' in l or l.startswith('  F12') or l.startswith('  F11') or l.startswith('rc='):
            print('  ', l.strip()[:230])
        elif l.startswith('T fam') and (' LEAK' in l or 'PHANTOM' in l or 'LATE' in l):
            m = re.match(r'T fam=(\S+) k=(\S+) act=(\S+) d=(\S+)\s+hangA=(\S+) hangB=(\S+)\s+(\S+)\s+idle\+(\S+)', l)
            tail = ' '.join(x for x in ('LEAK','PHANTOM','LATE') if x in l)
            print('   T', m.groups() if m else l[:120], tail)
            # the first dump after a LEAK
            if ' LEAK' in l:
                for j in range(i+1, min(i+24, len(L))):
                    s = L[j]
                    if ('bsy=1' in s or 'BUSY=1' in s or s.strip().startswith(('A:', 'X:', 'B:', 'mon cells', 'LIFT'))) :
                        print('      ', s.strip()[:200])
                    if 'after the lifts' in s: break
        elif 'rb ticks' in l and '(blips only)' not in l:
            print('      ', l.strip())
