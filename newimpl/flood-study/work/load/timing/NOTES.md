# timing/ -- SAFETY under load and the timing margins, at REAL timers

Agent: timing study (safety + guard reach at +define+SCALE1).  Started 2026-09-26 12:40.
Everything of mine is under work/load/timing/.  The snapshot RTL is read-only.

## Plan
1. tb_tim3.sv (chain A22-B23-C24, tb_load3 wiring) + tb_tim5.sv (chain of five,
   22-23-24-25-26) with bench-side hierarchical probes (tim_probe.svh): every
   flood tagged with the caller's call id and followed hop by hop:
   KEY -> SEIZE (origin) -> RISE at each incoming trunk -> CLS read -> HOLD ->
   cell ARMED -> FWD legs; every M edge on a tagged port (relayed pulses);
   cell digit counts vs dialled; CLAIM; ATT/attach; far register h s vs dialled.
2. tim_harness.svh = load_harness.svh + (a) +burst_ms (pair schedule period),
   (b) +idg0_ms/+idg0_jit_ms (the key->e pause alone).  Nothing else changed.
3. Clocks with +ppm_<X> knobs (plesiochronous runs at +-1000 ppm).
4. Runs: baseline hop timing; key->e pause scan (guard reach); bursts; ppm.

## Results (appended as they come)

## Infrastructure (12:40-13:15)
- tim_harness.svh: load_harness.svh + knobs +burst_ms (pair period), +idg0_ms/+idg0_jit_ms
  (key->e pause alone).  diff is 10 lines.
- tim_probe.svh: TE event lines (see header).  `tagged` is an SV keyword -> tim_ok().
- tb_tim5.sv (chain of five 22-23-24-25-26, 16 phones each on blocks 2,4), tb_tim3.sv
  (tb_load3 chain + ppm knobs).  +ppm_a..e knobs (defaults 0 +100 -100 +50 -50).
- tim_an.py LOG [--flood]: distributions + anomalies (MISCOUNT, FALSECLAIM, LATEARM,
  RESEIZE, REGMISCOUNT, C06).
