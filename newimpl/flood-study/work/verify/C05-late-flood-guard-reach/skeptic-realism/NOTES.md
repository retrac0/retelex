# C05 skeptic review (lens: REALISM AND SEVERITY) -- notes
Started 2026-09-27. Read-only; at most one short sim.

## Reading (00:30-00:50)
- net_unit.v 283 cls_seen, 566-567 st, 584-594 C_HOLD/C_UNHOLD, 862 guard abandon on r_brk: as the verifier says.
- tb_fx sc6: break at B at (129-dly) ms after B's rise. Correct owner (3 3) NOT modelled; upstream = a delay.
- verifier's C_LOW diff read: C_HOLD M-low -> C_LOW (cls_ms 0); M up -> C_HOLD (cls_ms 0); cls_ms>=ID -> C_UNHOLD. Hold stands -> BUSY=bsy=1 -> no R_GONE, st set at the make. Correct, zero packages (ID=128 is one counter bit).
- network.md (new) 2: carrier delay costs the guard nothing (seizure and pulses share it) -> D in my arithmetic = processing only.
- network.md 6: "The guard must cover the SLOW case" -> 128 tap planned at 4-5 hops. Typical D at 5 hops ~62 ms. Watch exposure needs D>=100 (t_guard-HIT-20). => in a network planned per today's doc rule the band needs >=2-3 coincident slow events on one path. Slow events are NOT correlated hop to hop: a convoy (2nd flood behind a 1st) waits once, then trails ~20 ms and waits no more (arith: F2 legs at a1+33 vs F1 at a1+12.4 -> gap 20.6 > 19.8 watch).
- Claim race: both cells claim at b's end + ID; backward claim ~1-2 ms/hop (resolver scan turn + write). If (e,b) exists and is >=1 hop nearer than (e-1,b), (e,b) wins, origin drops the rest before h is dialled -> the wrong register sees CLR -> no ring. Wrong number needs (e,b) vacant (misdial) or no nearer than (e-1,b), or (e,b) behind the misreading transit (then its re-forward carries e-1: lost call there).
- Real equipment: pulse-gen card 700 ms pause (exchange-docs/pulse-gen.md:64-66) -> safe at every tap (512 band needs D>=541). Keypad pulse ICs 500-800 ms. Rotary: dial lost motion + wind; sub-280 ms after a '1' implausible for most; register.md's own test drew 250-1000 ms, and network.md 10 lists "how fast people dial" as not run.
- Stopgap "lateness bit alone": agree with mechanism skeptic (reasoning): the make after a missed first break has M low at the last visit -> bit says fresh -> cell -> e-1. Their run_late is in progress (00:40).
## Evidence re-checked (00:55)
- Verifier's logs: snap d108 PASS, d112 FAIL, d124 FAIL, l1 d104 PASS (but unhold 56.68 + re-seize 117.8 on E30); fix d112/d124/l1 d104 PASS, l1 d112 FAIL; cls l1 d112 PASS; tb_net fix 88/0. All as claimed.
- fix l1 d104: E30's legs written at 61.0 ms, 6 ms INTO the first break (break 55-115) -> downstream sees its rise at the make and counts e-1. Inherent beyond-reach (forward 31 ms after rise), not the fix's fault; but "clean" is clean at B only. fix d124 likewise (legs ~42, break 35).
- Design's own promise: analysis/monitor-rules.md 5 "Both rules: none, at any pause a pulse register can read" (uniform 140-900 ms pause model); "worn dial, non-conforming instrument, operator's practised hand" named as the fast callers the guard exists for. So finding 1 breaks a stated invariant.
- Reference load: network.md 10 resolver 0.19 E / 2.7 s hold -> ~0.07 floods/s reach each exchange -> P(another seizure in the 18 ms before) ~0.13 %/flood/exchange. cls slice traffic runs: 5 floods/s p99 rise->hold 15.6 ms max 19.3, no wrong claim; 30 floods/s max 38.7, no wrong claim (audit/cls/NOTES.md sec 4).
- Joel's own diallers: pulse-gen and hotline card 700 ms between digits -> safe at every tap.
- Human rotary after a '1': dial lost motion + wind for e -> sub-280 ms essentially out of reach; 256-tap band (387-407) IS human-reachable, but needs D>=228 (~18 typical hops) -> only a network planned at the 256 tap's typical reach (21), which network.md 6 forbids (slow case 8-11).
- C_LOW caveat (fault only): a held trunk chattering with makes <18 ms keeps cst in C_HOLD<->C_LOW; snapshot instead re-seizes each cycle (new cell + forward each time) -> C_LOW still better.
- ID vs CLR for C_LOW: CLR matches port T_REL (armed port, 128-256 ms low = not a release; ID would unhold and re-seize at return = same misread). Real deaths inside watch come from far guard abandons of fast callers; extra 128 ms block delays other floods only (~1 % chance at ref load). Prefer CLR (C04 verifier's choice); not material.
## Verdicts (draft)
- F1 confirmed-overstated, medium (agree). Add: claim race (nearer rightful owner wins; bench has none), doc slow-case plan makes it ~0, deterministic for fixed-cadence diallers.
- F2 confirmed-overstated, low (agree). Verifier's lateness-bit stopgap is wrong (reasoning; mech skeptic testing).
- F3 confirmed-overstated, low (agree). Stale RTL header comment "ten hops".
- 01:00 mech skeptic's run_late_sc6_l1_d112.log (snapshot + lateness bit alone) finished: "109.514 SKEPTIC hold 30 late 0 -> cell", CLAIM 1437, B21 rung, FAIL 2. Verifier's cheap stopgap REFUTED by measurement.
- No sim of my own run (none needed).
