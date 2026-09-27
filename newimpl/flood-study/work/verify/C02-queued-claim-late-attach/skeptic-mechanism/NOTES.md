# C02 skeptic review (lens: MECHANISM) -- notes
(2026-09-27) read-only; no sims unless one settles a disagreement.

## RTL re-derivation (snapshot) -- done
- net_unit.v:487 w_claim needs cl_st==CL_IDLE; :673 CL_WAIT->att on q_empty; :674 CL_ACK holds att until att_ack, no bound. CONFIRMED.
- :641 M_DONE: cell ignores digits after b but stays held; :647-649 d_clr (256 ms break) still clears it (m_want too);
  :666-668 freed at w_claim. So a queued claim IS withdrawn if its far caller hangs up >=256 ms before cl_st frees.
- mini_marker.v:282 att_refuse excludes S_WATCH; :273-274 att_take IDLE/TAKE/DRAIN & !r_busy. CONFIRMED.
- WATCH exits (541-553) need bus_idle, so room is 8 on the exit tick -> the stale-r_busy refusal (C01) of a lone
  waiting claim ALWAYS fires (room>=1, no u_local/done/nogo possible, no rd in flight). Verifier right: a lone claim
  is refused, never late-attached, in the snapshot.
- pulse_reg.v:86 arm = busy && seen, :106-107 seen cleared at attach and set at first own sample; pulse_rx.v:72-76 not
  armed -> cnt 0, m_d follows m. So counting starts at attach: a pulse in progress counts only if >= HIT of it remains.
  (Auditor's "pulse_rx.v:244-249" citation is wrong; file is 105 lines.)
- Other att delays: S_READ with r_busy=0 (a read, ~1-2 ms), CL_WAIT (unit queue, ms). Nothing else unbounded.
- Class marker marker.v:271-273 same exemption; top_max.v:183 fits a net_unit, so the class marker IS networked.

## Logs
- verifier's run_att2_snap_dstop8.log == auditor's run_att2_dstop8.log (diffed bar wall time). B22 rings.
- run_att2r_snap.log (real timers): attach 96 ms into h, counts 2 2, B22 rings. Consistent with RTL.
- run_att2_fix_dstop8.log: both claims refused in state 7 (WATCH), no wrong number.

## New points (mine)
1. STIMULUS NOT PHYSICAL through a line card: site_net.v:121 drives port M straight from hook (s_a = hook). The real
   cvsd_line_card.v:110-130 hook RC (tau 4 ms, 0.85/0.70) needs ~7.6 ms of break to show on_hook and shows makes
   ~6.1 ms long. The bench's 1 ms break / 2 ms make chatter would read as a steady make -> settled -> WATCH ~33 ms.
   The fault class survives but narrower: line breaks ~8..260 ms, line makes < ~26 ms, from within ~33 ms of the
   connect, for > ~0.6 s (e.g. an on-hook line with an intermittent short / chattering hook switch at 20-40 Hz).
2. RING/MESH, NO FAULT: two copies of ONE call reach the owner (C18's ring case); both cells decide b within ms
   (digits are relayed live), so claim 2 always queues behind claim 1. If a normal ~33 ms WATCH (or <=~290 ms
   hang-up WATCH) covers claim 1's att: claim 1 (the path the origin KEPT) is refused on stale r_busy, claim 2 (the
   path the origin/transit DROPPED at claim 1) is TAKEN: register on a dead trunk until CLR, caller gets
   cannot-complete, and the second CLAIM goes out ~WATCH later than normal -> C18's late-claim race is more likely
   lost (phantom seizure at the dropping exchange). Not a wrong number. Reasoned, not run.
   +fixatt alone handles this (claim 1 taken at WATCH end, before h). Deletion refuses both (as a busy register).
3. Bound alternative: an nd_t-based tap (from the connect) bounds EVERY queued claim at once; a per-att counter
   (C01 auditor's att_wait) lets k queued claims wait k*W (NMON=2 -> 3W). Prefer the nd_t tap; any tap <= 512
   keeps attach before h (margin ~580-590 ms); 512 keeps every conforming WATCH (<= ~320) a take, 128/256 refuse
   only in the hang-up/flash tail of a WATCH.

4. Deletion also restores C18's normal race timing in the ring case (second CLAIM ~1 ms after the first); +fixatt
   (with or without a bound) keeps the second CLAIM delayed by the WATCH. Point for the deletion.
5. Deletion cost vs spec intent: WATCH ~34 ms per local call; at C15's ~22 % register occupancy (~0.03 calls/s)
   that is ~0.1 % more claims refused. Negligible. vs snapshot: no cost (snapshot refuses them late).

## Verdicts (mine)
- F1: agree with verifier: confirmed-overstated, low. Mechanism exact. Reachability narrower still (line-card RC).
- F2: agree: confirmed-overstated, low (lone claim is refused in the snapshot, not attached).
- Fix: agree deletion in both markers + doc/comment edits; needs a class-marker regression (tb_max) not yet run.
No sims run by me.
