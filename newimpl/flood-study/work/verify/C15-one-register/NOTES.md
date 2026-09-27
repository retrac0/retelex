# C15-one-register verification notes

Started 2026-09-26. Findings: one-register-claim-refusal (origin), one-register-refuses-claims (monclaim, proto), refusal-heard-after-hs (monclaim).

## Code reading (snapshot)
- mini_marker.v:282 att_refuse = u_att && !att_ack && r_busy && !rd_done && state!=S_WATCH; 320-327 writes trunk<-03 BSY CLM. CONFIRMED.
- Refusal is the DOCUMENTED rule: monitor.md 2, common-control.md 2.3 + table, mini-marker.md 8 ("With the register busy the marker instead writes trunk <- 03"), new network.md 4.2 "Busy is the owner's to say". So by design, not an RTL-vs-spec defect.
- net_unit.v:881 N_WAITCL -> N_DONE needs claimed && o_last && dmo==0; o_last (410) = ndig>=4 or 3rd digit 0/9. N_DONE (818) writes caller<-trunk and done -> mini marker S_YIELD frees register. Until then caller on SILENCE (key write, mini_marker 428). CONFIRMED.
- New exchange/network.md 4.1: "connect at the last digit", "The caller hears silence from the key to the connect." RTL MATCHES the new spec. Old monitor.md 2 / common-control.md 2.3 say "hears it at once / through the path already up" -> contradiction is with old docs (and loosely with new 4.2 "heard through the path already up").
- o_last used only at 881. h s are "the far register's business" (net_unit _unused comment). So connect-at-claim needs no other change.
- exch.py net model (sim/exch.py claim()/answered()) never takes a register at the OWNER on a claim: the design's traffic numbers (network.md 5.1, "one register" row) omit claim refusals entirely. That is the real gap.
- Audit fixed copies (work/audit/origin/rtl_fix) do NOT implement fix (1); they are other findings' fixes. My fix: work/verify/C15-one-register/rtl_fix/net_unit.v (drop o_last at 881).
## Runs (launched)
- tb_c15.v = copy of work/audit/origin/tb_orig.v, S2 only used (+scen=2), plus a tracker printing when A20/B20 first hear 03 (8 frames of 0); -DREAL gives real timers (T_ARM 16, T_REL 256, HIT 8, ID 128, CLR 256, NODIG 10000, GUARD 128, T_KEY 5000, T_CLAIM 2000, dial 60/40 with 800 ms digit gap).
- run.sh tags: snap8, fix8 (scale 8), snapR, fixR (real). runtb.sh: tb_net + tb_lfull on the fix.
- reg1.py re-run: output identical to auditor's reg1.out (deterministic). Model arithmetic checked by hand: 48 lines 3/h 30%: local ~4.4 s x 0.028/s + origin ~7.9 s x 0.012/s + claims ~2.7 s x 0.012/s = ~0.25 E. Matches 0.24.
- Predicted bench artefact on fix: tb_net 11 "a second after b the trunk is still held, waiting for h s" (dirs_a==0100) encodes connect-at-last-digit; will fail on the fix by construction.
## Results
- snap8 (snapshot, scale 8, S2): REPRODUCED, timestamps identical to work/audit/origin/run_s2_5.log. A refuses B20's claim at 352.295 (A mk 6 = S_YIELD, A20's register), B refuses A20's at 370.295. B20 hears 03 at 611.409, A20 at 629.409: 258 ms (scaled) after each claim = ~2.1 s real, i.e. only after s. Both called lines never ring. log run_snap8.log
- fix8 (connect at claim, scale 8, S2): B20's claim at A still REFUSED (352.295; A's register holds A20, who has not reached b). B's origin connects at the claim (353.177, N_DONE at ndig 2), B's register freed at once, B20 hears 03 at 353.566 (0.4 ms scaled after the claim, vs 258 ms before). A20's claim at B at 370.295 is TAKEN (B's register now free); B21 rings (ring-hi 64). refusals A 1 B 0: at most one of a crossing pair fails. idle ok. (The "A20 HEARS 03" at 631.550 is my tracker misreading B21's idle tx=0 after the connect, not a 03.) log run_fix8.log
- Slots congested (long load/transit and C12 jobs). Re-queued as two chains to hold at most 2 slots: chainA = tb_net on fix, then snapR; chainB = fixR, then tb_lfull on fix. (sim_chainA.out, sim_chainB.out)
- tb_net on fix: 88 checks, 1 error = the predicted bench check tb_net 11 "a second after b the trunk is still held, waiting for h s" (dirs_a==0100: encodes connect-at-last-digit; with the fix the origin has connected and let go at the claim). Every other check passes, including 8 (refusal after CLAIM, heard through the path), 11's "at the no-digit timeout ... the caller hears cannot-complete" (now B's NODIG refusal through the path), 12, 13, 16. log run_net_fix.log
- snapR (snapshot, REAL timers, 60/40 dial, 800 ms digit gap, lifts 23 ms apart): REPRODUCED. B20's claim at A refused 2243.290 (A mk 6), A20's at B refused 2320.290 (B mk 6). B20 hears 03 at 4062.401 (1.82 s after its claim), A20 at 4139.400 (1.82 s after). Neither called line rings. idle ok. log run_snapR.log
- fixR (fix, REAL timers): B20's claim at A refused 2243.290 (A20 still dialling its code); B's origin connects at the claim, B20 hears 03 at 2244.562 (0.4 ms after, vs 1.82 s). A20's claim at B TAKEN at 2320.290, B21 rings (ring-hi 1024). refusals A 1 B 0. idle ok. log run_fixR.log. (A20 "HEARS 03" at 4141.541 = tracker misreading B21's idle tx after the connect.)
- tb_lfull on fix: 40/40 PASS, glare at try 0 (both origins connect at b now; the glare checks, "registers free, nothing held", "neither number rang", "A31 hears B21" all pass). log run_lfull_fix.log
## Verdicts (draft)
- one-register-claim-refusal (origin, high): confirmed-overstated -> medium. Mechanism, reproduction and real-timer reach confirmed; refusal on busy is the documented rule; the holding-time model is sound (re-run identical); it is a capacity property of the one-register build that the design's traffic model (exch.py net) never counted.
- one-register-refuses-claims (monclaim, medium): confirmed (duplicate).
- one-register-refuses-claims (protocol, medium): confirmed (duplicate; its 'at once' point = refusal-heard-after-hs).
- refusal-heard-after-hs (low): confirmed; 1.82 s at real timers in S2; RTL matches NEW network.md 4.1, contradicts old monitor.md 2 / common-control.md 2.3 and new 4.2's "heard through the path already up".
- Fix (1) connect-at-claim tested: S2 one refusal instead of two (scale 8 and real), refusal heard 0.4 ms after claim; tb_net 87/88 (only the check encoding connect-at-last-digit fails), tb_lfull 40/40.
