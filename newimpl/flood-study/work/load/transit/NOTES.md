# transit under load (tb_load3, chain A 2 2 - B 2 3 - C 2 4) -- running notes
Agent: transit study, started 2026-09-26 12:35.  Dir work/load/transit/.
All runs via ./sim.sh from /home/joel/telco/newimpl/build/flood.

## Runs
### R0 smoke3 (tb_load3 prebuilt, scale 8): +seed=3 +dur_ms=3000 +idle_ms=30000 +pnet=600
- log smoke3.log; sim 5.52 s, wall 537 s (97 wall-s per sim-s at machine load ~10).
- 16 calls (11 N, 5 L): OK 4, NOGO 5, CUT 7 (at hang-up). INVARIANT 38/38 PASS, safety all 0, no STUCK.
- ALL 5 NOGO are far-register refusals (F_REFUSE 3 attributed + A refuse_unattributed 2): C15 dominates already at
  reg_occ 0.66-0.93. B: seized_in 4, nofwd 0, res_max 1, mon_max 1. A,C: nofwd_empty 6 each (every incoming at a leaf
  sweeps for nothing: C14 leaf-sweeps).
- tb_load3 smoke: PASS (previous one was cut off).

## Setup (for a successor)
- tb_tr3.sv = tb_load3 wiring + tr_harness.svh (copy of load_harness.svh with dest_mode 5 = end to end, x dials
  exchange NX-1-x; +pair_per_ms period override; +pair_jit_ms lift jitter) + transit probe (tr_probe_*.svh: TP lines
  SEIZE/UNHOLD/NFEMPTY/FWD/RES/CLAIM/OFLOOD/OSEIZE/OCLAIM/ODONE/OEND, and TPSUM/TPHIST at the end).
- tr_an.py LOG: per-call attribution by flood tree (origin write -> neighbour classification -> forward -> legs -> claim).
- obj_tr3 (scale 8, NMON=NRES=2) build: vl_tr3.log.

## Expectation written before the runs (to check)
- One register an exchange => at most one origin flood pending at A and one at C, so B (pure transit) never has more
  than 2 floods pending: with NRES=2, RESNONE at B should be 0 on this chain, whatever the load.  The doc sec 10
  figure (1.4 pct) assumes Poisson floods from many registers.  To show the mechanism: an LD_NRES=1 build.
- FWDBUSY at B: at scale 8 the classifier watch is 4 ms, so a second flood within ~12 ms of the first is lost; at real
  timers the 18 ms watch spaces classifications past the 11 ms forward, and a loss needs B's own origin sweep too.
- Far-register refusal (C15) will dominate end-to-end failure at load (smoke already: all 5 NOGO).

## Slot contention (13:10): ~30 sim.sh jobs queued for 5 slots.  So everything is ONE batch, job1.sh
(./sim.sh bash work/load/transit/job1.sh): builds s8, s1 (SCALE1), n1 (LD_NRES=1) under work/load/transit/obj_*,
runs t1..t9 in turn; progress in job1.progress (START/END rc wall_s per step).  If cut off: see which logs exist,
run tr_an.py on them, and resubmit a job with only the missing steps.
job1 got slot 4 at 14:00 (waited 50 min).  build_s8 206 s.

