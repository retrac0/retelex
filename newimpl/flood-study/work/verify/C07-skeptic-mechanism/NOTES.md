# C07-link-outage-pulse -- skeptic review, MECHANISM lens

(started 2026-09-27)

## Reading so far (snapshot rtl/, no sims)
- baseband_card.v:154 a_tx = a_s2 && link_up && settled -- confirmed; a_out = a_rx ungated (98).
  local_trunk.v:132,188,189: a_tx = live ? x_a : 0 AND mute_blk = !live (BUSY on every port of the group).
- pulse_rx.v:78-90: count needs m=0 at 9 consecutive 1 kHz samples (t==HIT-1 checked on old t) -> break > ~8 ms.
- port.v:176-181: fM rides < T_REL; rel only on fM/fE FALL.
- net_unit.v:283 cls_seen = M && !BUSY && !st; st cleared by any M-down sample (566) -> a returning link
  is a seizure.  Resolver R_GONE on !sp_busy of rs_in (682).
- N_DONE needs claimed && o_last (net_unit ~888): origin register stays on the caller until h s are in,
  so a post-claim outage >= T_REL never makes the caller a fresh LOCAL caller mid-dial (that idea dropped).
  Post-claim >= T_REL outage = C11's dead claimed trunk (N_DONE latches caller to released A11).
- Audit fix (work/audit/proto/rtl_fix/baseband_card.v): poison <= 0 on rst_n; clear = link_up && !a_rx
  for CLEAR.  Verifier mut adds && !a_s2 and gates the word with !poison.
- MF8 (mf8/mf8-spec.md 4.1/4.2): acquisition 0.58-1.3 ms at 64 kHz frames, slip recovery <= 13 frames,
  0 LOF to 3e-2 BER -> verifier right: an MF8 re-frame is far under HIT.
- Verifier's one-way analysis of the audit fix (sc5) re-derived from the code: right.

## Candidate additions (reasoned from code)
1. RESET PATH: poison <= 0 on rst_n in both fix copies.  A far exchange (or its trunk card) restarting
   mid-flood: B's net unit/ports reset (st=0), card holds A=0 for HOLDOFF (100 ms, < T_REL), then
   a_tx = caller's M -> fresh seizure counted from mid-number (finding 2's window) -- NOT closed by the fix.
   A card-only power-up RC re-trigger = 100 ms break = exactly a pulse (finding 1's window).
   Free fix: preset poison at power-up ('74 /PRE instead of /CLR).
2. CHATTER EVADES RIDE: dn <= 0 at any frame_edge with link_up; link_up returns at the first far edge.
   A burst of sub-4 ms opens with brief closures never poisons, but a_tx = a_s2 && link_up is 0 at nearly
   every 1 kHz sample -> a counted break (possibly several).  Fix covers clean outages only.
3. ONE-WAY asymmetry of the both-ways clear: the unpoisoned end's word stays valid, its hunt can seize
   the channel whose far card is poisoned (deaf) -> flood lost that way; failed call, not wrong number.
   rtl_echo (far card poisons too) would close it.
4. sc2 "designed price" = C11 state: N_DONE (needs o_last) writes caller->A11 while A11 M already 0,
   A11 releases at T_REL, caller's fE never rose -> caller latched to a dead channel (C11).
- launched ONE run: job.sh (tb_c07k sc=192 on RTL_mut.list, TRACE_B) -> run_mut_sc192_p680.log

## RESULT of the ONE run (tb_c07k.v, RTL_mut.list = verifier's fixed card, TRACE_B, real timers,
## HOLDOFF 6400 = the real 100 ms RC) -> run_mut_sc192_p680.log (221 s; obj dir deleted)
- sc6 CHATTER (13 x [3.0 ms open, 60 us closed], ~40 ms, all conductors both ways, 30 ms into b's last
  make, A20 dials 1 2 2 2 1): NO card ever poisoned (no PZ line); B's monitor counted b = 4
  (d_stb cnt 04 at 2319.0 = ID after the chatter: one sampled closure split the burst into TWO counted
  breaks).  No claim only because B is 2 3; an exchange 2 4 would have claimed.  The fix's RIDE
  (4 ms CONTINUOUS link-down, dn reset by any frame with link_up) is evaded by a disturbed connector.
- sc7 B RESTART (B alone reset 1 ms at 1100, in e's 1st break; A20 dials 1 4 3 2 1 = exchange 43):
  B's hold and monitor wiped; card powers up UNPOISONED; after HOLDOFF A20's M is presented; fresh rise
  1240 (e's 2nd make) -> cst 0->1->2->3 at 1241-1242, cell d_stb cnt 2 at 1570, cnt 3 at 2550,
  'B raises att' 2550.3, A's origin claims 2551.2, B21 RANG.  A20 dialled 43-21, got 23-21 WITH THE
  VERIFIER'S FIX IN PLACE.  Same timings as the verifier's sc4 trace (1241.2 ...).  Fix gap confirmed.

## After the run: /RESET widens the restart path
- clock_card.v:9-10 "no reset beyond power-on"; baseband_card rst_n is power-on; the channel socket
  (a1-a14) carries no /RESET.  mainboard.md 153/736: /RESET (marker, power-on, pushbutton; a glitch on it)
  clears every latch.  So a /RESET of B clears B's ports/unit while B's trunk card keeps A20's M on B11
  and the link never drops: fresh seizure at the next rise, counted from mid-number.  No card-level
  poison can see it (link up both ends, card not reset).  sc7 reset the card too (the power-on form);
  the /RESET form is reasoned, same mechanism.  Fix: bring /RESET to the card's poison '74 preset
  (socket spare a14 in, or the block's filtered /RST) so either restart holds every trunk released
  until idle both ways; or a unit-side rule (first make after a rise must outlast an in-digit make),
  which costs guard budget at far hops (network.md 4) -- noted, not tested.
- Also: sc6 on mut is identical to the snapshot card in that regime (poison never set, so the mut
  card's extra gates are all transparent): the snapshot counts chatter as multiple pulses too.

## Verdicts
- link-outage-dial-pulse: agree, confirmed-overstated, medium.  + chatter form (2 extra pulses), 100 ms
  power-up RC break = one pulse.
- link-return-fresh-seizure: agree, confirmed-understated, medium.  + receiving-exchange restart path
  (sc7 reproduced wrong line with the fix in place).
- link-hit-extra-pulse: agree, duplicate, confirmed-overstated, low.  Nuance on its fix (b).
- Fix: right direction; gaps: power-up/RESET clears poison; RIDE continuous (chatter); one-way
  asymmetry (unpoisoned end hunts a deaf channel); sc2 price = C11 state; local_trunk + 4 benches untested.
