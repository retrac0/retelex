# reg1.py -- AUDIT model: one register per exchange (mini marker + net unit),
# two exchanges, calls at random.  Not RTL: the holding times follow the
# RTL's rules (the origin holds the register from lift to its LAST digit;
# a claim finding the register busy is refused at once).
import heapq, random, sys

PPS_T = 0.1        # s a pulse (10 pps)
PAUSE = 0.8        # s between digits (network.md 3.1's worked example)
ID    = 0.128
WATCH = 0.035      # SETTLE + words, after a connect
def dig(rng, lo=0, hi=7):
    d = rng.randint(lo, hi); return (10 if d == 0 else d) * PPS_T
def react(rng):    # dial tone to the first pulse
    return rng.uniform(1.0, 4.0)

def run(L, calls_h, p_net, T=200000.0, seed=1, connect_at_claim=False):
    rng = random.Random(seed)
    lam = L * calls_h / 3600.0
    # per exchange: register busy-until, FIFO of waiting callers
    busy = [False, False]; q = [[], []]
    ev = []; n = 0
    def push(t, kind, *a):
        nonlocal n; n += 1; heapq.heappush(ev, (t, n, kind, a))
    for x in (0, 1): push(rng.expovariate(lam), 'arr', x)
    st = dict(net=0, net_ok=0, net_ref=0, loc=0, wait=0.0, busy_t=[0.0, 0.0])
    last = [0.0, 0.0]
    def start(t, x, job):
        busy[x] = True; last[x] = t
        kind = job[0]
        if kind == 'loc':
            hold = react(rng) + dig(rng, 2, 7) + PAUSE + dig(rng) + ID + WATCH
            push(t + hold, 'free', x)
        else:                                   # network origin: 1 e b h s
            pre = react(rng) + PPS_T + PAUSE + dig(rng) + PAUSE + dig(rng) + ID
            post = PAUSE + dig(rng, 2, 7) + PAUSE + dig(rng) + ID
            push(t + pre + 0.005, 'claim', 1 - x, post)
            push(t + pre + (0.0 if connect_at_claim else post), 'free', x)
    while ev:
        t, _, kind, a = heapq.heappop(ev)
        if t > T: break
        if kind == 'arr':
            x = a[0]; push(t + rng.expovariate(lam), 'arr', x)
            job = ('net',) if rng.random() < p_net else ('loc',)
            st['net' if job[0] == 'net' else 'loc'] += 1
            if busy[x]: q[x].append((t, job))
            else: start(t, x, job)
        elif kind == 'claim':
            x, post = a
            if busy[x]: st['net_ref'] += 1
            else:
                st['net_ok'] += 1; busy[x] = True; last[x] = t
                push(t + post + WATCH, 'free', x)
        elif kind == 'free':
            x = a[0]; st['busy_t'][x] += t - last[x]; busy[x] = False
            if q[x]:
                t0, job = q[x].pop(0); st['wait'] += t - t0; start(t, x, job)
    tot = st['net_ok'] + st['net_ref']
    return dict(occ=sum(st['busy_t']) / (2 * T), refused=st['net_ref'] / max(tot, 1),
                wait=st['wait'] / max(st['net'] + st['loc'], 1))

if __name__ == '__main__':
    print("lines calls/h p_net | occupancy  claims refused  mean wait for dial tone | same, connect at claim")
    for L in (16, 32, 48):
        for c in (3.0, 5.0):
            for p in (0.3, 0.5):
                a = run(L, c, p); b = run(L, c, p, connect_at_claim=True)
                print(f"{L:5d} {c:7.1f} {p:5.1f} | {a['occ']:9.2f} {100*a['refused']:13.1f}% {a['wait']:12.2f} s"
                      f"          | {b['occ']:5.2f} {100*b['refused']:6.1f}% {b['wait']:6.2f} s")
