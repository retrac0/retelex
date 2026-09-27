#!/usr/bin/env python3
"""model.py -- a discrete-event model of the tb_load2 traffic (two exchanges, one
register each, pulse-flood network calls), to compare with the RTL runs and to
extrapolate them to the real timers.  NOT the RTL: it keeps only what the RTL
runs show dominates under load:

  * one register an exchange; a waiting line is served when the register frees:
    after a TIMER-DRIVEN release (tick_1k at scan 00: WATCH settled, N_DONE at
    o_last, gone) the lowest-numbered waiting line; after a release at a probe
    (BUSY/NOGO at the called port's turn) the next waiting line in scan order
    after the called port;  NODT after dt_ms
  * a local call holds the register from dial tone to the probe of the called
    line (end of s + ID + ~6 ms), then SETTLE in WATCH if connected
  * a network call holds the ORIGIN register from dial tone to o_last (s + ID),
    whatever happens to the claim; the claim is made at b + ID + ~3 ms and is
    TAKEN only if the far register is free at that instant (C15), else REFUSED;
    a taken claim holds the far register over h s + ID + probe (+ SETTLE)
  * a called line is busy when off hook or being rung
Usage: model.py [--scale 1|8] [--idle MS] [--pnet PM] [--dur MS] [--seed N]
                [--switch MS --idle2 MS] [--series MS] [--reps N]
"""
import heapq, random, argparse, math, collections

def params(scale):
    if scale == 8:
        return dict(pre=60, brk=12, mk=8, idg=100, ID=16, settle=4, ans=300, hold=1500, lag=50,
                    rest=120, hup=100, dt=3000, ring=192, verify=20, hunt=11, probe=6, clr=32)
    return dict(pre=500, brk=60, mk=40, idg=720, ID=128, settle=32, ans=3000, hold=10000, lag=400,
                rest=800, hup=800, dt=20000, ring=6144, verify=20, hunt=11, probe=6, clr=256)

def digit_ms(P, d):
    n = 10 if d == 0 else d
    return n * (P['brk'] + P['mk'])

