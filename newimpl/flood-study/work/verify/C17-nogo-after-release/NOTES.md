# C17-nogo-after-release verify notes

- started 2026-09-26; reading cluster JSON (1 finding: nogo-write-after-caller-release, audit origin)
- evidence log work/audit/origin/run_fix_s6.log (fixed RTL, scen S6): A20 left BUSY at end; the nogo wr dst 20 src 03 at 428.578 after mk 6->3 at 428.161

## Code reading (snapshot)
- port.v:176-194: fM falls on the T_REL-th tick after m=0 (m = a_tx direct); rel then clears addr/bsy/clm.
- pulse_reg/pulse_rx: m via probe (published at the end of the port's bit-time, 1/pass); pulse_rx clear fires on the
  CLR-th tick after the tick that first sees the changed sample, gone one clk after. With CLR == T_REL (top_net 256/256,
  benches 32/32) r_gone rises 1 tick (hang-up before the port's sample in the pass) or 2 ticks after the port's rel.
- mini_marker S_YIELD (515-523): u_nogo|y_nogo|r_nodig -> caller<-NOGO bsy=1; guarded only by r_gone (checked first).
  S_COLLECT (404-410): r_nodig -> caller<-NOGO bsy=1, same guard. Nothing else checks the hook.
- net_unit N_WAITCL :882 T_CLAIM, N_NET :876 T_KEY: checked after o_gone (=r_gone|r_nodig|!r_busy), which lags too.
- "8 or 9 in the code" (isvc at dig_stb) NOT a trigger: a digit completes on a make of ID, caller off-hook; port cannot
  have released. Only timer-driven nogos (T_KEY, T_CLAIM, register NODIG) can coincide with a hang-up.
- Tone source 03 has M=0 (site_net), so a port latched to 03 has no E edge either: stuck until its own M rises+falls.
- WIDER than the cluster says: S_COLLECT's r_nodig branch is the same race with NO network unit (top_min too): lift, no
  digits, hang up ~NODIG-CLR (real 9.744 s) after the register attached.

## Sims (queued through sim.sh)
- run1.sh: auditor's tb_orig (traced copy tb_orig_c17.v) scen 32 on work/audit/origin/RTL_fix.list -> run_orig_s6.log
- tb_c17.v (mine, tb_orig harness): mode 1 = T_CLAIM sweep (A20 dials 1 3 3, hang-up X ms after f2), mode 2 = NODIG
  sweep in S_COLLECT (A21 lifts, no digits, hang-up X ms after attach). Built on snapshot as obj_snap.
- Prediction (scale 8, T_REL=CLR=32): T stuck for X in ~(217.25, 219) ms; N stuck for X in ~[1216.7, 1218.7) ms.
- rtl_fixB/mini_marker.v: FIX B = gate the S_COLLECT r_nodig and S_YIELD nogo BSY writes on r_hook (wait while on-hook).

## Real hardware: the port's T_REL is an RC, not a count
- port.v:29-35 "THESE ARE RC NETWORKS"; old marker.md s8 (exchange-docs/marker.md:297) "The model gives each a fixed time
  drawn +-20 %" and s7 table "breaks <= 103 ms against a release >= 204 ms". CLR is a '4040 tap on the crystal tick:
  exact 256. So on real boards T_REL(port) is 204..307 ms per port while CLR = 256: for a port whose RC is short by D ms
  the window is D + 1..2 ms, not 1..2 ms. RTL equality (256/256) is the BEST case. -> finding UNDERSTATED on window size.
- Consequence for fix A (CLR shorter than T_REL): margin must exceed the RC's worst-case short (~52 ms) -> CLR ~192;
  then breaks in [CLR, T_REL) are 'gone' to the register but not to the port (hookflash-length breaks) -> new
  hazards (WATCH: called freed while the caller stays latched to it = listen-in once reused). Fix B (hook gate) is
  independent of the timer ratio.
- sim.sh queue is very long (29 procs, C12 jobs with 10 h timeouts); my build + reproducer waiting since ~22:40.
- 22:5x: killed my own still-waiting build (never had a slot); queued combined jobs jobS.sh (snapshot T+N sweeps),
  jobF.sh (fix B sweeps + tb_net on fix B), jobR.sh (snapshot, TREL_FIX=26 i.e. port RC 20 % short, T sweep 1 ms steps).
  run1.sh (auditor S6 rerun) still queued; added A11/B11 traces to tb_orig_c17.v before it started.
- Predicted T window with T_REL=26, CLR=32: X in ~(217.25, 225) ms (vs (217.25, 219) at 32/32).

## RESULT jobR (snapshot RTL, bench T_REL 26 vs CLR 32 = port RC 19 % short; T sweep 1 ms steps) -- rc26_T.log
- STUCK for X = 217.5 .. 224.5 (8 of 12), free at 215.5, 216.5, 225.5, 226.5: exactly the predicted (217.25, 225).
- each stuck case: rel at X+25.5, unit nogo at +250.000 with r_gone 0, wr dst 20 src 03 bsy 1 at +250.417 AFTER rel;
  port left latch 03 bsy 1; 2 CLR later still busy; lifted -> still busy, latch 03, register NOT attached (not a
  caller); hung up -> free.  At X=216.5 gone rose 1 us before the nogo -> silence path (marker checks r_gone first).
- window = (CLR - T_REL) + ~1.75 ms. In hardware T_REL is an RC (204..307 ms per old marker.md) vs CLR exact 256.
- walltime 348 s for 11 s sim (32 ms/s).

## RESULT jobF part 1: FIX B (rtl_fixB/mini_marker.v, hook-gated nogo/nodig writes), equal timers -- fixB_TN.log
- 0 stuck of 16 (T 215.5..219.0, N 1216.0..1219.5, 0.5 ms steps); idle-bad 0, clash 0, ovf 0.
- e.g. X=217.5: rel +248.999, unit nogo +250.000 (r_gone 0), gone +250.999, then wr dst 20 src 00 bsy 0 (deferred, then
  the silence path). N X=1216.0: nodig +1249.715 ONE CLK before gone +1249.716 (would be stuck on the snapshot).
- measured gone lag after the port's REL at equal timers: 1 or 2 ms (not 0-1 as the auditor wrote).
- tb_net on fix B: running next in jobF.
- tb_net on FIX B: 88 checks, 0 errors, PASS (fixB_tbnet.log; snapshot base-net.log also 88/88). Scenario 7 (guard
  abandon mid-break) passes: the NOGO is deferred to the make and the caller still hears cannot-complete.
- 00:32 run1 (auditor S6 rerun, traced) got a slot. jobS (snapshot sweeps) and jobReal still queued.

## RESULT run1: auditor's S6 on the CURRENT work/audit/origin/RTL_fix.list (traced) -- run_orig_s6.log
- DOES NOT REPRODUCE: PASS, 0 errors, A20 free. rtl_fix/*.v mtime 02:08:59 is AFTER run_fix_s6.log (02:07:07): the
  auditor's evidence came from an intermediate fix (one-sample claim loss, no a' refusal); the current copy has the
  4-sample debounce ("so that a caller who hung up ... is seen as gone first"), added in response. run_fix2.log (02:46)
  S6 passes too. So the evidence log is an artefact of a superseded audit fix, not of the snapshot.
- Traced timing (equal timers): A20 hangs up ~396.2; A20 port REL 427.004; B11 REL + clm->0 428.004; A11 backward A
  -> 0 at 428.035; A r_gone 429.004. A one-sample loss detector sees A11 low at ~428.16 -> nogo inside the
  (427.004, 429.004) window -> the auditor's stuck A20. With 4 samples it lands after gone.
- In hardware (RC spread) a short-RC B11 + short-RC A20 moves the loss earlier than gone again: queued jobO2 to test
  the current audit fix with T_REL 26 both sites, and the same with FIX B added.

## RESULT jobO2: auditor S6, every port T_REL 26 vs CLR 32 (tb_orig_c17r.v) -- run_o2_fix.log, run_o2_fixcB.log
- CURRENT audit fix (RTL_fix.list, 4-sample claim loss): FAIL, A20 STUCK (busy_a bit 16). A20 REL 421.004, B11 REL
  422.004, A11 backward A -> 0 422.035, 4 samples -> unit nogo 425.161, wr dst 20 src 03 bsy 1 at 425.579, r_gone only
  at 429.004. So the correlated trigger comes back as soon as the RCs run short: deterministic for every caller who
  hangs up with a claim pending before N_DONE, not 1 in 1000. (Cross-cluster: any claim-loss -> nogo fix.)
- audit fix + FIX B (RTL_fixcB.list): PASS; nogo at 425.161 deferred (A20 on-hook), r_gone 429.004, wr dst 20 src 00
  bsy 0 at 429.132, A20 free.

## RESULT jobS part 1: SNAPSHOT, equal timers (T_REL = CLR = 32), T_CLAIM sweep -- snap_T.log
- STUCK at X = 217.5, 218.0, 218.5 (3 of 10, 0.5 ms steps 215.5..220.0) = predicted (217.25, 219): window ~1.75 ms.
- each: rel +248.999/+249.999, unit nogo +250.000 with r_gone 0, wr dst 20 src 03 bsy 1 at +250.417 (after rel);
  lift -> still busy, latch 03, not taken as a caller; hang up -> free.  Same RTL with FIX B: all free (fixB_TN.log).

## RESULT jobS part 2: SNAPSHOT, equal timers, NODIG in S_COLLECT (no unit involved) -- snap_N.log
- STUCK at X = 1216.0 .. 1218.5 (6 of 8), free at 1219.0, 1219.5. Window ~3 ms (lower edge below my sweep start;
  computed ~1215.7). Wider than T_CLAIM's because r_nodig rises one clk BEFORE r_gone when both fall on the same tick
  (X=1216.0: nodig +1249.715, gone +1249.716, marker already in S_DRAIN with wr dst 21 src 03 bsy 1).
- So the race is not network-only: mini_marker S_COLLECT r_nodig branch (:404-410) on top_min as well. Real: a caller
  who takes dial tone, dials nothing (or a partial number) and hangs up ~9.744 s later.
- jobReal (real timers) still queued.

## RESULT jobReal: SNAPSHOT at REAL timers (T_REL = CLR = 256, T_CLAIM 2000, 10 pps 60/40, 720 ms pauses) -- real_T.log
- STUCK at X = 1743.5 and 1744.5 ms after b; free at 1742.5 and 1745.5 = predicted (1743.25, 1745), ~1.75 ms.
- stuck: rel +1998.995/+1999.995, unit nogo +1999.995 (r_gone 0), wr dst 20 src 03 bsy 1 at +2000.413; lift: still
  busy, latch 03, not taken; hang up: free. At 1742.5 gone rose one clk before the nogo -> silence path, free.
- walltime 675 s. All obj dirs removed.

## VERDICT (final)
- nogo-write-after-caller-release: CONFIRMED-UNDERSTATED, medium. Mechanism right; auditor's evidence log is from a
  superseded audit fix (does not reproduce on the current copy), but the snapshot reproduces independently at scale 8
  (T_CLAIM 3/10) and at REAL timers (2/4, window 1743.25..1745 ms after b). Understated: NODIG in S_COLLECT (no unit,
  top_min too) is the same hole with a ~3 ms window; RC spread widens every window to (CLR - T_REL_rc) + ~1.75 ms;
  the audit's claim-loss->nogo fix makes it deterministic once RCs run short. Overstated detail: "8 or 9" is no trigger;
  gone lag is 1-2 ms not 0-1.
- One root cause. Best fix: FIX B (hook-gated BSY writes), tested: 0/16 stuck, tb_net 88/88, S6-RC-short PASS.
