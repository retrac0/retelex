#!/usr/bin/env python3
"""resocc.py LOG -- A's resolvers from the HUB lines: per leaf, the fraction of the
traffic period a resolver held one of its floods; the fraction of A's seizures not
forwarded and why; and the independent-sources prediction of the no-resolver loss
(a flood from leaf k is refused when both other leaves hold one: p_i * p_j)."""
import sys, re, collections
L = open(sys.argv[1], errors='replace').read().splitlines()
t0 = t1 = None
for l in L:
    m = re.match(r'START t=(\d+) traffic until (\d+)', l)
    if m: t0, t1 = int(m.group(1)), int(m.group(2))
seize = []; fwd = {}; open_ = {}; hold = collections.defaultdict(float); resv = []
for l in L:
    m = re.match(r'HUB t=(\S+) ex=A (\S+) (.*)', l)
    if not m: continue
    t = float(m.group(1)); k = m.group(2); rest = m.group(3)
    if k == 'SEIZE':
        src = re.search(r'from=(\S)', rest).group(1)
        fw = re.search(r'fwd=\s*(\S+)', rest).group(1)
        inp = re.search(r'port=(A\d\d)', rest).group(1)
        seize.append((t, src, fw, inp)); fwd[inp] = src
    elif k == 'FWD':
        inp = re.search(r'in=(A\d\d)', rest).group(1); r = re.search(r'res=(\d)', rest).group(1)
        open_[r] = (t, fwd.get(inp, '?'))
    elif k == 'RES':
        r = re.search(r'r=(\d)', rest).group(1)
        if r in open_:
            ts, src = open_.pop(r); resv.append((ts, t, src))
    elif k == 'CLAIM' and 'HERE' in rest:
        for r in re.findall(r'HERE r=(\d)', rest):
            if r in open_:
                ts, src = open_.pop(r); resv.append((ts, t, src))
T = (t1 - t0) if t0 is not None else 1
for ts, te, src in resv:
    a, b = max(ts, t0), min(te, t1)
    if b > a: hold[src] += b - a
p = {s: hold[s] / T for s in hold}
c = collections.Counter((s[1], s[2]) for s in seize if t0 <= s[0] <= t1)
tot = collections.Counter(s[1] for s in seize if t0 <= s[0] <= t1)
print('traffic ms', T, ' resolver-held fraction by source leaf:', {k: round(v, 3) for k, v in sorted(p.items())})
for s in sorted(tot):
    others = [p.get(o, 0) for o in 'BCD' if o != s]
    pred = others[0] * others[1] if len(others) == 2 else 0
    print('from %s: seizures %d  %s  nores %.3f  fwdr %.3f  predicted nores (indep) %.3f' % (
        s, tot[s], dict((k[1], v) for k, v in c.items() if k[0] == s),
        c[(s, 'BUSY-NORES')] / tot[s], c[(s, 'BUSY-FWDR')] / tot[s], pred))
