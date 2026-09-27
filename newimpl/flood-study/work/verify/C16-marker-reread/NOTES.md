# C16-marker-reread -- verification notes

## Code reading (snapshot rtl/)
- mini_marker.v:337-354 S_IDLE: any p_fresh && M && !BUSY && !r_busy && bus_idle with /NET -> S_READ (no per-port memory).
- mini_marker.v:358-365 S_READ: trunk word (or word 0) -> S_IDLE. Nothing remembered. Confirmed.
- word_rx.v: request lands, select waits for scan==at && win==0; 8 frames collect; done at a_stb of frame T+8.
  => marker in S_READ from edge T->T+1 (pass k) until mid-frame T+8 (pass k+1); back in S_IDLE in time for
     T+8's fresh (published at edge T+8->T+9). Blind ports: T+1..T+7 (7, not 8). Re-read every 2 passes.
- net_unit.v:277 st[] prevents the UNIT re-reading; the marker has no equivalent.
- Window length (reasoning, port.v:147,153): at the terminating exchange B, B21 hangs up first -> B11 keeps
  backward A up through CLAIM (a_rx = e||clm) until its fE falls (T_REL) and the latch clears; then B11 is
  M.!BUSY until A11's fM falls (another T_REL) and A11 clears, dropping forward A: window ~T_REL + link.
  Caller-hangs-up-first gives the origin trunk M.!BUSY only for ~2x link delay (no CLAIM on the origin side).
- Finding 1's fix "share the unit's st" is WRONG as stated: st is set for LINES too (cls_seen, net_unit.v:283,570),
  so a line that lifted while the register was busy would be skipped by the marker until it hung up.
- Sweep interaction (word_rx.v select rule): during a running sweep win==0 only at the sweep's own select
  frame, so the marker's select can only coincide with the sweep's (both read the same port) -> the marker
  WAITS on the sweep, not vice versa; the sweep loses a pass only when the marker's select lands in a sweep gap.
- Fixed copy: rtl_fix/mini_marker.v (fix.patch): tk[p] set by a caller-candidate read that says trunk,
  cleared by any M-low sample; S_IDLE skips tk ports.  RTL_fix.list.
