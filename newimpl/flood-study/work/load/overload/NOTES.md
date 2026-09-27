# OVERLOAD + RECOVERY study NOTES (agent: overload)
Dir: work/load/overload/. Started 2026-09-26 ~12:35.
Rules: one sim of mine at a time, all via ../../../sim.sh, timeouts on every run.

## Plan
- R1 speed + always-trying on tb_load2 (prebuilt scale 8)
- knee estimate from sweep / PROG intervals
- load step overload -> normal (recovery)
- abandon storm, dest_mode 2/3, accidental key (harness copy), reserved codes 18/19
- tb_load3 overload; local service under network jam (orig_x / pnet)
- SCALE1 recheck of the key results

## Results (append as they come)
- Harness copy: overload/load_harness.svh (+ tb_load2/3/2b.sv copies). New knobs: +ab_dt +ab_tail_ms,
  +trunc_pm +trunc_nd, +own_pm, +netlines, +netidle_ms +netidle2_ms, +burst_ms +burst_every_ms;
  PROG adds "| now X:wdt= mon= res= nst= trk=". Build: obj_l2 (scale 8) -- vl_l2.rc ends BUILD_rc=.
  NB rc-file waiters must grep '^BUILD_rc=' / '^rc=' (the sim.sh echo line contains 'rc=').
- an.py: per-run analysis (outcomes by kind, series by lift time, hold times, fairness -f).
- R1 r1_l2_always: tb_load2 prebuilt, idle 50 (always trying), dur 8000, seed 21. Speed ~16 ms/s
  (1 s sim ~ 60 s wall). First 4 s: 0 OK -- every called line is off hook (BUSY) + NODT at 3 s.
### R1 r1_l2_always.log  (tb_load2, idle 50 = every line always trying, dur 8 s, seed 21)
 wall 662 s, sim 10.5 s, 303 attempts (96 phones), 18.9 attempts/s/exchange.
 OK=0 (!), BUSY 19 (called phone off hook), NOGO 12 (all F_REFUSE: far register busy, C15),
 NODT 177 (3 s dt timeout), CUT 95.  Only 33/303 got dial tone; reg_occ 0.996 both.
 att_take=0 att_refuse 7/6: EVERY network claim refused (C15 at 100% register occupancy).
 carried 0.000 E.  Subscriber-level collapse: waiting lines are off hook -> every called line busy.
 STUCK marker_state A at 7.5 s = watchdog threshold only (marker never idle at 100% load), ended at hang-up.
 Invariants 26/26 PASS; no WRONG/JOINED/PHANTOM.
 Fairness: A20 4 att 0 NODT, B20 6 att 0 NODT; lines 22-47 nearly all NODT -> port 20 favoured.
   Hypothesis: the register frees on tick_1k (scan 00) after timer-driven ends (WATCH settled, N_DONE on
   digit decision, T_KEY/T_CLAIM nogo) so the next caller taken is the lowest-numbered waiting line.
### Capacity arithmetic (scale 8)
 register hold: local ~370 ms (pre 60 + h 90 + idg 100 + s 95 + ID 16 + read/probe/watch ~10);
 origin network ~770 ms (held to o_last even when the claim is refused, C15); far register for a
 taken claim ~410 ms (h s).  pnet 0.5 symmetric -> ~0.78 s register per attempt -> saturation
 ~1.3 attempts/s/exchange; knee ~1.0/s.  Offered ~ 48/(idle+~3 s): idle 60000 = 0.75/s (0.7x),
 20000 = 2.1/s (~1.6x), 6000 = 5.3/s (~4x), 1500 = 10.7/s (~10x), 50 = always (R1, 19/s measured).
 R5 step changed to idle 1500 -> idle2 60000 (the smoke baseline load) at 6 s, dur 18 s.
