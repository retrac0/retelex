# C01-watch-late-refusal verification notes
(started 2026-09-26)

## Static check (RTL snapshot)
- mini_marker.v:282 att_refuse = u_att && !att_ack && r_busy && !rd_done && (state != S_WATCH).
- S_WATCH exit (550-552 settled -> r_release, S_IDLE; 542-548 gone/nodig -> r_release, S_DRAIN).
  r_release is a reg; pulse_reg.v:117-118 clears busy on the edge AFTER release_it is seen,
  so on tick T+1 (state IDLE/DRAIN, r_release=1) r_busy is still 1 -> att_refuse true,
  att_take false (!r_busy). CONFIRMED by reading: the waited claim is refused one tick
  before the register frees.
- Refusal (320-327) writes trunk <- 03 BSY CLM. port.v:176-193: only a FALL of fM/fE clears.
  On a trunk whose fM already fell (far caller gone T_REL before), M=0, fm=0; E = M(03)=0,
  so no edge ever again -> BSY+CLM for good; a_rx = e||clm (port.v:153) = 1 backward.
- net_unit.v:666-668: the claiming monitor cell is FREED at w_claim; CL_ACK (674) waits only
  for att_ack; nothing supervises the claimed trunk while att waits.
- A take (att_take branch) writes NOTHING to the trunk: so the stuck state needs the refusal.
  With !r_release gate, a late answer is a take -> no no-edge write (but late attach).
- Real-timer WATCH length: normal = words + SETTLE(32). Extended only if the local caller's
  makes stay < SETTLE (never `steady`) or it goes on-hook inside SETTLE (then WATCH = +CLR 256).
  A conforming dial cannot restart pulsing within ~165 ms of the connect (720 ms min pause),
  so a long pulsing WATCH needs a FAULT (chattering hook/jack). The conforming route to the
  stuck state: claim, far hang-up, local hang-up all inside the ~33 ms WATCH, in that order.
