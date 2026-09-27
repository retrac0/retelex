#!/usr/bin/env python3
"""regmodel.py -- a call-level model of tb_load2 / tb_load2b (cap2).

NOT RTL.  It mirrors the load harness's phones (load_harness.svh: finite
source, exponential idle, dial timing, dial-tone timeout, quit on tone, ring
cadence, answer, exponential hold, rest) and the RTL's resource rules that
the RTL runs showed to matter:

  one register an exchange (mini_marker.v): a caller waits for it (random
  order ~ scan order), dial tone, pre, digits.  Local: held to the probe
  (last + ID) + SETTLE.  Network origin: held from attach to o_last
  (net_unit.v:880-881: last + ID) -- the whole 1 e b h s.
  a claim (net_unit.v:656-676) arrives at the far exchange at b's end + ID
  + a few ms; the far register free -> taken, held to the far probe
  (last + ID) + SETTLE; busy -> refused at once (mini_marker.v:282), and
  the origin still holds its register to o_last, the caller hears 03 then.
  trunks: CH channels shared by both directions; seized at key + ID + sweep;
  none -> nogo at once.  Held until the caller has hung up + T_REL.
  monitors: NMON a exchange, from seizure to b + ID (a claim) or to e + ID
  (not this exchange's e: never, two exchanges).  None free -> unwatched ->
  the origin's T_CLAIM after b (N_TCLAIM).

usage: regmodel.py [key=value ...]   (see DEF); prints one summary line.
"""
import heapq, random, sys, math, collections

SC8 = dict(scale=8, brk=12, mk=8, idg=100, pre=60, ID=16, settle=4, T_REL=32, T_CLAIM=250,
           ring_on=64, ring_off=128, ans=300, hold=1500, lag=50, rest=120, hup=100, dt=3000,
           verify=20, sweep=10, dtdet=4)
SC1 = dict(scale=1, brk=60, mk=40, idg=720, pre=500, ID=128, settle=32, T_REL=256, T_CLAIM=2000,
           ring_on=2048, ring_off=4096, ans=3000, hold=10000, lag=400, rest=800, hup=800, dt=20000,
           verify=20, sweep=10, dtdet=4)
DEF = dict(scale=8, lines=48, idle=60000, pnet=300, mode=0, orig='AB', CH=8, NMON=2,
           T=2000000, seed=1, warm=20000, nreg=1, connect_at_claim=0, far_noreg=0, org_free_at_key=0, pre_hi=0, claim_wait=0)

def pulses(d): return 10 if d == 0 else d

