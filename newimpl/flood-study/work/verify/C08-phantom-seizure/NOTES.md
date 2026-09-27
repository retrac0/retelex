# C08-phantom-seizure verification notes
- started 2026-09-26
- Code read (snapshot): mechanism holds. pulse_rx has no steady-make timeout; cell freed only by
  d_stb mismatch / d_clr (CLR break) / claim (net_unit.v 633-649, 659-665). Resolver freed only by
  R_LEG / R_GONE (681-708) / rs_mine claim. Port B11 held: bsy=1, fM stays 1, E=00's M=0 -> no
  release edge ever (port.v 176-194). baseband link_up watches only clk_in (109); a_tx = a_s2 &&
  link_up (154). Project's own benches (tb_tie/tb_ltu/tb_lnet) model receivers as FAILSAFE-HIGH, so
  an open A conductor alone (clock conductor intact) = M stuck 1 = phantom seizure. Plausible fault.
- The 'A cut off' consequence (A's key always picks A11) is NOT caused by the missing unit timeout:
  B11 stuck-M means B never sees A's seizure edge on 11, hold or no hold. Killer-trunk / hunt issue.
- Fix design note: a resolver timeout on a ONE-LEG forward (rs_two) must re-point the incoming
  (B11, which was patched to listen to B14) back to 00 with the hold, else stale B11->B14 patch leaks
  C's later seizure on B14 back to A11 as a phantom.
- Fix copy: rtl_fix/net_unit.v (RTL_fix.list): 2-bit age per cell and resolver, shared strobe every
  T_KEY (tick_1k count); expire at age 3 = (2,3] x T_KEY = 10-15 s real, 1.25-1.875 s scale 8.
  Cell: frees, hold stays (port parked). Resolver: new rs_act R_AGE: drop every leg; if one-leg (rs_two)
  also rewrite incoming -> 00 held (bsy 1).  Legit max resolver life ~ T_KEY+T_CLAIM+T_REL = 7.3 s.
- rtl_naive/: same without the incoming re-hold (auditor's fix (b) literally) -> expect stale B11->B14.
- Bench: tb_c08.v = tb_pchain sc1 with wait to 3.0 s, parked/leak checks, pool change timestamps.
- Queued (sim.sh): base tb_pchain +sc=2 (run_base_sc2.log); job_fix (c08_fix, c08_base);
  job_reg (net_fix, chain_fix); job_naive (c08_naive).
- tb_net on rtl_fix: 88/88 PASS, output identical to base-net.log (run_net_fix.log)
- tb_chain on rtl_fix: 32/32 PASS (run_chain_fix.log)
- Slots all held by long work/load runners (3-4 h). Killed my own queued (not running) wrappers for
  job_fix/job_naive/job_lt (outer timeouts would expire in the queue) to requeue as one job_all.sh;
  the requeue was DENIED by the permission classifier ("Interfere With Workloads"). Not requeued.
  So c08_fix / c08_naive / lt_base / c08_base did NOT run. Still queued: base tb_pchain +sc=2.
- Waited ~4 h: base tb_pchain +sc=2 never got a sim.sh slot (slots held by work/load runners and
  other verify jobs). Finalising on code reading + auditor log + fix regression (tb_net, tb_chain).
- Verdict: core CONFIRMED (code, every cited line). Two root causes: (1) no permanent-signal timeout on
  cells/resolvers; (2) near-end hunt re-picks a dead channel (killer trunk) -- not fixed by (a)-(c).
  Auditor's fix (b) incomplete for one-leg forwards: must re-hold incoming on 00 (rtl_fix does).
