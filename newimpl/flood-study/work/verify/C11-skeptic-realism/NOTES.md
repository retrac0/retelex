# C11 claimed-trunk-loss -- skeptic review, lens REALISM AND SEVERITY

Read-only review of the auditor finding + verifier verdict. Snapshot only.

## Results as they come
- started 2026-09-27; read findings JSON + verifier NOTES/progress.
- RTL re-read (snapshot): net_unit.v:795-804 claim latched once; :881 N_WAITCL->N_DONE ignores claim level;
  :818-822 N_DONE writes caller<-trunk bsy1. port.v:147 busy = bsy|fe|(fm&!m); :176-193 release only on fM/fE fall.
  Dead trunk: fM falls T_REL after claim loss -> latch cleared; but its E was the caller's M (=1), so fe keeps it
  BUSY another T_REL: huntable ~2*T_REL after the loss (verifier says T_REL; minor).
- mini_marker far writes: att_refuse :326 clm1; NOGO :370/:407/:437/:450/:477 ctx_clm; connect :488-489 ctx_clm;
  only r_gone writes (:400,:470,:500) clear CLM. Verifier right: far refusal/busy/NODIG are not triggers.
- Links: baseband tie = 5 conductors, link-down = far TX_CLK absent ~3 frames -> A=0, word NONE. local_trunk same (+MUTE_BLK).
  So a >=256 ms interruption = pulled/loose cable, far/transit power loss, card reseat; any far/transit RESET of any
  length (latches cleared -> CLM gone for good). MF8 relock is 5-26 frames (ms): C07 territory, not C11.
- Snapshot log c11_snap.log S4 re-read: matches (A20<-A11 at 789, A22 takes A11 at 859, 'A20 follows B20 4/4').
- Window claim->last digit: new network.md 4.3 worked example 3311->5828 = 2.5 s; range ~1.8-3.6 s at 0.8 s pauses.
- Traffic (topology.md/traffic.md): 3 calls/line/h, 20-50% leave; 24-45 lines -> ~15-65 net originations/exch/BH.
  Exposure: ~1-5% of the BH an exchange's originations are in the window; element carrying several origins 3-10%.
- Fault path: per >=256 ms interruption/reset of an element in the BH: ~3-10% chance of one strand.
  At 1 such fault/element/month -> ~5e-5..1.4e-4 strands per exchange-BH (years apart).
- Glare path: P(exactly one free) Erlang ~1.0% (1.38 E on 6), ~1.6% (5.63 E on 12); per-link flood seizures ~0.12/s
  each way in the 24-line/20% reference net (867 net calls/h, every call floods every link); blind window 3-10 ms
  -> ~0.005-0.02 glares/link/BH; 10-30% of glares strand one side (other side hangs up, dials own code = O_LOCAL,
  8/9, 5 s rule) -> ~5e-4..6e-3 strands/link/BH. Small nets ~100x less (rate^2). Baseline glare already joins
  two strangers (documented, network.md 5), so glare-strand's marginal harm is modest.
- Listen-in | strand: dead trunk was the origin's first choice, so the next flood from this exchange (or a
  transit forward) takes it; needs a seizure claimed that way and ringback before the stranded caller quits
  (~10-20 s patience; after ringback appears they stay on). Estimate 5-20% at BH, not 'likely'.
- Dial-break envelope: register.md 1 designs for 7-12 pps 56-72% -> longest break 102.9 ms (not 'about 70 ms'
  as the verifier wrote). Bench breaks 12 ms at scale = 96 ms real, so tb_lfull 5 already tests near-worst.
  128 ms persistence clears it by ~25 ms.
- RC spread of the '14 detectors: NOT MEASURED (fabric.md 8). 74HC14 VT- spread alone gives ~0.7x-1.4x of nominal
  discharge time. Claim drop at origin after a caller hang-up = min over the path's incoming-side ports' RC T_REL
  and the owner's CLR -> multi-hop paths sample the fast tail.
- Persistence bounds (real): > 103 ms (keep glare joined); > CLR - T_REL_min(path) + ~2 ms (gone must win);
  < ~2*T_REL_min (dead trunk BUSY via fE until then; N_DROP must not hit a re-hunted trunk). 128 ok to ~45% fast RC.
- Verifier's 'shorter ~40 ms, still above the RC skew' is WRONG at its own tested skew: 19% = ~49 ms real (6 ms at
  scale); 40 ms real = 5 passes at scale < 6 -> would fail c11 trel26 S7 like the auditor's.
- Auditor's 4-sample fix at real hardware: stuck-BUSY needs far RC < CLR-~2 ms AND the caller's own RC < fire time;
  not 'every' abandon (bench set all ports equal), but a large fraction of post-claim abandons (a few % of net
  calls) -> order 0.1-1 stuck lines per exchange per BH: far worse than C11 itself. Reject.
- No sim run needed: disagreements are arithmetic.
- rtl_alt diff checked: lost counts sp samples of `trunk` while claimed in N_NET/N_WAITCL, sat at 16; NOGO after
  o_gone and the guard-break check; N_DONE gated on lost==0. rtl_c11 = same with 3 bits, fire at 4.
- VERDICT (realism lens): confirmed, MEDIUM (agree). Triggers are a spec-named event (cut during a dialled call,
  far/transit reset) or glare + far abandon; per exchange per BH ~1e-5..1e-3 strands at plausible fault rates,
  glare adds ~5e-4..6e-3 per link-BH in the reference network (much less in small nets); 5-20% of strands become
  a one-way listen-in. Stranded caller: silence, no tone, BUSY to incoming, clears on hang-up. Not a silent wrong
  number to the caller; a silent privacy leak for the overheard pair.
- FIX: verifier's alt is the right shape and 74HC-cheap ('4040 on TICK reset by each high sample, Q8=128 ms, like
  the register's own timer; half a '74 for last-sample-high; origin's d_trunk comparators reused). Corrections:
  dial-break bound 103 ms; 40 ms option unsafe; RC spread unmeasured -> state the margin or take C17's CLR fix;
  optional post-connect watch closes the ~T_ARM residual; add a 'claim lost' row to network.md 4.1.