class M:
    def __init__(s, **kw):
        base = SC8 if int(kw.get('scale', DEF['scale'])) == 8 else SC1
        p = dict(DEF); p.update(base); p.update(kw)
        s.p = p
        s.r = random.Random(int(p['seed']))
        s.t = 0.0; s.ev = []; s.n = 0
        L = int(p['lines'])
        s.lines = [[{'x': x, 'i': i, 'st': 'IDLE', 'relt': -1e9, 'epoch': 0} for i in range(L)] for x in (0, 1)]
        s.reg = [[None] * int(p['nreg']) for _ in (0, 1)]     # holder kind per register, None free
        s.regbusy_t = [0.0, 0.0]; s.reg_kind_t = [collections.Counter(), collections.Counter()]
        s.wait = [[], []]
        s.pend = [[], []]
        s.trunks = 0; s.trunk_t = 0.0; s.trunk_last = 0.0
        s.mon = [0, 0]
        s.st = collections.Counter()
        s.dtd = []
        s.last_upd = 0.0
        s.codes = [(2, 2), (2, 3)]

    # ---- time accounting -------------------------------------------------------
    def upd(s):
        dt = s.t - s.last_upd
        if s.t > s.p['warm'] and dt > 0:
            w0 = max(s.last_upd, s.p['warm']); dt = s.t - w0
            for x in (0, 1):
                for k in s.reg[x]:
                    if k is not None:
                        s.regbusy_t[x] += dt / len(s.reg[x]); s.reg_kind_t[x][k] += dt / len(s.reg[x])
            s.trunk_t += s.trunks * dt
        s.last_upd = s.t

    def at(s, dt, fn, *a):
        s.n += 1; heapq.heappush(s.ev, (s.t + dt, s.n, fn, a))

    def cnt(s, k, v=1):
        if s.t > s.p['warm']: s.st[k] += v

    # ---- the phones --------------------------------------------------------------
    def sched_idle(s, ln):
        ln['epoch'] += 1
        s.at(s.r.expovariate(1.0 / s.p['idle']), s.lift, ln, ln['epoch'])

    def lift(s, ln, ep):
        if ep != ln['epoch'] or ln['st'] != 'IDLE': return
        x = ln['x']
        if x not in [ 'AB'.index(c) for c in s.p['orig'] ]:
            return
        c = {'g': ln, 'x': x, 'lift': s.t, 'out': None}
        # destination
        p = s.p
        net = False
        if int(p['mode']) == 1:
            net = (x == 0) and s.r.random() * 1000 < p['pnet']
        else:
            net = s.r.random() * 1000 < p['pnet']
        y = 1 - x if net else x
        L = s.lines[y]
        while True:
            d = L[s.r.randrange(len(L))]
            if d is not ln: break
        c['net'] = net; c['y'] = y; c['d'] = d
        c['digits'] = ([1] + list(s.codes[y]) if net else []) + [2 + (d['i'] // 8) % 6, d['i'] % 8]
        ln['st'] = 'WAITDT'; ln['call'] = c
        s.cnt('att'); s.cnt('att_' + 'AB'[x]); s.cnt('att_' + ('N' if net else 'L'))
        s.wait[x].append(c)
        c['nodt_ep'] = ln['epoch']
        s.at(p['dt'], s.nodt, c, ln['epoch'])
        s.try_reg(x)

    def nodt(s, c, ep):
        if c['g']['epoch'] != ep or c['g']['st'] != 'WAITDT' or c not in s.wait[c['x']]: return
        s.wait[c['x']].remove(c)
        s.finish(c, 'NODT', 0)

    def reg_free_idx(s, x):
        for i, k in enumerate(s.reg[x]):
            if k is None: return i
        return -1

    def claim_timeout(s, c):
        if not c.get('pending'): return
        c['pending'] = False; s.pend[c['y']].remove(c)
        s.cnt('refuse'); s.cnt('refuse_wait'); c['refused'] = True

    def try_reg(s, x):
        i = s.reg_free_idx(x)
        if i >= 0 and s.pend[x]:
            c = s.pend[x].pop(0); c['pending'] = False
            s.upd(); s.reg[x][i] = 'claimed'; c['fri'] = i
            s.cnt('take'); s.cnt('take_waited')
            return
        if i < 0 or not s.wait[x]: return
        c = s.wait[x].pop(s.r.randrange(len(s.wait[x])))
        s.upd(); s.reg[x][i] = 'local'; c['ri'] = i
        s.at(0.5 + s.p['dtdet'], s.dialtone, c)

    def dialtone(s, c):
        ln = c['g']
        if ln['st'] != 'WAITDT': return
        ln['epoch'] += 1                  # cancels the NODT
        ln['st'] = 'DIAL'
        s.cnt('dt_n');
        if s.t > s.p['warm']: s.dtd.append(s.t - c['lift'])
        p = s.p
        t = p['pre'] if not p['pre_hi'] else s.r.uniform(p['pre'], p['pre_hi'])
        marks = []
        for k, d in enumerate(c['digits']):
            n = pulses(d)
            t += n * p['brk'] + (n - 1) * p['mk']
            marks.append(t)               # end of this digit's last break
            t += p['idg']
        c['marks'] = [s.t + m for m in marks]
        c['last'] = c['marks'][-1]
        if c['net']:
            s.at(marks[0] + p['ID'] + 1, s.key, c)
        else:
            s.at(marks[-1] + p['ID'] + 2, s.local_probe, c)

    # ---- local ---------------------------------------------------------------------
    def busyline(s, d):
        if d['st'] in ('IDLE',): return s.t < d['relt'] + s.p['T_REL']
        if d['st'] == 'REST': return s.t < d['relt'] + s.p['T_REL']
        return True

    def local_probe(s, c):
        x = c['x']; s.upd()
        if s.busyline(c['d']):
            s.reg[x][c['ri']] = None; s.try_reg(x)
            s.cnt('L_BUSY')
            s.at(1 + s.p['hup'], s.hangup_fail, c, 'BUSY')
            c['g']['st'] = 'POST'
            return
        s.reg[x][c['ri']] = 'settle'
        s.at(s.p['settle'], s.free_reg, x, c['ri'])
        s.connect(c)

    def free_reg(s, x, i):
        s.upd(); s.reg[x][i] = None; s.try_reg(x)

    # ---- network -------------------------------------------------------------------
    def key(s, c):
        x = c['x']; s.upd(); s.reg[x][c['ri']] = 'yield'
        s.cnt('floods')
        if int(s.p['org_free_at_key']):
            s.reg[x][c['ri']] = None; s.try_reg(x); c['ri_freed'] = True
        s.at(s.p['sweep'], s.seize, c)

    def seize(s, c):
        x = c['x']; p = s.p
        if c['g']['st'] != 'DIAL': return
        s.upd()
        if s.trunks >= p['CH']:
            s.cnt('N_NOTRUNK')
            if not c.get('ri_freed'): s.reg[x][c['ri']] = None; s.try_reg(x)
            c['g']['st'] = 'POST'
            s.at(1 + p['hup'], s.hangup_fail, c, 'NOGO')
            return
        s.trunks += 1; c['trunk'] = True
        y = c['y']
        # the far monitor
        if s.mon[y] >= p['NMON']:
            s.cnt('nomon')
            c['nomon'] = True
            # the origin's T_CLAIM after b (marks[2])
            s.at(c['marks'][2] + p['ID'] + p['T_CLAIM'] - s.t, s.tclaim, c)
            return
        s.mon[y] += 1
        s.at(c['marks'][2] + p['ID'] + 3 - s.t, s.claim, c)

    def tclaim(s, c):
        x = c['x']; s.upd()
        s.cnt('N_TCLAIM')
        if not c.get('ri_freed'): s.reg[x][c['ri']] = None; s.try_reg(x)
        c['g']['st'] = 'POST'
        s.at(1 + s.p['hup'], s.hangup_fail, c, 'NOGO')

    def claim(s, c):
        y = c['y']; x = c['x']; p = s.p
        s.mon[y] -= 1
        s.upd()
        s.cnt('claims')
        i = s.reg_free_idx(y)
        if int(p['far_noreg']):
            s.cnt('take'); c['fri'] = None
        elif i < 0 and p['claim_wait'] > 0:
            s.pend[y].append(c); c['pending'] = True
            s.at(p['claim_wait'], s.claim_timeout, c)
        elif i < 0:
            s.cnt('refuse'); s.cnt('refuse_' + '+'.join(sorted(k for k in s.reg[y] if k)))
            c['refused'] = True
        else:
            s.cnt('take')
            s.reg[y][i] = 'claimed'; c['fri'] = i
        if c.get('ri_freed'):
            s.at(c['last'] + p['ID'] + 1 - s.t, s.o_last, c, False)
        elif int(p['connect_at_claim']):
            s.reg[x][c['ri']] = None; s.try_reg(x)
            s.at(c['last'] + p['ID'] + 1 - s.t, s.o_last, c, False)
        else:
            s.at(c['last'] + p['ID'] + 1 - s.t, s.o_last, c, True)

    def o_last(s, c, free):
        x = c['x']; y = c['y']; p = s.p
        s.upd()
        if free:
            s.reg[x][c['ri']] = None; s.try_reg(x)
        if c.get('refused'):
            s.cnt('F_REFUSE')
            c['g']['st'] = 'POST'
            s.at(1 + p['hup'], s.hangup_fail, c, 'NOGO')
            return
        # the far register probes the called line
        s.at(2, s.far_probe, c)

    def far_probe(s, c):
        y = c['y']; s.upd()
        if s.busyline(c['d']):
            if c['fri'] is not None: s.reg[y][c['fri']] = None; s.try_reg(y)
            s.cnt('F_BUSY')
            c['g']['st'] = 'POST'
            s.at(1 + s.p['hup'], s.hangup_fail, c, 'BUSY')
            return
        if c['fri'] is not None:
            s.reg[y][c['fri']] = 'settle'
            s.at(s.p['settle'], s.free_reg, y, c['fri'])
        s.connect(c)

    # ---- the call ------------------------------------------------------------------
    def connect(s, c):
        d = c['d']; p = s.p
        c['g']['st'] = 'RING'
        d['epoch'] += 1; d['st'] = 'ALERT'
        cyc = p['ring_on'] + p['ring_off']
        ph = s.r.uniform(0, cyc)
        wait_bell = 0 if ph < p['ring_on'] else cyc - ph
        bell = 5 + wait_bell
        s.cnt('pdd_n'); s.cnt('pdd_sum', s.t - c['last'])
        s.at(bell + s.r.uniform(0, p['ans']), s.answer, c)

    def answer(s, c):
        p = s.p
        hold = max(s.r.expovariate(1.0 / p['hold']), p['verify'] + 30)
        c['g']['st'] = 'TALK'; c['d']['st'] = 'TALK'
        lag = s.r.uniform(0, p['lag'])
        s.cnt('talk_ms', hold)
        s.at(hold, s.end_call, c, lag)

    def end_call(s, c, lag):
        s.cnt('OK'); s.cnt('OK_' + 'AB'[c['x']]); s.cnt('OK_' + ('N' if c['net'] else 'L'))
        s.at(lag, s.release_both, c)

    def release_both(s, c):
        s.upd()
        for ln in (c['g'], c['d']):
            s.rest(ln)
        if c.get('trunk'):
            s.at(s.p['T_REL'], s.trunk_free)

    def trunk_free(s):
        s.upd(); s.trunks -= 1

    def hangup_fail(s, c, cls):
        s.upd()
        s.finish(c, cls, 1)

    def finish(s, c, cls, onhook):
        s.cnt(cls); s.cnt(cls + '_' + ('N' if c['net'] else 'L'))
        s.rest(c['g'])
        if c.get('trunk'):
            s.at(s.p['T_REL'], s.trunk_free)

    def rest(s, ln):
        ln['st'] = 'REST'; ln['relt'] = s.t; ln['epoch'] += 1
        s.at(s.p['rest'], s.rested, ln, ln['epoch'])

    def rested(s, ln, ep):
        if ep != ln['epoch'] or ln['st'] != 'REST': return
        ln['st'] = 'IDLE'
        s.sched_idle(ln)

    def run(s):
        for x in (0, 1):
            for ln in s.lines[x]: s.sched_idle(ln)
        T = s.p['T']
        while s.ev:
            t, _, fn, a = heapq.heappop(s.ev)
            if t > T: break
            s.t = t
            fn(*a)
        s.t = T; s.upd()
        return s

    def summary(s):
        p = s.p; T = (p['T'] - p['warm']) / 1000.0
        st = s.st
        att = st['att']; claims = st['claims']
        r = dict(att_s_ex=att / T / 2, ok_min_ex=st['OK'] / T * 60 / 2, okN_min_ex=st['OK_N'] / T * 60 / 2,
                 okL_min_ex=st['OK_L'] / T * 60 / 2,
                 N_ok=st['OK_N'] / max(st['att_N'], 1), L_ok=st['OK_L'] / max(st['att_L'], 1),
                 refuse=st['refuse'] / max(claims, 1), nodt=st['NODT'] / max(att, 1),
                 reg=sum(s.regbusy_t) / (2 * T * 1000), trunk=s.trunk_t / (T * 1000),
                 dt_mean=(sum(s.dtd) / len(s.dtd) if s.dtd else 0),
                 dt_p99=(sorted(s.dtd)[int(len(s.dtd) * .99)] if s.dtd else 0),
                 carried_E=st['talk_ms'] / (T * 1000),
                 notrunk=st['N_NOTRUNK'] / max(st['att_N'], 1), nomon=st['nomon'] / max(st['att_N'], 1),
                 yield_frac=sum(s.reg_kind_t[x]['yield'] for x in (0, 1)) / max(sum(s.regbusy_t), 1e-9))
        ref_by = {k[7:]: v for k, v in st.items() if k.startswith('refuse_')}
        r['refuse_by'] = ref_by
        return r

if __name__ == '__main__':
    kw = {}
    for a in sys.argv[1:]:
        k, v = a.split('=', 1)
        try: v = float(v) if '.' in v else int(v)
        except ValueError: pass
        kw[k] = v
    m = M(**kw).run()
    r = m.summary()
    print(' '.join(f"{k}={v:.3f}" if isinstance(v, float) else f"{k}={v}" for k, v in r.items()))
