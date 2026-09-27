#!/usr/bin/env python3
"""parse.py LOG... -- one row a run from the load harness's SUMMARY lines (cap2)."""
import sys, re, os, collections, json

def kv(s):
    return dict(t.split('=', 1) for t in s.split() if '=' in t)

def parse(path):
    r = {'log': path, 'name': os.path.basename(path)[:-4]}
    knobs = {}
    ex = collections.defaultdict(dict)
    calls = []
    refs = []; takes = []
    for line in open(path, errors='replace'):
        if line.startswith('KNOB '):
            knobs.update(kv(line[5:]))
        elif line.startswith('CALL '):
            calls.append(kv(line[5:]))
        elif line.startswith('C2REF '):
            refs.append(kv(line[6:]))
        elif line.startswith('C2TAKE '):
            takes.append(kv(line[7:]))
        elif line.startswith('SUMMARY '):
            w = line.split()
            k = w[1]; d = kv(' '.join(w[2:]))
            if k in ('c2refst', 'c2takest'):
                d = dict(re.findall(r'([A-Z]+(?:/c)?)\s*=(\d+)', ' '.join(w[2:]))); d['ex'] = w[2].split('=')[1]
            if k in ('exchange', 'link', 'unit', 'nogo_written', 'checks', 'attempts', 'c2reg', 'c2refst', 'c2takest'):
                x = d.get('ex')
                ex[x][k] = d
            elif k == 'outcome':
                if 'kind' in d: r['outcome_' + d['kind']] = d
                else: r['outcome'] = d
            elif k == 'line':
                pass
            else:
                r[k] = d
        elif line.startswith('INVARIANT TOTAL'):
            r['inv'] = kv(line[15:])
        elif 'walltime' in line:
            m = re.search(r'walltime ([\d.]+)', line); r['walltime'] = float(m.group(1)) if m else None
        elif line.startswith(('STUCK ', 'WRONGRING', 'PHANTOM', 'DRAINRING', 'IDLEHEAR', 'TIMEOUT')):
            r.setdefault('events', []).append(line.strip())
    r['knobs'] = knobs; r['ex'] = dict(ex); r['calls'] = calls; r['refs'] = refs; r['takes'] = takes
    return r

def row(r):
    k = r['knobs']; run = r.get('run', {})
    T = int(run.get('traffic_ms', 1)) / 1000.0
    o = r.get('outcome', {})
    oN = r.get('outcome_N', {}); oL = r.get('outcome_L', {})
    out = []
    out.append(f"{r['name']:18s} idle={k.get('idle_ms'):>6s} pnet={k.get('pnet'):>4s} mode={k.get('dest_mode')} orig={k.get('orig_x')} "
               f"T={T:.0f}s sim={int(run.get('sim_ms',0))/1000:.1f}s wall={r.get('walltime') or 0:.0f}s calls={run.get('calls')}")
    out.append("   all: " + ' '.join(f"{a}={b}" for a, b in o.items() if b != '0'))
    out.append("   N  : " + ' '.join(f"{a}={b}" for a, b in oN.items() if b != '0'))
    out.append("   L  : " + ' '.join(f"{a}={b}" for a, b in oL.items() if b != '0'))
    out.append("   why: " + ' '.join(f"{a}={b}" for a, b in r.get('why', {}).items()))
    for x, d in sorted(r['ex'].items()):
        a = d.get('attempts', {}); e = d.get('exchange', {}); u = d.get('unit', {}); l = d.get('link', {})
        ok = int(a.get('OK', 0)); tot = int(a.get('total', 0))
        cl = int(u.get('claims', 0)); rf = int(u.get('att_refuse', 0)); tk = int(u.get('att_take', 0))
        out.append(f"   {x}: att={tot} ({float(a.get('per_s',0)):.2f}/s) ok={ok} ({ok/T*60:.1f}/min) "
                   f"reg={e.get('reg_occ')} org={e.get('origin_occ')} mon={e.get('mon_mean')}/{e.get('mon_max')} "
                   f"res={e.get('res_mean')} link={l.get('busy_mean')}/{l.get('busy_max')} dtwait={e.get('dt_wait_mean')} "
                   f"floods={u.get('floods')} in={u.get('seized_in')} claims={cl} take={tk} refuse={rf} "
                   f"({(rf/cl*100 if cl else 0):.0f}%) nomon={u.get('nomon')} nofwd_busy={u.get('nofwd_busy')} glare={u.get('n_glare')}")
        if 'c2reg' in d:
            c = d['c2reg']
            out.append(f"      c2reg yield={c.get('yield')} claimed={c.get('claimed')} other={c.get('other')} att_occ={c.get('att_occ')}")
        if 'c2refst' in d:
            out.append("      refuse_st: " + ' '.join(f"{a}={b}" for a, b in d['c2refst'].items() if a != 'ex'))
        if 'c2takest' in d:
            out.append("      take_st  : " + ' '.join(f"{a}={b}" for a, b in d['c2takest'].items() if a != 'ex'))
    c = r.get('carried', {}); dt = r.get('dialtone_delay', {}); pd = r.get('postdial_alert', {})
    out.append(f"   carried_E={c.get('erlangs')} dt: n={dt.get('n')} mean={dt.get('mean')} p50={dt.get('p50')} p99={dt.get('p99')} max={dt.get('max')} "
               f"pdd_alert mean={pd.get('mean')} max={pd.get('max')}")
    s = r.get('safety', {})
    out.append("   safety: " + ' '.join(f"{a}={b}" for a, b in s.items()) + f" | inv {r.get('inv')}")
    for e in r.get('events', [])[:10]:
        out.append("   EV " + e)
    return '\n'.join(out)

if __name__ == '__main__':
    for p in sys.argv[1:]:
        try:
            print(row(parse(p)))
        except Exception as e:
            print(p, 'ERR', e)
