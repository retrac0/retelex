#!/usr/bin/env python3
"""tr_an.py -- analyse a tb_tr3 transit run (TP lines + CALL lines).

usage: tr_an.py LOG [LOG...]      prints a per-log report; -j for a JSON dict

Per network call it rebuilds the flood tree from the TP events: the origin's
seizure write, each neighbour's classification (monitor? forwarded?), each
forward's legs and the next classification, the claims, the resolvers, and
attributes every failed end-to-end call to a cause.
"""
import re, sys, json, collections

X = "ABC"


def far(x, p):
    # tb_load3: A 010+i = B 010+i, B 030+i = C 010+i
    if x == 'A' and 8 <= p < 16: return ('B', p)
    if x == 'B' and 8 <= p < 16: return ('A', p)
    if x == 'B' and 24 <= p < 32: return ('C', p - 16)
    if x == 'C' and 8 <= p < 16: return ('B', p + 16)
    return None


def port(s):
    # "B13" -> ('B', 0o13)
    if s in ('-', None): return None
    return (s[0], int(s[1:], 8))


def kv(line):
    d = {}
    for m in re.finditer(r'(\w+)=(\S+)', line):
        d[m.group(1)] = m.group(2)
    return d


def num(v):
    if v in (None, '-'): return None
    try: return float(v)
    except ValueError: return None


def load(path):
    calls, tp, summ, tpsum, inv, stuck, other = [], [], [], [], [], [], []
    with open(path, errors='replace') as f:
        for line in f:
            if line.startswith('CALL '):
                calls.append(kv(line))
            elif line.startswith('TP '):
                d = kv(line)
                d['ev'] = line.split()[4]
                d['t'] = float(d['t']); d['n'] = int(d['n'])
                tp.append(d)
            elif line.startswith('SUMMARY'):
                summ.append(line.rstrip())
            elif line.startswith('TPSUM') or line.startswith('TPHIST'):
                tpsum.append(line.rstrip())
            elif line.startswith('INVARIANT'):
                inv.append(line.rstrip())
            elif line.startswith('STUCK') or line.startswith('WRONGRING') or line.startswith('PHANTOM') \
                    or line.startswith('IDLEHEAR') or line.startswith('DRAINRING') or line.startswith('TIMEOUT'):
                stuck.append(line.rstrip())
            elif line.startswith(('START', 'STOP', 'HANGUP', 'END', 'KNOB scale', 'PROG')):
                other.append(line.rstrip())
    return calls, tp, summ, tpsum, inv, stuck, other


