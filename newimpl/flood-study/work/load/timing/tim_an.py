#!/usr/bin/env python3
"""tim_an.py -- analyse a timing-study log (TE lines from tim_probe.svh, CALL
lines from the harness).  Usage: tim_an.py LOG [--flood] [--quiet]

Per flood (tagged by the caller's call id): the origin's KEY, SEIZE, the
caller's first break after the key (e's first break), and at every other
exchange the RISE on the incoming trunk, CREAD, HOLD, ARM, FSWEEP, FWD, the
first FALL (e's first break arriving), the cell's E and B counts, CLAIM, TAKE,
the far register's h s.  Prints distributions and every anomaly."""
import sys, re, collections, math

def pct(v, p):
    if not v: return float('nan')
    v = sorted(v); k = (len(v) - 1) * p / 100.0
    f = math.floor(k); c = math.ceil(k)
    return v[f] if f == c else v[f] + (v[c] - v[f]) * (k - f)

def dist(name, v, unit='ms'):
    if not v:
        return '%-44s n=0' % name
    return '%-44s n=%-4d mean=%7.2f p50=%7.2f p90=%7.2f p99=%7.2f max=%7.2f min=%7.2f' % (
        name, len(v), sum(v) / len(v), pct(v, 50), pct(v, 90), pct(v, 99), max(v), min(v))

XI = {c: i for i, c in enumerate('ABCDEFGH')}