- SCALE1 build obj_l2_s1 OK (266 s). r30 SCALE1 step queued after r10: idle 60000 (≈4x real knee) 40 s -> idle2 400000.
- SLOT CONTENTION: ~30 sim.sh waiters (verify workflow + load agents); R2 waited 38 min for a slot.
  q.sh now runs BATCHES: one queue line = runs joined by ' ;; ', run sequentially inside ONE sim.sh
  slot (still one sim of mine at a time).  Runner: setsid bash (waits for R2's rc, then ./q.sh) > q.out.
  queue.txt batches: [r3 step 6k->60k, r5 step 1500->60k, r7 abandon] [r10 bad, r16a jam-net, r16c jam-none]
  [r30 SCALE1 step] [r20 load3 6k, r12 patho mix, r6 burst] [r9 hot, r16b jam-bad, r14 resv 1 8].
### R2 r2_l2_i20k.log (tb_load2 prebuilt, idle 20000 (~1.6x knee), dur 10 s, seed 22)
 wall 801 s, sim 12.5 s, 34 attempts (thin!).  A 2.5 att/s, B 0.9 att/s.
 OK 7 (L 3/9, N 4/22 excl CUT), NOGO 12 all F_REFUSE (C15), NODT 10 (all at A), BUSY 2.
 reg_occ A 0.91 B 0.70; origin_occ A 0.72; att_take A 0/6, B 4/12 -> refusal ~ occupancy.
 carried 1.108 E; dt mean 660 p50 380 max 2687.  Invariants 26/26 PASS, no safety events.
 STUCK marker_state A 7.5 s = watchdog threshold (marker never idle), not a leak.
- 13:58 runner changed: inner.sh runs inside ONE slot and keeps taking queue lines until 2 h (BUDGET_S)
  have passed, then releases; q2.sh re-acquires (./sim.sh bash inner.sh) until the queue is empty.
  Pending request pid 1300161 runs batch_133446.sh -> exec inner.sh.  Log of the runner: q.out.
### model.py (DES of tb_load2: one register/exchange, C15 claim refusal, tick-priority, busy lines)
 Validated vs RTL: idle 60000 model 0.87 att/s/exch reg .56 dt 221 netOK 49% succ 72%  <->  smoke RTL
 0.85 att/s reg .50/.53 dt 297 netOK 8/15 succ 23/31;  idle 20000 model reg .93 netOK 6% dt 737 <-> R2 RTL
 reg .91/.70 netOK 4/22 dt 660;  idle 50 model 19.4 att/s succ 1% <-> R1 RTL 18.9 att/s 0 OK.
 Scale 8 sweep (10 s x10 reps): idle 60k/30k/20k/12k/6k/3k/1.5k/50 -> att/s/exch .87/1.59/2.27/3.51/5.75/
 8.58/11.8/19.4; OK/s (2 exch) 1.26/1.77/1.74/1.87/1.64/1.35/1.02/0.30; netOK% 49/22/6/1/1/0/0/0;
 carried E 1.71/2.38/2.55/2.83/2.25/1.79/1.59/0.54.  => throughput plateau ~1.8 OK/s from ~1.6 to ~6
 att/s/exch, then decline (collapse to 0.3 OK/s at always-trying); network completion collapses first.
 Real timers (120 s x6): idle 600k/300k/150k/100k/60k/30k/10k/400 -> att/s/exch .09/.15/.30/.41/.62/.99/
 1.64/2.5; OK/s .14/.22/.27/.28/.24/.23/.12/.04; netOK% 69/50/10/4/1/0/0/0; reg_occ .40/.63/.90/.97/.99/1.
 => knee ~0.2-0.3 att/s/exch (700-1100 attempts/h per 48-line exchange), throughput peak ~0.28 calls/s.
- Harness: +switch_redraw=1 re-draws every idle phone's next lift at the step (else pending draws at the
  OLD mean keep lifting -- at SCALE1 idle 60 s that masks recovery for a minute).  Queue: build_l2 at the
  head of batch 1, build_l2s1 before r30; r3/r5/r30 use +switch_redraw=1 (r3 moved to obj_l2).
