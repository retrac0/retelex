# C18-late-claims verification notes
(started 2026-09-26)
## Plan
- F1: tb_late.v (copy of origin auditor's tb_orig + S7): S5 topology (A-B two direct links, both B cells claim),
  B's marker blind to claim 1's att for DLY (bench force on u_att = what S_WATCH does) so claim 2 goes out ~DLY after claim 1.
  Sweep DLY: 10 ms (control: auditor's 'path delay > 1.5 ms') and around T_REL=32 (scale 8).
- F2: mechanism already reproduced by C13 verifier (tb_pchain pass 1, run_pchain_snap.log). Check consequence at real timers.


## Reading results (22:40)
- F1: auditor MISSED port.v:148 `busy = bsy || fe || (fm && !m) || mute_blk`. The dropped origin trunk was listening to
  the caller (E up, fE up); the drop re-points it to 00, so E falls, but fE falls only T_REL later: the trunk stays
  BUSY for T_REL (256 ms real) after dmo/N_DROP. A claim landing inside that is M-under-BUSY -> st[p] set (net_unit
  :566-570) and stays set while M stays up -> cls_seen false. So the auditor's ring trigger (path delay difference
  > 1.5 ms) and "claim just after T_CLAIM" are NOT enough; the claim must FIRST reach the origin > T_REL after the drop.
- But the owner's cell clears at CLR (256) of forward-M break and its in-port self-releases at T_REL (256): both
  equal to the origin's fE hold. Window = ~1 ms (round-trip carrier delay + sampling) at ~T_REL after the drop.
- The only conforming way to delay the owner's 2nd claim ~T_REL: cl_st waits on claim 1's att, which the marker
  holds in S_WATCH (SETTLE 32, or CLR+SETTLE when the local caller hangs up at the connect; NODIG with a chattering line).
  Normal claim-2 lag is 0.3 ms (tb_orig S5 log: 6738.272 -> 6738.563).
- New network.md 7 expects: "the long way ... may claim too, gets a register or a refusal and releases unheard".
- F2: mechanism = C13 forward-glare-collapse (ii); C13 verifier re-ran tb_pchain on snapshot (run_pchain_snap.log,
  identical to proto auditor): pass 1 resolver resolved on glare 2130.203, B cell claims 2389.999, B11 -> 0 clm 1
  2390.284, B11 released 2422.999 (T_REL), then A11, B14, C11. Consequence = collapse, not "two exchanges ring".
- F2 at real timers: late claim at b_end+~130 -> in-port rel b_end+~386 -> origin trunk rel b_end+~642 < 720 ms
  min pause: h never reaches anyone; call lost; origin later latched to released trunk (C11).

## Jobs
- job_late.sh 10000 33000 (tb_late snapshot) queued 22:37 -> run_late_<dly>.log
- job_f2.sh (rtl_f2 = free cells at w_res: tb_pchain sc1 + tb_net) queued 22:39
- 22:55 restructured: job_late.sh <tag> <list> <dlys>; snapshot sweep = tag snap; job_fix.sh = rtl_fix (F1 gate:
  claim only while cell's mp_m up; F2: free cells whose m_port == rs_in at w_res) + monclaim auditor fix (d_lbrk frees
  a cell on a break >= ID) on tb_late sweep, tb_pchain sc1 and tb_net on rtl_fix.
- 23:40 independent evidence (hub load study, work/load/hub/NOTES.md:126-128, 133-136; logs g1_ring_unstrapped,
  g2_ring_strapped, s8, snapshot RTL): in a triangle ring the owner claims TWICE every call; the 2nd claim (0.3-1 ms
  later) reaches a path the origin/hub dropped ~1 ms earlier "inside T_REL: absorbed (st set), no phantom";
  harness PHANTOMSEIZE count 0. => the auditor's ring trigger does not produce the phantom.
- 23:35 slots: 5 busy with long jobs (tim5 load 1 h, etc.), ~13 waiting; my snap + fix jobs waiting since 22:43.

## RESULT run_late_snap_10000.log (snapshot, s8, control: claim 2 held 10 ms) -- PASS, no phantom
- 401.445 A drops A13 (bsy 0) but fE 1 -> BUSY 1.  410.580 B writes CLAIM on B13; 410.598 A13 M 1.
- 411.191 A probe 13: M 1 BUSY 1 st 0 -> st set; st 1 every sample after.  434.004 A13 fE falls (BUSY 0, st 1);
  434.004 B13 fM falls -> B13 releases (clm 0); 434.035 A13 M 0.  No cls on 13, no monitor. A claim 9 ms after the
  drop (6x the auditor's 1.5 ms) is absorbed.
- Timing seen: A13 fE fall and B13 self-release on the SAME ms (434.004); B's cell 1 CLR would fire at 435.004.
  Prediction: CLAIM write landing in (434.004, ~435.3) = on a B13 that already released -> no edge -> B13 stuck
  bsy/clm, A13 M up forever with BUSY 0, st 0 -> PERMANENT phantom at A (C01 no-edge + C08). DLY window
  ~(33.42, 34.71) ms. Transient window (write before B13 rel, M at A after A's fE fall) ~0 wide in RTL.

## RESULT snapshot sweep (run_late_snap_<dly>.log, s8, 88-98 s each)
- DLY 10, 31, 31.5, 32, 32.5, 33 ms: PASS. Claim 2's CLAIM lands on B13 before B13 self-releases (434.004) while A13
  is still BUSY by fE -> st set -> absorbed; everything idle afterwards.
- DLY 33.5 ms: FAIL x3. 434.004 A13 fE falls (BUSY 0) and B13 releases itself; 434.080 B's CLAIM word lands on the
  RELEASED B13 (bsy 1 clm 1, M 0 fM 0: no edge); marker refuses -> B13 src 03 bsy 1 clm 1; 434.098 A13 M 1, BUSY 0,
  st 0 -> 434.192 A cls takes 13 -> A holds A13 (listening 00) + monitor cell; A13 fM rises 436.004.
  400 ms after A20 hung up (> 12 x T_REL): A13 and B13 BUSY, A mon 01 -> PERMANENT (no timer frees it).
- DLY 34 ms: same (write 434.580, cls 435.192), permanent.
=> finding 1 CONFIRMED only in a ~1.3 ms window of the owner's 2nd-claim lag at ~T_REL after the drop, and there
   the consequence is WORSE than the auditor said: permanent (no-edge CLAIM on the owner's released in-port, C01
   family, and a steady-M phantom at the origin with no timeout, C08), not "until the refused copy releases".
## RESULT fix sweep (rtl_fix: F1 gate + F2), DLY 31..34: PASS, claim 2 never written (B13 fwd M fell at 402).
- snapshot DLY 35, 36 ms: PASS -- B's cell 1 cleared by d_clr at 435.004 (as predicted) before claim 2: no claim.
  => on the snapshot the bad window is DLY in (~33.42, ~34.71) ms: CLAIM word after B13's self-release (434.004)
  and w_claim before B's CLR (435.004). Lags below it are absorbed by A13's fE hold; lags above it never claim.
- rtl_fix (gate: claim only while mp_m) DLY 31..35 PASS: claim 2 never written.
- monclaim auditor fix (d_lbrk frees a cell after ID of break) DLY 31..33.5 PASS: B's cell 1 freed 419.004
  (16 ms = ID after the forward M fell), so claim 2 never written. Also closes F1.

## RESULT run_pchain_fix.log (rtl_fix, tb_pchain +sc=1 +trace, s8) -- 18 checks 5 FAIL (snapshot 4)
- pass 1: F2 fix frees B's cell at the glare R_LEG (2130.203); B never claims (snapshot: 2389.999 claim, B11 -> 0 clm 1,
  collapse). The glare join stays: B11->14, B14->11, A20->11 and C20->11 joined, "C20 hears A20" FAIL (new).
  => the proposed F2 fix removes the re-point/collapse but leaves C13's glare join (documented residual glare joins two
  callers); on its own it trades a lost call + later listen-in (C11) for strangers joined. Needs C13's fix (origin
  re-check F3' or armed-leg R_LEG) to be a clean outcome. Pass 0 unchanged.

## RESULT run_net_fix.log (rtl_fix = F1 gate + F2 cell-free): tb_net 88 checks, 0 errors, PASS (750 s), = base.
All obj dirs deleted.

## VERDICTS
- F1 late-claim-on-dropped-origin-trunk: confirmed-overstated. Stated triggers (ring path-delay difference > 1.5 ms,
  claim just after T_CLAIM) are ABSORBED: dropped trunk BUSY by fE for T_REL (port.v:148) + st (net_unit :566-570).
  Measured: tb_late lag 10..33 ms PASS; hub study G1/G2 no phantom. Residual: ~1.3 ms window of owner claim-2 lag at
  ~T_REL+1.5 ms (owner's CLAIM lands on its self-released in-port before its cell's CLR tick) -> no-edge CLAIM at the
  owner + phantom at the origin; permanent if the owner's register refuses claim 2 (it is busy with claim 1), ~2 T_REL
  if it takes it. Conforming route: claim 1's att waits in owner's S_WATCH stretched to CLR+SETTLE by a local caller
  who hangs up at the connect (or NODIG chatter). Fix: the auditor's 2nd option = gate w_claim on the cell's M (tested,
  1 AND a cell); monclaim d_lbrk (tested) and origin a' (CLR/2 WATCH bound) also close it. Auditor's 1st option
  (origin-side mask) does not free the stuck owner port.
- F2 late-claim-after-resolve: confirmed (mechanism reproduced in tb_pchain pass 1 = C13 forward-glare-collapse (ii));
  trigger understated (residual glare on the OWNER's forward leg, no false claim or waiting cell needed); consequence
  wrong: not two exchanges ringing -- the re-pointed in-port's fE falls and it self-releases T_REL later, path collapses
  before h (b_end+~642 ms < 720 ms pause), call lost, origin later latched to released trunk (C11).
  Proposed fix tested: removes the collapse (B never claims) but leaves the glare join (C20 hears A20): needs C13's fix.
