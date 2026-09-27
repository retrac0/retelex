# cap2 -- traffic capacity of two exchanges on one link (NOTES, running)

Agent working dir: /home/joel/telco/newimpl/build/flood/work/load/cap2
Runner: runq.sh QUEUE (sequential, each job through sim.sh with timeout); two lanes q1/q2 at most.
Logs: NAME.log, NAME.rc (rc, wall_s). runq.out has start/done times.

## Plan
- tb_load2 (8-ch local trunk) pnet 1000 (q1) and 300 (q2): idle_ms 30k 60k 15k 6k 120k, seed 11, dur 12 s, drain 2.5 s
- tb_load2b (2 baseband ties) same sweep
- knee: second seed; one-way (dest_mode=1) vs two-way at equal network load
- SCALE1 build + one point; NMON/NRES 4 build + one point

## Prior (smoke, work/load/smoke/load2_light.log: idle 60k pnet 500 seed 11, dur 20 s)
- 34 calls; N: 17 -> 8 OK, 7 NOGO all why=F_REFUSE (att_refuse: far register busy), 2 CUT. 41% of network calls refused at 0.75-0.95 att/s/exch.
- reg_occ A 0.50 B 0.53; origin_occ 0.20/0.32; mon_mean 0.13/0.08; res 0; link busy_mean 1.2 of 8.
- speed: 22.5 sim s in 2648 wall s (cpu 1127 s) = 20 ms sim per cpu s.

## Results (appended as they come)

### 12:51 first two points (tb_load2, seed 11, dur 12 s, 14.5 sim s, 960 wall s each = 15 ms sim / wall s)
- l2_p1000_i30k: 43 calls, ALL network: OK 1, NOGO 26 (all F_REFUSE), NODT 8, CUT 7, BUSY 1.
  att/s A 1.58 B 2.00. claims A 14 (take 0, refuse 14), B 15 (take 2, refuse 13). reg_occ A .955 B .901,
  origin_occ .82/.71, link busy_mean 2.15 of 8 (max 5). carried 0.26 E. dt delay mean 676 p99 2829.
  => CONGESTION COLLAPSE at 1.6-2 att/s/exch: each origin holds its register through 1 e b h s, so the far
  register is almost always busy when a claim arrives; refused calls cost the full dial anyway.
- l2_p300_i30k: 42 calls: L 29 (OK 19, BUSY 2, NODT 1, NOSPEECH 1, CUT 6), N 13 (OK 4, NOGO 6 F_REFUSE, NODT 2, CUT 1).
  reg_occ .67/.79; claims A 8 (4 take/4 refuse), B 2 (0/2). carried 3.17 E. link 1.48 of 8.
  NOSPEECH id=21 is a bench artefact: ans=5737 end=5751, a 14 ms exponential hold < verify_ms 20.
- invariants 26/26 PASS both; 0 wrong, 0 phantom, 0 stuck.
- Slot contention: ~25 jobs from other agents queue on sim.sh; expect waits.
- Plan change: pnet 1000 knee is below idle 30k -> sweep 60k 120k 240k 15k; c2 harness build
  (cap2/load_harness_c2.svh: C2REF/C2TAKE lines with the marker state at each refusal/take,
  SUMMARY c2reg register split yield/claimed/other, c2refst) for tb_load2.

### 13:20 regmodel.py (call-level model of the harness + the RTL's register rules; NOT RTL)
Validated against the RTL points so far (scale 8):
| point | RTL | model |
| p1000 i30k | att 1.58/2.00/s, refuse 27/29=93%, reg .955/.901, NODT 8/43, carried .26 E, OK 1 | att 1.50, refuse 93%, reg .96, nodt 16%, carried .30 E, OK 5.4/min/ex |
| p300 i30k  | refuse 6/10, reg .67/.79, N ok 4/13, carried 3.17 E, OK 57/min/ex | refuse 64%, reg .74, N ok 31%, carried 3.13 E, OK 62/min/ex |
| smoke p500 i60k | refuse 7/16, reg .50/.53, N ok 8/17, carried 1.93 E | refuse 46%, reg .48, N ok 51%, carried 1.59 |
Model sweep, scale 8, 48 lines, carried OK calls/min/exchange (network part), refuse = claims refused:
pnet 1000 baseline: i240k 9.2 (ref 19%), i120k 16.2 (33%), i60k 19.0 (55%) PEAK, i30k 5.4 (93%), i15k 0, i6k 0  -> COLLAPSE
  refusals by far-register holder at i30k: yield 803 / local 95 => mutual refusal (both registers in YIELD)
