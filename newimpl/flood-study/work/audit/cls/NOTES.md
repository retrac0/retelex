# cls slice -- the CLASSIFIER and the READ PATH (round 2: the traffic view)

Dir: /home/joel/telco/newimpl/build/flood/work/audit/cls/.  Snapshot RTL only (rtl/, tb/);
all sims through ../../../sim.sh, one of mine at a time, with timeouts.

## 0. Reconstruction of the cut-off agent's work (round 1, 01:15-04:17), from its files

Benches (single exchange = site_net code 2 2, every trunk's far end driven by the bench,
REAL timers by default; +define+SCALE8, +define+POOL8 = NMON=NRES=8):
- tb_cls.v  sc1-5;  tb_cls2.v = tb_cls.v + sc6.  Bench bug: nseen[] prints negative in sc6
  ("classified -62/-63 more times"): the sc6 check on nseen is an artefact; use the claim count.
- fix/net_unit.v, fix/mini_marker.v (+ .diff): a large fix set (4-deep rise queue with rise
  times, 4 hold watchers timed from the rise and unholding only after CLR of low, `ml` delay
  line = rule 1 late pickups held only, st cleared only on M low AND BUSY low, mine re-check
  at C_ACT/UNHOLD, one retry on a non-trunk non-line word; marker: a caller must read as a
  line (xxxx1111) or tone trunk 11011, a called port must read as a line).  RTL_fix.list.
  Cost is large (~15+ packages); cheaper equivalents proposed below.

Runs and what they showed (PLAIN snapshot = r2/r8/o6/s8; FIX = f2/f3):
| run | what | result |
|---|---|---|
| r2 sc1 K8 D128 | 8 far seizures at once, NMON 2 NRES 2, real | classifier 19 ms/seizure (seen +0.1,19.1,38.1,...,114.2); 12-17 NOFWD(busy); 16's C_HOLD watch met the first break (+128) -> UNHOLD, re-seized at the make (+188) (C04/C05). No claim (cells exhausted). PASS |
| r8 sc1 K8 D128 | same, NMON=NRES=8 | 16 re-seized -> mon7 counts e=2 (dialled 3) -> CLAIM -> 21 rings: WRONG NUMBER at real timers (C04/C05 class) |
| s8 sc1 K8 | scale 8, POOL8 | 13 and 14 both CLAIM (e counted 2 and 1): wrong numbers; 3 cells armed after the first break |
| r2 sc1 K1 D10 | break 10 ms after the seizure (inside T_ARM watch) | UNHOLD + re-classify; mon1 counts 2 -> CLAIM -> 21 rings (C03+C04; D=10 is inside the far guard, bench-only) |
| r2 sc2 | link glitch during the first word read (both readers select 10) | word 01001000: unit drops it (not trunk); MARKER TAKES THE TRUNK AS A CALLER, far digits 3 2 dialled locally -> CONNECT 10->32: WRONG NUMBER (NEW) |
| r2 sc3 | same, register busy (only the unit reads) | unit drops it with st set; first dial break clears st; the make is classified fresh mid-digit; mon counts e=2 (dialled 3) -> CLAIM -> 21 rings: WRONG NUMBER (NEW trigger of the C05 mid-digit mechanism) |
| r2 sc4 | sub-ms far blip on 71 during the origin sweep's last read | classifier HOLDs 71 (mine=0: nst=N_HUNT), origin SEIZEs 71, classifier UNHOLDs 71 -> origin's trunk written free; far end later seizes 71 -> origin takes it as the claim: caller 20 joined to a stranger: WRONG NUMBER (NEW: mine gap) |
| r2 sc5 | 22 dials 3 0 = a trunk whose link is down (word 00000000) | marker connects 22 to trunk 30; when the link returns 22's dial pulses go out on it (3 breaks) (NEW) |
| o6 sc6 | called party hangs up first; far M kept standing by the bench; far caller dials 3 2 2 1 | the first break clears st; make re-classified; CLAIM again, 21 rings again (NEW trigger; realistic window only ~1 ms + RC tolerance) |
| f2/f3 sc1-6 | the fix set | all safety checks pass (sc6 FAIL is the nseen artefact; marker re-read loop C16 ran 1331 reads while the bench held far M) |
| reg_fix_net | tb_net on the fix set | 88 checks 0 errors (1612 s) |
| reg chain/lfull | | NOT RUN (cut off; obj_reg_chain left, vl_reg_chain.log only) |