class Sim:
    def __init__(s, a):
        s.a = a; s.P = params(a.scale); s.rng = random.Random(a.seed)
        s.NL = 48; s.NX = 2
        s.t = 0.0; s.q = []; s.seq = 0
        s.state = {}          # (x,i) -> 'IDLE','WAIT','DIAL','TALK','ALERT','REST','POST'
        s.reg = [None, None]  # who holds each register: None or tag
        s.regbusy_since = [0.0, 0.0]; s.regocc = [0.0, 0.0]
        s.wait_since = {}
        s.calls = []          # (lift, kind, outcome, dt_delay)
        s.talk = 0.0
        for x in range(s.NX):
            for i in range(s.NL):
                s.state[(x, i)] = 'IDLE'
                s.at(s.idle_draw(), 'lift', (x, i))
    def idle_draw(s):
        m = s.a.idle
        if s.a.switch and s.t >= s.a.switch: m = s.a.idle2
        return s.t + s.rng.expovariate(1.0 / m)
    def at(s, t, ev, arg):
        s.seq += 1; heapq.heappush(s.q, (t, s.seq, ev, arg))
    # ---- the register ----------------------------------------------------------
    def reg_take(s, x, tag):
        s.reg[x] = tag; s.regbusy_since[x] = s.t
    def reg_free(s, x, pos):
        if s.reg[x] is not None:
            s.regocc[x] += max(0.0, min(s.t, s.a.dur) - min(s.regbusy_since[x], s.a.dur))
        s.reg[x] = None
        # serve the next waiting line in scan order from pos (0 = after a tick)
        w = [i for i in range(s.NL) if s.state[(x, i)] == 'WAIT']
        if not w: return
        w.sort(key=lambda i: (i - pos) % s.NL)
        i = w[0]
        s.reg_take(x, ('call', i))
        s.at(s.t + 2.5, 'dialtone', (x, i))
    def busy_line(s, x, i):
        return s.state[(x, i)] not in ('IDLE', 'REST')
    # ---- events -------------------------------------------------------------------
    def ev_lift(s, xi):
        x, i = xi
        if s.t >= s.a.dur or s.state[xi] != 'IDLE': return
        s.state[xi] = 'WAIT'; s.wait_since[xi] = s.t
        c = dict(lift=s.t, x=x, i=i, kind='N' if s.rng.random() < s.a.pnet / 1000 else 'L', out=None, dt=None)
        s.cur = getattr(s, 'cur', {}); s.cur[xi] = c
        s.at(s.t + s.P['dt'], 'nodt', (xi, s.t))
        if s.reg[x] is None:
            s.reg_take(x, ('call', i)); s.at(s.t + 2.5, 'dialtone', xi)
    def ev_nodt(s, arg):
        xi, lift = arg
        c = s.cur.get(xi)
        if s.state[xi] == 'WAIT' and c and c['lift'] == lift:
            s.end(xi, 'NODT', 0)
    def end(s, xi, out, extra):
        c = s.cur.pop(xi)
        c['out'] = out; s.calls.append(c)
        s.state[xi] = 'POST' if extra else 'REST'
        s.at(s.t + extra, 'rest', xi)
    def ev_rest(s, xi):
        s.state[xi] = 'REST'
        s.at(s.t + s.P['rest'], 'idle', xi)
    def ev_idle(s, xi):
        if s.state[xi] == 'REST':
            s.state[xi] = 'IDLE'; s.at(s.idle_draw(), 'lift', xi)
    def ev_dialtone(s, xi):
        x, i = xi
        if s.state[xi] != 'WAIT':      # left meanwhile: the register frees at a tick later (gone)
            s.at(s.t + s.P['clr'], 'regfree', (x, 0)); return
        c = s.cur[xi]; c['dt'] = s.t - c['lift']
        s.state[xi] = 'DIAL'
        P = s.P
        if c['kind'] == 'L':
            y = x; j = s.rng.choice([k for k in range(s.NL) if k != i])
            t = P['pre'] + digit_ms(P, j // 8 + 2) + P['idg'] + digit_ms(P, s.rng.randrange(8)) + P['ID']
            s.at(s.t + t + P['probe'], 'probe', (xi, (y, j), False))
        else:
            y = 1 - x; j = s.rng.randrange(s.NL)
            e, b = 2, (3 if y == 1 else 2)
            t_b = P['pre'] + digit_ms(P, 1) + P['idg'] + digit_ms(P, e) + P['idg'] + digit_ms(P, b) + P['ID'] + 3
            t_s = t_b - 3 + P['idg'] + digit_ms(P, j // 8 + 2) + P['idg'] + digit_ms(P, s.rng.randrange(8)) + P['ID']
            c['t_s'] = s.t + t_s
            s.at(s.t + t_b, 'claim', (xi, (y, j)))
    def ev_claim(s, arg):
        xi, yj = arg
        if xi not in s.cur: return
        c = s.cur[xi]; y = yj[0]
        if s.reg[y] is None:
            s.reg_take(y, ('claim', xi)); c['taken'] = True
            s.at(c['t_s'] + s.P['probe'], 'probe', (xi, yj, True))
        else:
            c['taken'] = False
        s.at(c['t_s'], 'olast', xi)
    def ev_olast(s, xi):
        x = xi[0]
        s.at(s.t, 'regfree', (x, 0))      # N_DONE at the tick
        c = s.cur.get(xi)
        if c and not c['taken']:
            s.end(xi, 'NOGO', s.P['hup'] + 20)
    def ev_regfree(s, arg):
        x, pos = arg
        s.reg_free(x, pos)
    def ev_probe(s, arg):
        xi, yj, net = arg
        y, j = yj
        c = s.cur.get(xi)
        if c is None: return
        if s.busy_line(y, j):
            s.at(s.t, 'regfree', (y, j))   # released at the called port's turn
            s.end(xi, 'BUSY', s.P['hup'] + 20)
            return
        # connect; WATCH, then the register frees at a tick
        s.at(s.t + s.P['settle'] + 1, 'regfree', (y, 0))
        if not net:
            pass
        s.state[yj] = 'ALERT'
        s.state[xi] = 'TALK'
        bell = s.rng.uniform(0, s.P['ring'])
        ans = s.t + bell + s.rng.uniform(0, s.P['ans'])
        hold = max(s.rng.expovariate(1.0 / s.P['hold']), s.P['verify'] + 30)
        c['out'] = 'OK'
        s.talk += (hold)
        s.at(ans + hold, 'hang', (xi, yj))
    def ev_hang(s, arg):
        xi, yj = arg
        c = s.cur.pop(xi, None)
        if c: s.calls.append(c)
        s.state[xi] = 'REST'; s.at(s.t + s.P['rest'], 'idle', xi)
        s.state[yj] = 'REST'; s.at(s.t + s.P['lag'] / 2 + s.P['rest'], 'idle', yj)
    def run(s):
        end = s.a.dur + 30 * s.P['hold']
        while s.q:
            t, _, ev, arg = heapq.heappop(s.q)
            if t > end: break
            s.t = t
            getattr(s, 'ev_' + ev)(arg)
        for x in range(s.NX):
            if s.reg[x] is not None: s.regocc[x] += max(0.0, min(s.t, s.a.dur) - min(s.regbusy_since[x], s.a.dur))
        return s

def summarise(sims, a):
    tot = collections.Counter(); dts = []; n = 0; talk = 0; occ = 0; series = collections.defaultdict(collections.Counter)
    for s in sims:
        for c in s.calls:
            if c['lift'] >= a.dur: continue
            tot[(c['kind'], c['out'])] += 1; n += 1
            if c['dt'] is not None: dts.append(c['dt'])
            b = int(c['lift'] // a.series)
            series[b]['n'] += 1; series[b][c['out']] += 1
            if c['dt'] is not None: series[b]['dts'] += c['dt']; series[b]['ndt'] += 1
        talk += s.talk; occ += sum(s.regocc) / 2
    R = len(sims); T = a.dur / 1000.0
    att = n / R / T / 2
    ok = sum(v for (k, o), v in tot.items() if o == 'OK') / R
    okN = tot[('N', 'OK')] / R; okL = tot[('L', 'OK')] / R
    nN = sum(v for (k, o), v in tot.items() if k == 'N') / R
    print(f'scale={a.scale} idle={a.idle} pnet={a.pnet} dur={a.dur}: attempts/s/exch={att:.2f} '
          f'OK/s(both)={ok/T:.2f} okL={okL/T:.2f}/s okN={okN/T:.2f}/s netOK%={100*okN/max(1,nN):.0f} '
          f'succ%={100*ok/max(1,n/R):.0f} reg_occ={occ/R/(a.dur):.2f} dt_mean={sum(dts)/max(1,len(dts)):.0f} '
          f'carried_E~={talk/R/a.dur:.2f}')
    print('   ', ' '.join(f'{k}{o}={v/R:.1f}' for (k, o), v in sorted(tot.items())))
    if a.switch:
        for b in sorted(series):
            v = series[b]
            print(f'    t={int(b*a.series):6d} n={v["n"]/R:5.1f} OK={v["OK"]/R:5.1f} NODT={v["NODT"]/R:5.1f} '
                  f'dt_mean={v["dts"]/max(1,v["ndt"]):7.0f}')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--scale', type=int, default=8)
    ap.add_argument('--idle', type=float, default=60000)
    ap.add_argument('--pnet', type=float, default=500)
    ap.add_argument('--dur', type=float, default=10000)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--switch', type=float, default=0)
    ap.add_argument('--idle2', type=float, default=60000)
    ap.add_argument('--series', type=float, default=1000)
    ap.add_argument('--reps', type=int, default=20)
    a = ap.parse_args()
    sims = []
    for r in range(a.reps):
        a2 = argparse.Namespace(**vars(a)); a2.seed = a.seed * 1000 + r
        sims.append(Sim(a2).run())
    summarise(sims, a)
