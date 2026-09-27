# C17 skeptic review (mechanism + realism)

Started 2026-09-27. Read-only review; verifier dir ../C17-nogo-after-release.

## Code re-derivation (snapshot), 1st pass
- port.v:176-193: rel on the T_REL-th tick after the hang-up (first tick after h counts 1); busy = bsy|fe|(fm&!m)|mute.
  After rel with a later wr (addr 03, bsy 1): fm=0, fe=0 (03 M=0) -> BUSY, no edge. Confirmed.
- pulse_rx: t<=0 on the tick that first sees the new sample; clear on the CLR-th tick after; gone +1 clk.
  Probe sample is at the port's bit-time in the pass: hang-up before it -> change tick = P1 -> gone at P(CLR+1);
  after it -> P2 -> gone at P(CLR+2). So gone lags rel by 1 or 2 ticks (+2 clk). Verifier right, auditor's 0-1 wrong.
- mini_marker BSY writes to the caller that are TIMER-driven: S_COLLECT r_nodig (404-410), S_YIELD u_nogo|y_nogo|r_nodig
  (515-523), S_WATCH r_nodig (542-548, needs 10 s of chatter). Digit-driven NOGOs (d0==0, svc1, key refused, trunk
  dialled, PROBE busy) all fire within a few ms of a completed digit = caller off-hook: not triggers. Agree.
- net_unit nogo sources: T_KEY :876 (tmr from N_SEIZE, not from the key), T_CLAIM :882, isvc :865/868 (digit-driven, not
  a trigger), guard :862 (fires at HIT into a break, word lands long before any T_REL: not a trigger), no-trunk :855
  (within ~10 ms of key: not a trigger). N_DROP/N_END do not recheck o_gone; marker checks r_gone first. Agree.
- Verifier's logs re-read: snap_T 3/10, snap_N 6/8, rc26_T 8/12, real_T 2/4 stuck, fixB_TN 0/16, fixB tb_net 88/88.
  They say what the verdict says. real_T X=1744.5: rel and nogo on the same tick -> stuck; 1745.5 word lands before rel.
- FIX B diff checked: only the two `room && r_hook` gates (+ _unused edit). Covers S_COLLECT nodig for ctx_clm too.

## SECOND PATH the verifier did not follow: far-end claimed trunk (ctx_clm) -> stuck CLAIM, C01's consequence
- At the far exchange a claimed trunk is the register's caller in S_COLLECT; its NODIG write is
  ent(caller, NOGO, BSY=1, CLM=ctx_clm=1) (mini_marker.v:404-410). The trunk port's M is the origin caller's
  hook relayed live (A11 a_rx = e_cap of A20, <=1 ms; baseband A crosses in ~2 frames, baseband_card.v:140-154).
  So the far trunk port releases T_REL after the origin caller hangs up (+~1 ms + link), and far `gone` lags
  that by 1-2 ms exactly as at a line. Same race, same window.
- But the consequence is NOT "busy until next lifted": latch 03 + CLM on the trunk -> port.v:153 a_rx = e|clm = 1
  for good = backward A stuck high. Nobody ever lifts a trunk. The dip between the far rel and the stuck write
  (0.13..2.1 ms) crosses the link; A's unit probe (1/ms) sees it with p ~ dip/1 ms -> st cleared -> A11 shows M
  with BUSY clear -> cls_seen -> A holds A11 as a PHANTOM seizure, monitor held for good, forwarded onward
  (C01 late-refusal-no-edge-hold, confirmed by the C01 verifier: attw_snap_scen2.log). If the dip is missed,
  A11 sits M=1/BUSY=0/st=1: channel dead both ends, and the mini marker re-reads A11 every other pass,
  blinding it to the 8 ports after A11 (known finding in clusters.json).