- 15:16 got slot 5 (waited 1 h 42 min). inner.sh started: build_l2 then r3 r5 r7, r10 r16a r16c, build_l2s1 r30 ...
- 15:25 queue merged into ONE line (runs after batch 1 without releasing the slot, ~3 h): r10 r16a r16c build_l2s1 r30 r20 r12 r6 r9 r16b r14
### r3 r3_l2_i6k_step.log (obj_l2, idle 6000 (~4x) for 8 s, then SWITCH redraw to 60000; dur 16 s; seed 23)
 wall 826 s, sim 18.5 s, 114 attempts (100 in the overload 8 s: 6.2 att/s/exch).
 Overload by lift 2-7 s: 56 att, OK 5, NODT 39 (70%), NOGO 12 (all F_REFUSE). Served 17: 12 N all refused, 5 L all OK.
 PROG ok/s (by end) 4-8 s: 0,1,0,1,1 => carried ~0.6 OK/s both exchanges vs ~1.2 OK/s at 0.7x (smoke) -> COLLAPSE.
 Network: att_take A 1/12, B 1/11 over the whole run (C15).  dt mean 1015 p99 2988 (NODT limit 3000).
 Recovery: backlog wdt A 14 B 18 at the switch (t 8 s) -> A 0 at 10 s, B 1 at 11 s: flushed in ~dt_ms (3 s):
   served in port order (B31 9292, B33 9663, B34 9974, B40 10365 (waited 2819), B60 10676 (waited 2988)).
   After 12 s: 13 lifts, 9 OK, 2 NOGO F_REFUSE, dt mostly 5-400 ms; one A70 waited 1690 ms behind A35
   (lifted 570 ms LATER, lower port) -> order inversion by port number (known priority).
 Invariants 26/26 PASS; no WRONG/JOINED/PHANTOM/IDLEHEAR; STUCK marker_state A,B = watchdog artefact (ended 10.1/10.4 s).
- fair.py (per port block, overload window by lift): r3 0-8 s: 2x 20 att 19 served NODT 5% OK 50% | 3x NODT 42% |
  4x 75% | 5x 100% (0 served of 14) | 6x 84% | 7x 100% (0 of 15).  R1 0-8 s: 2x NODT 65%, 3x 88, 4x 94, 5x 78, 6x 94, 7x 97.
  => fixed lowest-port priority, strong: under sustained overload blocks 5x-7x get (almost) no dial tone.
### r5 r5_l2_step.log (obj_l2, idle 1500 (~10x) for 6 s, SWITCH redraw -> 60000; dur 18 s; seed 25)
 wall 1077 s, sim 20.5 s, 174 attempts (153 in 6 s = 12.75 att/s/exch).
 0-6 s by lift: OK 9/153 (6%), NODT 80%; fair.py: 2x NODT 21% ... 4x 96%, 6x 96%, 7x 100%.
 att_take A 1/13 B 1/13 (whole run).  Backlog wdt A31/B33 at the switch -> 23/20 (7 s), 9/12 (8 s), 1/0 (9 s): ~3 s = dt_ms.
 After the backlog: B's register busy 100% 9-12 s with wdt 0: back-to-back B network calls (B62,B23,B34) each
 ~0.7 s, all refused at A (A64 lifted at the same time: mutual refusal, C15); network 7/9 refused 9-17 s.
 Invariants 26/26 PASS, no safety events, stuck 0.
### Window table (win.py: lifts in window, connected+answered by alert time, carried E over the window)
 smoke 1-20 s (0.7x):  0.87 att/s/exch, 1.21 conn/s (2 exch), 2.03 E, net OK 7/14
 R2 1-10 s (1.6x):     1.78, 0.78, 1.23 E, net OK 4/20, NODT 10/32
 r3 2-8 s (4x):        5.58, 1.17, 1.35 E, net OK 0/36, NODT 42/67
 r5 1.5-6 s (10x):    10.67, 0.67, 1.16 E, net OK 0/50, NODT 74/96
 R1 1.5-8 s (always): 15.5, 0, 0 E, NODT 91/202, BUSY 7
 recovery: r3 11-16 s 1.30 att/s -> 2.20 conn/s 3.70 E (backlog completing); r5 9-18 s 1.00 -> 1.44 conn/s.
 Register service at A in r3 (overload): N holds 700-840 ms, L 300-470 ms, gaps 2-14 ms between callers.