- SLOT CONTENTION: ~25 sim.sh jobs queued for 5 slots (random acquire, not FIFO): a lint
  waited 25 min and never started.  So: runner.sh holds ONE slot and runs
  queue/*.sh in order (exits after 10 min idle or queue/STOP).  Log: runner.log.
  To continue: drop job scripts into queue/ and (if the runner exited) restart it:
  ./sim.sh work/load/timing/runner.sh  (in background).

## Results
- 13:20 tim5 build OK (369 s).  SPEED: tb_tim5 SCALE1 (5 exchanges, 80 phones) runs
  ~220 wall-s per sim-s at machine load 15 (PROG 1000->1500 ms in 110 s).  The speed test
  (run_speed.log, A20 dials E20) gave one clean flood through 4 hops:
  key->seize 10.0 ms; seize->B rise 2.1; rise->CREAD 0; rise->HOLD 1.1; HOLD->ARM 0.9;
  HOLD->FWD 10.7; rise-to-rise per transit 13.15, 13.89, 13.07 ms; seize->ARM at E 44.2 ms;
  the leaf E sweeps for nothing (FNONE, C14 leaf).  A dial break relays ~0.5 ms a hop.
- Added +pair_off=a,b,.. (per-pair lift offsets, period +burst_ms) to tim_harness.svh;
  tim5 rebuilt with it (job 026).
- PLAN (queued 13:45, runner holds the slot): 100 cv8 (8-chain, A20+B20 keyed together
  -> bad code 4 3 then 21; H=33 falsely claims iff its cell loses e's first pulse; key->e
  pause 255..305 ms so the seizure->first-break gap spans 115..165 ms; other pauses 300;
  a burst every 5 s, 6 bursts); 110 cv8x4 (same with NMON=NRES=4 and a 4-flood convoy
  A,B,C,D); 120 cv8ppm (cv8, 3 bursts, crystals alternating +-1000 ppm); 130 load5 (5-chain
  Poisson, 70% network, 720 ms pauses (ES minimum), real calls).
- MODEL to test (from the RTL): a hop is ~13.4 ms; the destination's T_ARM watch ends
  ~20 ms after arrival; a break arriving inside it re-seizes (C04/C05).  The classifier
  serialises holds 18-19 ms apart, so a flood trailing another is held back to ~19 ms
  behind it ONCE (the gap then persists, it does not grow per hop); a local origin sweep
  at a transit adds up to ~10 ms (F_WANT yields to N_WANT).  With NRES=2 a transit forwards
  at most 2 floods at once, so the 3rd of a convoy is dropped (C14) rather than delayed:
  the small pools turn the late-flood hazard into silent loss.  Predicted required gap at
  7 hops: front flood ~88 ms, rear of a 2-convoy ~118-131 ms (vs the 120 ms minimum gap
  that passes the 128 ms guard) -> borderline; 4-convoy with NRES=4: ~170 ms -> failures.
- 13:50 cv8 burst 1 (run_cv8.log, 8-chain, tb_timn ~420 wall-s/sim-s): A key 415.004, B key
  414.964.  B's flood (front, 6 hops east) rise-to-rise 13.0-14.0 ms a hop; A's flood (rear,
  7 hops): delayed 6 ms ONCE at C (C_WAIT behind B's flood's T_ARM watch: rise 440.20, CREAD
  446.20), thereafter trailing B's by 19 ms with no further loss.  A's hold at H = seizure
  +90.2 ms, watch end +108.2; A's e first break at A = seizure +141.3, reached H at 570.10
  (+145.1), 54.9 ms after H's hold.  Pulses relay ~0.5 ms a hop, 7 hops in 3.8 ms.
  => a 2-flood convoy at 7 hops leaves ~12 ms of the 120 ms minimum gap.  MODEL REVISED:
  the convoy penalty depends on the key offset d (B after A): ~0 for d<0, ~d+6 for
  0<d<12.6 (max ~18 ms when B keys just before A's flood reaches B: B's origin sweep
  delays A's forward (F_WANT yields) and B's flood then leads A's by 19 ms), 0 for d>12.6.
  With NRES=2 at most 2 floods can be in flight through any transit, so penalties cannot
  compound: worst single penalty ~18 ms -> 128 ms covers 7 hops.  With larger pools a
  WAVE of local keys at transits can compound them.
- QUEUE REVISED 14:00: cv8 cut after 2 bursts; 110 cvd8 (key offsets d = 6,9,12,15 ms over
  4 bursts); 115 wave8x4 (NMON=NRES=4: A keys, C keys +24, E +65, G +106 ms, each timed so
  its origin sweep delays A's forward and its flood then leads A's; predicted A hold at H
  ~seizure+127, watch end +145 -> false claims by H for gaps 120-145); 118 wave8 (same on
  NRES=2: predicted A dropped at F, no resolver: silent NOGO); 120 wave8x4ppm (+-1000 ppm);
  130 load5.
- RUN cv8 rc=143 wall=2825s args: +seed=1 +pairs=A20Z21,B20Z21 +pair_off=0,1 +bad_e=4 +bad_b=3 +dur_ms=30000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000
  ONELINE run_cv8.log | sim_end=8286ms calls=4 {'SILENT': 4} | floods=4 guard_ab=0 no_seize=0 | miscount=0/28 falseclaim=0 regmis=0 latearm=0 reseize=0 C06=0 unwatched=0 nofwd=0 inwatch=0 | seize->arm h1:3.9/4.2/4.2(n6) h2:21.0/24.6/24.7(n4) h3:34.5/38.6/38.6(n4) h4:48.0/51.6/51.7(n4) h5:61.5/65.6/65.6(n4) h6:75.0/78.7/78.7(n4) h7:91.9/92.6/92.6(n2) | margin(all) 108.6/160.0/160.0(n28) | WRONG=0
- cv8 DONE (2 bursts, 8.3 s sim, 2825 wall-s = 283 wall-s/sim-s): 4 floods, 28 cell digits, 0
  miscounts, 0 false claims, all SILENT (bad code, as designed).  Nominal transit hop
  (rise->next rise) 13.08-13.93 (alternating with the scan phase; mean 13.5); hop 1 (seize
  -> neighbour rise) 1.3-2.2; rise->HOLD 1.12; HOLD->ARM 0.9; rise->legs written 11.86.
  Rear flood penalty: burst 1 (B keyed 0.04 ms before A) 6 ms at C; burst 2 (B keyed 1.5 ms
  after A) 9 ms at C -- once, then 19 ms behind the front flood.  Rear flood hold at H
  (7 hops) = seizure +90.2 / +91.7, T_ARM watch end +108 / +110; the minimum gap passing the
  guard is ~120 (+3.8 ms of relay to H) -> slack 14-16 ms at 7 hops.
  RELAYED PULSES: 280 breaks over 1-7 hops: length 58.99-60.01 ms for 60 ms dialled;
  relayed-minus-origin mean -0.05, min -1.0 ms at every depth (no accumulation); the
  edge reaches hop k ~0.55k ms after the origin sees it.  network.md 10's "relayed
  dial pulses" item: measured, no distortion beyond the 1 ms sampling.
- 14:40 queued 125 burst5 (5-chain, all five exchanges key at once, bad code 3 2 so A=22
  falsely claims iff its cell loses e's first pulse; 3 bursts).

## Draft findings (update as runs land)
1. guard-reach-measured (C05, spec-mismatch): hop 13.5 ms (not ~12); the guard must also
   cover the destination's rise->hold (1.1) + T_ARM watch (18) and loses HIT (8): a break
   passes the guard only if it starts >= 120 ms after the seizure.  Nominal reach =
   1 + floor((120 - 1.9 - 1.1 - 18 + 0.55K)/13.5) -> 8 hops (doc: ~10).  One slow event
   (a penalty <= ~18 ms) -> 7 hops.  (cvd8/wave runs pending for the max penalty and
   compounding.)
2. relayed pulses: no distortion (see cv8).
- 15:05 cvd8 partial (2 of 4 bursts): d=5 ms: A's hold at H +97.2 (penalty 11 over
  cv8's no-penalty ~86); d=9.5: A's hold at H +100.7, watch end ~+118.7; that burst's gap
  was 117.3 -> GUARD abandon (ODROP guard=1), correctly; its break reached H 19.9 ms after
  H's hold, i.e. 2 ms past the watch.  A gap of 120 (the smallest the guard passes) would
  have cleared the watch by ~4-5 ms.  B's key->seize 11-12 ms when A's flood's classifier
  read interleaves B's origin sweep (vs 10.0).
- 15:25 cvd8 burst 3 (d=12): A's hold at H +102.2 = penalty 18.2 ms over the no-penalty
  ~84 (hop1 1.9 + 6x13.5 + 1.1): the predicted worst single penalty.  Required gap at H =
  hold + 18 (watch) - 3.8 (relay) = 116.4 < 120: SAFE at 7 hops by 3.6 ms; at 8 hops the
  same event needs 129.9 > 120 -> late flood (C05).  Nominal reach: 8 hops (97.5+18-4.4 =
  111 < 120), 9 hops fails (124.6).  B (burst 3) gap 117.3 -> GUARD abandon, correct.
- 15:35 queued 113 wave2n (DEFAULT pools, 8-chain): A keys 0, B +12 (worst convoy
  penalty, ~18 ms), G +95 (its origin sweep delays A's forward at G and its flood then
  holds H's classifier ahead of A's): predicted A hold at H ~seizure+117, watch end +135,
  required gap ~131 -> key->e pauses 256-272 (gaps ~118-134) should give FALSE CLAIMS at
  H for gaps 120-131: a wrong number at 7 hops with the default pools and 3 keys.
  (revised: wave2n moved after wave8x4 and cut to 2 bursts: with NMON=2, B's and G's
  floods take both of H's cells before A's arrives, so the prediction is A UNWATCHED at H
  (cell=-), a silent NOGO, not a false claim -- the pools protect.)
- RUN cvd8 rc=0 wall=6357s args: +seed=3 +pairs=A20Z21,B20Z21,A21Z21,B21Z21,A22Z21,B22Z21,A23Z21,B23Z21 +pair_off=0,6,5000,5009,10000,10012,15000,15015 +dur_ms=20000 +dest_mode=4 +burst_ms=20000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_cvd8.log | sim_end=18264ms calls=8 {'SILENT': 6, 'NOGO': 2} | floods=8 guard_ab=2 no_seize=0 | miscount=0/42 falseclaim=0 regmis=0 latearm=0 reseize=0 C06=0 unwatched=0 nofwd=0 inwatch=0 | seize->arm h1:4.4/11.3/12.2(n12) h2:24.3/35.1/35.2(n8) h3:37.8/49.0/49.1(n8) h4:51.3/62.1/62.2(n8) h5:64.8/76.0/76.1(n8) h6:78.3/89.1/89.2(n8) h7:96.6/103.1/103.1(n4) | margin(all) 90.4/148.0/148.0(n56) | WRONG=0
- 16:18 cvd8 DONE (4 bursts, 18.3 s sim, 6357 wall-s = 350 wall-s/sim-s): 8 floods, 56 hop
  arrivals, 42 cell digits, 0 miscount, 0 false claim, 2 guard abandons (gaps 117.3,
  117.3: correctly abandoned), 6 SILENT (bad code), INVARIANT 98/98 PASS, WRONG 0.
  Penalty vs key offset d (B after A): d=-0.04: 6; d=1.5: 9; d=5: ~11; d=9.5: ~15;
  d=12: 18.2 (A's hold at H +102.2); d=15.4: A's flood reached B first, so B's ORIGIN
  waited for A's forward sweep: B key->seize 17.0 ms (not 10), then B's flood waited
  10 ms at C -> B's penalty ~17.  => the worst single slow event is ~18 ms (model OK);
  the key->seize stretch (+7 ms here, up to ~11) is the C06 window widening under load:
  a key->e pause up to ~145-150 ms then puts e's first break before the seizure write.
- 16:29 wave8x4 burst 1: A's gap 118.3 -> guard abandon (correct).  The wave worked: A's
  flood reached H at seizure +121.1 (nominal ~83: +38 ms from three slow events: holds
  at D +46.2, F +92.2 behind the local floods' watches, forwards waiting for C/E/G origin
  sweeps).  e's first break reached H 1.0 ms after the flood did, and reached G 15.9 ms
  after G's hold -> UNHOLD at G (C04 shape; harmless here, the origin had abandoned).
  C, E, G key->seize 11, 12, 14 ms (reads/sweeps interleaving).
- 16:50 *** WRONG NUMBER REPRODUCED *** wave8x4 burst 2 (NMON=NRES=4, 8-chain, real
  timers): A20 dialled 1 4 3 2 1 (code 43: nobody's) with a key->e pause giving a gap
  of 135.3 ms (passes the 128 ms guard by 15 ms).  C, E, G keyed 24.5/65.5/106.5 ms
  after A.  A's flood reached H (7 hops) at seizure +123.6 (nominal ~83: +40 from the
  slow events at D and F).  H's classifier was watching E's hold (5526.7) then G's
  (CREAD 5544.6 after waiting 7 ms, hold 5545.7, watch to ~5563.7): A's rise at 5547.6
  waited; e's first break reached H at 5562.6 (1 ms before the classifier was free), M
  low cleared st, and at the make (5622.6) the classifier took port 13 as a FRESH
  seizure (HOLD 5623.7, cell 3): the cell counted e=3 (dialled 4), b=3 -> CLAIM by H
  (33) at 6611.3; A's origin took it (OCLAIM 6615.1), connected at o_last (ODONE
  7428.0), H's register counted h=2 s=1 -> H21.  Mechanism C05 (late flood +
  serialised classifier, net_unit.v:283-284, 566-570, 584-588, 612-615).  Evidence:
  run_wave8x4.log lines TE 5547.633 H RISE 13 5 ... TE 6611.338 H CLAIM 13 5.
  Harness verdict: "WRONGRING t=7443 at=H21 caller=A20" and "CALL id=5 from=A20
  to=43?? kind=BAD dial=14321 ... out=WRONG rang=H21".  End to end.
- wave8x4 burst 3: A's gap 158.3; A's hold at H +139.3 (watch end ~157); break at H
  +162.1 -> safe by ~5 ms.  So under this 3-key wave the gap needed at 7 hops is ~153 ms:
  gaps 120-153 -> wrong number (1 of 1 in range, burst 2), <120 abandoned (burst 1),
  >153 safe (burst 3).  128 ms covers ~4-5 hops against 3 compounding slow events.
- RUN wave8x4 rc=0 wall=3952s args: +seed=4 +pairs=A20Z21,C20Z21,E20Z21,G20Z21 +pair_off=0,24,65,106 +dur_ms=15000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_wave8x4.log | sim_end=13381ms calls=12 {'NOGO': 1, 'SILENT': 10, 'WRONG': 1} | floods=12 guard_ab=1 no_seize=0 | miscount=1/78 falseclaim=1 regmis=0 latearm=1 reseize=0 C06=0 unwatched=0 nofwd=0 inwatch=2 | seize->arm h1:5.4/11.1/11.1(n21) h2:17.1/22.0/22.2(n18) h3:34.3/49.4/49.6(n15) h4:46.8/62.5/62.7(n12) h5:68.6/95.5/95.6(n9) h6:86.7/108.6/108.7(n6) h7:170.4/200.0/200.6(n2) | margin(all) 110.1/155.3/157.0(n83) | WRONG=1
- 17:45 FIX UNDER TEST (work/load/timing/fix/net_unit.v, diff vs rtl/net_unit.v ~30 lines):
  "a late rise is not a seizure".  Per port: hi_a/hi_b = M seen high at a visit in this /
  the last CLR/2 (128 ms) window; taint = M seen LOW at a visit with hi_a|hi_b (a dial
  break or a release), cleared at a window boundary when the ended window saw no M high.
  The classifier latches taint at cls_seen/cls_issue (cls_late); a late seizure is HELD
  (so the marker never takes it, and the port still releases itself) but gets NO cell and
  is NOT forwarded.  Board: a 64x4 RAM on SCAN + a tap of the 1 ms count, ~3 packages.
  Jobs: 122 build timn4fix (NMON=NRES=4, +define+TIM_FIX), 123 wave8x4fix (replay of
  wave8x4 bursts 1-2, same seed: burst 2 must turn WRONG into a lost call), 124 regression
  of the fix on tb_net/chain/lnet/lchain/lfull (scale 8, window = CLR/2 = 16 ms there).
- 17:37 wave2n DONE (default pools, 1 burst; A keys 0, B +11, G +94): A's gap 125.3
  (passes the guard).  A's flood reached H at +108.1, waited 13 ms behind G's hold, HOLD
  at +121.2 with NO CELL (B's and G's floods held both of H's cells); e's first break
  arrived 7.9 ms into the hold's T_ARM watch -> UNHOLD -> re-seized at the make (2nd HOLD,
  C04) -> still no cell -> nobody claims -> A's call cannot-complete.  G's flood westbound:
  no resolver at F (nofwd, C14).  So with NMON=2 the pool (not the design) stopped a wrong
  number: a free cell at the re-seizure would have counted e=3 and H would have claimed.
- RUN wave2n rc=0 wall=2146s args: +seed=7 +pairs=A20Z21,B20Z21,G20Z21 +pair_off=0,12,95 +dur_ms=5000 +idg0_ms=256 +idg0_jit_ms=16 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_wave2n.log | sim_end=3343ms calls=3 {'NOGO': 1, 'SILENT': 2} | floods=3 guard_ab=1 no_seize=0 | miscount=0/7 falseclaim=0 regmis=0 latearm=0 reseize=1 C06=0 unwatched=2 nofwd=1 inwatch=1 | seize->arm h1:4.7/7.0/7.1(n4) h2:26.7/35.0/35.2(n2) h3:40.2/48.9/49.1(n2) h4:53.7/62.0/62.2(n2) h5:67.2/75.9/76.1(n2) h6:80.7/89.0/89.2(n2) | margin(all) 83.5/121.6/122.0(n14) | WRONG=0
- wave2n harness verdict: A20 SILENT (lost, not wrong), B20 NOGO why=N_GUARD, G20 SILENT;
  INVARIANT 98/98 PASS.  18:00 wave8x4ppm started (same seed as wave8x4, crystals +-1000).

## Findings so far (for the final report)
F1 CRITICAL wrong-number under load, C05, reproduced (wave8x4 burst 2, see above).
F2 guard reach measured: 8 hops with no slow event, 7 with one (worst single event 18.2
   ms, cvd8), ~4-5 against 3 compounding events (wave8x4 needs gap ~153 at 7 hops).
   Default pools (NMON=NRES=2) prevent compounding in a chain in every pattern tried
   (wave2n: no cell at H; C14 drops): so 7 hops is safe with the default card, 8 hops
   is not (one event: need 129 > 120).  network.md 6's "~10 typical, 4-5 slow" is
   optimistic by 2 hops typical because it leaves out the destination's T_ARM watch
   (18 ms) and HIT (8 ms), and pessimistic for the default card (slow hops cannot
   compound with 2 resolvers).  Doc's 12 ms hop is 13.5 measured.
F3 the default pools are what stops it: raising NMON/NRES (the capacity fix for C14)
   re-exposes C05 unless the late-rise fix goes in first.
F4 relayed pulses: no distortion (cv8).
F5 C06 window widens under load: B key->seize 17 ms when its origin waited for a
   forward sweep (cvd8 burst 4); 11-15 ms in the wave.
- 18:40 wave8x4ppm (crystals 0, +1000, -1000, ... ppm alternating: 2000 ppm between
  neighbours): burst 1 the same guard abandon (gap 118.3); burst 2 the SAME WRONG NUMBER
  (A's flood at H: arrival +123.6, hold +199.7 at the make, cell counted E3 B3, H
  claims).  Every hop within ~1 ms of the +-100 ppm run.  Plesiochronous clocks at
  +-1000 ppm do not move the margins: the effect is below the 1 ms scan quantum.
  Relayed breaks at +-1000 ppm: 435 breaks, 57.94-61.94 ms for 60 dialled (vs 58.99-60.01
  at +-100 ppm): +-2 ms, no accumulation with depth (hop 7 mean -0.06).  Harmless against
  HIT 8 / ID 128.
- RUN wave8x4ppm rc=0 wall=5677s args: +seed=4 +pairs=A20Z21,C20Z21,E20Z21,G20Z21 +pair_off=0,24,65,106 +dur_ms=10000 +ppm_amp=1000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_wave8x4ppm.log | sim_end=8360ms calls=8 {'NOGO': 1, 'SILENT': 6, 'WRONG': 1} | floods=8 guard_ab=1 no_seize=0 | miscount=1/50 falseclaim=1 regmis=0 latearm=1 reseize=0 C06=0 unwatched=0 nofwd=0 inwatch=2 | seize->arm h1:5.4/11.1/11.1(n14) h2:17.6/22.2/22.2(n12) h3:34.7/48.6/48.7(n10) h4:47.4/62.6/62.6(n8) h5:68.9/94.6/94.6(n6) h6:86.9/108.7/108.7(n4) h7:200.6/200.6/200.6(n1) | margin(all) 107.9/155.8/156.8(n55) | WRONG=1
- 20:35 FIX REPLAY (wave8x4fix, same seed, NMON=NRES=4 + fix/net_unit.v): every event
  identical to wave8x4 up to H's late classification; at 5623.744 H holds port 13 with
  "late=1" -> no cell, no forward -> no count, no CLAIM (the unfixed run claimed at
  6611.3).  A's call becomes a lost call (cannot-complete/silent) instead of a WRONG.
- RUN wave8x4fix rc=0 wall=6609s args: +seed=4 +pairs=A20Z21,C20Z21,E20Z21,G20Z21 +pair_off=0,24,65,106 +dur_ms=10000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_wave8x4fix.log | sim_end=8361ms calls=8 {'NOGO': 1, 'SILENT': 7} | floods=8 guard_ab=1 no_seize=0 | miscount=0/48 falseclaim=0 regmis=0 latearm=0 reseize=0 C06=0 unwatched=1 nofwd=1 inwatch=2 | seize->arm h1:5.4/11.1/11.1(n14) h2:17.1/22.0/22.2(n12) h3:34.4/49.4/49.6(n10) h4:46.8/62.5/62.7(n8) h5:68.6/95.5/95.6(n6) h6:86.7/108.6/108.7(n4) | margin(all) 111.0/155.9/157.0(n54) | WRONG=0
- 21:34 wave8x4fix DONE (13 s sim, 6609 wall-s): A20's burst-2 call SILENT (was WRONG),
  WRONG 0, INVARIANT 98/98 PASS (the late hold released itself: nothing left held).
  126 fix regression on the snapshot benches started.
fix-regress net build=0 rc=0 fails=0 secs=1050 
fix-regress chain build=0 rc=0 fails=0 secs=357 
fix-regress lnet build=0 rc=0 fails=0 secs=303 
fix-regress lchain build=0 rc=0 fails=0 secs=395 
fix-regress lfull build=0 rc=0 fails=0 secs=1161 
- 22:28 FIX REGRESSION: tb_net 88/0 PASS, tb_chain 32/0 PASS, tb_lnet 37/0 PASS, tb_lchain
  48/0 PASS, tb_lfull 40/0 PASS (fix/run_*.log; scale 8, window CLR/2).  130 load5 next
  (5-chain Poisson, 720 ms pauses, idle 50 s, 20 s traffic).
- 23:35 load5 interim (22 s sim): registers at 0.6-1.0 occupancy; 17 floods, 85 cell digits,
  0 miscount, 0 false claim, 0 guard abandons; margins 566-580 ms (720 ms pauses: the
  guard is irrelevant, as computed).  11 claims, 10 REFUSED (the far register busy with a
  local caller: C15); network calls 1 OK of 12 so far; N_TCLAIM 3 (C14: 6 holds with no
  cell, 4 not forwarded).  claim->att 0.29-0.43 ms; claim->take 0.42 ms.
- RUN load5 rc=0 wall=5896s args: +seed=5 +dest_mode=0 +pnet=700 +idle_ms=50000 +dur_ms=20000 +grace_ms=5000 +drain_ms=8000 +ans_ms=1000 +hold_ms=3000 +prog_ms=5000
  ONELINE run_load5.log | sim_end=25279ms calls=24 {'OK': 4, 'NOGO': 14, 'BUSY': 1, 'CUT': 5} | floods=18 guard_ab=0 no_seize=0 | miscount=0/104 falseclaim=0 regmis=0 latearm=0 reseize=0 C06=0 unwatched=7 nofwd=4 inwatch=0 | seize->arm h1:3.4/4.3/4.3(n23) h2:16.3/17.1/17.1(n16) h3:29.0/30.5/30.5(n9) h4:41.5/44.1/44.1(n6) | margin(all) 566.9/580.0/580.1(n54) | WRONG=0
- 00:07 load5 DONE (5-chain, Poisson, 720 ms pauses, idle 50 s, 80 phones; 33.0 s sim, 20 s
  traffic, 5896 wall-s = 179 wall-s/sim-s).  24 attempts (1.2/s offered): LOCAL 5 (3 OK,
  1 BUSY, 1 CUT); NETWORK 19: 1 OK, 14 NOGO, 4 CUT.  Of 13 CLAIMS, 12 REFUSED (far
  register busy: C15) and 1 taken; 7 holds got no cell (NMON=2 full: C14), 4 not
  forwarded (resolvers/forwarder busy: C14), leaves swept for nothing 23 times.  Register
  occupancy 0.43-0.89, dial-tone delay mean 2.07 s, p99 11.1 s.  SAFETY: wrong 0, joined
  0, xtalk 0, phantom 0, stuck 0, INVARIANT 62/62; 104 cell digits, 0 miscount; margins
  arm->first break 540-580 ms (the guard is irrelevant at 720 ms pauses); hop 12.0-13.9.
  CAPACITY: with one register an exchange, a claim finds the far register busy with a
  local caller about as often as that register is occupied, and is refused at once (no
  queue): network completion collapses to ~5% at register occupancy ~0.75.
- RUN burst5 rc=0 wall=2252s args: +seed=6 +pairs=A20Z21,B20Z21,C20Z21,D20Z21,E20Z21 +pair_off=0,1,2,3,4 +bad_e=3 +bad_b=2 +dur_ms=10000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000
  ONELINE run_burst5.log | sim_end=8091ms calls=10 {'NOGO': 1, 'SILENT': 9} | floods=10 guard_ab=1 no_seize=0 | miscount=0/20 falseclaim=0 regmis=0 latearm=0 reseize=0 C06=0 unwatched=8 nofwd=6 inwatch=0 | seize->arm h1:6.8/22.2/22.4(n12) h2:26.4/35.0/35.2(n8) | margin(all) 133.1/161.9/163.0(n20) | WRONG=0
- 00:44 burst5 DONE (5-chain, all five key within 3 ms, 2 bursts, 13 s sim, 2252 wall-s):
  10 floods: 20 of 40 possible (flood, exchange) arrivals reached; 8 holds with no cell
  (NMON=2), 6 holds not forwarded (resolvers/forwarder); A's floods never reach E, D's and
  E's never pass C/D.  The classifier queue at D: holds at +3, +22, +40, +58 ms after
  their rises (19 ms a place, 4 deep).  0 miscount/20, 0 false claim, WRONG 0, INVARIANT
  62/62.  => a 5-way simultaneous burst at a transit is absorbed as silent loss; the late
  (58 ms) holds all had no cell, so no hazard with the default pools.
- 00:47 queued 140 wave2x4: wave2n's two-event pattern (B +12, G +95) on NMON=NRES=4: if 2
  coincident keys suffice for a wrong number at 7 hops with 4-cell pools, H claims when
  A's gap is ~120-131 ms.
- 00:55 wave8 burst 1 (DEFAULT pools, the wave8x4 pattern): A's flood held at F with no
  cell and NOT forwarded (F's two resolvers held by C's and E's floods) -> never reaches
  G, H: the call is lost, not wrong.  E's westbound flood dropped at D, G's at F; G's flood
  at H got no cell.  Same pattern, NRES/NMON=4 -> WRONG (wave8x4); =2 -> lost.
- RUN wave8 rc=0 wall=2700s args: +seed=4 +pairs=A20Z21,C20Z21,E20Z21,G20Z21 +pair_off=0,24,65,106 +dur_ms=10000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_wave8.log | sim_end=8359ms calls=8 {'NOGO': 1, 'SILENT': 7} | floods=8 guard_ab=1 no_seize=0 | miscount=0/24 falseclaim=0 regmis=0 latearm=0 reseize=0 C06=0 unwatched=8 nofwd=6 inwatch=0 | seize->arm h1:5.0/9.0/9.1(n8) h2:17.9/22.1/22.2(n8) h3:38.3/49.5/49.6(n6) h4:52.8/62.6/62.7(n4) h5:58.1/58.1/58.1(n2) | margin(all) 116.0/155.0/155.0(n28) | WRONG=0
- 01:29 wave8 DONE (default pools, 2 bursts, 13 s sim, 2700 wall-s): burst 2 is wave8x4's
  WRONG burst (same seed, A's gap 135.3): A's flood held at F with no cell, not forwarded
  -> SILENT.  8 unwatched, 6 not forwarded, 0 miscount/24, WRONG 0, INVARIANT 98/98.
  Pair: identical dialling, NMON=NRES=4 -> WRONG; =2 -> lost call.
- 01:40 *** SECOND WRONG-NUMBER SHAPE *** wave2x4 burst 1 (NMON=NRES=4, wave2n's dialling:
  A keys 0, B +11, G +94): A's gap 125.3 (passes the guard by 5 ms).  A's flood reached H
  at +108.1, held at +121.2 behind G's hold (cell 1, counted E4 correctly); e's first
  break reached H 7.9 ms into the T_ARM watch -> UNHOLD (net_unit.v:584-594) -> at the
  make the port was classified afresh (st cleared by the M-low visit, :566-570) -> second
  HOLD with a second cell (:612-615) -> counted E3 B3 -> CLAIM by H at 1602.8.  C04
  (hold-watch-dial-break) under load.  In wave2n (NMON=2) the same re-seizure found no
  free cell -> lost call instead.  Only 2 coincident keys needed with 4-cell pools.
  Harness verdict: "CALL id=1 from=A20 to=43?? kind=BAD dial=14321 ... out=WRONG
  rang=H21".  145 wave2x4fix queued (the fix on this shape, 1 burst).
- RUN wave2x4 rc=0 wall=1671s args: +seed=7 +pairs=A20Z21,B20Z21,G20Z21 +pair_off=0,12,95 +dur_ms=10000 +idg0_ms=256 +idg0_jit_ms=16 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_wave2x4.log | sim_end=8258ms calls=6 {'NOGO': 2, 'WRONG': 1, 'SILENT': 3} | floods=6 guard_ab=2 no_seize=0 | miscount=2/32 falseclaim=2 regmis=0 latearm=1 reseize=2 C06=0 unwatched=0 nofwd=0 inwatch=2 | seize->arm h1:4.4/7.1/7.1(n10) h2:23.2/36.6/36.7(n6) h3:36.5/50.5/50.6(n6) h4:49.5/63.6/63.7(n6) h5:62.8/77.5/77.6(n6) h6:76.0/90.6/90.7(n6) h7:122.9/123.6/123.6(n2) | margin(all) 80.5/122.0/122.0(n42) | WRONG=1
- 01:57 wave2x4 DONE (2 bursts, 13 s sim, 1671 wall-s, machine load fell to 2):
  burst 2 again: A's gap 120.3, hold at H +122.7, e's break 0.9 ms later -> UNHOLD ->
  re-seized -> E3 B3 -> H claims (6596.3) -> "WRONGRING t=7428 at=H21 caller=A20" (the
  CALL line says SILENT: the caller's 700 ms post-dial window closed before it decoded
  the callee -- a harness classification limit, the ring is the safety event).  So 2 of
  2 A-floods with gaps 120-135 at 7 hops were claimed by H; 2 wrong rings; INVARIANT
  98/98.  Default pools, same dialling (wave2n): lost call.
- RUN wave2x4fix rc=0 wall=915s args: +seed=7 +pairs=A20Z21,B20Z21,G20Z21 +pair_off=0,12,95 +dur_ms=5000 +idg0_ms=256 +idg0_jit_ms=16 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3
  ONELINE run_wave2x4fix.log | sim_end=3345ms calls=3 {'NOGO': 1, 'SILENT': 2} | floods=3 guard_ab=1 no_seize=0 | miscount=0/14 falseclaim=0 regmis=0 latearm=0 reseize=1 C06=0 unwatched=0 nofwd=0 inwatch=1 | seize->arm h1:4.4/6.9/7.1(n5) h2:22.9/34.9/35.2(n3) h3:36.2/48.8/49.1(n3) h4:49.3/61.9/62.2(n3) h5:62.6/75.7/76.1(n3) h6:75.8/88.9/89.2(n3) h7:122.1/122.1/122.1(n1) | margin(all) 82.3/122.0/122.0(n21) | WRONG=0
- 02:12 wave2x4fix DONE (fix on the second shape, 1 burst, 8 s sim, 915 wall-s): the
  re-seizure at H held with "late=1" (615.233) -> no second cell -> A20 SILENT (was
  WRONG); wrongring 0; INVARIANT 98/98.
- 02:13 STUDY CLOSED: queue/STOP set; runner exits.  All results above; the final
  report went to the orchestrator.  Not run: tb_tim3 (tb_load3 SCALE1) -- the 5- and
  8-chains cover it; 9+ exchanges (harness NX <= 8) -- the 8-hop single-event failure
  is arithmetic from the measured hop.