## 1. Round 2 plan (traffic view)
1. Analysis (no sim): classifier service time, burst/priority behaviour, /WS starvation
   bounds, mine coverage table, word-glitch consequences (direction misread).
2. Sims (queue is shared, all 5 slots busy with load agents at 12:40): a load bench
   tb_clsload.v (Poisson far seizures on the 18 trunks + Poisson local lifts, real timers),
   counting: rise->hold, late pickups, C_HOLD unholds on a dial break, re-classifications,
   marker reads per trunk, local dial-tone delay, sweep length.
3. Regress a CHEAP fix set on tb_chain/tb_lfull.

## 2. Results (appended as they come)

### 2.1 Job c3 queued 12:5x (run_c3.sh through sim.sh; progress in c3.progress, logs run_c3_<name>.log)
tb_cls3.v (new, POOL8 = NMON 8 NRES 8, REAL timers, snapshot RTL):
- sc7 scan-order priority: 10 at t0, 47 at +5 (dials 3 2 2 1, first break +128), 11..16 at +10,+25,+45,...,+105.
  Expect 47 held only after 16 (C_HOLD ends on tick_1k = scan 00, so the next taken is the LOWEST waiting port).
- sc8 direction misread: glitch the link for the frames carrying bits 6-7 of the unit's read of W 10.
- sc9 CONFIRM without a second choice: far end seizes W 10 after the origin sweep read it free.
- ovl: Poisson 30 floods/s, mode 1 (85% short copies dropped at t1 100-400 ms, 15% dial 3 2), 15 s.
- r1: Poisson 5 floods/s, 50% dial 3 2, 10% 2 2, rest 4-7 4-7, first break 60-700 ms after the rise, 30 s.

### 2.2 fix2 (cheap fix set, written 12:57; NOT yet simulated) -- fix2/{net_unit,mini_marker}.v, RTL_fix2.list
- F1+F3u unit: read the word TWICE a pass apart (C_WAIT2/C_READ2), act only if they agree, and
  look again at the second select's turn: hold only if M . /BUSY . /mine then.  ('574 + '688 + gates;
  +~1 ms per classification).  One bounded re-read on a word that is neither trunk nor caller class.
- F2 unit: the C_HOLD watch writes no UNHOLD on a port that is `mine` at the sample (1 gate).
- F4' unit: st BUSY-precedence: set on any BUSY sample, clear only on M low AND BUSY low (0 gates).
  Makes a make after a dial break of an armed unheld port never a fresh seizure (sc6, C05b, sc3 path)
  and makes a waiting seizure that reached its first break a LOST copy (never forwarded mid-digit).
  Also closes C07 link-return-fresh-seizure on an LTU (MUTE_BLK is BUSY, so st stays set through the
  outage).  Cost of the loss: that copy is not held/watched/forwarded; marker C16 loop on it.
- F3m marker: caller only if a line (xxxx1111) or tone trunk (11011); called only if a line.
  CAVEAT: port-form words (answers-to 01..., call nail 10...) are callers too and would be refused;
  fine for top_net today.  Better: the card holds its WORD through hits like C07's poison fix (gate
  word_n by !poison, not link_up): 0 extra parts on top of C07's card fix, and covers all readers.

