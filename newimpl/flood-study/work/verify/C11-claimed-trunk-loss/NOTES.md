# C11 claimed-trunk-loss -- verifier notes

- Read cluster JSON: one finding (claimed-trunk-loss-listen-in), auditor origin.
- RTL read (snapshot rtl/net_unit.v): claim set at 795-804 on first M sample, never re-examined;
  N_WAITCL 881 only claimed && o_last && dmo==0 -> N_DONE 818-822 writes caller<-trunk BSY.
  port.v: release only on fall of fM/fE, which arm after T_ARM. Caller listened to 00 during flood,
  so after N_DONE caller's E = trunk M; if trunk M already 0, fE never rises -> no release edge.
  baseband_card: link down -> a_tx 0 and word NONE (trunk released by its own fM fall after T_REL).
  mini_marker refusal keeps CLM=1 (so a far refusal is NOT a trigger).
- Auditor log run_s2_5.log S4 matches the claimed sequence (A wr dst 20 src 11 at 4786, A22 seizes 11 at 4856, A20 follows B20 4/4).
- Wrote tb_c11.v (S4 = auditor's cut repro; S7 = hang-up-after-claim race sweep, B clock +bppm/boff), build.sh, run.sh; rtl_c11/net_unit.v = snapshot + ONLY the auditor's lost fix (fix c).
- Other triggers reasoned from RTL: glare + far origin abandoning (far caller hangs up / dials own code -> O_LOCAL drop / 8,9) drops the "claim" (far caller's hook) for > T_REL -> same stranding, NO fault needed but glare is rare (last free channel). Transit: a cut on either side of a transit also drops A at origin. Far refusal/busy keep CLM=1 -> not triggers. Far B writes that clear CLM happen only on B's r_gone (i.e. after A side gone).
- C17 (nogo-after-release) is the hazard the auditor's fix leans on: r_gone lags the caller port's own release 0-1 ms; the fix's NOGO must come after r_gone. S7 sweeps that race.
- rtl_alt/net_unit.v: 16-pass persistence + N_DONE gated on lost==0 (alternative, closes late window).
- 2026-09-26 ~17:30: sim slots saturated by load workflows (29 waiters). Killed my 3 single-step waiters; queued job1.sh (snap S4+S7, alt S4+S7, tb_net alt) and job2.sh (c11 S4+S7, tb_net c11). Progress lines go to progress.txt; logs c11_snap.log, c11_alt.log, c11_fix.log, net_c11.log, net_alt.log.
- Timing analysis (RTL counts): after a caller hang-up at u (probe update at A20's turn), r_gone = ceil_A(u)+32 ms (pulse_rx t==CLR-1 at 32nd tick); the claim's drop reaches A at ceil_B(u+~0.2)+31 +0.125..0.25, seen at A11's next turn. So one-sample fires up to ~1.75 ms BEFORE gone (auditor saw ~0.85 ms), four-sample >= ~1.2 ms AFTER gone -- only because the port's T_REL (counter here, RC-and-'14 on the board: port.v) equals CLR (register counter). A far/transit port whose RC runs a few ms fast puts the claim drop before gone -> NOGO onto a released caller (C17 class).
- Planned: c11 (P=4) vs alt (P=16 passes at scale = 128 ms real; N_DONE gated on lost==0) with ports' T_REL 26 vs CLR 32 (-19%, RC tolerance) in S7. alt at P=16 also ignores 12 ms bench dial breaks, so glare (tb_lfull 5) should stay "joined" as documented.
- Jobs reorganised: lib.sh step(); job1 snap+alt tb_c11 (+trel26), job2 c11 tb_c11 (+trel26), job3 tb_net+tb_lfull c11, job4 tb_net+tb_lfull alt.
- Line cites check out (794-804 claim, 818-822 N_DONE, 881 N_WAITCL). Old network.md 3 says "The claim is a level, not a wink" -- the RTL takes it as an edge; the finding is a departure from the spec's own principle. New network.md 4.1 has no claim-loss row; §10 lists "a cut during a dialled call" as Not run.
- Real timers: mechanism has no timer race; only needs claim lost >= T_REL (256 ms) between claim and N_DONE (+T_ARM after). Scale-8 run represents it; not re-run at real timers (does not decide anything).
- ~18:40: all 4 jobs still queued (33 waiters, load sims hold all 5 slots with multi-hour timeouts).
- 19:26 job4 got a slot (net_alt). Rewrote job4 tail in place: net_alt -> c11_snap -> c11_fix -> lfull_alt; job1 now c11_alt + c11_alt_trel26; job2 c11_fix_trel26; job3 net_c11 + lfull_c11.
- net_alt (tb_net on rtl_alt): 88 checks, 0 errors, PASS (net_alt.log)
- c11_snap.log (snapshot, +bppm=100): S4 REPRODUCED: A nst 5 kept through cut, N_DONE wrote A20<-A11, A20 BUSY; A22's call took A11; "A22 follows B20 4/4; A20 follows B20 4/4" FAIL (listen-in). S7 (no fix): claim drop seen at A 0.844 ms BEFORE r_gone in 10/12 phases, 0.156 ms after in 2/12 (quantised by A11's 1 ms turn); so a 1-sample fix would NOGO before gone; 4-sample margin ~2.16 ms at T_REL==CLR.
- c11_fix.log (auditor fix alone): S4 closed (A nst 5->7 at 463.161, 4 ms after the cut; A wr dst 20 src 03: caller hears NOGO; A20 follows B20 2/4 ok); S7 12/12 gone first, no NOGO on released A20: PASS 19/19. Appended trel26 runs + c11_alt to job4 (after lfull_alt); lib.sh step() skips tags already started.
- lfull_alt (tb_lfull on rtl_alt): 40/40 PASS, glare provoked at try 0 and the documented 'residual glare joins the two callers' checks still pass (P=16 > 12 ms bench breaks).
- c11_fix_trel26.log (auditor fix, ports T_REL 26 vs CLR 32 = an RC detector ~19% fast): 12/12 trials FAIL: claim low at +25.9..27.8 ms, fix N_DROP 3 ms later (+28.9..30.8), NOGO written onto A20 at +29.3..31.2, AFTER A20 released itself (26 ms) and BEFORE gone (32; gone never rose: the NOGO released the register) -> A20 LEFT BUSY on-hook every time. At real timers the 4-sample margin is still ~2.2 ms absolute (quantisation does not scale), i.e. <1% of T_REL=256: the fix is only safe if every port RC releases no faster than CLR - 2 ms.
- c11_alt_trel26.log (alt P=16, ports T_REL 26): 12/12 PASS; claim low +25.9..27.7, gone +32.8..33.7 first (margin to the fix ~9 ms), no NOGO on A20.
- net_c11 (tb_net on auditor fix alone): 88/88 PASS.
- c11_alt.log (alt P=16 + gated N_DONE, nominal T_REL): S4 closed (A20 NOGO, follows B20 2/4), S7 12/12 ok: PASS 19/19.
- lfull_c11.log (tb_lfull on auditor fix): 40 checks, 2 errors: "B21 hears A31" and "A31 hears B21: residual glare joins the two callers" FAIL -- the fix turns documented glare (network.md §5) into two cannot-completes, as the auditor said. lfull_alt stays 40/40.
- VERDICT: confirmed, medium; one root cause (claim latched as an edge at net_unit.v:795-804, N_DONE at :881 not conditioned on the claim level). Auditor fix closes the hole and passes tb_net, but relies on a ~2 ms absolute margin that a fast port RC (T_REL < CLR - ~2 ms) breaks (12/12 callers left BUSY), and breaks tb_lfull 5. Recommended: persistence ~T_REL/2 (16 passes at scale, 128 ms real) + gate N_DONE on lost==0: S4 closed, S7 ok at T_REL 32 and 26, tb_net 88/88, tb_lfull 40/40.
