# C04 hold-watch-dial-break -- verification notes

- started: read cluster json; reproducer work/audit/cableb/tb_brk.v, log run_brk.log (plain RTL claimed)
- RTL read: mechanism holds at snapshot lines: C_HOLD 584-588 unholds on ANY M-low sample (no discrimination
  break vs death); st cleared on any M-low sample 566-567; unhold writes bsy=0; port.v:147 BUSY=bsy|fe|(fm&!m)
  so at the make BUSY=0, M=1 -> cls_seen 283-284 -> second hold, second cell (first cell NOT released by unhold).
- net_unit_k.v (auditor's knob copy) differs only in +fixfc, off by default: tb_brk log = snapshot behaviour.
- re-running tb_brk on snapshot (run_brk_snap.log) and on my C_LOW fix copy fix/net_unit.v (run_brk_fix.log)
- fix: C_HOLD M-low -> C_LOW (write nothing); M up -> back to C_HOLD, watch restarts from the make;
  M low >= CLR (default; +lowid = ID) -> C_UNHOLD.
- related: work/audit/cls/fix/net_unit.v (another auditor) already moves the watch to 4 watchers with a CLR
  low-streak test + st kept on M-low-under-BUSY: bigger fix, same idea.
- queued (sim.sh, all 5 slots busy with other agents at queue time): brk_snap, brk_fix, brkrt_snap
  (tb_brk_rt.v: REAL timers, guard lowered to 16 ms so hop C sits at its edge; offsets 2,10,17,26,60),
  net_fix, chain_fix.
- arithmetic (real timers): hold = rise + 2..3.5 ms; watch = T_ARM+2 = 18 ms more. network.md 6 budgets the
  guard to "the last exchange's monitor attaching" only -- misses this 18 ms. 128 tap: ~10 typical hops
  documented -> ~8-9 once the watch counted. Trigger needs first break in [hold, hold+18] at a hop inside
  the reach: first break <= guard+18 after seizure => key1->e pause ~267-285 ms at 128 tap (651-669 at 512):
  NON-conforming (ES 201 187 >= 720 ms). Conforming dial: first break >= ~580 ms after seizure; exposed
  hop would hold at 562-578 ms = ~45 typical hops / ~20 slow -- beyond any tap <= 512's documented reach.
- tb_brk_rt offsets at real T_ARM: C holds ~A-tmr 17, watch to ~36; break reaches C ~tmr 17+off.
  off 2,10 inside watch (port fM not yet up), off 17 inside (fM up), off 26 and 60 outside = controls.
- also queued: tb_brk on work/audit/cls/RTL_fix.list (does the cls auditor's watcher fix close C04 too?)
- RTL reading (not run): at a MID-path exposed hop the unhold also kills the first forward: F_WANT/F_HUNT by
  f_cancel (net_unit.v:594/714/722), or, if already written, the resolver sees rs_in with BUSY clear
  (688-689: R_GONE) at the make and drops every leg; the re-classification then re-forwards after pulse 1
  (if the forwarder is idle) = a late flood downstream, or none. Victim set unchanged (downstream hops hold
  later still, so they are in the band or past the guard anyway), but the consequence there can be a lost call
  as well as a wrong number.
- tb_net on fix/net_unit.v (C_LOW, CLR): 88 checks, 0 errors PASS (run_net_fix.log); scenario 7 (death inside the watch) still cleared
- tb_brk on fix/net_unit.v: 7 checks 0 errors PASS; wrong-number 0 of 5, C unholds 0, C monitor cells 5 (run_brk_fix.log)
- tb_chain on fix: 32 checks 0 errors PASS (run_chain_fix.log; base-chain same count)
- tb_brk on work/audit/cls/RTL_fix.list (watchers + CLR low streak): 7/7 PASS, see run_brk_clsfix.log
- REAL-TIMER run (tb_brk_rt, snapshot, run_brkrt_snap.log): FAIL 1 -- wrong number 2 of 5.
  off 2: C HOLD tmr17, B UNHOLD + C UNHOLD at tmr 19-20, C re-HOLD tmr 94 (B also unheld: its resolver
  dropped the leg to C and B re-flooded after pulse 1), cell1 counts 2 then 4 -> C CLAIMS, C21 rings.
  off 10: C UNHOLD tmr 28, re-HOLD tmr 89 (make), cell0 counts 3 (right), cell1 counts 2, 4 -> CLAIMS, rings.
  off 17 (break reaches C ~tmr 35, the watch's end), 26, 60: clean.  Band at C ~16-17 ms wide = T_ARM+2
  less ~2 ms propagation.  Confirms the mid-path mode too: B, in its own watch, dropped its legs and
  re-forwarded late.
- brk_snap (the auditor's scaled tb_brk re-run on plain snapshot) and brkrt_fix (real-timer bench on the fix)
  sat queued ~3.5 h behind long load sims and were withdrawn un-run (killed while waiting; no slot held).
  The snapshot failure is reproduced by tb_brk_rt instead (same bench, real timers); net_unit_k.v is the
  snapshot with its only knob off, so run_brk.log stands for the snapshot.