### 2.3 Analysis notes (13:05, while c3 waits for a slot -- ~30 sim.sh jobs queued)
- sc4 order (from run_r2_sc4.log): HOLD of 71 at 229.029 with nst=4 (N_NET): the origin's N_SEIZE of
  71 was pushed FIRST (h_done ~229.0), then the classifier's C_ACT pushed HOLD (71->00 BUSY) on top,
  then the watch's UNHOLD (71 free).  `mine` printed 0 because mine is computed for sp_port, not
  cls_port.  So the needed fix is a mine check at C_ACT (prior fix mine_c, or F1's look-again at a
  turn of cls_port); F2 alone (no UNHOLD on mine) would leave 71 held listening to 00 (direction lost
  silently until the origin drops it, no join).
- Classifier service time (run_r2_sc1.log): holds at +1.2, 20.3, 39.3, 58.3, 77.3, 96.3, 115.3 =
  19.0 ms apart = read (~1.1) + C_HOLD (T_ARM+2 ticks of tick_1k).  Capacity ~52 trunk seizures/s.
  C_HOLD exits right after a tick_1k (scan 00), so the next seizure taken is the lowest-numbered
  waiting port: strict priority by port number, not FIFO (sc7 tests it).
- A line lift also costs a classifier read (cls_seen is any M./BUSY port), ~1.1 ms, and a sweep
  pre-emption; lines (o20-o32) outrank E trunks (o40-o47) after a C_HOLD.
- The C_WAIT/cls_issue priority costs the sweep ~1 pass per classification that lands in it.
- Other agents reference work/audit/cls/RTL_fix.list and fix/ (C04 verify 'brk_clsfix'): DO NOT TOUCH.
- 13:15 job f4 queued behind c3 (chained: starts only after c3's sim.sh exits): run_f4.sh = fix2 on
  tb_cls2 sc2-6 + sc1 K8 (NMON 2), tb_cls3 sc7-9 (POOL8), tree tb_net/tb_lfull/tb_chain, overload.
  Progress in f4.progress; logs run_f4_<name>.log.
- New spec text (exchange/network.md 3.3/3.4) claims: "a trunk whose BUSY falls under a standing M is
  no fresh seizure" (false once the far caller dials: the break's M-low sample clears st, sc6) and
  rule 1 "the classifier takes a port only on a rise its bit has seen ... up to 20 ms behind a busy
  classifier" (false: the make after a dial break of an unheld port is taken; wait is 19(k-1) ms and
  unbounded under scan-order priority).
- 13:20 tb_cls3 sc10: the bench's far end now hunts HIGHEST first (opposite to the unit), before the build started.
- 13:10 added sc11 (3 ms far-M dip inside the C_HOLD watch, then our code 2 2 2 1: double claim + refusal?) to tb_cls3, run_c3.sh, run_f4.sh (the origin audit's speculative cross-slice item).
- an_model.out: classifier capacity 53 trunk seizures/s; at monitor.md's reference loads (48 lines,
  3 calls/h, 30-50% leaving, 8-47 exchanges, 2-4 copies a flood) rho_cls = 0.4%-7%, P(two or more
  seizures ahead) 1e-5..5e-3.  16 channels at ~2 s a copy cannot offer more than ~8/s (rho 0.15):
  the classifier is never the capacity limit; it matters only as latency inside the guard (C05) and
  for multi-path copies of one flood, which always meet (the second waits ~19 ms).
- 13:30 RE-SUBMITTED as ONE job (17 sim.sh jobs were queued; re-entering the lottery between jobs
  costs hours): run_all.sh through sim.sh (timeout 36000 incl. the wait).  Order: snapshot tb_cls3
  sc7 sc8 sc9 sc11 -> fix2 tb_cls2 sc2-6 + sc1K8 -> fix2 tb_cls3 sc7-11 -> snapshot ovl -> fix2 tree
  net/lfull/chain -> snapshot r1 -> fix2 ovl.  Progress: all.progress; logs run_<name>.log
  (c3_* snapshot, f4_* fix2).  run_c3.sh / run_f4.sh are superseded (never ran).

