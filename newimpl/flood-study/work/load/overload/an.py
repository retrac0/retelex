#!/usr/bin/env python3
"""an.py -- overload analysis of load-harness logs (work/load/overload).

usage: an.py [-b BUCKET_MS] [-f] LOG [LOG ...]
  per log: run facts, outcomes by kind, per-interval time series (by LIFT time):
  started, OK (L/N), success %, NODT, mean/max dial-tone delay; failing-call hold
  times; fairness (per line success and dial-tone delay by port order);
  safety lines, STUCK, INVARIANT FAIL; SUMMARY exchange/unit lines.
"""
import sys, re, collections, statistics as st

def kv(line):
    return dict(x.split('=', 1) for x in line.split()[1:] if '=' in x)

def num(v):
    try: return int(v)
    except (TypeError, ValueError): return None

def pct(xs, p):
    if not xs: return None
    xs = sorted(xs); return xs[min(len(xs) - 1, max(0, (len(xs) * p + 99) // 100 - 1))]

def fmt(x):
    return '-' if x is None else (f'{x:.1f}' if isinstance(x, float) else str(x))

def analyse(path, bucket, fair):
    calls, prog, other, summ, knobs = [], [], [], [], {}
    wall = None
    for line in open(path, errors='replace'):
        if line.startswith('CALL '): calls.append(kv(line))
        elif line.startswith('PROG '): prog.append(line.rstrip())
        elif line.startswith('KNOB '):
            k = line.split()[1]
            if '=' in k: knobs[k.split('=')[0]] = k.split('=', 1)[1]
        elif re.match(r'(WRONGRING|PHANTOM|DRAINRING|IDLEHEAR|STUCK|INVARIANT FAIL|INVARIANT TOTAL|SELFTEST FAIL|TIMEOUT|WARN|BURST|START|STOP|HANGUP|END)', line):
            other.append(line.rstrip())
        elif line.startswith('SUMMARY') and not line.startswith('SUMMARY line'):
            summ.append(line.rstrip())
        m = re.search(r'walltime ([\d.]+) s', line)
        if m: wall = float(m.group(1))
    print(f'==== {path}')
    keys = ['seed','dur_ms','idle_ms','switch_ms','idle2_ms','pnet','dest_mode','abandon','ab_dt',
            'trunc_pm','trunc_nd','own_pm','netlines','burst_ms','nlines','bad_e','bad_b','hot','rest_ms','dt_ms']
    print('   knobs', ' '.join(f'{k}={knobs[k]}' for k in keys if k in knobs))
    simms = None
    for s in summ:
        if s.startswith('SUMMARY run'):
            simms = num(kv(s.replace('SUMMARY run', 'X')).get('sim_ms')); print('  ', s)
    print(f'   wall_s={wall} sim_ms={simms} calls={len(calls)}')
    # outcomes by kind
    by = collections.Counter((c.get('kind'), c.get('out')) for c in calls)
    outs = sorted({o for _, o in by})
    for k in sorted({k for k, _ in by}):
        n = sum(by[(k, o)] for o in outs)
        print(f'   kind={k:3s} n={n:4d}', ' '.join(f'{o}={by[(k, o)]}' for o in outs if by[(k, o)]))
    why = collections.Counter(c.get('why') for c in calls if c.get('out') != 'OK' and c.get('why', '-') != '-')
    if why: print('   why', ' '.join(f'{w}={n}' for w, n in why.most_common()))
    ab = collections.Counter(c.get('ab') for c in calls if c.get('out') in ('ABANDON', 'CUT'))
    if ab: print('   ab/cut phases', dict(ab))
    # time series by lift time
    series = collections.defaultdict(lambda: collections.Counter())
    dts = collections.defaultdict(list)
    for c in calls:
        lift = num(c.get('lift'))
        if lift is None: continue
        b = lift // bucket
        s = series[b]; s['n'] += 1; s['n_' + c.get('kind', '?')] += 1
        o = c.get('out')
        s[o] += 1
        if o == 'OK': s['ok_' + c.get('kind', '?')] += 1
        d = num(c.get('dt'))
        if d is not None: dts[b].append(d - lift)
    if series:
        print(f'   series (by lift, {bucket} ms): t n nL nN ok okL okN succ% NODT BUSY NOGO ABAN dt_mean dt_p90 dt_max')
        for b in sorted(series):
            s = series[b]; d = dts[b]
            att = s['n'] - s['CUT']
            print(f'     {b*bucket:6d} {s["n"]:3d} {s["n_L"]:3d} {s["n_N"]+s["n_BAD"]:3d} {s["OK"]:3d} {s["ok_L"]:3d} {s["ok_N"]:3d}'
                  f' {100.0*s["OK"]/att if att else 0:5.1f} {s["NODT"]:3d} {s["BUSY"]:3d} {s["NOGO"]:3d} {s["ABANDON"]:3d}'
                  f' {fmt(st.mean(d) if d else None):>7s} {fmt(pct(d,90)):>6s} {fmt(max(d) if d else None):>6s}')
    # hold times of failing calls: lift->rel (the line and, mostly, the register)
    for o in ('NOGO', 'BUSY', 'OK'):
        for k in ('L', 'N', 'BAD'):
            xs = [num(c['rel']) - num(c['lift']) for c in calls if c.get('out') == o and c.get('kind') == k
                  and num(c.get('rel')) is not None and num(c.get('lift')) is not None]
            ks = [num(c['tone']) - num(c['key']) for c in calls if c.get('out') == o and c.get('kind') == k
                  and num(c.get('tone')) is not None and num(c.get('key')) is not None]
            ls = [num(c['tone']) - num(c['last']) for c in calls if c.get('out') == o and c.get('kind') == k
                  and num(c.get('tone')) is not None and num(c.get('last')) is not None]
            if xs:
                print(f'   hold {o:4s} {k:3s} n={len(xs):4d} lift->rel mean={st.mean(xs):.0f} p90={pct(xs,90)}'
                      + (f'  key->tone mean={st.mean(ks):.0f} max={max(ks)}' if ks else '')
                      + (f'  last->tone mean={st.mean(ls):.0f} max={max(ls)}' if ls else ''))
    # fairness: per line success and dial tone delay, by port order
    if fair:
        per = collections.defaultdict(lambda: [0, 0, 0, []])
        for c in calls:
            if c.get('out') == 'CUT': continue
            p = per[c['from']]; p[0] += 1
            if c.get('out') == 'OK': p[1] += 1
            if c.get('out') == 'NODT': p[2] += 1
            l, d = num(c.get('lift')), num(c.get('dt'))
            if l is not None and d is not None: p[3].append(d - l)
        print('   fairness per line: port att ok NODT dt_mean')
        rows = sorted(per.items())
        for x in sorted({r[0][0] for r in rows}):
            xs = [(k, v) for k, v in rows if k[0] == x]
            line = ' '.join(f'{k[1:]}:{v[0]}/{v[1]}/{v[2]}/{fmt(st.mean(v[3]) if v[3] else None)}' for k, v in xs)
            print(f'     {x}', line)
            # octants: success by block of 8 ports
            blk = collections.defaultdict(lambda: [0, 0, []])
            for k, v in xs:
                b = k[1]
                blk[b][0] += v[0]; blk[b][1] += v[1]; blk[b][2] += v[3]
            print(f'     {x} by block:', ' '.join(f'{b}x: att={v[0]} ok={v[1]} ({100.0*v[1]/v[0] if v[0] else 0:.0f}%) dt={fmt(st.mean(v[2]) if v[2] else None)}'
                                             for b, v in sorted(blk.items())))
            succ = [v[1] / v[0] for k, v in xs if v[0]]
            if succ:
                print(f'     {x} per-line success: min={min(succ):.2f} median={st.median(succ):.2f} max={max(succ):.2f} '
                      f'lines_with_0_ok={sum(1 for s in succ if s == 0)}/{len(succ)}')
    for s in summ:
        if re.match(r'SUMMARY (outcome|safety|carried|dialtone|postdial|exchange|link|unit|nogo_written|why|attempts)', s):
            print('  ', s)
    for o in other:
        if not o.startswith(('START', 'STOP', 'HANGUP', 'END')) or True:
            print('  ', o)
    for p in prog:
        print('  ', p)

def main(argv):
    bucket, fair = 1000, False
    args = argv[1:]
    while args and args[0].startswith('-'):
        if args[0] == '-b': bucket = int(args[1]); args = args[2:]
        elif args[0] == '-f': fair = True; args = args[1:]
        else: break
    for p in args: analyse(p, bucket, fair)

if __name__ == '__main__':
    main(sys.argv)
