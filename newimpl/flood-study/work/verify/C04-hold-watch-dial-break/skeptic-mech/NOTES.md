# C04 skeptic review (lens: MECHANISM) -- notes

## RTL re-derivation (snapshot, read-only)
- net_unit.v:584-588 C_HOLD: any one probe sample of M low on cls_port within cls_ms<=T_ARM+1 -> C_UNHOLD. No
  filtering at all (every other consumer of M filters: pulse_rx HIT 8 ms, port T_ARM/T_REL). CONFIRMED.
- 590-594 unhold writes ent(port,P00,0,0), f_cancel only if fst!=F_IDLE && f_in==port. Monitor cell NOT released.
- 566-567 st cleared on any M-low sample; port.v:147 BUSY=bsy|fe|(fm&!m) -> 0 at the make whether fm is 0 or 1.
  cls_seen 283-284 re-takes it. CONFIRMED, both fm cases.
- Verifier's mid-path mode: R_GONE (688-689) needs only !sp_busy on rs_in. If the transit's fm is still 0 at the
  break, BUSY is 0 DURING the break (after the unhold lands), so R_GONE fires in the break, not at the make.
  Same result. In the verifier's off-2 log there is no flicker hold at C near the make, consistent with that.
- Guard: net_unit.v:862 abandons on `guarding && r_brk`; r_brk is the register's brk_stb at HIT (8 ms into the
  break). A break STARTING up to ~HIT before t_guard passes. Widens the band by ~8 ms on the early side; the
  break's own ~1 ms/hop propagation lag roughly offsets it at hop 8. Small refinement, not a verdict change.
- e=1: the late cell sees no break in e, pulse_rx never strobes cnt=0, so it takes b as e and h as b:
  wrong claim iff (b,h) = own code. The auditor's "(e-1,b)" is wrong for e=1.
- mini_marker S_WATCH (its analogous watch) waits for r_gone = CLR, not one sample: supports CLR in the fix.

## Second path (RTL reading): a single-sample A dropout inside the watch, conforming dial
- dropout at transit B before its forward is written (hold+0..~11 ms): unhold sets f_cancel; re-hold 1-2 ms later
  finds fst=F_HUNT so no new forward, f_cancel stays 1, sweep ends -> F_IDLE. Flood dies at B. Lost call.
- dropout after B's forward is written (hold+~11..18): next sample M=1 BUSY=0 -> R_GONE drops the leg, B re-holds
  and re-forwards; the old leg has fe=0 (E stood <16 ms) so the sweep takes the same trunk ~12 ms later. Next hop
  C sees a ~12 ms gap >= HIT: every cell C already holds counts a spurious pulse, digit "1" at ID. C (in its own
  watch) unholds at the gap and re-holds after it with a fresh cell (if free). Bad cell = (1,e): wrong claim iff
  C's code is (1,e); C's own call lost if its fresh cell is not free.
- dropout at the owner: two cells, both count right -> second w_claim after att_ack -> second CLAIM word + att
  while the register is busy (tb_net 8: marker points the trunk at cannot-complete).

## Run (one allowed)
- tb_drop.v: real timers (as tb_brk_rt), C strapped 1 4. control; mode 1; mode 3. See run_drop.log.
- run started (sim.sh, one run): tb_drop on work/RTL.list -> run_drop.log / vl_drop.log

## Fix review (reading)
- verifier's C_LOW fix: correct for the dial break and for the dropout (M up in C_LOW -> C_HOLD, nothing written).
- cost: classifier stalled up to CLR (256 ms) after a death inside a watch (cls_seen needs C_IDLE). Deaths in a
  watch need a guard abandonment (non-conforming dial) or a hang-up within ~18 ms of a hold -- rare. A seizure
  arriving meanwhile is held late (its st bit stays clear, so it is taken later, not lost).
- C_LOW takes ANY rise on the port within CLR as the make, incl. a new seizure after a death: merged, no fresh
  cell or forward. Needs the far end to re-seize the channel within 256 ms, which its own fe/fm hold-off
  prevents unless E/M stood < T_ARM there. Ultra-rare. Snapshot has a sibling: the unhold never releases the
  port's monitor cell, which stays until its own CLR and counts a gap before a re-seizure as a digit "1".
  With the fix the unhold and the cell's CLR coincide, so that sibling goes away.
- mini_marker S_WATCH already waits for r_gone (CLR) on its own watch: the fix makes the unit match the marker.

## RUN RESULT (run_drop.log, snapshot work/RTL.list, real timers, 128 guard, 800 ms pauses) -- 7 checks, 1 FAIL
- attempt 0 control 1 1 4: C holds tmr 17, cell counts 1 then 4, C CLAIMS. ok.
- attempt 1 (dropout 2 ms into B's watch, fst=F_HUNT): B UNHOLD tmr 6, B re-HOLD tmr 8 with fst 2 -> no forward,
  B n_nofwd +1, C holds 0, nobody claims. LOST CALL from one 0.9 ms A dropout, conforming dial. CONFIRMED.
- attempt 3 (dropout at B's forward, cls_ms 11): B UNHOLD, resolver drops leg, re-HOLD, re-FORWARD 14 ms later;
  C had not yet held the first forward, so C held only the re-forward (tmr 31) and counted 4 right. No harm:
  the flood was just 14 ms late. The spurious-"1" mode needs the dropout after C holds (B's cls_ms ~14-17);
  NOT reproduced, stays a reading-only lead. No further runs (one allowed).
- obj dir removed by run.sh.
