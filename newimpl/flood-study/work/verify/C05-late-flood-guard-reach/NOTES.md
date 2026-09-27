# C05-late-flood-guard-reach -- verification notes

Started 2026-09-26. Findings: late-flood-truncated-count (fwd), classifier-hold-serialises (monclaim), guard-reach (proto).

## Reading (done)
- net_unit.v:584-588 C_HOLD: any M-low sample within cls_ms>T_ARM+1 (18 ticks from the hold PUSH, ~19.5 ms after rise) -> C_UNHOLD (590-594) writes hold away. Confirmed.
- port.v:147 busy = bsy||fe||(fm&&!m): if fm armed (M stood 16 ms) the port stays BUSY through the break; at make BUSY=0 -> R_GONE (688-689) drops legs, and st (cleared by M-low, 566-567) lets cls_seen (283) re-take it as fresh -> 2nd cell mid-digit. Confirmed by reading + auditor log run_fx_sc6load0dly112.log (:46 unhold 47.68, :62 re-seize 108.5, :115 CLAIM, :128 B21).
- If fm NOT armed (break <16 ms after rise) same end: unhold -> BUSY falls at once -> R_GONE; re-seize at the make.
- load1 variant (run_fx_sc6_l1_d112.log): E30 never classified before its break (S41's C_HOLD) -> first seen at the make = late pickup (finding 2's mechanism), not the unhold.
- monclaim burst log run_real13_all.log:260-264: 2/21/40/59/78 ms rise->BUSY. Consistent with RTL (C_HOLD 18 ticks + read).
- NEW exchange/network.md (today) ALREADY says hop ~12 typ / 22-30 slow, 128 tap ~10 typ / 4-5 slow (sec 6), burst 1 per 18 ms (3.3), cell up to 20 ms late (3.4 rule 1), and lists guard reach as open (sec 10). It does NOT budget the destination's own watch (~20 ms after rise). -> guard-reach finding largely already absorbed into the new doc.
- Same root mechanism as C04-hold-watch-dial-break (cableb): C04's fix = C_LOW state.
- monclaim fix (a) frees the cell at C_UNHOLD: would free the CORRECT cell in this scenario (makes it worse, not better) -- note.
- Conforming dial (pause >=720 ms): first break of e is >=581 ms after seizure; flood would need ~560 ms arrival = 40+ nominal hops -> unreachable. Needs pause ~259..400 ms (fast/non-conforming dialler) and >=~9 links nominal on the 128 tap.

## Fix under test (mine): rtl_fix/net_unit.v = C_HOLD M-low -> C_LOW (write nothing, time it); M back -> C_HOLD again from the make; low >= ID -> C_UNHOLD.
- decisions.md (today) retired: 7 ms hop / hub hop-and-a-third / "128 covers ten" as slow case; and rule 1 "cell within one scan" -> "2-3.5 ms (~20 ms behind a busy classifier), the guard covers it". So guard-reach's doc complaints are against SUPERSEDED docs; new sec 6 already uses ~12 / 22-30 ms.

## Sims queued (2026-09-26): slots full of long load runs; scripts run_fx.sh / run_net.sh (build+run+rm obj in one slot)
- snap: tb_fx sc6 l0 d112, l0 d124, l0 d108, l1 d104   -> run_snap_sc6_l*_d*.log
- fix : tb_fx sc6 l0 d112, l0 d124, l1 d104, l1 d112   -> run_fix_sc6_l*_d*.log
- fix : tb_net                                            -> run_net_fix.log
- C04 verifier (work/verify/C04-hold-watch-dial-break/NOTES.md) independently reached the same arithmetic and tests the same C_LOW fix (theirs CLR default, mine ID). C05 finding 1 = C04 root cause reached via late flood.
- C_LOW cost to note: on a REAL death inside the watch (far guard abandon at the flood front, blip, outage) the classifier stays busy ID=128 ms before the unhold (snapshot: immediate) -> other rises at that exchange wait up to 128 ms (finding-2 exposure). Rare.
- tb_net on C_LOW fix: 88 checks 0 errors PASS (run_net_fix.log, 1003 s); base-net.log same count
- FIX sc6 l0 d112: PASS 6/6 (run_fix_sc6_l0_d112.log): no unhold, one monitor lets go at 436 ms (e=3), forward legs carry the whole digit, no claim
- FIX sc6 l0 d124 (break 5 ms after rise, port unarmed): PASS 6/6
- FIX sc6 l1 d104 (2nd seizure, held 19.8 ms after rise, break 25 ms after rise): PASS 6/6
- FIX sc6 l1 d112 (busy classifier, E30 never classified before its break): FAIL 2 (claim 1437, B21 rung) -- as expected: late pickup, finding 2's mechanism, not the watch. C_LOW does not close it.
- SNAP sc6 l0 d112: FAIL 2 -- identical to auditor's run_fx_sc6load0dly112.log (diff = blank lines only). REPRODUCED.
- SNAP sc6 l0 d124 (break 5 ms after rise; inside the doc's own model the monitor at 1.8 ms sees the rise): FAIL 2 -- unhold 35.68, BUSY falls at once (fm unarmed), forward cancelled, re-seized at the make 96.5, 2nd cell claims 1424, B21 rung.
- SNAP sc6 l0 d108 (break 21 ms after rise): PASS -> window is ~19.5-20 ms after the rise (hold ~1.8 ms + 18-tick watch).
- SNAP sc6 l1 d104 (2nd seizure, held 19.8 ms after rise, break 25 ms after rise): bench PASS, BUT log shows the mechanism fired: unhold 56.68 (hunting forward cancelled), re-seized 117.8 mid-digit, NO 2nd cell only because NMON=2 was exhausted (S41 + E30's first cell), and a NEW forward at 128 ms from mid-digit (legs 75/40/11 carry e-1 downstream). With NMON>=3 B itself would claim. Fix run l1 d104: clean.
- Next: cls slice's fix (watch off the classifier + rise queue) on sc6 l1 d112 / l0 d112 -- does it close the busy-classifier variant?
- CLS slice fix (work/audit/cls/RTL_fix.list: T_ARM watch moved to 4 watchers timed from the rise with a CLR low test, rise queue, lateness bit): sc6 l1 d112 PASS (E30 held 1.8 ms after its rise despite S41 1 ms earlier), sc6 l0 d112 PASS. Closes both variants; cls slice's own tb_net on it: reg_fix_net.log 88/88.
- obj dirs removed.
