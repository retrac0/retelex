# C20-misc verification notes

Started 2026-09-26. Findings: claim-legs-slot-collision-two-resolvers, wait-constant-doc-stale, port00-must-be-unfitted, release-margin-thin.

## Code reading (snapshot), 2026-09-26
- F1 claim-legs-slot-collision: mechanism true as code (net_unit.v:659-663 later u overwrites slots j2+1),
  but precondition (two busy resolvers with same rs_in) needs P re-classified while old resolver busy.
  cls_seen needs !sp_busy at P's visit; the SAME visit sets R_GONE on the old resolver (688-689) if R_NONE,
  else it is already R_LEG/acting. New resolver needs a full sweep (64 reads, no early exit) + confirm:
  >= ~10 ms. w_res would have to be starved 10 ms; higher pushers are one-shot, queue drains 7 words/ms.
  Marker cannot busy P between the two probes' samples: both probes sample the same bit-time.
  -> not reachable. not-a-bug / info.
- F2 WAIT: marker go = ureq_n combinational (mini_marker.v:227). Traced ctl_queue/ctl_write edges:
  marker oe from edge 0 to edge 547; unit granted at edge 640, oe from edge 641 -> gap 94 ticks (auditor 93).
  ctl_write.v:80 hard-codes n<=16 (not `CWW). exch.vh "WIDENS WITH `PW" five-site list omits net_unit WAIT;
  at PW=9, CWW=22 -> 23 bit-times*32+3 = 739 ticks > 640. Live spec exchange/bus.md:183-185 already says
  640 ticks and lists it Open (bus.md:268 "derived by hand, not measured"); the 1152 is only in the retired
  exchange-docs/mini-marker.md:313. tb_net counts b_clash every tick (tb_net.v:157-160, 504, 508).
- F3 port 00: exchange/numbering.md:30 "00 idle, never fitted" and :36-37 gives the ringing reason.
  site_net: LTU[0] would also collide with tone sources 01/03 on block 0 (site_net.v:95-99,132-133,
  "all eight sockets of such a block are its"), so it is already an invalid bench config.
  Consequence "wrong numbers everywhere" overstated: monitors claim only on e b; a false backward A
  makes the origin keep the wrong direction (glare-as-claim) -> lost calls, not wrong numbers; every idle
  phone rings (port.v:144-153).
- F4 release margin: port.v:147,176-193. Detectors are RC+'14 on the board (exchange/fabric.md:254-255,
  and fabric.md:395 Open "detectors as RCs ... nothing has checked them"). The near end's fE RC and the
  far end's fM RC are different parts -> release skew = RC spread, not +/-1 tick. C03 verifier already
  showed (tb_c03r, TRELA=200) the port-level loss with the monclaim fix. Sweep order stride 9 from 1:
  port p read at step k=(p-1)*57 mod 64; A11 (9) at k=8 -> ~9 ms of sweep after its read; port 070 (56)
  at k=63 -> only the confirm pass + write after its read (the auditor's worst case).
  network.md:51 allows a pots tie to shorten breaks 5-10 ms a hop (= fall later than rise).

## Sims
- run_n11_full.log (tb_c20r, TRELA=256, TA=A11, rs=258): PASS 7/7. TA and X11 free same ms (936), re-seized 949 (13 ms after), X holds X11 fresh (#2), claims, X22 rung. Control OK.
- run_n11_scan.log (TRELA 256, TA=A11, scan rs 254..258): rs=258 re-seized, margin 14.8 ms (X11 free -> re-seizure M);
  rs 254-257 NOT re-seized (257 unexplained by "read while busy": TA free at +257 same ms as far_m; queued
  n11d debug run with A cls/fwd/sweep prints).
- Analytic worst case, exact counters: step k select at port p=(1+9k) mod 64; for k>=57 p+(63-k)*9 = 56 frames
  constant, so min free->far-M ~ 56 + 8 + 64 (confirm) + 1 + 10 (WAIT) + 8.5 (word) + 2 (far card flops)
  ~ 150 frames = 2.3 ms + E capture (0-1 ms); far end frees up to ~1 ms + 2 frames later (tick phase)
  -> worst margin ~1.3 ms (auditor 0.13-0.29: omitted the p-frame wait and E capture). Same order.
- tb_wait first attempt died in the queue (outer timeout 900 on sim.sh); relaunched as run_w.sh.
- Other RC-tolerance hole seen by reading (not simmed): origin's late drop (N_DROP after register CLR) can
  write away a port that self-released early (fast RC) and was already re-seized by the forwarder; the sweep
  does not exclude d_held/rs_held ports (net_unit.v:759). Same root.
- F3: auditor wrong that the local trunk may sit on block 0: exchange-docs/local-trunk.md:213 "Block 0 is never this group"; live exchange/numbering.md:43-44 likewise (group trunks never block 0).
- run_s240_full.log (TRELA 240 = A RC 6% short, TA=A11, rs=242): FAIL 3/7 as predicted. TA free +241, re-seized +254 (933), X11 still held (busy=1), X never re-holds X11 (fresh holds=1, the old one), no claim, no X register, X22 not rung: the flood dialled to X is LOST. X11 frees only 256 ms after the flood ends (5876). Confirms F4 with conforming equipment (RC tolerance).
- run_z.log (tb_c20z, phone fitted at X00 and off-hook, real timers): X21 (idle, no call) being rung 50/50 ms;
  ALL X lines 20-27 read BUSY (idle latches listen to 00 -> E=1 -> fE -> BUSY, port.v:147); A11 went BUSY at
  590 ms before A20 had keyed: idle X11 listens to 00 and sends 00's M forward = a phantom seizure at A, which
  A holds (and, inferred from h_ok=0, forwards onto A12). A20's flood then found no free trunk (origin
  2->8->0 at 730, nogo, A20 on 03). X's unit never claims; no register at X. So: whole-exchange outage plus
  phantom seizures at every neighbour, loud and immediate -- not "wrong numbers". Bench check wording
  "no X line seized by the call" is mine and misleading: the busy lines are the fault's fE, not the call.
- run_wait.log (tb_wait: both ctl_queues + net_unit's request logic verbatim, marker word at 0, unit word at
  -4..600): marker '244 on 547 ticks; WAIT=640 -> min gap 94 ticks (auditor said 93), no clash at any offset.
  Clash-free down to WAIT=546 (gap 0); WAIT=500 clashes (1081 ticks over the sweep, overlap 46). Worst offset
  is +2 (unit push lands the edge after the marker sampled /UREQ high). Confirms the arithmetic.
- run_n11d_scan.log: rs=256/257 "NOT re-seized" was MY BENCH ARTEFACT: TA still BUSY (old call) when Y's M rose,
  so the wait loop exited at once and Y's M dropped after ~10 ms (< T_ARM): C_UNHOLD cancelled the forward
  (cls 4 at 945). rs 254-257 in run_n11_scan.log are void; rs=258 (14.8 ms margin) is valid. The trace shows the
  forward sweep starting the same ms TA freed (936), so port 9's best case is ~11 ms. Fixed the scan loop (wait
  for a seizure after the free, hold Y's M 30 ms) before the n70 run built.
- run_n70_scan.log (TRELA 256, TA = A70 = read LAST in the sweep, scan rs 244..252, fixed bench): rs<=246 the
  read found TA still busy (no forward); rs=247 is the tightest: A free -> re-seize write 2.285 ms, X11 free ->
  re-seizure M at X11 3.891 ms, with X's tick 0.68 ms AHEAD of A's (bench phase; drifts 50 ppm). Adverse phase
  (X up to ~1 ms behind) takes ~1.7 ms off: worst exact-counter margin ~2 ms, not 0.13-0.29 (auditor omitted
  the port's own bit-time wait and the E capture). MF8's 0.5 ms asymmetry fits inside; a pots tie's 5-10 ms
  (network.md:51) does not at this placement; at A11 (step 8) the margin is ~11-15 ms.
- run_n70_fd500.log (A70, MF8's 0.5 ms fall-late asymmetry on A->X): all re-seizures safe; tightest rs=247
  margin 3.06 ms (X11 now frees 0.14 ms AFTER TA). MF8's figure does NOT reopen it at exact counters, contrary
  to the auditor; the pots tie's 5-10 ms and any RC skew beyond ~0.5-5 % (placement-dependent) do.

## Verdicts (final)
- F1 claim-legs-slot-collision: NOT-A-BUG / info. Precondition unreachable (reasoning above). No fix needed;
  optional bench assertion.
- F2 wait-constant-doc-stale: CONFIRMED-OVERSTATED / info. 547-tick marker word, 94-tick margin measured
  (run_wait.log). Live spec already says 640 (bus.md:183-185, Open at :268). SCLK-off-HCLK/4 jumper is 128 kHz
  = same word. Residual: WAIT not in exch.vh WIDENS WITH `PW list; ctl_write.v:80 hard-codes 16 bits.
- F3 port00: CONFIRMED-OVERSTATED / low. Rule documented (numbering.md:30,36-37); LTU trigger forbidden by the
  spec (local-trunk.md:213, numbering.md:43-44) and collides with tones in site_net. Fault = loud total outage
  + phantom seizures at neighbours (run_z.log), no wrong number.
- F4 release-margin-thin: CONFIRMED-UNDERSTATED / medium. Reachable with conforming parts via RC tolerance
  (run_s240_full.log: 6 % short RC, flood to X lost). Exact-counter margin 2-15 ms by placement, not 0.13-0.29.
  Same root as C03 rc-tolerance-reseize. Doc-only fix insufficient.
- Roots: F1, F2, F3 independent hygiene items; F4 its own (release race between two independent RC detectors,
  no release handshake), shared with C03 finding 3 and the C17 CLR=T_REL family.