- Bench: tb_c16.v (tb_net's two exchanges, scenario 2; +case=0/1/2; -DREAL)

## Auditor evidence (monclaim logs, not re-run yet)
- run_real13_all.log burst (line 164+): mk alternates 4/0 every ms while cls=3 (C_HOLD) takes T11..T15
  one per ~19 ms (holds at 16906, 16925, 16944, 16963): the marker re-reads the waiting trunks. CONFIRMED as described.
- Sweep durations (fwd 2 -> 3/0) at REAL: 11 ms everywhere, including 16906->16917 and 16925->16936 while the
  marker re-read (mk=4 lines) -- NO sweep stretch at real timers.  At scale 8 the burst sweeps are 15 ms vs 11 idle;
  at scale 8 C_HOLD is only ~3 ms so the classifier interleaves reads into the sweep; to separate: fixed-marker run.
- Classifier spacing at real: 19 ms = T_ARM+1 hold + ~1 ms read; no visible marker-induced pass.
- Side note: debugger.v REG_WAIT (M.!BUSY 16 passes) would also light for an unheld trunk in the T_REL window
  (independent of the marker; not in this cluster).
- Jobs queued (5 slots, ~35 waiters): jobS (snapshot s8 c1/c2, tb_mc sc2, REAL c1), jobF (same on fix), jobN (tb_net on fix).

## RESULT run_s8_c1.log (snapshot, scale 8, B20 = B11+7)
- control dial-tone delay B20 2.27 ms, B21 2.28 ms
- B11 BUSY fell 32.00 ms (T_REL) after B21 hung up; then M.!BUSY 32.01 ms (T_REL) -- window = T_REL, as reasoned
- B20 lifted 2 ms into window: dial-tone delay 32.27 ms (blind for the rest of the window)
- B marker reads of B11 in window: 16 (one per 2 ms); B unit reads: 0 (st works); S_READ ~55% of window
- run_s8_c2.log: B21 (B11+8) lifted in window: 31.28 ms -- CONFOUNDED: B21 was the called port; after its
  release its fE (it listened to B11, whose M stands) holds BUSY for T_REL.  Not marker blindness.
  Added case 3 (B20 called with s=0, B21 lifts) -> jobX.

## RESULT run_f8_c1.log (FIX, scale 8, B20 = B11+7)
- B20 dial-tone delay 2.27 ms (= control); B marker reads of B11 in window: 1; S_READ 2.7% (vs 21.8%)
- run_f8_c2.log (fix): B21 still 31.28 ms, B11 read once -> confirms case 2's delay is B21's own fE, not the marker.

## RESULT burst reproducer tb_mc +sc=2, scale 8 (run_mc_sc2.log snapshot vs run_fmc_sc2.log fix), both PASS 8/8
- BUSY after rise T11..T15: snapshot 2/7/12/17/23 ms; fix 2/7/12/17/22 ms (marker costs the 5th one pass)
- forward sweeps (fwd 2->3): snapshot 15, 15 ms; fix 15, 13 ms (idle sweep 11 ms).  The 11->15 is the
  classifier's interleaving at scale-8 C_HOLD (~3 ms); the marker's share is 0-2 ms on one sweep.
- At REAL (auditor's run_real13_all.log) sweeps during the re-reads are 11 ms = idle: no stretch.

## RESULT REAL timers, case 1 (run_sr_c1.log snapshot, run_fr_c1.log fix), both PASS 8/8
- (print bug in these logs: "fell 17.00 ms after the called B400" = cp and time swapped: read "256 ms after B21 (o21=17)")
- B11 BUSY fell 256 ms (T_REL) after B21 hung up; M.!BUSY window 256.01 ms
- snapshot: B20 (B11+7) dial-tone delay 256.27 ms vs control 2.27; marker read B11 128 times; unit 0
- fix: B20 2.27 ms; marker read B11 once
- Added case 4: FAULT -- B->A A conductor of link 11 stuck at 1; caller A20 hangs up first -> A11 releases on fE
  and stays M.!BUSY at A for as long as the fault lasts; A20 (A11+7) and A21 (A11+8, uninvolved: clean T+8 test)
  lift afterwards.  jobX = case 3 + case 4, snapshot and fix (nohup, sim.sh).

## RESULT case 3 snapshot (run_s8_c3.log), PASS 8/8
- B20 called and hung up first; B21 (B11+8) lifted 2 ms into the 32 ms window: dial tone in 3.28 ms (control 2.28)
  -> B11+8 is NOT blind.  Blind zone is B11+1..B11+7 (seven ports), as computed from word_rx timing.
- only 2 re-reads of B11: once B21 holds the register (r_busy) the marker stops reading anything.

## RESULT case 4 snapshot (run_s8_c4.log), PASS 7/7 (the bench's checks; the numbers are the finding)
- FAULT: B->A A of link 11 stuck at 1, caller A20 hangs up first: A11 releases (fE) and is M.!BUSY at A for as
  long as the fault lasts.  A20 (A11+7): NO dial tone within 1000 ms; A21 (A11+8): 3.28 ms.  651 marker reads of A11.
  -> "would last for ever" is REACHABLE with one plausible fault (stuck-at-1 backward A with the link clock alive,
     or a far port wedged BUSY+CLAIM): seven innocent local lines lose dial tone until the far fault clears.
- FIX case 4 (run_f8_c4.log) PASS: A20 2.27 ms, A21 2.28 ms, 0 reads of A11 in the window (read once before it).
- FIX case 3 (run_f8_c3.log) PASS: B21 2.28 ms, B11 read once.
- pending: tb_net on the fixed marker (jobN).

## RESULT tb_net on the fixed marker (run_fix_tbnet.log)
  88 checks, 0 errors.  PASS
(tb_net 88/88 on the fix = base-net.log 88/88.)

## VERDICT
One root cause (mini_marker.v:337-345 + :365: no per-port memory of a trunk read).  Both findings confirmed,
numbers overstated (7 blind ports not 8; window T_REL=256 ms not ~0.5 s; no sweep stretch at real timers),
the "for ever" case reachable only with a fault (stuck backward A) -- then 7 lines dead for the fault's duration.
Fix: rtl_fix/mini_marker.v (tk bit, set on trunk read, cleared by M low) -- tested; "share the unit's st" is wrong.