- jobA queued 12:51: tb_c01r snapshot s2,s1,s3 then tb_attw snapshot scen2,scen1
- jobB (RTL_k +fixwatch s2,s3,s1; +fixatt s2,s1) and jobC (rtl_hk hook-gated, rtl_of origin a+a'; s2,s3,s1) queued 12:53
- tb_c01r alignment made event-based (+lag, default 9 ms into WATCH); offs default 1200
- jobA got a slot 13:06

## RESULT r_snap_s2.log (snapshot, REAL timers, conforming double abandon) -- STUCK REPRODUCED
- WATCH 2660..2937; att 2670 (WATCH+10); A20 on-hook 2671; B20 on-hook 2679 (both inside SETTLE).
- B11 releases itself 2928 (A20 + T_REL); A drops A11 2929; WATCH ends on B20's gone 2937 -> S_DRAIN,
  REFUSED same ms: B wr dst 11 src 03 bsy 1 clm 1; 2939 A holds A11 as a phantom seizure (dst 11 src 00 bsy 1).
- 3 s later: B11 03/bsy/clm BUSY, A11 BUSY, A monitor 01 held, A n_nofwd 1. 4 FAILs.
- So a conforming-equipment trigger exists at real timers: claim, far abandon, local abandon, in that
  order, all inside one ~33 ms SETTLE window (margin here 8 ms: B20 after A20). Probability tiny.

## RESULT r_snap_s1.log (snapshot, REAL timers, nobody hangs up) -- watch-exit-refusal CONFIRMED
- WATCH 2660..2692 (32 ms = SETTLE); att 2670; REFUSED 2692 on the WATCH-exit tick (state 0); B11 <- 03 bsy clm.
- A20 hears 03, B22 never connected; all idle 3 s after hang-up (graceful). 2 FAILs (intent checks).

## RESULT r_snap_s3.log (snapshot, REAL timers, FAULT: B20 chatters 4 ms break/12 ms make) -- STUCK
- WATCH 2660..3347; att 2670; A20 on-hook 2671; B11 releases 2928; chatter to 3070, B20 on-hook 3089;
  gone 3347 -> REFUSED -> B11 03/bsy/clm; A holds A11 phantom 3349; 3 s later the same held state.

## RESULT auditor's tb_attw rebuilt on pure snapshot (work/RTL.list), scale 8
- attw_snap_scen2.log: identical to work/audit/cableb/run_attw_scen2.log (REFUSED 725, B11 03/bsy/clm, A11 phantom, A mon 01; 4 FAIL).
- attw_snap_scen1.log: identical to run_attw_scen1.log (REFUSED 593, A20 hears 03; 2 FAIL).
- jobA done; obj dirs removed.
- C02's tb_net on fixwatch (their rtl_fix/mini_marker.v = snapshot minus (state != S_WATCH)): 88/88 PASS (work/verify/C02-queued-claim-late-attach/run_net_fix.log)

## Interim verdicts (before fix runs)
- ONE ROOT CAUSE, two parts, mini_marker.v:282: (1) the wait in S_WATCH is answered on the stale r_busy
  (r_release -> busy lags a tick, pulse_reg.v:117-118), so every waited claim is REFUSED at WATCH exit, never
  taken; (2) the wait is unbounded and unsupervised (unit freed the monitor cell at w_claim, net_unit.v:666-668),
  so the refusal's BSY+CLM write can land on a trunk that released itself (port.v:193: no edge left).
  A take writes nothing to the trunk, so (1) alone fixed also removes the stuck state -- but then a long
  WATCH gives a late attach (C02's hazard). Same defect in rtl/marker.v:273 (class marker).
- watch-exit-refusal: confirmed at real timers; graceful; severity low (auditor: medium).
- att-watch-late-refusal-stuck-clm / late-refusal-no-edge-hold: duplicates; confirmed at real timers both
  with a chatter FAULT and with conforming equipment (double abandon inside SETTLE); permanent, spreads.
  Conforming route needs three events inside ~33 ms -> negligible rate; realistic route is a chattering
  line at the owner (fault) + an abandoning far caller. Severity medium (auditors: high).
- Fix candidates: fixwatch (delete the exemption; C02 tb_net 88/88), origin a+a' (!r_release + 9-bit
  bound CLR/2), hook-gated (!r_release && (state!=S_WATCH || !r_hook): 2 gate inputs, no counter).

## RESULT hook-gated fix (rtl_hk), REAL timers
- r_hk_s2.log (double abandon): REFUSED at 2680 (B20's first break sample), B11 then releases 2928 on its own; 3 s later all idle. PASS 9/9.
- r_hk_s3.log (chatter fault): REFUSED at 2678 (first chatter break after att); clean. PASS 9/9.
- r_hk_s1.log (no abandon): TAKEN at WATCH exit 2692 (32 ms wait), B22 connected to B11 (latch 11). PASS 8/8.

## RESULT origin a+a' (rtl_of = work/audit/origin/rtl_fix/mini_marker.v only), REAL timers
- r_of_s2.log: REFUSED at 2798 (att + 128 = CLR/2), before B11's own release 2928; clean, PASS 9/9.
- r_of_s3.log: same, REFUSED 2798; clean, PASS 9/9.
- r_of_s1.log: TAKEN at WATCH exit 2692, B22 connected. PASS 8/8. jobC done.
- marker.v:273 (class marker) has the identical exemption and lag; top_max has r_hook on the register card but not wired to marker.v (hk fix there needs that ribbon wire).
- jobE (tb_net on rtl_of) queued 15:04; jobB trimmed to fw s2, fw s1, fa s2
- net_of.log: tb_net on rtl_of (origin a+a'): 88 checks 0 errors PASS
- net_hk.log: tb_net on rtl_hk (hook-gated): 88 checks 0 errors PASS, output identical to work/base-net.log. obj removed.
- jobB (fixwatch/fixatt at real timers) cancelled 16:09 after ~1.5 h in the queue: not decisive; fixwatch covered by cableb run_attw_scen{1,2}fixwatch.log (scale 8) and C02 tb_net 88/88. No obj dirs left.