## 3. Draft findings (to be finalised with the run_all results)
N1 word-read-across-link-hit (NEW; sc2, sc3 reproduced round 1; sc8 dir misread pending)
   baseband_card.v:157 / local_trunk.v:192 gate the word pin by raw link_up (47 us of far-clock
   silence); a hit only CLEARS bits.  mini_marker.v:365 takes any word not trunk and not 0 as a
   caller; net_unit.v:572-574 drops a non-trunk word with st already set (570); cls_dir = rd_word[7:6]
   unchecked (573).  Fix: gate the word with C07's poison/ride-through latch (0 parts on top of C07's
   card fix); reader-side: read twice and agree (fix2).
N2 classifier-overwrites-own-seizure / mine gap (NEW; sc4 reproduced round 1)
   mine (429-438) has no term for the sweep's candidates; cls_seen checks mine only at its sample;
   C_ACT (595-622) and C_UNHOLD (590-594) write cls_port unchecked.  Order in run_r2_sc4.log:
   SEIZE 71 (origin), HOLD 71, UNHOLD 71.  Fix: F1 look at M/BUSY/mine at a later turn of cls_port
   (zero latency if taken at the read's own select turn) + F2 no UNHOLD when mine.
N3 st-cleared-by-a-dial-break (NEW root cause + 0-gate fix F4'; triggers sc6 and sc3 new; C05b, C04,
   C07 LTU-return cited).  Spec mismatch network.md 3.3.
N4 classifier scan-order priority (NEW aspect of C05 classifier-hold-serialises; sc7 pending)
N5 marker connects a caller to a trunk whose link is down (NEW; sc5 reproduced round 1): spec says
   OOS/none and trunks get cannot-complete (extensions.md 2.2 OOS; mini-marker.md table).
N6 dip inside the hold watch -> second cell -> double claim -> refusal over the taken call (sc11
   pending; origin audit's speculative item).  Downstream cascade: R_GONE + re-forward on the same
   lowest channel gives a >=HIT gap = a counted pulse downstream (C03-like) -- reasoning.
N7 CONFIRM has no second choice (sc9 pending; harmless when the link's ends are strapped for
   opposite hunt order, costs a direction when they are not).
- 13:37 run_all started 13:34, obj_c3 built in 126 s.

## 4. Results of run_all (snapshot = c3_*, fix2 = f4_*)
- c3_sc7 (snapshot, POOL8, real): SCAN-ORDER PRIORITY REPRODUCED, WRONG NUMBER.  47 seized at +5 ms
  (26.004) behind 10; 11..16 arrived at +10..+105 and were each held first (holds 41.3, 60.3, 79.3,
  98.3, 117.3, 136.4 = 19 ms apart); at ~155 the classifier was free but 47 was in its first break
  (+128..+188); taken at the make: seen +188.6, hold +189.7, cell +190.6 AFTER THE FIRST BREAK, e
  counted 2 (dialled 3) -> '1143.002 WRONG CLAIM on 47: far caller dialled 3 2' -> register on 47.
  FIFO would have held 47 at ~+20.  run_c3_sc7.log.
- BENCH BUG found in tb_cls3: 'MARKER TAKES TRUNK x AS A CALLER' tested att_take on the r_attach tick
  (att_take is a tick earlier); a legit claim attach was flagged.  Fixed 13:40 to test att_ack (same
  edge as r_attach) -- affects obj_c3 runs (sc8/9/11/ovl/r1: recount from the log: a flagged attach
  right after 'CLAIM x' is legit); obj_f4b (fix2) is built after the fix.
- c3_sc8 (snapshot): DIRECTION MISREAD REPRODUCED.  Link hit over the frames of bits 6-7 of the
  unit's (and marker's) read of W trunk 10: '22.264 cls read 10 word 00001011 trunk 1' -> HOLD dir 0
  -> '33.005 FWD 10 -> ok 1110 cand 00 30 40 11': legs W 11 (back the way it came), S 30, E 40; N 71
  not seized.  The W neighbour gets its own flood back late on channel 11.  run_c3_sc8.log.
- c3_sc9 (snapshot): NO SECOND CHOICE REPRODUCED.  Far end seized W 10 after the origin sweep read it
  free (h_n 16); CONFIRM dropped W; origin holds dirs 0111 (N S E) with W 11-17 all free.
  run_c3_sc9.log.  Harmless when each link's ends are strapped for opposite hunt order (then the two
  ends meet only on the last free channel); costs a direction when both ends hunt the same way.