- 16:05 appended r8a (abandon 900 from dial tone, idle 15000, 16 s) and r8b (abandon 600 from lift, idle 15000, 12 s) to the running .cur_batch.sh (r7's 12 abandons at 4x were too few)
### r7 r7_l2_abdt.log (idle 6000 (4x), abandon 700 timed from dial tone, dur 10 s, seed 27)
 wall 676 s, sim 12.5 s, 125 attempts; only 43 got dial tone -> 12 ABANDON (dial before key 1; 20-47 ms after the key
 (hunt/seize window) 4; mid e/b 3; ~600 ms after key (around b/claim) 2; POST 20 ms after last (at connect) 1; others).
 OK 8, NOGO 15 F_REFUSE, BUSY 6, NODT 49, CUT 35.  Invariants 26/26 PASS; no leaks, no safety events.
### r10 r10_l2_bad.log (idle 6000 (4x), dest_mode 3: every network attempt dials 1 2 7 h s, nobody's code; dur 8 s; seed 30)
 wall 496 s, sim 10.5 s, 91 attempts (BAD 40, L 51).  BAD: NOGO 11 (N_TCLAIM, T_CLAIM 250 after b -- heard MID-DIAL
 before s, 10 of them; the caller quits), NODT 12, CUT 17.  L: OK 14, BUSY 7, NODT 14, CUT 16.
 Hold of a doomed flood: key->tone 634 ms (1 e b + T_CLAIM) vs refused good call key->tone ~650-790 (1 e b h s).
 origin_occ .41/.45; link busy_mean .91 (max 2); far monitor mon_mean .26 (freed at b mismatch).  claims 0.
 Invariants 26/26 PASS, stuck only the marker_state watchdog artefact. No safety events.
### r16a/r16c: local service while the network side is jammed (tb_load2 obj_l2, seed 36, dur 8 s)
 netlines 24: lines 20-47 of each exchange may dial the network; lines 50-77 local only (idle 20000).
 r16a: lines 20-47 ALWAYS trying network calls (netidle 300, pnet 1000). r16c: lines 20-47 idle (netidle 2e7).
 (jam.py, lifts 0.5-8 s)
  r16a: local-only lines 50-77: 8 att, 0 served, NODT 100%, OK 0%.   net lines: 71 att, 18 served, NODT 75%, OK 0
        (all 21 NOGO F_REFUSE; att_take 0/11 A, 0/10 B).  reg_occ .996 both; origin_occ .85/.84; carried 0.
  r16c: local-only lines 50-77: 11 att, 11 served, NODT 0, dt mean 82 p90 245, OK 91%.  reg_occ .40/.20.
 => a network jam takes the ONE register from local service entirely: the network callers (all doomed:
    mutual refusal) hold it ~0.7 s each, and the fixed lowest-port priority hands it to them (they are 20-47)
    every time.  (Confound: priority favours the network lines here; with the classes swapped the local lines
    would win the register but every network attempt still costs 2x a local call.)  r16a wall 409 s (25.7 ms/s),
    r16c 351 s.  Invariants 26/26 both; no safety events.
- 16:25 harness +net_hi=1 (network lines = the LAST netlines lines). Appended build_l2b (rebuild obj_l2) + r16e (jam with network lines 50-77, local-only 20-47) to the running batch.
## DRAFT FINDINGS (update as runs land)
1 overload-collapse (C15 + new aspects): network completion ~0 above ~1.5x knee (att_take 0-2 of 10-13 claims per
  exchange in every overload run); completions 1.21/s (0.7x) -> 0.78 (1.6x) -> 1.17 (4x) -> 0.67 (10x) -> 0 (always);
  every doomed network attempt holds the ORIGIN register 0.7-0.84 s (2x a local call), so network attempts steal
  register time from local calls that would succeed.  Positive feedback: busier register -> more refusals of the
  other side's claims -> more wasted register time there.
2 network-jam-starves-local (new): r16a -- local-only lines 0/8 served while 24 lines/exch retry network calls.
3 fixed-port-priority (known, quantified): fair.py r3/r5/R1 -- 2x blocks served 80-95%, 5x-7x 0-8%.
4 recovery-by-nodt (info): backlog flushed only by the callers' own dt timeout (3 s at scale 8); verify at SCALE1 (r30).
5 watchdog-marker_state (bench-gap): STUCK marker_state fires at 7.5 s under any sustained overload.
6 doomed bad-code floods (info, C14-related): r10 -- key->tone 634 ms, nothing held beyond T_CLAIM+T_REL; no leak.
### r30 r30_l2s1_step.log  SCALE1 (real timers) obj_l2_s1: idle 60000 (~4x real knee) 30 s, SWITCH redraw -> 400000 30 s; drain 10 s; seed 50
 wall 2258 s, sim 70 s (31 ms/s), 42 attempts (thin; A 27 B 15).
 Overload 0-30 s: 33 lifts (0.55 att/s/exch; model 0.55), dial tone mean 3.3 s p99/max 19.8 s (dt_ms 20 s), NODT 13
 (all at A, reg .93), connects 5-30 s 0.16/s both (model ~0.24), carried .85 E.  Network: att_take A 1/5 B 1/9 ->
 N served 14: OK 2, NOGO 12 (F_REFUSE, C15).  Refused call holds: key->tone 4185 ms mean (max 4652), lift->rel 9.1 s.
 fair.py 0-30 s: 2x NODT 0%, 3x 0%, 4x 12%, 5x 43%, 6x 80%, 7x 83%  -> the priority holds at real timers.
 Recovery: A backlog 12 at the switch -> 7 (35 s) 4 (40 s) 1 (45 s) 0 (50 s): ~15-20 s = dt_ms (20 s); after 45 s
 dt mean 1.1-1.4 s.  Scale-8 recovery 3 s = its dt_ms: recovery time = the callers' dial-tone patience, x ~7 real.
 Invariants 26/26 PASS; no safety events; no STUCK (the SCALE1 watchdog threshold is 60 s).
### r20 r20_l3_i6k.log (tb_load3 prebuilt chain A-B-C, idle 6000 (~4x), dur 8 s, seed 40)
 wall 527 s, sim 10.5 s, 134 attempts (136 phones), 1.5-8 s: 8.15 att/s/exch, 2.15 connects/s (3 exch), 3.09 E.
 att_take 0 at A (0/8), B (0/5), C (0/6): EVERY claim refused -> network 0 OK of 61 (NOGO 16 F_REFUSE, 2 N
 "BUSY" = unattributed refusals classified by the called line's hook, NODT 25, CUT 18).  Local OK 21.
 Transit B: seized_in 13, nofwd 0, nomon 0, res_max 2 res_mean .43, mon_max 2 -- the unit is not the bottleneck
 (one register a leaf => at most one flood from each side), the far registers are.  Invariants 38/38 PASS.
### r12 r12_l2_patho.log (idle 6000, pnet 700, own_pm 250, trunc_pm 300 trunc_nd 1; dur 8 s; seed 32)
 wall 300 s, 92 attempts. KEY-ONLY (dial "1" and stop) 25: DTAGAIN 15 = HARNESS ARTEFACT: POST begins at the
 key's make, while dial tone is still on (the marker drops it only at ID after the make), so steady 1 is heard in
 2-5 ms -> DTAGAIN, the phone hangs up 100 ms after the key.  So r12 tested "hang up 100 ms after the key"
 (inside the origin's hunt/seize window) 15 times: all clean.  Own-code floods: 5 attempts, none served (NODT/CUT);
 B unit local=1.  N (41): NOGO 9 F_REFUSE, NODT 16, CUT 16.  Invariants 26/26 PASS, no safety events.
 -> appended r13a (1 e and stop: T_KEY), r13b (1 e b to a real code and stop: far claim + NODIG), r13c (own code, idle 20000).
### r6 r6_l2_burst.log (idle 2e7 = nobody lifts except the bursts: all 96 phones lift in ONE ms at 0.5 s and 8.5 s; seed 26)
 wall 633 s, sim 18.5 s, 192 attempts.  Each burst: 13 of 96 served within dt_ms 3 s (6-7 per exchange, one every
 ~0.46 s), NODT 86%.  Served 26: OK 3, BUSY 12 (called lines off hook, waiting in the burst), NOGO 11 (F_REFUSE; att_take 0/11).
 fair.py burst 1: 2x 9/16 served, 3x 1, 4x 2, 5x 1, 6x 0, 7x 0.  Burst 2: 2x 5, 3x 2, 4x 1, 5x 0, 6x 4, 7x 1 --
 after a BUSY/NOGO decided at the called port's turn the scan resumes there, so the priority is not purely by port.
 No STUCK, no hunting/att watchdog, invariants 26/26 PASS: the unit's classifier reading 48 lifted lines at once is harmless.
### r9 r9_l2_hot.log (dest_mode 2: EVERY caller dials B20; idle 6000; dur 8 s; seed 29)
 wall 366 s, 85 attempts.  B20 answered 4 (OK 4 local); B callers BUSY 14 (L_BUSY); A callers (all network):
 10 floods, 10 claims at B, att_take 0/10 -> NOGO 9 F_REFUSE, NODT 27 (A's register held 83% by doomed floods).
 => a hot line's own exchange register, busy with local callers being told BUSY, refuses every network caller
 for it even at moments the line is free.  Invariants 26/26 PASS; no safety events.
### r16b r16b_l2_jam_bad.log (as r16a but the network lines dial 1 2 7 h s, a code nobody has)
 wall 422 s.  Local-only lines 50-77: 8 att, 0 served, NODT 100%.  Net lines: 73 BAD att, 16 served, all NOGO N_TCLAIM
 (20 of 22 heard before the last digit: T_CLAIM 250 ms after b ends before h s at scale 8), key->tone 634 ms.
 Invariants 26/26; no safety events.  => doomed bad-code floods starve local service exactly as refused good calls do.
### r14 r14_l2_resv8.log (dest_mode 3 bad_e 8: network callers dial 1 8 3 h s -- a reserved digit in the code; dur 4 s)
 wall 296 s, 47 attempts.  BAD 28: NOGO 14 why N_SVC, heard 272 ms after the key (as soon as the 8 is counted;
 all 14 before the last digit), NODT 4, CUT 10.  unit A/B floods 7, nogo 7; far monitors seized_in 7, freed at e (isvc).
 Invariants 26/26 PASS, no safety events.  (1 x 9 not run separately: same isvc() path, net_unit.v:170 and :868.)
### r8a r8a_l2_ab_dt.log (idle 15000 (~2x), abandon 900 timed from dial tone, dur 16 s; seed 28)
 wall 804 s, sim 18.5 s, 83 attempts, 30 ABANDON: L pre-key 1, mid h s 4, after last digit/ringing 6;
 N pre-key 1, 40-400 ms after the key (flood, e, b) 14, >400 ms (claim, h s) 3, after the last digit 1.
 OK 11, NOGO 18 F_REFUSE (att_take 1/25), NODT 13, CUT 10.  Invariants 26/26 PASS, no port/unit leak.
 WRONGRING t=3274 at=B75 caller=B44 dialled=B75 calling=0: HARNESS ARTEFACT -- B44 (who did dial B75) hung up in
 RINGBACK at 3266, the same ms the ring cadence's first bell came; the judge 8 ms later finds calling(B44)=0.
 Right caller, right line (as the hub agent's IDLEHEAR note).  alert_nobell 1 is the same call.
### r8b r8b_l2_ab_lift.log (idle 15000, abandon 600 timed from LIFT (original harness rule), dur 12 s; seed 38)
 wall 582 s, 68 attempts, 36 ABANDON (WAITDT/DIAL/POST/RINGBACK), OK 15, NOGO 12 F_REFUSE.  Invariants 26/26, no events.
### C15 tally over the overload runs (SUMMARY unit claims/att_take/att_refuse summed): 228 claims, 15 taken, 213 refused (93%).
 nofwd_busy 0 and nomon 0 in every run (tb_load2 has no transit; the chain's B never ran out: r20).
### r16e r16e_l2_jam_net_hi.log (as r16a but +net_hi=1: network lines 50-77 always trying, local-only lines 20-47)
 wall 555 s, 163 attempts.  Local-only lines (now scan-favoured): 13 att, 13 served, NODT 0, dt mean 467 p90 598
 (r16c baseline 82 / 245), OK 8 (54%, baseline 91%): 6 BUSY -- half their called lines are the network callers,
 off hook waiting.  Network lines: 65 att, 10 served, 85% NODT, 0 OK (F_REFUSE 15).  Invariants 26/26.
 => network overload DEGRADES local service even when local lines have the scan priority (dial tone 5.7x slower =
 one doomed network attempt's register hold, success 91% -> 54%) and DENIES it when they do not (r16a: 0/8).
### r13a r13a_l2_key_e.log (network callers dial "1 e" and stop: T_KEY; idle 6000; dur 6 s; seed 43)
 wall 428 s, 69 attempts.  BAD 28: NOGO 6 why N_TKEY, heard 655 ms after the key (T_KEY 625) = 523 ms after e;
 NODT 9, CUT 13.  Origin register + one trunk held for T_KEY each (5 s real).  Invariants 26/26, no events.
### r13b r13b_l2_key_eb.log ("1 e b" to the real far code and stop; idle 6000; pd_ms 3000; dur 6 s; seed 44)
 wall 368 s, 60 attempts.  BAD 34: NOGO 6 why N_NODIG -- the far claim (3+3) was refused (register busy), but the
 refusal's 03 is on the trunk, not yet on the caller (N_DONE waits for o_last); the caller hears cannot-complete only
 at the ORIGIN register's NODIG, 1270 ms after b (1554 after the key); reg_maxrun 1.6 s.  At real timers: ~13 s of
 origin register (e b 3.3 s + NODIG 10 s) per abandoned partial dial.  COLLIDE 1 (lifted into its own incoming call:
 harness handles it).  Invariants 26/26, no events.
### r13c r13c_l2_owncode.log (every network attempt dials 1 + OWN code + h s; idle 20000; dur 8 s; seed 45)
 wall 638 s, 35 attempts.  Own-code 13: OK 7, BUSY 2, NODT 1, CUT 3; unit local_go A 2, B 8 (the origin drops its
 trunks at b and the register goes on as local); far monitors seized_in 8/2, freed at b.  Invariants 26/26, no events.
- 18:42 slot released (inner budget); queue empty; q2.sh exited.  Held slot 5 from 15:16 to 18:42 (3 h 26 min).
- 18:45 queued r21 (tb_load3 idle 1500 -> 60000 at 6 s) + r22 (tb_load3 always trying) as one batch; q2.sh waiting for a slot
### regshare.py: ORIGIN register time by outcome (dial tone -> tone/alert/hang-up), callers given dial tone in a window
 smoke 1-20 s (0.7x):  N-NOGO 33% (763 ms each), N-OK 32% (745), L-OK 31% (331)
 r3 2-8 s (4x):       N-NOGO 77.5% (750 ms each), L-OK 22.5% (373)
 r5 1-6 s (10x):      N-NOGO 72% (729), L-BUSY 15% (350), L-OK 12% (372)
 r16a 0.5-8 s (jam):  N-NOGO 96% (734)
 r30 3-30 s REAL:     N-NOGO 64% (4712 ms each), L-OK 21.5% (2214), L-BUSY 14% (2440)
 => under overload 2/3-3/4 of the only register's time is spent on network attempts that are refused (C15),
    each 2x a local call, at both scales.  This is the positive feedback: the busier each register, the more of
    the other's claims it refuses, and every refusal has already cost the other register a full 1 e b h s.
### r21 r21_l3_i1500_step.log (tb_load3 prebuilt chain, idle 1500 (~10x) 6 s -> idle2 60000 (no redraw); dur 14 s; seed 41)
 wall 2232 s (135 wall-s/sim-s at machine load 25), sim 16.5 s, 275 attempts.
 1.5-6 s: 14.6 att/s/exch, 2 connects (0.44/s, 3 exch), 0.48 E; NODT 82% (fair.py 0-6 s: 2x 25/38 served, 3x-7x 2-4 of ~40).
 Claims: A 0/15, B 0/11, C 0/11 taken -> network 0 OK of 137 (F_REFUSE 31, 2 unattributed shown as BUSY).
 Transit B: seized_in 27, nofwd 0, nomon 0, res_max 2 (mean .50), mon_max 2.  C nofwd_busy 1 (leaf's own sweep; C14, harmless).
 Recovery: registers 100% until ~13 s (switch 6 s + pending 1.5 s-mean lifts (no redraw in the prebuilt harness) + dt_ms 3 s);
 9-14 s: 1.6 att/s/exch, 1.80 connects/s, 2.72 E.  Invariants 38/38 PASS; STUCK only the marker_state watchdog.
### r22 r22_l3_always.log (tb_load3 chain, idle 50 = every line always trying, dur 6 s; seed 42)
 wall 988 s, sim 8.5 s, 300 attempts (17.7 att/s/exch).  OK 0, BUSY 25, NOGO 9 F_REFUSE (claims 12, take 0), NODT 130, CUT 136.
 Invariants 38/38 PASS, no safety events.
- 19:45 all runs done; q2 exited.  obj_l2 / obj_l2_s1 deleted afterwards (rebuild: build_l2 / build_l2s1 lines in done.txt).
## FINAL (19:50): 23 runs, 2832 attempts, 339.5 sim s, 16695 wall s; 234 connected, 78 abandoned, 0 WRONG/JOINED/XTALK/PHANTOM;
 every INVARIANT PASS (26 or 38 each); claims 298, taken 15, refused 283 (95%).  runs.json = the run table.
 Binaries: r1,r2 obj_load2 (original harness); r20-r22 obj_load3 (original); the rest overload/obj_l2(_s1) (this harness copy).
 Findings reported: F1 register spent on refused network attempts (C15), F2 network jam denies local service (new),
 F3 tick-aligned release = fixed lowest-port priority (known, quantified), F4 recovery = dial-tone patience,
 F5 partial dial holds origin register to NODIG (C15), F6 doomed floods bounded / no unit feedback (C14), F7 harness
 artefacts, F8 hot spot (C15), F9 burst, F10 no safety/liveness failure under load.
