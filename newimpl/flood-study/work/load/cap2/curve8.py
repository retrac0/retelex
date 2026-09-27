#!/usr/bin/env python3
"""curve8.py -- scale-8 model curves for the two topologies (cap2).  NOT RTL."""
import sys
sys.path.insert(0, '.')
from regmodel import M
for ch in (8, 2):
    for pnet in (300, 1000):
        print(f"\n== scale 8, CH={ch}, pnet {pnet/10:.0f}%  (idle ms: att/s/ex -> OK/min/ex [net], net ok%, refuse%, reg, trunk E, notrunk%, NODT%)")
        for idle in (240000, 120000, 60000, 40000, 30000, 20000, 15000, 6000):
            r = M(scale=8, idle=idle, pnet=pnet, CH=ch, T=2000000).run().summary()
            print(f"  {idle:6d}: {r['att_s_ex']:4.2f} -> {r['ok_min_ex']:5.1f} [{r['okN_min_ex']:4.1f}]  N {100*r['N_ok']:3.0f}%  ref {100*r['refuse']:3.0f}%  reg {r['reg']:.2f}  trk {r['trunk']:.2f}  notrunk {100*r['notrunk']:3.0f}%  NODT {100*r['nodt']:3.0f}%")
