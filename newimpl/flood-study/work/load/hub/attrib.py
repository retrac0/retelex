#!/usr/bin/env python3
"""attrib.py LOG -- for every network call through the hub (A), follow it:
caller -> its seizure at A (SEIZE, src = the caller) -> the forward (FWD in=) ->
the seizure at the called exchange (SEIZE from=A<leg>) -> the claim there ->
the resolver (RES) -> the origin's OCLAIM; and say where it stopped.
Star topology only (A = hub)."""
import sys, re, collections
fn = sys.argv[1]
L = open(fn, errors='replace').read().splitlines()
hub = []
for l in L:
    m = re.match(r'HUB t=(\S+) ex=(\S) (\S+) (.*)', l)
    if m: hub.append((float(m.group(1)), m.group(2), m.group(3), m.group(4), l))
calls = []
for l in L:
    if not l.startswith('CALL '): continue
    d = dict(re.findall(r'(\w+)=(\S+)', l))
    calls.append(d)
def ms(v): return None if v in ('-', None) else int(v)
res = collections.Counter(); ex = collections.defaultdict(list)
for c in calls:
    if c.get('kind') not in ('N', 'BAD'): continue
    caller = c['from']; X = caller[0]; key = ms(c.get('key'))
    out = c['out'] + '/' + c['why']
    if key is None: res[(out, 'no-key')] += 1; continue
    if X == 'A':
        to = c['to']; Y = to[0]
        sy = [g for g in hub if g[1] == Y and g[2] == 'SEIZE' and key - 5 <= g[0] <= key + 400
              and re.search(r'from=A\d\d\[src=' + caller + r' ', g[3])]
        if c['kind'] == 'BAD': st = 'from-hub:bad'
        elif not sy: st = 'from-hub:owner-no-seize'
        elif 'mon=0' in sy[0][3]: st = 'from-hub:owner-NOMON'
        else: st = 'from-hub:owner-seized'
        res[(out, st)] += 1
        if c['out'] != 'OK': ex[(out, st)].append(c.get('id'))
        continue
    # the seizure at A whose far end listens to the caller
    s = [h for h in hub if h[1] == 'A' and h[2] == 'SEIZE' and key - 5 <= h[0] <= key + 400
         and re.search(r'from=' + X + r'\d\d\[src=' + caller + r' ', h[3])]
    if not s: st = 'A:no-seize'
    else:
        h = s[0]; inp = re.search(r'port=(A\d\d)', h[3]).group(1)
        fw = re.search(r'fwd=\s*(\S+)', h[3]).group(1)
        if c['kind'] == 'N' and c['to'][0] == 'A':
            if 'mon=0' in h[3]: st = 'hub:NOMON'
            else:
                cl = [k for k in hub if k[1] == 'A' and k[2] == 'CLAIM' and k[0] >= h[0] and ('port=' + inp + ' ') in k[3] and k[0] <= h[0] + 3000]
                st = 'hub:claimed' if cl else 'hub:no-claim'
        elif fw != 'ok': st = 'A:' + fw
        else:
            f = [g for g in hub if g[1] == 'A' and g[2] == 'FWD' and g[0] >= h[0] and g[0] <= h[0] + 400 and ('in=' + inp + ' ') in g[3]]
            if not f: st = 'A:fwd-never-written(nofwd-empty/cancel)'
            else:
                legs = re.findall(r' ([NSEW]):(A\d\d)', f[0][3])
                to = c['to']; Y = to[0] if to[0] != 'e' else None
                if c['kind'] == 'BAD' or Y is None: st = 'bad-code(fwd legs=%d)' % len(legs)
                elif Y == 'A':
                    if 'mon=0' in h[3]: st = 'hub:NOMON'
                    else:
                        cl = [k for k in hub if k[1] == 'A' and k[2] == 'CLAIM' and k[0] >= h[0] and ('port=' + inp + ' ') in k[3] and k[0] <= h[0] + 3000]
                        st = 'hub:claimed' if cl else 'hub:no-claim'
                else:
                    # the seizure at Y whose far end is one of the legs
                    sy = [g for g in hub if g[1] == Y and g[2] == 'SEIZE' and f[0][0] <= g[0] <= f[0][0] + 400
                          and any(('from=' + lg[1] + '[') in g[3] for lg in legs)]
                    if not sy: st = 'owner:no-seize(legs=%d)' % len(legs)
                    else:
                        g = sy[0]
                        if 'mon=0' in g[3]: st = 'owner:NOMON'
                        else:
                            yp = re.search(r'port=(' + Y + r'\d\d)', g[3]).group(1)
                            cl = [k for k in hub if k[1] == Y and k[2] == 'CLAIM' and k[0] >= g[0] and ('port=' + yp + ' ') in k[3] and k[0] <= g[0] + 3000]
                            if not cl: st = 'owner:no-claim'
                            else:
                                r = [k for k in hub if k[1] == 'A' and k[2] == 'RES' and k[0] >= f[0][0] and ('in=' + inp + ' ') in k[3] and k[0] <= cl[0][0] + 100]
                                if not r: st = 'claimed:no-RES'
                                elif 'GONE' in r[0][3]: st = 'claimed:RES-GONE'
                                elif 'NOCLAIM' in r[0][3]: st = 'claimed:RES-NOCLAIM'
                                else: st = 'claimed:resolved'
    res[(out, st)] += 1
    if not c['out'] in ('OK',): ex[(out, st)].append(c.get('id'))
for k, v in sorted(res.items()): print('%-28s %-45s %d' % (k[0], k[1], v))
print('examples (call ids):')
for k, v in sorted(ex.items()): print('  ', k, v[:8])
