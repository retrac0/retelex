#!/usr/bin/env python3
"""reach.py -- how many hops each GUARD tap covers, from the measured timings.

A flood is safe at an exchange K hops from the origin if the caller's first
break reaches that exchange after its hold's T_ARM watch has ended:
    gap >= age(K) + rise->hold + watch - relay(K)
The origin passes a break only if it starts >= t_guard - HIT after the seizure
(r_brk comes HIT into the break; tmr counts from the seizure push), so the
smallest gap a caller can get through is gmin = t_guard - HIT.
Measured at real timers (runs cv8, cvd8; work/load/timing/NOTES.md):
    hop 1 (seizure -> neighbour's rise)   1.9 ms (1.3-2.2)
    transit hop (rise -> next rise)       13.5 ms (13.08-13.93)
    rise -> hold                          1.1 ms
    T_ARM watch after the hold            18 ms (cls_ms > T_ARM+1)
    relay of a break                      0.55 ms a hop (helps)
    one slow event (penalty)              up to 18.2 ms (cvd8 d=12)
"""
HOP1, HOP, R2H, WATCH, RELAY, PEN, HIT = 1.9, 13.5, 1.1, 18.0, 0.55, 18.2, 8

def need(K, npen):
    return HOP1 + HOP * (K - 1) + R2H + WATCH - RELAY * K + PEN * npen

print('%-6s %-6s %s' % ('tap', 'gmin', 'hops covered with 0 / 1 / 2 / 3 slow events'))
for tap in (128, 256, 512, 1024):
    gmin = tap - HIT
    row = []
    for npen in range(4):
        K = 0
        while need(K + 1, npen) <= gmin: K += 1
        row.append(K)
    print('%-6d %-6d %s' % (tap, gmin, ' / '.join(str(k) for k in row)))
print()
for K in range(1, 11):
    print('K=%-2d need gap %6.1f (0 ev) %6.1f (1 ev) %6.1f (2 ev)' % (K, need(K, 0), need(K, 1), need(K, 2)))