pnet 300 baseline: total 11.4/22.3/38.7/61.8/71.1/60.5; network 3.4/6.2/7.6/8.6/0.9/0.0 (N collapses past i30k)
fixes (pnet 1000 network OK/min/ex at i240k..i6k):
  connect_at_claim: 9.7 19.0 26.7 29.7 6.7 0   (collapse delayed ~2x)
  nreg=2:           11.2 20.7 33.9 43.6 8.3 0  (still collapses)
  nreg=3:           12.8 22.4 41.4 61.3 69.2 0.2
  far_noreg (monitor collects h s, no far register): 11.3 21.5 39.5 63.3 63.7 53.0 (graceful: saturates)
  far_noreg+org_free_at_key: 11.4 22.8 41.3 66.4 82.4 91.5 (trunks become the limit: notrunk 41-71%)

### 13:30 more model + the RTL i60k point
- l2_p1000_i60k (RTL): 22 calls, OK 7, NOGO 12 (F_REFUSE), NODT 1, NOSPEECH 1, CUT 1; att .83/1.00 /s; refuse 12/21=57%;
  reg .77/.78; carried .98 E. Model: refuse 59%, reg .68, N ok 39%, carried 1.03 E.  Agrees.
- NOSPEECH x2 so far (ids p300_i30k#21 talk 14 ms, p1000_i60k#15 talk 18 ms): both talk < lag 50 ms -> harness
  artefact (callee's "partner gone" rule, load_harness.svh ~1027, cuts the call within lag on the answer's ms).
- Model SCALE1 (real timers), 48 lines, pnet 1000: idle 2400k 1.0 OK/min/ex (ref 12%), 1200k [=3 calls/line/h] 1.8 (19%),
  600k 2.9 (36%) PEAK = 175 calls/h/ex, 300k 2.3 (73%), 150k 0.25 (98%), 75k 0.  pnet 300 at 1200k: 2.3/min (137/h), refuse 9.8%.
  Scale-8 peak 19/min/ex vs SCALE1 2.9 -> conversion factor ~6.5 (not 8: pulses scale 5x, idg 7.2x, pre 8.3x).
- Model CH=2 (tb_load2b): trunk blocking acts as admission control: pnet 1000 i30k carries 17/min/ex vs 5.4 with CH=8.
  -> RTL test queued: l2b_p1000_i30k should carry MORE than l2_p1000_i30k.
- Model one-way (mode=1 orig=A): 0 refusals ever (A's one register serialises its claims), A saturates ~77/min;
  at equal total offered network load (1.5 att/s) one-way carries ~72/min vs two-way 38/min (55% refused).
  -> RTL test queued: l2_oneway_i30k (orig_x=1, dest_mode=1) vs l2_p1000_i60k.

### model at REAL timers with a 1-4 s dial-tone-to-first-pulse reaction (C15's assumption; harness SCALE1 uses 0.5 s)
(model_s1_react.txt) 48 lines, harness hold 10 s.  idle 1200k = 3 calls/line/h, 600k = 6, 300k = 12.
pnet 300 baseline: 3/h: refuse 15%, N ok 83%, dt mean .54 s p99 6.1 s | 6/h: refuse 38%, N ok 59%, dt p99 15.6 s | 12/h: refuse 73%, N ok 24%
pnet 1000 baseline: 3/h: 98 net calls/h/ex carried, refuse 29%, dt p99 12.7 s | 6/h: 130/h PEAK, refuse 49% | 12/h: 64/h, refuse 86%
fixes at pnet 1000, 6/h: nreg=2 refuse 17% (232/h); nreg=3 3% (253/h); connect_at_claim 34% (168/h); far_noreg 0% (254/h, dt p99 18 s)
13:09 build_c2_load2 done (222 s).  l2_oneway_i30k started.

### 13:24 l2_oneway_i30k (c2 build; dest_mode=1 orig_x=1: only A originates, all to B), 835 wall s, 14.5 sim s
- A: 19 att (1.58/s), OK 14 (70/min), NODT 2, CUT 3; B took 15/15 claims, 0 refused. reg A .93 (yield .82), B .47 (claimed .47).
- vs TWO-WAY at about the same total offered network load (l2_p1000_i60k: 1.83 att/s total): OK 7 (35/min), 12 refused (57%).
- vs two-way l2_p1000_i30k (3.58 att/s total): OK 1.   Model predicted one-way i30k: 72/min, 0 refused, NODT 19%. Confirmed.
- => refusals come from the two registers refusing each other; one-way traffic is never refused (A's one register
  serialises its claims to B).
- harness copy bug: my c2 counter insertion displaced 'else x_regrun=0' -> reg_maxrun_ms reads 1 in obj_c2_load2 and the
  cac build (only that stat). Fixed in load_harness_c2.svh for later builds (S1). take_st/refuse_st print fixed in parse.py.
- model: a bounded claim wait (C15 fix 2) barely helps: scale 8 pnet 1000 i60k refuse 55% -> 50% at a 70 ms wait;
  real timers pnet 300 6/h refuse 38% -> 31% at 500 ms.  The busy far register is mostly an origin in YIELD with ~2 s to go.
- SCALE1 check switched to idle 190k (the collapse point, = scale-8 i30k by model: refuse 93% vs 92%, reg .956 vs .950),
  dur 60 s: model spread over 7 replications 78-96% refused. Queued in lane 1 (lane 1 keeps its slot; lane 2 waits).
- queued RTL fix test: cap2/fix_cac/net_unit.v (N_DONE at the claim, net_unit.v:881 without o_last), run cac_p1000_i30k.
  Model predicts OK 29.7/min/ex at i30k vs 5.4 baseline.

### real-timer capacity table (regmodel, calibrated on the RTL points): captable_real.txt

== real timers, pre (500, 0), pnet 30%, 48 lines/ex, hold 10 s mean
 calls/line/h | att/h/ex | carried/h/ex (net) | net completed | claims refused | reg occ | dt mean / p99 s | NODT
            1 |       45 |       45 (  12)   |         99%   |            1%  | 0.04    |   0.1 /   2.4  | 0.0%
            2 |       94 |       90 (  24)   |         88%   |            9%  | 0.09    |   0.2 /   2.9  | 0.0%
            3 |      143 |      135 (  38)   |         89%   |            9%  | 0.14    |   0.3 /   4.4  | 0.0%
            4 |      181 |      166 (  44)   |         80%   |           18%  | 0.18    |   0.3 /   4.4  | 0.0%
            6 |      284 |      250 (  67)   |         72%   |           26%  | 0.28    |   0.6 /   6.7  | 0.0%
            8 |      376 |      323 (  71)   |         66%   |           30%  | 0.36    |   0.8 /   7.7  | 0.0%
           12 |      524 |      419 (  83)   |         52%   |           44%  | 0.49    |   1.3 /  11.1  | 0.1%
           24 |      978 |      618 (  53)   |         17%   |           80%  | 0.82    |   3.9 /  18.8  | 4.6%

== real timers, pre (500, 0), pnet 100%, 48 lines/ex, hold 10 s mean
 calls/line/h | att/h/ex | carried/h/ex (net) | net completed | claims refused | reg occ | dt mean / p99 s | NODT
            1 |       49 |       44 (  44)   |         90%   |            9%  | 0.09    |   0.2 /   4.1  | 0.0%
            2 |       95 |       83 (  83)   |         86%   |           12%  | 0.18    |   0.4 /   4.5  | 0.0%
            3 |      139 |      112 ( 112)   |         81%   |           18%  | 0.26    |   0.7 /   8.4  | 0.1%
            4 |      192 |      135 ( 135)   |         70%   |           28%  | 0.34    |   0.9 /   9.7  | 0.0%
            6 |      281 |      170 ( 170)   |         60%   |           38%  | 0.48    |   1.7 /  14.0  | 0.2%
            8 |      369 |      180 ( 180)   |         49%   |           49%  | 0.61    |   2.3 /  16.5  | 1.0%
           12 |      557 |      142 ( 142)   |         26%   |           73%  | 0.80    |   3.8 /  18.5  | 4.1%
           24 |     1040 |       17 (  17)   |          2%   |           98%  | 0.98    |   7.4 /  19.5  | 29.6%

== real timers, pre (1000, 4000), pnet 30%, 48 lines/ex, hold 10 s mean
 calls/line/h | att/h/ex | carried/h/ex (net) | net completed | claims refused | reg occ | dt mean / p99 s | NODT
            1 |       43 |       43 (  12)   |         96%   |            3%  | 0.07    |   0.1 /   2.3  | 0.0%
            2 |       92 |       89 (  24)   |         92%   |            7%  | 0.14    |   0.4 /   5.7  | 0.0%
            3 |      143 |      131 (  36)   |         82%   |           16%  | 0.22    |   0.6 /   6.9  | 0.2%
            4 |      182 |      165 (  43)   |         75%   |           23%  | 0.28    |   1.0 /  11.3  | 0.0%
            6 |      278 |      235 (  50)   |         61%   |           37%  | 0.42    |   1.7 /  15.5  | 0.4%
            8 |      361 |      284 (  50)   |         47%   |           51%  | 0.53    |   2.2 /  15.4  | 0.9%
           12 |      537 |      371 (  42)   |         26%   |           70%  | 0.74    |   3.9 /  19.0  | 4.9%
           24 |      982 |      434 (   5)   |          2%   |           97%  | 0.97    |   7.4 /  19.7  | 28.8%

== real timers, pre (1000, 4000), pnet 100%, 48 lines/ex, hold 10 s mean
 calls/line/h | att/h/ex | carried/h/ex (net) | net completed | claims refused | reg occ | dt mean / p99 s | NODT
            1 |       47 |       43 (  43)   |         93%   |            6%  | 0.12    |   0.3 /   5.5  | 0.0%
            2 |       95 |       77 (  77)   |         81%   |           19%  | 0.23    |   0.8 /   8.8  | 0.0%
            3 |      143 |      101 ( 101)   |         70%   |           29%  | 0.34    |   1.3 /  12.6  | 0.1%
            4 |      185 |      116 ( 116)   |         63%   |           36%  | 0.42    |   1.8 /  15.2  | 0.5%
            6 |      278 |      127 ( 127)   |         46%   |           52%  | 0.59    |   2.7 /  17.7  | 2.9%
            8 |      359 |      115 ( 115)   |         32%   |           66%  | 0.72    |   3.9 /  18.8  | 4.4%
           12 |      548 |       61 (  61)   |         11%   |           86%  | 0.89    |   5.9 /  19.3  | 17.5%
           24 |     1012 |        4 (   4)   |          0%   |           99%  | 0.99    |   8.5 /  19.7  | 48.1%

### RTL vs model (compare.py; each cell RTL then model)
run                  |  att/s/ex |  OK/min/ex |  N ok% |  refuse% |       reg |  NODT% | notrunk | carried E
l2_p1000_i30k        | 1.79 1.49 |   2.5  6.0 |   3   7 |  93  92  | 0.955/0.901 0.95 |  19  17 |  0   0% | 0.260 0.32   (RTL: 43 calls, 29 claims, T=12s)
l2_p1000_i60k        | 0.92 0.75 |  17.5 19.7 |  33  44 |  57  55  | 0.771/0.777 0.67 |   5   1 |  0   0% | 0.979 0.98   (RTL: 22 calls, 21 claims, T=12s)
l2_p300_i30k         | 1.75 1.45 |  57.5 62.2 |  33  32 |  60  66  | 0.672/0.791 0.73 |   7   1 |  0   0% | 3.165 3.07   (RTL: 42 calls, 10 claims, T=12s)
l2_oneway_i30k       | 0.79 0.73 |  35.0 35.9 |  88  82 |   0   0  | 0.932/0.468 0.69 |  11  16 |  0   0% | 1.188 1.74   (RTL: 19 calls, 15 claims, T=12s)
load2_light          | 0.85 0.76 |  34.5 33.4 |  53  55 |  44  43  | 0.498/0.533 0.50 |   0   1 |  0   0% | 1.927 1.66   (RTL: 34 calls, 16 claims, T=20s)

### 13:52 FINDINGS DRAFT (for the successor if cut off)
1. register-congestion-collapse (C15, overload, high, reproduced): two-way network traffic -> carried network calls
   DECREASE past ~0.75 att/s/ex (scale 8): p1000 i60k 17.5 OK/min/ex -> i30k 2.5 (1 OK in 43). Mechanism
   mini_marker.v:282 (refuse at once), :273-274, :430-432/:496-520 (YIELD holds the register), net_unit.v:410,:881 (origin
   holds register to o_last), :795-798 (refusal's CLM taken as a claim). Real timers (model, RTL-calibrated): peak 130-175
   net calls/h/ex at 6-8 att/line/h; 24 att/line/h -> 4-17/h.
2. symmetric-mutual-refusal (C15, capacity): one-way (oneway_i30k) 0/15 refused, 70 OK/min vs two-way i60k 57% refused 35/min.
3. design-load refusal (C15): 48 lines 3 calls/line/h 30% leaving: 9-16% of claims refused (real timers, pre 0.5-4 s);
   1% needs < ~10 att/h/ex.
4. docs (C15 docs side / new specifics): analysis/topology.md §11 (old network.md §5/5.1, exch.py net: answered() gives back
   only the origin's register; the owner's register is never charged, sim/exch.py:2499-2525) sizes by link erlangs;
   register.md §4 "not refused: dial tone is late"; network.md §3.4 "a busy register only delays dial tone"; numbering.md:74
   names the refusal, nothing quantifies it. RTL link occupancy stays <= 2.4 of 8 channels while 57-93% of claims are refused.
5. bench-gap new: NOSPEECH artefact (talk < lag).  6. bench-gap new: scale-8 traffic conversion ~6.4x not 8; SCALE1 pre 500 ms.
7. pending: trunk scarcity as admission control (l2b), connect-at-claim RTL fix, SCALE1 check, overload i15k safety.
Cluster notes: C02 structurally impossible here (one register a side -> at most one claim in flight at an exchange);
C14 leaf-sweeps-for-nothing seen in every run (nofwd_empty == seized_in); C01 signature = C2REF with st=0 (IDLE) or 3.

### scale-8 model curves (curve8.txt)

== scale 8, CH=8, pnet 30%  (idle ms: att/s/ex -> OK/min/ex [net], net ok%, refuse%, reg, trunk E, notrunk%, NODT%)
  240000: 0.20 ->  11.3 [ 3.3]  N  90%  ref   8%  reg 0.11  trk 0.27  notrunk   0%  NODT   0%
  120000: 0.39 ->  21.3 [ 5.4]  N  77%  ref  21%  reg 0.22  trk 0.46  notrunk   0%  NODT   0%
   60000: 0.75 ->  38.2 [ 8.4]  N  62%  ref  35%  reg 0.41  trk 0.81  notrunk   0%  NODT   0%
   40000: 1.12 ->  52.3 [ 8.8]  N  45%  ref  52%  reg 0.58  trk 0.99  notrunk   0%  NODT   0%
   30000: 1.45 ->  62.2 [ 8.4]  N  32%  ref  66%  reg 0.73  trk 1.11  notrunk   0%  NODT   1%
   20000: 2.06 ->  71.7 [ 3.8]  N  10%  ref  87%  reg 0.90  trk 1.08  notrunk   0%  NODT   9%
   15000: 2.57 ->  73.2 [ 1.2]  N   3%  ref  96%  reg 0.97  trk 1.00  notrunk   0%  NODT  20%
    6000: 5.16 ->  60.7 [ 0.0]  N   0%  ref 100%  reg 1.00  trk 0.97  notrunk   0%  NODT  58%

== scale 8, CH=8, pnet 100%  (idle ms: att/s/ex -> OK/min/ex [net], net ok%, refuse%, reg, trunk E, notrunk%, NODT%)
  240000: 0.20 ->   9.8 [ 9.8]  N  83%  ref  16%  reg 0.21  trk 0.81  notrunk   0%  NODT   0%
  120000: 0.40 ->  16.4 [16.4]  N  68%  ref  31%  reg 0.40  trk 1.49  notrunk   0%  NODT   0%
   60000: 0.75 ->  19.7 [19.7]  N  44%  ref  55%  reg 0.67  trk 2.19  notrunk   0%  NODT   1%
   40000: 1.13 ->  13.0 [13.0]  N  19%  ref  79%  reg 0.86  trk 2.32  notrunk   0%  NODT   7%
   30000: 1.49 ->   6.0 [ 6.0]  N   7%  ref  92%  reg 0.95  trk 2.24  notrunk   0%  NODT  17%
   20000: 2.09 ->   0.9 [ 0.9]  N   1%  ref  99%  reg 0.99  trk 2.10  notrunk   0%  NODT  36%
   15000: 2.71 ->   0.0 [ 0.0]  N   0%  ref 100%  reg 1.00  trk 2.08  notrunk   0%  NODT  50%
    6000: 5.40 ->   0.0 [ 0.0]  N   0%  ref 100%  reg 1.00  trk 2.08  notrunk   0%  NODT  75%

== scale 8, CH=2, pnet 30%  (idle ms: att/s/ex -> OK/min/ex [net], net ok%, refuse%, reg, trunk E, notrunk%, NODT%)
  240000: 0.19 ->  11.0 [ 3.0]  N  88%  ref   8%  reg 0.11  trk 0.23  notrunk   1%  NODT   0%
  120000: 0.39 ->  21.4 [ 5.5]  N  77%  ref  15%  reg 0.22  trk 0.48  notrunk   5%  NODT   0%
   60000: 0.75 ->  37.6 [ 7.8]  N  56%  ref  31%  reg 0.39  trk 0.71  notrunk  14%  NODT   0%
   40000: 1.09 ->  50.7 [ 9.0]  N  44%  ref  41%  reg 0.53  trk 0.91  notrunk  21%  NODT   0%
   30000: 1.43 ->  62.1 [ 7.9]  N  30%  ref  56%  reg 0.66  trk 0.99  notrunk  23%  NODT   1%
   20000: 2.06 ->  75.0 [ 4.5]  N  12%  ref  83%  reg 0.87  trk 0.96  notrunk  18%  NODT   6%
   15000: 2.60 ->  76.4 [ 1.6]  N   3%  ref  95%  reg 0.96  trk 0.93  notrunk  11%  NODT  17%
    6000: 5.13 ->  61.5 [ 0.0]  N   0%  ref 100%  reg 1.00  trk 0.93  notrunk   5%  NODT  57%

== scale 8, CH=2, pnet 100%  (idle ms: att/s/ex -> OK/min/ex [net], net ok%, refuse%, reg, trunk E, notrunk%, NODT%)
  240000: 0.20 ->   9.1 [ 9.1]  N  76%  ref   9%  reg 0.18  trk 0.74  notrunk  16%  NODT   0%
  120000: 0.39 ->  13.6 [13.6]  N  58%  ref  12%  reg 0.29  trk 1.13  notrunk  33%  NODT   0%
   60000: 0.76 ->  16.7 [16.7]  N  37%  ref  20%  reg 0.41  trk 1.46  notrunk  53%  NODT   0%
   40000: 1.16 ->  17.2 [17.2]  N  25%  ref  32%  reg 0.50  trk 1.60  notrunk  63%  NODT   0%
   30000: 1.54 ->  17.4 [17.4]  N  19%  ref  39%  reg 0.57  trk 1.67  notrunk  68%  NODT   1%
   20000: 2.24 ->  13.4 [13.4]  N  10%  ref  67%  reg 0.75  trk 1.77  notrunk  65%  NODT   4%
   15000: 2.88 ->   4.3 [ 4.3]  N   2%  ref  93%  reg 0.94  trk 1.81  notrunk  47%  NODT  17%
    6000: 5.53 ->   0.0 [ 0.0]  N   0%  ref 100%  reg 1.00  trk 1.83  notrunk  21%  NODT  58%

### 14:15 throttle contention
- 15-20 jobs wait on sim.sh (some waited 1.5 h). Switched to runqb.sh (batches of K jobs per slot).
- lane 1 batch: build_c2_load2_cac, cac_p1000_i30k, l2b_p1000_i30k.  lane 2 batch (rewritten): build_c2_load2_s1,
  s1_p1000_i190k (SCALE1 check, ~85 min), l2_p300_i60k.  Both waiting since 13:50.
- Model predictions for them: cac i30k OK ~30/min/ex (vs 6), refuse ~66%; l2b p1000 i30k OK 17.4/min/ex, refuse 39%,
  N_NOTRUNK 68% of net attempts; s1 i190k refuse ~93% (78-96% over 60 s), OK ~0.8/min/ex, reg .96, NODT ~19%.
16:26:30 lane 2 got a slot 16:24; build_c2_load2_s1 84 s; s1_p1000_i190k running

### 17:06 s1_p1000_i190k (SCALE1 real timers, c2 build; idle 190 s, pnet 100%, dur 60 s, 75 sim s, 2386 wall s)
- 33 calls: OK 1, NOGO 18 (F_REFUSE), BUSY 1 (F_BUSY), NODT 8 (20 s dt timeout), CUT 5. att .27/.28 /s/ex.
- claims A 10 (0 take / 10 refuse), B 12 (2/10): 91% refused (model 93%); reg .957/.872 (model .95); NODT 24% (18%).
- refusal states: YIELD=10 at A and YIELD=10 at B: EVERY refusal found the far register holding its own network origin
  (mutual refusal), none local, none in WATCH/IDLE (no C01 signature).  c2reg: A yield .82, B yield .67, claimed .08.
- dial tone mean 3.7 s p99 15.8 s; postdial alert 133 ms (ID 128 + ~5).  26/26 invariants PASS, 0 safety events.
- => the scale-8 collapse point i30k (93% refused, reg .95/.90, NODT 19%, 1.79 att/s/ex) is reproduced at real timers
  at 0.28 att/s/ex: conversion factor 6.4 on attempt rates (register-limited), as the model said (6.3-6.5).
  Real-time: collapse at ~1000 attempts/h/exchange (21 att/line/h on 48 lines) with 100% network traffic.
- 17:12 l2_p300_i60k (409 wall s -- machine quieter): 26 calls OK 18 (L 15/17, N 3/9), NOGO 3 F_REFUSE, BUSY 2, NOSPEECH 2,
  CUT 1; claims A 7 (5/2) B 1 (0/1) = 38% refused (model 35%); reg .52/.68; carried 1.54 E; 26/26 PASS.
  NOSPEECH pairs recur across runs with the same talk: A20->A57 14 ms, B40->A50 18 ms (below answer()'s 50 ms floor):
  a deterministic harness path ends them, not the RTL (both parties' xv=cv=0 because listening starts at +20 ms).
- 17:21 l2_p300_i15k (c2, 522 wall s): 75 calls: OK 29 (L 28/53, N 1/22), NOGO 11 F_REFUSE, BUSY 5 (L_BUSY), NODT 20, CUT 10.
  total OK 72.5/min/ex (model 73.2) -- local calls still carried at the register's limit; network 1 of 22.
  claims 13: take 1 / refuse 12 (92%, model 96%); refusal states: COLLECT 8 (a local caller dialling), YIELD 4.
  reg .93/.92; NODT 27% (model 20%); dt mean 647 p99 2604.  STUCK marker_state A 7.5 s -> STUCK-END at 10.4 s
  (the marker never idle for 10 s at overload: a watchdog threshold, not a leak).  26/26 PASS, 0 safety events.

### 17:31 cac_p1000_i30k -- RTL FIX TEST: connect at the claim (fix_cac/net_unit.v:881-883, one term removed), c2 build
- 47 calls: OK 10, NOGO 29 (26 F_REFUSE attributed), BUSY 1, CUT 7, NODT 0.  att 1.83/2.08 /s.
- vs baseline l2_p1000_i30k (same seed/knobs): OK 1 -> 10 (2.5 -> 25 OK/min/ex; model 6 -> 30), NODT 8 -> 0,
  refused 93% -> 72% (model 64%), reg .96/.90 -> .81/.79, dt mean 676 -> 351 ms, carried .26 -> 1.06 E.
- refused callers now hear 03 right after b (29 'heard before the last digit' vs 0) and hang up at once.
- refusal states: YIELD 20, COLLECT 6, COLLECT/c 3 (the register reading another claim's h s).  26/26 PASS, 0 safety.
- => the one-gate fix multiplies carried traffic at this overload by ~10 and removes the NODT; it does not remove the
  collapse (model: at i15k still 6.7/min/ex, at i6k 0).

### 17:40 l2b_p1000_i30k (stock obj_load2b: two baseband channels), same seed/knobs as l2_p1000_i30k
- 45 calls: OK 7, NOGO 33 = N_NOTRUNK 28 + F_REFUSE 5, BUSY 1, CUT 4, NODT 0.  att 1.67/2.08 /s.
- OK 17.5/min/ex (model 17.4) vs 2.5 with EIGHT channels (l2_p1000_i30k): fewer trunks carry 7x more at this overload.
  no-trunk attempts are turned away at the key (register freed ~0.1 s after the key instead of ~0.74 s at o_last),
  so trunk blocking acts as admission control on the register.  refused 5/14 = 36% (model 39%), notrunk 62% (68%).
- link 1.62 of 2 channels busy; n_glare 0, JOINED 0; 26/26 PASS; 0 safety events.
- 17:51 l2_p1000_i15k (c2): 76 calls, OK 0 (!), NOGO 28 (F_REFUSE), NODT 32, CUT 15, BUSY 1. att 2.67/3.67 /s.
  claims 31: take 1 / refuse 30 (97%); every refusal YIELD (30/30). reg .98/.95; carried 0 E. Model: 0 OK, 100%, NODT 50%.
  STUCK marker_state A at 7.5 s (never idle) -- see STUCK-END.  26/26 PASS after drain; 0 safety events.
- 18:01 l2b_p1000_i60k (stock 2b): 24 calls OK 7 (17.5/min/ex, model 16.7), NOGO 16 all N_NOTRUNK (67%, model 53%),
  BUSY 1; claims 8: 8 taken, 0 refused (model 20%); link 1.38 of 2; reg .41/.48; glare 0; 26/26 PASS.
  (8-channel l2 at the same load: 17.5 OK/min/ex too, but with 57% of claims refused instead of 67% no-trunk.)
- 18:13 l2_p1000_i60k_s12 (second seed at the knee): 21 calls OK 7 (17.5/min/ex, same as seed 11), NOGO 12 F_REFUSE, CUT 2;
  claims 21: 7 taken, 14 refused (67%; seed 11 57%; model 55%); refusal states YIELD 11, COLLECT 3; reg .67/.73.
  Two seeds pooled at the knee: 43 calls, 14 OK, 26/42 claims refused (62%).
- 18:29 l2_p1000_i120k (dur 16 s): 16 calls OK 7, NOGO 6 F_REFUSE, CUT 3; claims 14: 7 refused (50%; model 31%, binomial
  SD ~12% at n=14); all refusals YIELD; reg .42/.40 (model .40). At i60k+i120k pooled RTL 33/56 refused vs model ~47%:
  RTL a little above the model, ~1.5 SD; not resolved (thin).
- 18:42 l2b_p300_i30k: 42 calls OK 28 (L 23/29, N 5/13), N_NOTRUNK 3, F_REFUSE 2 (claims 7: 2 refused), NODT 2, BUSY 2,
  CUT 5; 70 OK/min/ex (model 62); link 1.33 of 2; reg .67/.75; 26/26 PASS; glare 0.
- 18:43 runner stopped: the running batch finishes l2_p300_i120k and l2b_p1000_i15k; NOT RUN (queued only):
  l2_p300_i6k, l2b_p1000_i120k, l2b_p1000_i6k, l2_p1000_i240k, NMON/NRES build (not needed: mon_max 1, res never used).
- scan-order starvation (known, accepted) quantified, 14 runs pooled (dtblock.py): NODT 0 of 191 attempts from lines
  20-37 (blocks 2-3, both exchanges), 6 of 71 (8%) from 40-47, 70 of 269 (26%) from 50-77. The register frees on the
  1 ms tick at scan 00 and the next caller taken is the lowest-numbered one waiting (overload agent's reading).
- 19:07 l2_p300_i120k (dur 16 s, 1506 wall s: machine load 52): 15 calls OK 12 (L 10/10, N 2/5), F_REFUSE 2 of 5 claims,
  F_BUSY 1; reg .26/.29 (model .22); 12 OK in 16 s = 22.5/min/ex (model 21.3). 26/26 PASS.
- 19:26 l2b_p1000_i15k: 79 calls, OK 0 (model 4.3/min/ex), NOGO 49 = N_NOTRUNK 25 + F_REFUSE 24, NODT 18, CUT 11, BUSY 1;
  claims 27: 1 taken, 26 refused; reg .98/.95; STUCK marker_state A 7.5 s -> STUCK-END at 12.06 s; 26/26 PASS.
  => the two-channel topology collapses too, later than eight channels.

## STATE AT HAND-OFF (19:30)
All 16 runs done (logs + .rc here); rtl_vs_model.txt has every point beside the model. obj dirs deleted (rebuild: 84 s
each, commands in q1.txt/q2.txt; c2 harness = load_harness_c2.svh, fix = fix_cac/). Not run: l2_p300_i6k, l2b_p1000_i120k,
l2b_p1000_i6k, l2_p1000_i240k, NMON/NRES=4 build (pools never binding: mon_max 1 of 2, nomon 0, resolvers never used).
Findings draft: scratchpad findings.py (also summarised above under FINDINGS DRAFT).
- pooled scan-order (16 runs): lines 20-37 1 NODT / 224, 40-47 6/81, 50-77 87/320; SCALE1's 8 NODT all lines 51-76.
- totals over 16 runs: 625 calls, 171 OK, 0 WRONG/JOINED/XTALK/PHANTOM/WRONGRING, 416/416 invariants, 285 claims (195
  refused), 287 incoming seizures = 287 nofwd_empty (C14 leaf sweep), glare 0, unhold 0, nomon 0, mon_max 1, res never used.
