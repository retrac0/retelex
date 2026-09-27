#!/usr/bin/env python3
"""captable.py -- real-timer capacity table from regmodel (cap2).  NOT RTL."""
import sys
sys.path.insert(0, '.')
from regmodel import M
rows = []
for pre in ((500, 0), (1000, 4000)):
    for pnet in (300, 1000):
        print(f"\n== real timers, pre {pre}, pnet {pnet/10:.0f}%, 48 lines/ex, hold 10 s mean")
        print(" calls/line/h | att/h/ex | carried/h/ex (net) | net completed | claims refused | reg occ | dt mean / p99 s | NODT")
        for cph in (1, 2, 3, 4, 6, 8, 12, 24):
            idle = 3600000 / cph
            kw = dict(scale=1, idle=idle, pnet=pnet, T=12000000, warm=200000, pre=pre[0], pre_hi=pre[1])
            r = M(**kw).run().summary()
            print(f" {cph:12d} | {r['att_s_ex']*3600:8.0f} | {r['ok_min_ex']*60:8.0f} ({r['okN_min_ex']*60:4.0f})   | {100*r['N_ok']:10.0f}%   | {100*r['refuse']:12.0f}%  | {r['reg']:.2f}    | {r['dt_mean']/1000:5.1f} / {r['dt_p99']/1000:5.1f}  | {100*r['nodt']:.1f}%")
