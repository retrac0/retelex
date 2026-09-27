# C02 queued-claim-late-attach -- verification notes
(started 2026-09-26)

## Setup
- knob copies work/audit/cableb/{net_unit_k,mini_marker_k}.v == snapshot with plusargs off (diffed).
- fix copy: rtl_fix/mini_marker.v = snapshot minus `(state != S_WATCH)` in att_refuse (fixwatch as a real edit); RTL_fix.list.

## RTL reading (snapshot)
- net_unit.v:487 w_claim needs cl_st==CL_IDLE; 673-674 CL_ACK waits att_ack with no bound. A cell at M_DONE (640-642)
  keeps m_held/m_armed and still clears on d_clr (646-648) but ignores digits; freed at w_claim (665-668).
- mini_marker.v:273-274 att_take only IDLE/TAKE/DRAIN & !r_busy; :282 att_refuse excludes S_WATCH. Only S_WATCH (unbounded,
  to NODIG) and S_READ with r_busy=0 (<= a read, ~2 ms) delay an answer.
- WATCH exit (538-553): r_release + IDLE/DRAIN; pulse_reg busy drops one edge later, so att_refuse fires on the stale
  r_busy (C01): in the SNAPSHOT a single claim that waited in WATCH is always REFUSED, never late-attached. The late
  attach needs a SECOND claim queued behind cl_st (finding 1), or C01's +fixatt fix (then claim 1 itself).
- WATCH length with conforming lines (real timers): settled = steady (make >= SETTLE=32) && nd_t >= 32 from the connect
  words -> ~33 ms; caller abandons inside SETTLE -> CLR 256 -> <= ~290 ms; a hook flash then off-hook -> flash + 32.
  Only makes < 32 ms with breaks < 256 ms sustained (a fault) holds it to NODIG 10 s.
- Far side: claim-want = b's last make + ID(128); h's first break >= 720 ms pause after b -> >= ~590 ms margin
  (network.md 4.2 states exactly this). WATCH <= ~290-320 ms conforming -> no late attach without a fault.
- Spec: new exchange/marker.md 4.8 and 5 say "a claim waits out a watch" -- fixwatch contradicts the spec text.
- Same exemption in the class marker: rtl/marker.v:273 (att_take 271-272 IDLE/DRAIN). Any fix must cover both.

## Sims launched (2026-09-26)
- obj_att2_snap: tb_att2 on work/RTL.list (snapshot), +dstop=8 -> run_att2_snap_dstop8.log
- obj_att2_fix: tb_att2 on RTL_fix.list, +dstop=8 -> run_att2_fix_dstop8.log
- obj_net_fix: tb_net on RTL_fix.list -> run_net_fix.log (base: work/base-net.log)
- obj_att2r: tb_att2r.v (tb_att2 at REAL timers, 60/40, 800 ms pauses, dstop 64, chatter fault unchanged) on snapshot
  -> run_att2r_snap.log
- tb_net on RTL_fix: 88 checks, 0 errors, PASS (run_net_fix.log); output identical to work/base-net.log bar wall time. obj deleted.
- REAL TIMERS, snapshot (run_att2r_snap.log): reproduces. Chatter holds WATCH 1319->~8960 ms (7.6 s < NODIG 10 s).
  Claim 1 att 3689 ms waits; claim 2 wanted 8195 ms (131 ms after b's last make); A21's h at 8863 (800 ms pause);
  chatter stopped at h+64, settled +32 -> 8959: claim 1 REFUSED (stale r_busy, C01), claim 2 TAKEN, register attaches
  96 ms into h (first pulse's make) -> counts 2, 2 -> B22 rings, B32 does not. 6 checks 2 errors (the two ring checks).
  obj deleted.
- scale 8, snapshot RTL (not the knob copy): run_att2_snap_dstop8.log IDENTICAL to audit/cableb/run_att2_dstop8.log (bar wall time). Wrong number B22 reproduced. obj deleted.
- scale 8, RTL_fix (clean deletion): run_att2_fix_dstop8.log IDENTICAL to audit/cableb/run_att2_dstop8fixwatch.log:
  claim 1 refused at 569 ms (in WATCH, trunk up), claim 2 refused at 1206 ms, B22 does NOT ring. The two FAILs are
  the scenario's own expectations ("queued", "B32 rings") which the fix replaces with cannot-complete. obj deleted.

## Verdicts
- F1 queued-claim-late-attach-wrong-number: confirmed-overstated. Mechanism exact; reproduces at scale 8 and at REAL
  timers, but only with a faulted local line (makes < SETTLE 32 ms, breaks < CLR, from within ~33 ms of a connect,
  for > ~0.6 s). Conforming WATCH <= ~290-320 ms < ~590 ms margin. In a 2-site net the two claims come from one origin
  register, so claim 2 behind claim 1 needs a WATCH of seconds: fault only. Severity low (wrong number, fault-only).
- F2 claim-attach-unbounded-in-watch: confirmed-overstated. Unbounded wait is real; but in the snapshot a lone waiting
  claim is REFUSED at WATCH end (stale r_busy, C01), never attached; mid-h attach needs F1's queued claim or C01's
  +fixatt. Severity low.
- One root cause: the S_WATCH exemption in att_refuse (mini_marker.v:282; same at marker.v:273) with no bound on att.
- Fix: delete `(state != S_WATCH)` (both markers) + doc edits (marker.md 4.8/5, network.md 3.6). tb_net 88/88 identical.