- FIX B's r_hook gate covers this form too (same S_COLLECT branch). The att_refuse write (C01) is not covered.
- 02:06 queued job.sh (tb_c17f far-end form, 8 points f=0..3.5 ms) via sim.sh -> far.log
- Auditor evidence: run_fix_s6.log 02:07:07 < rtl_fix/*.v 02:08:59; run_fix2.log S6 PASS. Verifier right: the
  auditor's log is from a superseded fix, not evidence about the snapshot.
- Old docs: marker.md 5.1/8 model detectors +-20 % about 256 and say a real RC into a Schmitt '14 has threshold
  tolerance ON TOP (74HC14 VT- spread alone is roughly 2:1 in ln(Vcc/VT-)); fabric.md:229 RC+'14. CLR is a '4040
  tap: exact. So the per-port window D + 1.75..3 ms with D = CLR - T_REL(port) > 0 for every short-RC port is right,
  and D can plausibly exceed the verifier's 52 ms for an untrimmed RC.
- FIX B reasoning: harmful only if the BSY word lands after rel; rel needs T_REL ticks of M low; r_hook=1 means M was
  high at a probe sample <=1 ms ago; line-card M is filtered (ms), trunk M is a 1 kHz sample-and-hold of the far
  hook, so an M high the probe saw was also seen by some port tick -> cm reset -> no rel for ~T_REL. Holds for any
  RC spread. Residual: re-lift inside [rel, gone) with a make < T_ARM -- negligible (bounce is at hang-up start).
  Deferral always ends: on-hook -> gone at CLR (silence path); make -> word lands off-hook (cannot-complete as
  designed). Not covered: S_WATCH r_nodig (needs 10 s of chatter; optional same gate) and att_refuse (C01).
- The digit-driven NOGOs and the unit's N_DONE (o_last is digit-driven; a claim arrives tens of ms after b at most,
  and a hang-up >= T_REL before it would have corrupted b) are not triggers: agree with the verifier.
- FIX B INCOMPLETE for the tree: rtl/marker.v (class marker, top_max) has the identical timer-driven BSY writes,
  S_COLLECT r_nodig :396-399 and S_YIELD u_nogo|y_nogo|r_nodig :574-578, same r_gone-only guard. top_max builds
  r_hook on the register card (top_max.v:143,179) but leaves it unused (:217): FIX B there needs the register's
  hook carried to marker.v (one ribbon wire; C01's verifier noted the same for its hook-gated fix).
- predicted (by hand) for tb_c17f: B11 stuck at f=0..2.0, free 2.5..3.5; A20 possibly stuck too at small f (A NODIG ~1 tick before B's)

## RESULT tb_c17f (the one run): far-end form on the SNAPSHOT, scale 8, equal timers -- far.log
- B11 STUCK 5 of 8 (f = 0.0 .. 2.0 ms after B's nd_t = NODIG-T_REL-2), free at 2.5, 3.0, 3.5: as predicted.
- each stuck point: B11 port REL at +32/+33/+34, B r_nodig at +34.000 with r_gone 0, 'B wr dst 11 src 03 bsy 1 clm 1'
  at +34.128 AFTER the rel -> B11 latch 03 bsy 1 CLM 1 for good. A11 M dips 0 (+32.031..+34.031) and returns to 1
  at +34.156 (the stuck CLAIM, backward A); A's unit clears st[11] in the dip, then HOLDS A11 as an incoming seizure
  ('A wr dst 11 src 00 bsy 1' at +36.559), monitor 01 held and n_nofwd 1, still so 512 ms (4 s real) later.
- A20 ALSO stuck in 4 of the 8 (f 0..1.5): A's own S_YIELD r_nodig fires ~1 tick before B's, same race.
  So one hang-up at the unlucky moment on a claimed call can stick the caller's line AND the far trunk.
- Free points: the NOGO word lands before B11's rel and the rel clears it; everything idle after.
- Caveat: bench clocks are near phase-aligned, so even the 0.13 ms dip (rel on the nodig tick) was sampled; with
  plesiochronous real clocks a 0.13 ms dip is seen ~13 % of the time, a 1.1-2.1 ms dip always. Unseen dip: A11 sits
  M=1 BUSY=0 st=1 (channel dead both ends, marker re-read blinding). B11 stuck with CLAIM either way.
- walltime 244 s; obj dir removed by job.sh.

## VERDICT (skeptic)
- confirmed-understated; severity HIGH for the cluster (line forms alone: medium). The verifier named the
  claimed-trunk form but assumed the line consequence; it is C01's permanent stuck-CLAIM + phantom seizure, reached
  by ONE conforming event (partial-dial abandon on a claimed call, hang-up ~NODIG-T_REL after the last digit).
- FIX B right for mini_marker and covers the trunk form by construction (same branch; r_hook = relayed M) -- not
  run on fixB (one run allowed): next verifier should run tb_c17f on RTL_fixB.list. Incomplete: marker.v :396/:574
  (top_max) needs the same gate plus the register's hook wired to it; S_WATCH nodig gate optional; C01's
  att_refuse is a separate write site.
