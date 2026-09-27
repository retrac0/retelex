#!/usr/bin/env python3
"""refuse.py LOG... -- who held the far register when a claim was refused?

For every network call whose flood was claimed by the owner and which ended NOGO (F_REFUSE, or
the harness's unattributed '-'), take the owner's CLAIM time t and list what occupied the owner's
one register then, from the CALL lines:
  local  a caller of that exchange between its dial tone and its last digit (+40 ms)
  orig   a caller of that exchange dialling the network (dial tone .. last digit + 40)
  inc    another network call being completed there (its claim .. its last digit + 40)
  clear  a call touching that exchange that ENDED in the last 120 ms (the second party to hang up
         is taken into the register as a caller: lag + CLR)
  none   nothing visible
"""
import sys, collections
import tr_an


def num(v):
    try: return float(v)
    except (TypeError, ValueError): return None


for path in sys.argv[1:]:
    A = tr_an.analyse(path)
    calls = A['calls']
    # claim time per network call (owner's CLAIM event on the flood tree)
    def claim_time(c):
        fl = c.get('_flood')
        if not fl: return None
        tx = c['to'][0]
        def walk(nodes):
            for nd in nodes:
                if nd['at'][0] == tx and nd['claim'] is not None: return nd['claim']['t']
                r = walk(nd['legs'])
                if r is not None: return r
            return None
        return walk(fl['tree'])
    ct = {}
    for c in calls:
        if c.get('kind') == 'N': ct[c['id']] = claim_time(c)
    tally = collections.Counter()
    rows = []
    for c in calls:
        if c.get('kind') != 'N' or c.get('out') != 'NOGO' or c.get('why') not in ('F_REFUSE', '-'): continue
        t = ct.get(c['id'])
        if t is None: continue
        X = c['to'][0]
        why = []
        for d in calls:
            if d is c: continue
            dt, last, end = num(d.get('dt')), num(d.get('last')), num(d.get('end'))
            if d['from'][0] == X and dt is not None and dt <= t <= (last if last else (num(d.get('rel')) or 0)) + 40:
                why.append(('orig' if d.get('kind') == 'N' else 'local') + ':' + d['from'])
            if d.get('kind') == 'N' and d['to'][0] == X and ct.get(d['id']) is not None and \
                    ct[d['id']] < t <= (last or 0) + 40:
                why.append('inc:' + d['from'])
            if end is not None and (d['from'][0] == X or d['to'][0] == X) and 0 <= t - end <= 120 and \
                    d.get('out') in ('OK', 'CUT', 'NOANS'):
                why.append('clear:%s>%s(%.0f ms ago)' % (d['from'], d['to'], t - end))
        kinds = sorted(set(w.split(':')[0] for w in why)) or ['none']
        tally['+'.join(kinds)] += 1
        rows.append((c['id'], c['from'], c['to'], t, why))
    print(path, 'refused claims:', sum(tally.values()), dict(tally.most_common()))
    for r in rows:
        if 'clear' in ' '.join(r[4]) or not r[4]:
            print('   id=%s %s>%s claim at %.1f: %s' % (r[0], r[1], r[2], r[3], ' '.join(r[4]) or 'NOTHING VISIBLE'))
