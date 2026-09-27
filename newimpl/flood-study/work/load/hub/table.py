#!/usr/bin/env python3
"""table.py -- one line a run from logs/*.log and runs.rc: the numbers for the report."""
import re, glob, os, json
H = '/home/joel/telco/newimpl/build/flood/work/load/hub'
rc = {}
for l in open(H + '/runs.rc'):
    m = re.match(r'\S+ (\S+) rc=(\d+) wall_s=(\d+) bin=(\S+) args=(.*)', l.strip())
    if m: rc[m.group(1)] = (int(m.group(3)), m.group(4), m.group(5))
out = []
for f in sorted(glob.glob(H + '/logs/*.log')):
    n = os.path.basename(f)[:-4]
    L = open(f, errors='replace').read()
    d = {'name': n}
    m = re.search(r'SUMMARY run scale=(\d+) seed=\d+ traffic_ms=(\d+) sim_ms=(\d+) phones=(\d+) calls=(\d+)', L)
    if not m: continue
    d['scale'] = int(m.group(1)); d['traffic_ms'] = int(m.group(2)); d['sim_s'] = int(m.group(3)) / 1000
    d['attempts'] = int(m.group(5))
    m = re.search(r'SUMMARY outcome total=\d+ (.*)', L)
    oc = dict((k, int(v)) for k, v in re.findall(r'(\w+)=(\d+)', m.group(1)))
    d.update(oc)
    m = re.search(r'SUMMARY safety (.*)', L); d['safety'] = m.group(1)
    m = re.search(r'SUMMARY why(.*)', L); d['why'] = m.group(1).strip()
    m = re.search(r'INVARIANT TOTAL pass=(\d+) fail=(\d+)', L); d['inv'] = '%s/%s' % (m.group(1), int(m.group(1)) + int(m.group(2)))
    d['stuck_lines'] = len(re.findall(r'^STUCK ', L, re.M))
    m = re.search(r'SUMMARY carried erlangs=(\S+)', L); d['erl'] = m.group(1)
    hs = re.search(r'HUBSUM ex=A (.*)', L); d['hubA'] = hs.group(1) if hs else ''
    if n in rc: d['wall_s'] = rc[n][0]; d['args'] = rc[n][2]; d['bin'] = rc[n][1]
    out.append(d)
for d in out:
    print(json.dumps(d))