- c3_sc11 (snapshot): DIP IN THE HOLD WATCH -> DOUBLE CLAIM -> REFUSAL OVER THE TAKEN CALL, REPRODUCED.
  3 ms far-M dip at +8..+11 ms: '29.146 UNHOLD 10 far alive 1' (forward cancelled), '32.146 RECLASS 10',
  second HOLD 33.264, second cell mon1; both cells count 2 2: '1038.003 CLAIM 10' (register attached),
  '1038.695 CLAIM 10' again, '1038.985 MK refuses the claim on 10' -> 10 written to NOGO(03) with CLM
  while the register collects h s; the connect after s re-points 10 to 21 (21 rung).  The far caller
  hears cannot-complete for ~1.7 s between b and the end of h s.  run_c3_sc11.log.
- f4_c2_sc2/sc3/sc4 (fix2, NMON 2, real): all PASS.  sc2/sc3: first read 01001000 -> one re-read
  11001011 -> second read agrees -> HOLD at +3.2 ms (snapshot path held nothing / the wrong thing);
  marker rejects 01001000 as a caller.  sc4: the look-again at the second select finds the blip gone:
  no HOLD, the origin's 71 listens to 20, no join.  Cost seen: the hold is ~1 ms later (2 ms after a
  retry).
- f4_c2_sc5 PASS (marker refuses called 30 with word 0: 22 -> 03, no breaks out on 30's link).
- f4_c2_sc6 PASS: no re-classification, no second claim ("classified 0 more times, claims 0 more");
  the marker's C16 loop on 10 still runs while the bench holds far M (1332 reads over ~3 s).
- f4_c2_sc1K8 PASS: classifier now 20 ms a seizure (holds +2.2, 22.3, 42.3, ... +1 ms per the double
  read).  16's watch still unholds at its first break (C04 not fixed by fix2) but F4' keeps st set:
  no re-classification, no second cell.  17, still waiting at its first break, is NEVER taken (lost
  copy) -- the intended F4' trade.  Both 16 and 17 then sit unheld under M: marker C16 loop on them.
- f4_c3_sc7 (fix2): no claim; 47 is NEVER held (a lost copy: its first break came while it waited,
  F4' set st on the BUSY of the break).  The 'held within two watches' check passes only as a bench
  artefact (t_hold = -1).  So fix2 turns the wrong number into a lost copy; the priority remains.
- f4_c3_sc8 (fix2) PASS: reads 00001011 then 11001011 disagree -> re-read -> HOLD dir 3 at +4.2 ms;
  legs N S E, none west.
- f4_c3_sc9 (fix2) FAIL as expected (fix2 does not touch the sweep).
- f4_c3_sc11 (fix2) FAIL as expected: the watch still unholds on the 3 ms dip (UNHOLD at 29.146 is
  before any read question) -- needs C04's fix (M low must outlast a break before the watch unholds);
  the prior agent's watcher fix (unhold only after CLR of low) covers it too.
- c3_ovl (snapshot, POOL8, real; offered 30 floods/s, 85% short copies): the TRUNK GROUPS saturate
  first: 165 floods accepted, 266 blocked (no free trunk from the far end) in 15 s, ~11/s carried.
  Classifier busy 3102 ms of the 15 s load (~21%), backlog max 2, mean 0.07.  rise->hold p50 1.7,
  p90 13.7, p99 30.7, max 38.7 ms; W (ports 10-17) max 18.3 ms, E (40-47) max 38.7 and all 6 of the
  >19 ms waits: the scan-order priority shows statistically.  No late cell, no re-hold, no wrong
  claim (the 30 exposed 3 2 callers had t1 >= 100 ms and the wait never exceeded 39 ms).
  Sweeps 164, mean 10.49 ms, max 11.74 (nominal ~10, +<=1.7 ms of classifier pre-emption).
  Marker read request->select n=104 mean 1.64 max 7.99 ms (bounded by one sweep); classifier read
  request->select always 0.99 ms (never delayed by the marker).  Marker read trunks 99 times, lines 5.
  2 resolver-leg claims (bench far end seized the last free W channel as our forward took it: C13
  residual glare at a nearly full group, 2 in 165 floods, uncounted by the unit).  Dial-tone delays
  of 1.3-1.8 s were the one register held by a network call (C15), not the read path.
  an_c3_ovl.txt.
- f4_tree_net (fix2, tb_net as in the tree, 703 s): 88 checks, 1 error.  The one FAIL is scenario 14's
  "B read the blip as a seizure: it held it and gave it a monitor" -- the bench ASSERTS that a 0.9 ms
  blip is held.  fix2's look-again at the second select sees M down and never holds it (intended: no
  hold to write away, no stale C03 cell); 14's other check ("11 is not BUSY") passes.  Everything
  else in tb_net is green on fix2.
- f4_tree_lfull (fix2): 40 checks, 0 errors, PASS (971 s) -- the glare/mine bench stays green.
- f4_tree_chain (fix2): 32 checks, 0 errors, PASS (179 s).  fix2 regression: net 87/88 (the one is the intended blip change), lfull 40/40, chain 32/32.  lnet/lchain not run.
- c3_r1 (snapshot, POOL8, real; offered 5 floods/s, 50% dial 3 2 with first break 60-700 ms after the
  rise, 10% dial 2 2 2 1, 4 phones): 101 floods carried (3.4/s), 37 blocked (trunks), classifier busy
  ~6% of the load, backlog max 2, mean 0.007.  rise->hold p50 1.7, p90 1.7, p99 15.6, max 19.3 ms.
  No late cell, no re-hold, no unhold of a live seizure, no wrong claim (46 exposed 3 2 callers, 14 of
  them with t1 < 200 ms).  5 claims on 2 2: 3 attached, 2 REFUSED (register busy with a local caller:
  C15, 2 of 5).  Sweeps 101, mean 10.45 ms, max 10.74.  Marker read req->select n=56 mean 1.15, max
  8.99 ms.  Dial tone p50 3 ms; the 1.4-1.8 s ones were the one register held by a network call (C15).
  After the drain nothing held.  The one FAIL is the bench artefact (3 'MARKER TAKES TRUNK' lines, each
  right after 'CLAIM <same port>': legit claim attaches; obj_c3 was built before the probe fix).
  an_c3_r1.txt.
- f4_c3_ovl (fix2, same offered overload as c3_ovl): 176 carried, PASS, no late pickup, no wrong claim,
  nothing held after the drain.  rise->hold p50 2.7, p90 15.7, p99 29.7, max 41.7 ms (each hold ~1 ms
  later than the snapshot's: the double read); E still carries the long tail (8 of 10 waits > 19 ms,
  max 41.7 vs W 21.3): fix2 does not change the order.  an_f4_ovl.txt.
- 15:05 run_all ALLDONE (slot held 13:34-15:05); every obj_* removed; the directory is 1.2 MB.
- f4_c3_ovl: one lift (32 at 10220) got no dial tone in 3 s: 22 lifted later (11053) and took the
  register first (scan order: the known, accepted caller starvation) and then held it on a network
  call (C15).  Not the read path.

## 5. Status 15:10: all runs done; final report assembled from sections 0-4 (findings N1-N7 plus
counts for C13/C15/C16 and a bench gap).  Not run: fix2 on tb_lnet/tb_lchain; the forwarder-candidate
variant of the mine gap (same mechanism as sc4, argued not run).
