#!/usr/bin/env python3
"""an_model.py -- arithmetic for the classifier's queue at real timers.

S = 19.0 ms a trunk seizure (read ~1.1 + C_HOLD T_ARM+2; run_r2_sc1.log), and the
next seizure taken after a hold is the lowest-numbered one waiting.
Load: N exchanges, L lines, 3 calls/line/h, f leaving, c copies of each flood
reaching the exchange (one per link it arrives on).
"""
import math
S = 0.019
print("classifier capacity: %.0f trunk seizures/s" % (1 / S))
print("%4s %4s %5s %3s %9s %8s %10s %12s" % ("N", "L", "leave", "c", "floods/s", "seiz/s", "rho_cls", "P(wait>=2S)"))
for N, L, f, c in ((8, 48, 0.3, 2), (20, 48, 0.3, 2), (20, 48, 0.3, 4), (47, 48, 0.3, 4), (47, 48, 0.5, 4)):
    F = N * L * 3 / 3600 * f
    lam = F * c
    rho = lam * S
    # Poisson, M/D/1: P(>= 2 waiting ahead) ~ rho^2 (light load)
    print("%4d %4d %5.1f %3d %9.3f %8.3f %10.4f %12.2e" % (N, L, f, c, F, lam, rho, rho ** 2))
# trunk groups: a copy is held ~2 s (e b dialled, then dropped at the claim);
# 16 channels at the ~2 s hold carry at most ~8 seizures/s
print("16 channels at 2 s a copy: <= %.1f seizures/s -> rho_cls <= %.2f" % (16 / 2.0, 16 / 2.0 * S))