def main():
    path = sys.argv[1]
    quiet = '--quiet' in sys.argv
    ev = collections.defaultdict(list)       # call -> [(t, ex, EV, port, fields)]
    calls = {}
    knobs = {}
    codes = {}
    summ = []
    other = collections.Counter()
    last_t = 0.0
    for ln in open(path, errors='replace'):
        if ln.startswith('TE ') and not ln.endswith('\n'):
            continue                                   # a line still being written
        if ln.startswith('TE ') and ('MDIG' in ln and 'cnt=' not in ln):
            continue
        if ln.startswith('TE '):
            f = ln.split()
            t = float(f[1]); x = f[2]; e = f[3]; p = f[4]; c = int(f[5])
            kv = {}
            for w in f[6:]:
                if '=' in w:
                    a, b = w.split('=', 1); kv[a] = b
            if e == 'FWD':
                kv['legs'] = ln.split('legs=')[1].split()
            ev[c].append((t, x, e, p, kv))
            last_t = t
        elif ln.startswith('CALL '):
            d = dict(w.split('=', 1) for w in ln.split()[1:] if '=' in w)
            calls[int(d['id'])] = d
        elif ln.startswith('KNOB '):
            for w in ln.split()[1:]:
                if '=' in w:
                    a, b = w.split('=', 1); knobs[a] = b
        elif ln.startswith('TOPO ex='):
            m = re.match(r'TOPO ex=(\w) code=(\d+)', ln)
            if m: codes[m.group(1)] = m.group(2)
        elif ln.startswith(('SUMMARY', 'INVARIANT', 'WRONGRING', 'PHANTOM', 'IDLEHEAR', 'STUCK', 'DRAINRING', 'END', 'TIMEOUT', 'HANGUP', 'STOP')):
            summ.append(ln.rstrip())
        for k in ('WRONGRING', 'PHANTOM', 'IDLEHEAR', 'STUCK '):
            if ln.startswith(k): other[k.strip()] += 1
    code2x = {v: k for k, v in codes.items()}
    TARM = int(knobs.get('T_ARM', '16'))
    # ---------------------------------------------------------------------
    D = collections.defaultdict(list)
    anomalies = []
    cnt = collections.Counter()
    floods = []
    for c, L in sorted(ev.items()):
        if c <= 0: continue
        L.sort(key=lambda r: r[0])
        key = [r for r in L if r[2] == 'KEY']
        if not key: continue
        tk, xo, _, cport, kv = key[0]
        dial = kv.get('dial', '?')
        dest = kv.get('dest', '?')
        if len(dial) < 5: continue
        digs = [int(ch) for ch in dial]
        cnt['floods'] += 1
        fl = {'call': c, 'x': xo, 'tkey': tk, 'dial': dial, 'dest': dest}
        seize = [r for r in L if r[2] == 'SEIZE' and r[1] == xo]
        osw = [r for r in L if r[2] == 'OSWEEP' and r[1] == xo]
        # the caller's first break after the key: FALL on the caller port at the origin
        cfall = [r for r in L if r[2] == 'FALL' and r[1] == xo and r[3] == cport and r[0] > tk]
        crise = [r for r in L if r[2] == 'RISE' and r[1] == xo and r[3] == cport and r[0] > tk]
        tb0 = cfall[0][0] if cfall else None
        fl['tb0'] = tb0
        # the first make after it: the end of e's first break at the origin
        tm0 = None
        if tb0 is not None:
            r2 = [r for r in crise if r[0] > tb0]
            tm0 = r2[0][0] if r2 else None
        ced = [r for r in L if r[1] == xo and r[3] == cport and r[2] in ('FALL', 'RISE') and r[0] > tk]
        obrks = []
        for i2 in range(len(ced) - 1):
            if ced[i2][2] == 'FALL' and ced[i2 + 1][2] == 'RISE':
                obrks.append(ced[i2 + 1][0] - ced[i2][0])
        fl['obrks'] = obrks
        drop = [r for r in L if r[2] in ('ODROP', 'OEND') and r[1] == xo]
        guard_ab = any(r[2] == 'ODROP' and r[4].get('guard') == '1' and r[4].get('brk') == '1' for r in drop)
        fl['guard_ab'] = guard_ab
        if guard_ab: cnt['guard_abandon'] += 1
        if osw: D['key->osweep'].append(osw[0][0] - tk)
        if not seize:
            cnt['no_seize'] += 1
            if tb0 is not None and tb0 < (tk + 200):
                cnt['brk_before_seize(no seize)'] += 1
            floods.append(fl)
            continue
        ts = seize[0][0]
        fl['tseize'] = ts
        D['key->seize'].append(ts - tk)
        if tb0 is not None:
            D['seize->caller e brk (origin probe)'].append(tb0 - ts)
            if tb0 < ts:
                cnt['C06 break before seizure write'] += 1
                anomalies.append('C06? call %d %s: caller broke at %.3f before the seizure write %.3f (key %.3f)' % (c, xo, tb0, ts, tk))
        e_d, b_d = digs[1], digs[2]
        e_p = 10 if e_d == 0 else e_d
        # per exchange reached
        ox = XI[xo]
        per = {}
        for x in sorted(set(r[1] for r in L)):
            if x == xo: continue
            R = [r for r in L if r[1] == x]
            rises = [r for r in R if r[2] == 'RISE' and r[4].get('bsy') == '0']
            holds = [r for r in R if r[2] == 'HOLD']
            if not rises and not holds: continue
            hop = abs(XI[x] - ox)
            info = {'hop': hop}
            if rises:
                trise = rises[0][0]; port = rises[0][3]
            else:
                trise = None; port = holds[0][3]
            info['port'] = port
            info['trise'] = trise
            PR = [r for r in R if r[3] == port]
            def first(evn, after=None, cond=None):
                for r in PR:
                    if r[2] == evn and (after is None or r[0] >= after) and (cond is None or cond(r)):
                        return r
                return None
            h = first('HOLD'); a = first('ARM'); cr = first('CREAD'); cw = first('CWAIT')
            fs = first('FSWEEP'); fw = first('FWD'); un = first('UNHOLD')
            nholds = len([r for r in PR if r[2] == 'HOLD'])
            if nholds > 1:
                cnt['re-seized (2+ HOLDs)'] += 1
                anomalies.append('RESEIZE call %d dial %s at %s port %s: %d holds, unhold=%s' % (c, dial, x, port, nholds, un[0] if un else '-'))
            if un: cnt['unhold on a live flood'] += 1
            fall1 = first('FALL', trise) if trise is not None else None
            if trise is not None:
                D['age at arrival, hop %d' % hop].append(trise - ts)
                if fall1: D['arrival->first brk at port, hop %d' % hop].append(fall1[0] - trise)
            if h and trise is not None:
                D['rise->hold'].append(h[0] - trise)
                if cr: D['rise->cread'].append(cr[0] - trise)
            if h and h[4].get('cell') == '-':
                cnt['HOLD with no cell (unwatched)'] += 1
            if h and h[4].get('fwd') == '0':
                cnt['HOLD not forwarded (fwd=0)'] += 1
            if a and trise is not None:
                D['rise->arm'].append(a[0] - trise)
                D['seize->arm, hop %d' % hop].append(a[0] - ts)
                if fall1:
                    m = fall1[0] - a[0]
                    D['MARGIN arm->first brk at port, hop %d' % hop].append(m)
                    D['MARGIN arm->first brk at port (all)'].append(m)
                    if m < 0:
                        cnt['cell armed after e brk began'] += 1
                        anomalies.append('LATEARM call %d dial %s at %s(hop %d) port %s: armed %.3f, e brk arrived %.3f (margin %.1f)' % (c, dial, x, hop, port, a[0], fall1[0], m))
            if h and fall1:
                mh = fall1[0] - h[0]
                D['MARGIN hold->first brk at port, hop %d' % hop].append(mh)
                D['MARGIN hold->first brk at port (all)'].append(mh)
                if mh < TARM + 2:
                    cnt['e brk inside the T_ARM hold watch'] += 1
                    anomalies.append('INWATCH call %d dial %s at %s(hop %d) port %s: hold %.3f, e brk arrived %.3f (%.1f ms after the hold)' % (c, dial, x, hop, port, h[0], fall1[0], mh))
            info['thold'] = h[0] if h else None
            info['tarm'] = a[0] if a else None
            info['fall1'] = fall1[0] if fall1 else None
            info['cell'] = h[4].get('cell') if h else None
            info['fwd'] = h[4].get('fwd') if h else None
            info['nholds'] = nholds
            info['mdig'] = ','.join('%s%s' % (r[4].get('st'), r[4].get('cnt')) for r in PR if r[2] == 'MDIG')
            info['claim'] = 1 if first('CLAIM') else 0
            if fs and h: D['hold->fsweep'].append(fs[0] - h[0])
            if fs and fw: D['fsweep->fwd (sweep+confirm+write)'].append(fw[0] - fs[0])
            if trise is not None and h and fs and fw:
                cause = []
                if h[0] - trise > 2.0: cause.append('clsq')
                if fs[0] - h[0] > 0.5: cause.append('fwait')
                if fw[0] - fs[0] > 11.5: cause.append('slowsweep')
                cnt['transit delay cause ' + ('+'.join(cause) if cause else 'none')] += 1
            if fw and trise is not None:
                D['rise->fwd legs written'].append(fw[0] - trise)
            # relayed pulses: break lengths on this port vs the caller's at the origin
            if trise is not None:
                ed = [r for r in PR if r[2] in ('FALL', 'RISE') and r[0] > trise]
                brks = []
                for i2 in range(len(ed) - 1):
                    if ed[i2][2] == 'FALL' and ed[i2 + 1][2] == 'RISE':
                        brks.append(ed[i2 + 1][0] - ed[i2][0])
                obrk = fl.get('obrks', [])
                for i2 in range(min(len(brks), len(obrk), 12)):
                    if brks[i2] < 200 and obrk[i2] < 200:
                        D['relayed break - origin break, hop %d' % hop].append(brks[i2] - obrk[i2])
                        D['relayed break length (all hops)'].append(brks[i2])
            # the cell's counts
            for r in PR:
                if r[2] == 'MDIG':
                    st = r[4].get('st'); n = int(r[4].get('cnt', -1))
                    want = e_d if st == 'E' else b_d
                    wantp = 10 if want == 0 else want
                    cnt['cell digits'] += 1
                    if n != wantp:
                        cnt['cell digit MISCOUNT'] += 1
                        anomalies.append('MISCOUNT call %d dial %s at %s(hop %d) port %s: cell st=%s counted %d, dialled %d' % (c, dial, x, hop, port, st, n, wantp))
            cl = first('CLAIM')
            if cl:
                code = codes.get(x, '?')
                ok = (dial[1:3] == code)
                cnt['claims'] += 1
                if not ok:
                    cnt['FALSE CLAIM'] += 1
                    anomalies.append('FALSECLAIM call %d dial %s claimed by %s (code %s) port %s at %.3f' % (c, dial, x, code, port, cl[0]))
                tk2 = first('TAKE'); rf = first('REFUSE'); at = first('ATT')
                if at: D['claim->att'].append(at[0] - cl[0])
                if tk2:
                    D['claim->take (register attached)'].append(tk2[0] - cl[0])
                    # the first break of h at this port after the claim
                    fb = [r for r in PR if r[2] == 'FALL' and r[0] > cl[0]]
                    if fb:
                        D['MARGIN take->h first brk'].append(fb[0][0] - tk2[0])
                        if fb[0][0] < tk2[0]:
                            anomalies.append('LATETAKE call %d at %s: register attached %.3f after h began %.3f' % (c, x, tk2[0], fb[0][0]))
                            cnt['C02 register attached after h began'] += 1
                if rf: cnt['claim refused'] += 1
            for r in PR:
                if r[2] == 'RDIG':
                    n = int(r[4]['n']); d = int(r[4]['d'])
                    want = digs[2 + n] if 2 + n < len(digs) else None
                    if want is not None:
                        wantp = 10 if want == 0 else want
                        cnt['far register digits'] += 1
                        if d != wantp:
                            cnt['FAR REGISTER MISCOUNT'] += 1
                            anomalies.append('REGMISCOUNT call %d dial %s at %s: register digit %d counted %d, dialled %d' % (c, dial, x, n, d, wantp))
            per[x] = info
        # hop to hop: arrival times along the path
        fl['per'] = per
        floods.append(fl)
    # FWD -> next exchange's rise, per transit
    # (a transit's own delay: its incoming rise -> the next exchange's rise)
    for fl in floods:
        if 'tseize' not in fl: continue
        per = fl['per']
        byhop = {}
        for x, info in per.items():
            if info.get('trise') is not None:
                byhop.setdefault((XI[x] > XI[fl['x']]), []).append((info['hop'], info['trise']))
        for side, lst in byhop.items():
            lst.sort()
            prev = (0, fl['tseize'])
            for hp, tr in lst:
                if hp == prev[0] + 1:
                    D['hop %d->%d (rise to rise)' % (prev[0], hp) if prev[0] > 0 else 'origin seize->hop1 rise'].append(tr - prev[1])
                    if prev[0] > 0: D['transit hop (rise to next rise), all'].append(tr - prev[1])
                prev = (hp, tr)
    # ---------------------------------------------------------------------
    print('LOG', path)
    ks = ['idg_ms', 'idg_jit_ms', 'idg0_ms', 'idg0_jit_ms', 'dest_mode', 'pairs', 'burst_ms', 'pair_gap_ms', 'bad_e', 'bad_b', 'pnet', 'idle_ms', 'dur_ms', 'seed', 'scale', 'ppm_a', 'ppm_b', 'ppm_c', 'ppm_d', 'ppm_e']
    print('KNOBS', ' '.join('%s=%s' % (k, knobs[k]) for k in ks if k in knobs))
    print('sim end t=%.1f ms' % last_t)
    oc = collections.Counter(d['out'] for d in calls.values())
    ok = collections.Counter((d['kind'], d['out']) for d in calls.values())
    wy = collections.Counter(d['why'] for d in calls.values() if d['out'] not in ('OK',))
    print('CALLS', len(calls), dict(oc))
    print('  by kind', dict(ok))
    print('  why', dict(wy))
    print('COUNTS', dict(cnt))
    print('OTHER', dict(other))
    for k in sorted(D):
        print(dist(k, D[k]))
    if not quiet:
        for a in anomalies: print('ANOM', a)
    else:
        print('ANOM (%d, first 30)' % len(anomalies))
        for a in anomalies[:30]: print('ANOM', a)
    for s in summ:
        if s.startswith(('SUMMARY outcome', 'SUMMARY safety', 'INVARIANT TOTAL', 'INVARIANT FAIL', 'WRONGRING', 'PHANTOM', 'STUCK', 'END', 'TIMEOUT')):
            print(s)
    # one line for NOTES.md
    def q(k):
        v = D.get(k, [])
        return ('%.1f/%.1f/%.1f(n%d)' % (sum(v)/len(v), pct(v, 99), max(v), len(v))) if v else '-'
    print('ONELINE %s | sim_end=%.0fms calls=%d %s | floods=%d guard_ab=%d no_seize=%d | miscount=%d/%d falseclaim=%d regmis=%d latearm=%d reseize=%d C06=%d unwatched=%d nofwd=%d inwatch=%d | seize->arm %s | margin(all) %s | WRONG=%d' % (
        path.split('/')[-1], last_t, len(calls), dict(oc), cnt['floods'], cnt['guard_abandon'], cnt['no_seize'],
        cnt['cell digit MISCOUNT'], cnt['cell digits'], cnt['FALSE CLAIM'], cnt['FAR REGISTER MISCOUNT'],
        cnt['cell armed after e brk began'], cnt['re-seized (2+ HOLDs)'], cnt['C06 break before seizure write'],
        cnt['HOLD with no cell (unwatched)'], cnt['HOLD not forwarded (fwd=0)'], cnt['e brk inside the T_ARM hold watch'],
        ' '.join('h%d:%s' % (k, q('seize->arm, hop %d' % k)) for k in range(1, 8) if D.get('seize->arm, hop %d' % k)),
        q('MARGIN arm->first brk at port (all)'), oc.get('WRONG', 0)))
    if '--flood' in sys.argv:
        for fl in floods:
            s = 'FLOOD %d %s dial=%s key=%.1f' % (fl['call'], fl['x'], fl['dial'], fl['tkey'])
            if 'tseize' in fl: s += ' seize=+%.1f' % (fl['tseize'] - fl['tkey'])
            if fl.get('tb0') is not None and 'tseize' in fl: s += ' brk0=+%.1f' % (fl['tb0'] - fl['tseize'])
            if fl.get('guard_ab'): s += ' GUARD'
            for x, info in sorted(fl.get('per', {}).items()):
                if 'tseize' not in fl: continue
                ts0 = fl['tseize']
                f = lambda v: ('%.1f' % (v - ts0)) if v is not None else '-'
                s += ' %s:%s/%s/%s%s%s%s' % (x, f(info.get('trise')), f(info.get('thold')), f(info.get('fall1')),
                                            '' if info.get('cell') not in ('-',) else '!nocell',
                                            '' if info.get('fwd') != '0' else '!nofwd',
                                            ('[%s]' % info['mdig']) if info.get('mdig') else '')
                if info.get('nholds', 0) > 1: s += '!x%d' % info['nholds']
                if info.get('claim'): s += '!CLAIM'
            print(s)

main()
