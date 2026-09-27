# C01 skeptic review (lens: MECHANISM) -- notes
(started 2026-09-27)

## Reading (snapshot rtl/, no sims run)
- mini_marker.v:273-282, 320-327, 541-553; pulse_reg.v:101-124; pulse_rx.v:63; port.v:144-194;
  net_unit.v:283, 566-570, 584-622, 656-676, 795-883; marker.v:271-273, 543-555; top_max.v:143-217;
  baseband_card.v:154-158 (/ANS tied low: a_rx = e||clm, no ring chop -> phantom M is steady).
- watch-exit-refusal: DETERMINISTIC. WATCH exits only with bus_idle (541), so room>=6 at T+1;
  u_local/u_done/u_nogo cannot pulse (origin idle while register is on a local/claimed caller).
  So at T+1 att_refuse always fires on stale r_busy. No blocking condition found.
- Only unbounded wait is S_WATCH. Other no-take/no-refuse windows: S_READ with r_busy=0 (caller
  candidate, <=~2 ms, ends in S_TAKE where att_take fires), COLLECT for 1 tick after attach. Harmless.
- Stuck chain re-derived: B11 rel (fM fall) -> refusal 03/bsy/clm; e=M(03)=0, m=0, fm=0 -> no edge.
  a_rx=e||clm (on=0 since trunk ans_n=0) -> A11 M=1 steady. A st cleared by M-low samples in the gap.
  If the gap < 1 pass, A keeps st=1: no phantom at A but both trunk ends still dead (variant).
- Realism qualifier the verifier did not state: for the chatter fault the chatter must START within
  ~SETTLE (32 ms) of the connect words (any 32 ms make settles WATCH; chatter during dialling
  prevents ID so digits never complete). So the fault needs onset in a ~33 ms window after the
  connect -- rarer than "a chattering line". Medium still right given permanence + spread.
- Spread: with the ring strap the unstrapped links are a tree (network.md 7); a phantom at A is
  forwarded over the tree: every exchange beyond A gets one permanent hold+monitor, every transit
  a resolver. One event halves NMON=2/NRES=2 across A's subtree; two events end claiming/transit.
  Reasoned, not simulated (as verifier said).
- Ring side effect of the WATCH-exit refusal (graceful): at a ring end the direct copy claims first,
  waits WATCH, is refused; the queued long-way copy is then claimed with the register free and TAKEN;
  the origin has already dropped the long way, so the register sits on a dead trunk until gone.
- Hook-gated fix mechanism: wait bounded by first sampled break or settled (<= ~33 ms after claim +
  bus delay); w_claim itself only fires while the monitor cell is held (d_clr frees it on 256 ms
  break), so trunk is live at claim; release >= 256 ms after -> refusal/take always on a live trunk.
  !r_release: T+1 neither (IDLE blocked by r_busy), T+2 att_take in IDLE/DRAIN. Sound.
- Residual race (not introduced by the fix; pre-existing, ~1-2 ms): port T_REL (direct) vs
  register CLR / monitor d_clr (via probe, 1-2 ms later) -- a marker nodig NOGO write or a queued
  w_claim landing in that gap re-busies a released port. Negligible.

## Verdicts (final)
- watch-exit-refusal: confirmed-overstated, low; agree with verifier.
- att-watch-late-refusal-stuck-clm: confirmed-overstated, medium; agree (add onset-window qualifier).
- late-refusal-no-edge-hold: duplicate of the above; confirmed-overstated, medium; agree.
- Fix: hook-gated (!r_release && (state!=S_WATCH || !r_hook)) is sound; deleting the exemption is
  equally safe and simpler (needs network.md 3 / marker.md 5 text change). Port to marker.v:273.
- No simulations run.