def analyse(path, verbose=False):
    calls, tp, summ, tpsum, inv, stuck, other = load(path)
    # index TP events
    seizes = collections.defaultdict(list)      # (x,p) -> [ev]
    fwds = collections.defaultdict(list)        # (x,p in) -> [ev]
    claims = collections.defaultdict(list)      # (x,p) -> [ev]
    res = collections.defaultdict(list)         # (x,p in) -> [ev]
    orig = collections.defaultdict(list)        # x -> [ev] in order
    unhold = collections.defaultdict(list)
    for e in tp:
        x = e['ex']; ev = e['ev']
        if ev == 'SEIZE': seizes[port(e['p'])].append(e)
        elif ev == 'FWD': fwds[port(e['in'])].append(e)
        elif ev == 'CLAIM': claims[port(e['p'])].append(e)
        elif ev == 'RES': res[port(e['in'])].append(e)
        elif ev == 'UNHOLD': unhold[port(e['p'])].append(e)
        elif ev.startswith('O'): orig[x].append(e)

    def first_after(lst, t, win):
        for e in lst:
            if t - 0.01 <= e['t'] <= t + win: return e
        return None

    # the origin floods, as sequences OFLOOD .. OEND/ODONE
    floods = []
    for x in X:
        cur = None
        for e in orig[x]:
            if e['ev'] == 'OFLOOD':
                cur = {'x': x, 'caller': e['caller'], 't0': e['t'], 'n0': e['n'], 'seize': None,
                       'claim': None, 'end': None, 'done': None}
                floods.append(cur)
            elif cur is None:
                continue
            elif e['ev'] == 'OSEIZE': cur['seize'] = e
            elif e['ev'] == 'OCLAIM': cur['claim'] = e
            elif e['ev'] == 'ODONE': cur['done'] = e; cur = None
            elif e['ev'] == 'OEND': cur['end'] = e; cur = None

    def tree(x, p, t, depth=0):
        """the seizure written on (x,p) at t: follow it downstream."""
        fp = far(x, p)
        if fp is None: return []
        s = first_after(seizes[fp], t, 250.0)
        node = {'at': fp, 'wr_t': t, 'seize': s, 'fwd': None, 'legs': [], 'claim': None, 'res': None}
        if s is None: return [node]
        c = first_after(claims[fp], s['t'], 20000.0)
        node['claim'] = c
        if s['fwd'] == 'yes':
            f = first_after(fwds[fp], s['t'], 300.0)
            node['fwd'] = f
            if f is not None:
                r = first_after(res[fp], f['t'], 30000.0)
                node['res'] = r
                cand = int(f['cand'], 8); ok = int(f['ok'], 2)
                for j in range(4):
                    if ok >> j & 1:
                        leg = (cand >> (6 * j)) & 0o77
                        node['legs'] += tree(fp[0], leg, f['t'], depth + 1)
        return [node]

    for fl in floods:
        fl['tree'] = []
        if fl['seize']:
            cand = int(fl['seize']['cand'], 8); ok = int(fl['seize']['ok'], 2)
            for j in range(4):
                if ok >> j & 1:
                    fl['tree'] += tree(fl['x'], (cand >> (6 * j)) & 0o77, fl['seize']['t'])

    # match calls to floods: same caller, flood n0 within [key, key + 300]
    byc = collections.defaultdict(list)
    for fl in floods: byc[fl['caller']].append(fl)
    out = []
    for c in calls:
        if c.get('kind') != 'N':
            continue
        key = num(c.get('key'))
        fl = None
        if key is not None:
            for f in byc[c['from']]:
                if key - 5 <= f['n0'] <= key + 400:
                    fl = f; break
        c['_flood'] = fl
        out.append(c)

    def find_node(nodes, ex):
        for nd in nodes:
            if nd['at'][0] == ex: return nd
            r = find_node(nd['legs'], ex)
            if r: return r
        return None

    def path_to(nodes, ex):
        for nd in nodes:
            if nd['at'][0] == ex: return [nd]
            r = path_to(nd['legs'], ex)
            if r: return [nd] + r
        return None

    # attribution of every network call
    rows = []
    for c in out:
        fx, tx = c['from'][0], c['to'][0] if c['to'][0] in X else '?'
        o, why = c['out'], c['why']
        fl = c['_flood']
        cause = None
        detail = ''
        if o in ('OK', 'NOANS'):
            cause = 'ok'
        elif o == 'BUSY':
            cause = 'called_busy'
        elif o in ('NODT',):
            cause = 'no_dialtone'
        elif o == 'ABANDON':
            cause = 'abandon'
        elif o == 'CUT':
            cause = 'cut_at_end'
        elif o in ('WRONG', 'JOINED', 'XTALK', 'NOSPEECH', 'SILENT', 'DTAGAIN', 'COLLIDE'):
            cause = 'SAFETY_' + o
        else:
            # NOGO: find why
            if fl is None:
                cause = 'nogo_noflood_' + why
            elif why == 'F_REFUSE':
                cause = 'far_register_busy(C15)'
            elif why == 'N_NOTRUNK':
                cause = 'no_trunk_at_origin'
            elif why == 'N_GUARD':
                cause = 'guard_abandon'
            elif why in ('F_NODIG', 'N_NODIG'):
                cause = 'nodigit_' + why
            else:
                p = path_to(fl['tree'], tx)
                if p is None:
                    # where did it stop?
                    stop = 'unknown'
                    def walk(nodes):
                        nonlocal stop
                        for nd in nodes:
                            s = nd['seize']
                            if s is None: stop = 'not_classified_at_' + nd['at'][0]; return
                            if s['fwd'] != 'yes' and nd['at'][0] != tx:
                                stop = 'not_forwarded_at_%s_%s' % (nd['at'][0], s['fwd']); return
                            if s['fwd'] == 'yes' and nd['fwd'] is None:
                                stop = 'fwd_never_written_at_' + nd['at'][0]; return
                            if s['fwd'] == 'yes' and not nd['legs']:
                                stop = 'fwd_no_legs_at_' + nd['at'][0]; return
                            walk(nd['legs'])
                    walk(fl['tree'])
                    if not fl['tree']: stop = 'origin_no_seize'
                    cause = stop
                else:
                    last = p[-1]
                    s = last['seize']
                    if s is None:
                        cause = 'not_classified_at_owner'
                    elif s['mon'] == '0':
                        cause = 'no_monitor_at_owner'
                    elif last['claim'] is None:
                        cause = 'owner_no_claim_' + why
                    elif why == '-':
                        # the harness could not pin the refusal on one caller (two dialling the
                        # owner); claimed by the owner and cannot-complete at the connect: C15
                        cause = 'far_register_busy(C15,inferred)'
                    else:
                        cause = 'claimed_but_nogo_' + why
        rows.append({'id': c['id'], 'from': c['from'], 'to': c['to'], 'fx': fx, 'tx': tx, 'out': o, 'why': why,
                     'cause': cause, 'key': num(c.get('key')), 'tone': num(c.get('tone')),
                     'last': num(c.get('last')), 'flood': fl is not None})
    return {'calls': calls, 'rows': rows, 'floods': floods, 'summ': summ, 'tpsum': tpsum, 'inv': inv,
            'stuck': stuck, 'other': other, 'tp': tp}