### T1 t1_unif_heavy (s8): +seed=5 +dur_ms=15000 +idle_ms=30000 +pnet=600 -- mix (b) uniform, heavy
- sim 17.5 s, wall 1367 s (78 wall-s/sim-s). 55 calls (33 N, 22 L). INVARIANT 38/38 PASS. safety 0, STUCK 0.
- offered attempts/s A 1.20 B 0.87 C 1.60; reg_occ A .74 B .59 C .89; carried 2.0 E.
- B transit: 23 floods in, 23 forwarded (nofwd 0, RESNONE 0, FWDBUSY 0), res_max 2, mon_max 2, res_hold mean 261 ms
  (p99 284), classification 2.15 ms after the upstream write, forward 10.65 ms after classification (p99 13.4);
  res freed: 14 LEG + 9 MINE (B's own claim), 0 GONE; no leg taken, no leg glare, no fwd after claim/release.
- A: nofwd_fwdbusy 1 (nfb_hunt: a leaf's doomed sweep for an earlier incoming; harmless) + nofwd_empty 20.
- END TO END network calls (non-CUT 28): OK 11, BUSY 1, NOGO 16.  ALL 16 NOGO = far register busy (C15):
  12 attributed F_REFUSE + 4 inferred (claimed by the owner, tone 20 ms after last digit, harness could not pin).
  A>C 0/6 OK (6 x C15).  Refusal ratio att_refuse/claims: A 7/11, B 3/9, C 9/10.

### T3 t3_e2e_heavy (s8): +seed=7 +dur_ms=20000 +idle_ms=40000 +dest_mode=5 +orig_x=5 +pnet=1000 -- mix (a) A<->C
- sim 22.5 s, wall 1818 s. 37 calls (all N). INVARIANT 38/38 PASS. safety 0, STUCK 0.
- attempts/s A 0.85 C 1.00; reg_occ A .74 C .76 (B unused); carried 0.77 E; links busy_mean 2.1/8, max 5.
- B: 34 floods in, 32 forwarded, 2 FWDBUSY (5.9 pct), 0 RESNONE (res_max 2, res_mean .42), mon_max 2, nomon 0.
  Both lost floods: C flood classified at B, A flood 6.7 / 7.7 ms later, forwarder in F_HUNT (fst=2), rsb=00
  (both resolvers FREE). Logs: t3 TP t=9805.603 / 9812.274 and t=19479.643 / 19487.298.
  Cost: A-B channel held 544 ms (the whole flood, to T_CLAIM after b), caller hears cannot-complete 574 ms after
  the key, BEFORE finishing the dial (N_TCLAIM; last=-).  At real timers these two would be forwarded (18 ms watch).
- res_hold 261 mean (p99 283); forward 10.67 ms after classification (12.4 when a classification preempts the sweep).
- End to end: A>C 6/17 OK, C>A 7/20 OK.  Failures: C15 far-register refusal 18 (F_REFUSE, 49 pct of ALL calls),
  B not forwarded 1 (+1 CUT at end), NODT 2 (register busy 3 s).  att_refuse/claims A 11/18, C 8/14.

### T4 t4_cross_s8 (s8): +seed=9 +dur_ms=21000 +dest_mode=4 +pairs=A21C22,C21A22 +pair_gap_ms=1 +pair_per_ms=1400 +pair_jit_ms=30
- sim 23.5 s, wall 1716 s. 30 calls (15 crossings). INVARIANT 38/38 PASS, safety 0, STUCK 0.
- cross.py: 15 crossings at B; second flood LOST (FWDBUSY, fst=2 F_HUNT, rsb=00 both resolvers free) in all 10
  whose upstream writes were <= 8.1 ms apart (classification gap 4.6-8.4: the 4 ms scale-8 watch), forwarded in all
  5 with gap >= 19.5 ms.  Threshold = the forward's 10.6-12.4 ms.
- EVERY crossing call failed: 20 F_REFUSE (C15: the far register busy with the other crossing caller) + 10 N_TCLAIM
  (the lost forward).  Lost-forward cost: origin trunk held 504/544 ms (C/A), tone 534/574 ms after the key, i.e.
  6 ms after the last digit (T_CLAIM 250 after b ~ end of h s at scale 8).

### T9 t9_cross_s1 (SCALE1, real timers) -- running from 15:30; build_s1 250 s
- first crossing (log t=730-760): A flood classified at B 730.19; C flood written 4.08 ms after A's, classified
  19.36 ms after (hop 18.47: waited out the 18 ms T_ARM watch), forwarded (fst=0, rsb=01).  As predicted: no loss.
  Both calls F_REFUSE (C15), tone 132 ms after the last digit.
- DONE: +seed=9 +dur_ms=63000 +drain_ms=10000 pairs A21C22,C21A22 gap 1 per 7000 jit 30. sim 73.0 s, wall 5173 s
  (71 wall-s/sim-s). 18 calls = 9 crossings. INVARIANT 38/38, safety 0, STUCK 0.
- B: 18 in, 18 forwarded, 0 FWDBUSY, 0 RESNONE.  Crossing upstream-write gaps 1.14, 4.08, 4.11, 5.49, 6.45, 8.58,
  20.2, 21.2, 26.8 ms: the six <= 8.6 ms (ALL lost at scale 8) were classified 18.6-19.4 ms after the first (the
  watch) and forwarded.  hop p50 3 / p90 18 / max 21.3 ms; forward 10.67 mean after classification (max 11.7).
  res_hold at real timers 1833 ms mean (p50 1739, max 1938); B res_mean .52 E, mon_mean .53 E.
- All 18 calls F_REFUSE (C15: each far register busy with the other crossing caller).  reg_maxrun 4.4 s.
- CONCLUSION C14 forwarder: at real timers two crossing floods never lose a forward on this chain (the T_ARM watch
  serialises them past the 11 ms forward); scale 8 loses every second flood within ~12 ms.

### T8 t8_e2e_heavy_nres1 (s8, LD_NRES=1): T3 knobs (+seed=7 idle 40000 mode 5 orig_x 5 pnet 1000)
- sim 22.5 s, wall 1178 s. 37 calls. INVARIANT 38/38, safety 0, STUCK 0.
- B: 35 floods in, 26 forwarded, 8 RESNONE (22.9 pct) + 1 FWDBUSY.  Engset prediction (1 resolver, 2 sources,
  each with a flood pending at B for p = 0.85/s x 0.26 s = 0.22 of the time): 22 pct.  res_mean .34, res_hold 262.
- Every RESNONE flood -> caller N_TCLAIM, cannot-complete 533-574 ms after the key, mostly before the last digit;
  origin trunk (A-B channel) held 504-544 ms; B in-port + a B monitor held the same (no B resolver).
- End to end A>C 6/17, C>A 6/20 OK; failures: C15 13, B RESNONE 8, B FWDBUSY 1, NODT 1, CUT 2.
- So on this chain NRES=2 is exactly enough (never RESNONE, T1/T3/T4/T9); NRES=1 loses ~Engset(k=2,n=1).

### T2 t2_e2e_med (s8): +seed=3 +dur_ms=24000 +idle_ms=90000 mode 5 orig_x 5 pnet 1000 -- mix (a), medium
- sim 26.5 s, wall 1977 s. 21 calls. INVARIANT 38/38, safety 0, STUCK 0.
- attempts/s A .42 C .46; reg_occ A .48 C .47; carried 1.28 E; links busy_mean 2.07, max 4.
- B: 21 in, 21 forwarded; res_mean .23 res_max 2; mon_mean .24; forward 10.55 (max 10.74); res_hold 262.
- End to end: A>C 8/10, C>A 9/11 OK; the 4 failures all C15 (F_REFUSE); att_refuse/claims A 2/11, C 2/10.
- dial tone delay mean 67 ms, p99 747.

### T5 t5_borig (s8): +seed=4 +dur_ms=20000 +idle_ms=40000 +orig_x=2 +pnet=1000 -- mix (c) B-originated both ways
- sim 22.5 s, wall 1961 s. 25 calls. INVARIANT 38/38, safety 0, STUCK 0.
- B attempts 1.25/s; B reg_occ .90 (saturated): dial tone delay mean 676 ms, p99 2260; 1 NODT (3 s).
- 24 B floods, each seized A and C (A and C classify 24 each, all doomed-sweep nofwd_empty), all 24 claimed
  (A 14, C 10), losing direction dropped at the claim; origin write->claim 273 ms mean.
- End to end B>A 11/14, B>C 10/11 OK; BUSY 2 (called line busy), NODT 1, F_REFUSE 1 (A, t5 CALL id=2).
- The one refusal: A had no originating lines, yet A's register was busy at the claim (TP 1680.001).  Previous call
  B56->A21 ended at 1633 (caller B56 cleared first); A21 (callee, lag up to 50 ms) was still off hook when A17 and
  then A21's port released (T_REL 32 after 1633) -> A21 became a CALLER in A's one register (dial tone) until its
  hang-up + CLR -> the next B flood's claim at A (47 ms after the end) was refused.  Mechanism: whenever the caller
  clears first, the callee's exchange register is taken by the callee for lag + CLR (and the other way round).
  At real timers ~0.4 + 0.26 s per call end, longer with slow hanger-uppers.  Part of C15 (register busy).

### T6 t6_links (s8): +seed=6 +dur_ms=20000 +idle_ms=20000 +pnet=1000 +hold_ms=6000 -- uniform, all network, OVERLOAD
- sim 22.5 s, wall 2822 s. 119 calls. INVARIANT 38/38, safety 0.  STUCK marker_state A 9381..20055 (18.2 s) =
  watchdog false positive: A's marker served callers back to back (dial tone every ~0.7-0.8 s: 2296, 3038, 3780,
  4562, 5304, 6166 ...), never idle for a whole ms sample; cleared when traffic stopped; the register watchdog never
  fired.  Not a jam.
- attempts/s A 2.2 B 1.45 C 2.3; reg_occ A .96 B .86 C .995; dial tone delay mean 689, p99 2903; NODT 29/119.
- OUTCOME: OK 5 (4 pct), BUSY 4, NOGO 63, NODT 29, CUT 18.  att_refuse/claims A 30/32, B 17/20, C 20/20:
  CONGESTION COLLAPSE by C15 -- nearly every claim finds the far register busy, yet each doomed call holds its
  origin register for the whole dial (refusal heard only after h s), which keeps every register saturated.
- B: 51 floods in, 49 forwarded, 2 FWDBUSY (fst=2, scale-8 type), 0 RESNONE; res_mean .64 res_max 2; mon_max 2;
  forward p99 17.7 ms (B's own origin sweeps interleave); links busy_mean 3.2/2.5, max 7 (A-B) / 5: never full,
  no N_NOTRUNK, no NFEMPTY at B, no glare, no leg glare: C15 stops calls long before the links fill.

### T7 t7_step (s8): +seed=8 +dur_ms=22000 +idle_ms=8000 +switch_ms=10000 +idle2_ms=120000 +pnet=600 -- EXTREME overload
- sim 24.5 s, wall ~3200 s. 213 calls. INVARIANT 38/38 after the 2.5 s drain; safety 0; STUCK marker_state A
  7527..22055 (false positive, continuous service as T6).
- NOTE the step is soft: phones scheduled before the switch keep their 8 s-mean idle, so offered load decays over
  ~10 s; attempts/s still 5-7 at t=19 s.  Recovery shown only by the drain (everything idle, 38/38).
- attempts/s A 3.1 B 3.1 C 3.5 (~10x T2); reg_occ .96-.996; dial tone delay mean 818 ms, p99 2807; NODT 103 (48 pct).
- OUTCOME OK 35 (16 pct: 32 local + 3 network!), NOGO 56 (F_REFUSE 37 + inferred), BUSY 12, NODT 103, CUT 7.
  att_refuse/claims A 23/23, B 15/16, C 23/26: network completion ~2 pct.
- B: 43 in, 41 forwarded, 2 FWDBUSY (fst=2), 0 RESNONE, res_max 2, mon_max 2, res_mean .49; no glare, no stuck.

### FIX: pending forward (work/load/transit/fix/net_unit.v, RTL_fix.list; obj_fx; build 456 s)
- One pending slot: a seizure held while the forwarder is busy / no resolver is kept (pf_v, pf_in, pf_mask,
  pf_age) and started through F_WANT when fst is idle and a resolver is free; dropped on UNHOLD of that port, on
  a claim of it here, on its M seen low, or after PF_MAX = 24 ms.  ~3 packages ('574 port+mask, '161 age, flag).
- t4_cross_s8_fix (T4 knobs, seed 9): 10 B seizures not forwarded at once, ALL 10 forwarded 13.4-17.7 ms later,
  never 0.  Calls: 30/30 now F_REFUSE (C15) instead of 10 N_TCLAIM + 20 F_REFUSE: the transit no longer loses
  the flood; the crossing still fails at the far registers (C15).  INVARIANT 38/38, safety 0.  wall 3080 s.
- t3_e2e_heavy_fix (T3 knobs, seed 7): 34 B floods, 34 forwarded (the 2 T3 losses A55 @9812.3, A71 @19487.3
  forwarded 15.7 / 14.7 ms late); OK 13 as T3; the N_TCLAIM became F_REFUSE (C15 at C).  38/38, safety 0. wall 2623.

## Who held the far register at each refusal (refuse.py, 175 refusals over T1 T2 T3 T5 T6 T7 T9)
- orig (its own outgoing network caller dialling) alone 126; with inc/local/clear 30+; local alone 12; inc alone 4;
  'clear' (second party to hang up taken as a caller) alone 1 (T5) + 8 mixed.  C15 = mostly two registers each
  busy with its own network caller.

## Summary table (B = transit; att/s per exchange; reg_occ; links mean/max of 8)
```
t1_unif_heavy        att/s 1.200/0.867/1.600 reg 0.738/0.590/0.893 | B in=23 fwd=23 FWDBUSY=0 RESNONE=0 res 0.400/2 mon 0.415/2 | links A1:1.682/4 B1:1.696/4 B3:1.859/5 C1:1.848/5 | refuse/claims 7/11 3/9 9/10
t2_e2e_med           att/s 0.417/0.000/0.458 reg 0.475/0.000/0.473 | B in=21 fwd=21 FWDBUSY=0 RESNONE=0 res 0.230/2 mon 0.238/2 | links A1:2.065/4 B1:2.075/4 B3:2.075/4 C1:2.069/4 | refuse/claims 2/11 0/0 2/10
t3_e2e_heavy         att/s 0.850/0.000/1.000 reg 0.738/0.000/0.758 | B in=34 fwd=32 FWDBUSY=2 RESNONE=0 res 0.417/2 mon 0.461/2 | links A1:2.126/5 B1:2.144/5 B3:2.091/4 C1:2.075/4 | refuse/claims 11/18 0/0 8/14
t4_cross_s8          att/s 0.714/0.000/0.714 reg 0.468/0.000/0.439 | B in=30 fwd=20 FWDBUSY=10 RESNONE=0 res 0.248/2 mon 0.386/2 | links A1:0.785/2 B1:0.798/2 B3:0.788/2 C1:0.775/2 | refuse/claims 10/10 0/0 10/10
t5_borig             att/s 0.000/1.250/0.000 reg 0.255/0.898/0.192 | B in=0 fwd=0 FWDBUSY=0 RESNONE=0 res 0.000/0 mon 0.000/0 | links A1:1.317/3 B1:1.329/3 B3:1.158/3 C1:1.150/3 | refuse/claims 1/14 0/0 0/10
t6_links             att/s 2.200/1.450/2.300 reg 0.956/0.857/0.995 | B in=51 fwd=49 FWDBUSY=2 RESNONE=0 res 0.638/2 mon 0.691/2 | links A1:3.160/7 B1:3.196/6 B3:2.472/5 C1:2.454/5 | refuse/claims 30/32 17/20 20/20
t7_step              att/s 3.091/3.137/3.455 reg 0.996/0.965/0.964 | B in=43 fwd=41 FWDBUSY=2 RESNONE=0 res 0.488/2 mon 0.531/2 | links A1:2.018/5 B1:2.039/5 B3:2.140/5 C1:2.113/5 | refuse/claims 23/23 15/16 23/26
t8_e2e_heavy_nres1   att/s 0.850/0.000/1.000 reg 0.750/0.000/0.748 | B in=35 fwd=26 FWDBUSY=1 RESNONE=8 res 0.341/1 mon 0.476/2 | links A1:1.962/5 B1:1.974/5 B3:1.939/4 C1:1.927/4 | refuse/claims 7/14 0/0 6/12
t9_cross_s1          att/s 0.143/0.000/0.143 reg 0.630/0.000/0.602 | B in=18 fwd=18 FWDBUSY=0 RESNONE=0 res 0.524/2 mon 0.526/2 | links A1:1.367/2 B1:1.403/2 B3:1.403/2 C1:1.368/2 | refuse/claims 9/9 0/0 9/9
t4_cross_s8_fix      att/s 0.714/0.000/0.714 reg 0.471/0.000/0.443 | B in=30 fwd=30 FWDBUSY=10 RESNONE=0 res 0.369/2 mon 0.386/2 | links A1:0.970/2 B1:0.991/2 B3:0.991/2 C1:0.969/2 | refuse/claims 15/15 0/0 15/15
```

### T10 t10_e2e_heavy_s1 (SCALE1): +seed=7 +dur_ms=60000 +drain_ms=10000 +idle_ms=320000 mode 5 orig_x 5 pnet 1000
- sim 70.0 s, wall 6306 s.  Only 9 calls (thin: a sanity point, not a statistic).  INVARIANT 38/38, safety 0.
- attempts/s A .083 C .067; reg_occ A .53 C .47; OK 8, CUT 1, no refusal in this small sample.
- B: 9 in, 9 forwarded, res_hold 1847 ms mean (p50 1939), res_max 1, mon_max 1, 1 R_GONE (the call cut at the
  hang-up); forward 10.58 ms after classification; hop 2.13; origin write -> claim 1952 (A) / 1753 (C) ms;
  post-dial alert 134 ms.

## JOB1 finished 23:32 (all steps rc=0).  Obj dirs pruned to binaries.