def report(path):
    A = analyse(path)
    print('=' * 100)
    print(path)
    for l in A['other']:
        if l.startswith(('KNOB scale', 'START', 'STOP', 'HANGUP', 'END')): print(' ', l)
    kinds = collections.Counter((c.get('kind'), c.get('out')) for c in A['calls'])
    print('calls total', len(A['calls']), dict(sorted(kinds.items())))
    # by direction
    bydir = collections.defaultdict(collections.Counter)
    for r in A['rows']:
        bydir[r['fx'] + '>' + r['tx']][r['cause']] += 1
    for k in sorted(bydir):
        tot = sum(bydir[k].values())
        ok = bydir[k]['ok']
        print('  %s n=%d ok=%d (%.1f%%) %s' % (k, tot, ok, 100.0 * ok / max(tot, 1), dict(bydir[k].most_common())))
    # transit nodes at B: count floods passing B and their fate
    fate = collections.Counter()
    hold = []
    for fl in A['floods']:
        for nd in fl['tree']:
            if nd['at'][0] == 'B' and fl['x'] != 'B':
                s = nd['seize']
                if s is None: fate['B_not_classified'] += 1; continue
                fate['B_seize_' + s['fwd']] += 1
                if s['mon'] == '0': fate['B_nomon'] += 1
                if s['fwd'] == 'yes' and nd['fwd'] is None: fate['B_fwd_missing'] += 1
    print('  floods through B:', dict(fate))
    # the cost of each flood B did not forward: how long the origin held its trunk, and what the caller heard
    cmap = {}
    for c in A['calls']:
        if c.get('_flood') is not None: cmap[id(c['_flood'])] = c
    for fl in A['floods']:
        for nd in fl['tree']:
            s = nd['seize']
            if nd['at'][0] == 'B' and fl['x'] != 'B' and s is not None and s['fwd'] != 'yes':
                c = cmap.get(id(fl))
                endt = fl['end']['t'] if fl['end'] else (fl['done']['t'] if fl['done'] else None)
                held = (endt - fl['seize']['t']) if (endt and fl['seize']) else None
                print('  LOST-FWD at B: flood %s caller=%s t=%.1f why=%s rsb=%s fst=%s | origin trunk held %s ms | call %s'
                      % (fl['x'], fl['caller'], s['t'], s['fwd'], s['rsb'], s['fst'],
                         '%.0f' % held if held else '?',
                         ('to=%s out=%s why=%s key=%s last=%s tone=%s (tone-key %s ms)' %
                          (c['to'], c['out'], c['why'], c['key'], c['last'], c['tone'],
                           (float(c['tone']) - float(c['key'])) if c['tone'] not in ('-',) and c['key'] not in ('-',) else '-'))
                         if c else '?'))
    for l in A['tpsum']: print(' ', l)
    for l in A['summ']:
        if any(k in l for k in ('SUMMARY outcome', 'SUMMARY why', 'SUMMARY safety', 'SUMMARY unit', 'SUMMARY exchange',
                                'SUMMARY link', 'SUMMARY carried', 'SUMMARY postdial', 'SUMMARY dialtone', 'SUMMARY attempts',
                                'SUMMARY run')):
            print(' ', l)
    fails = [l for l in A['inv'] if 'FAIL' in l or 'TOTAL' in l]
    for l in fails: print(' ', l)
    for l in A['stuck'][:40]: print(' ', l)
    return A


if __name__ == '__main__':
    for p in sys.argv[1:]:
        report(p)
