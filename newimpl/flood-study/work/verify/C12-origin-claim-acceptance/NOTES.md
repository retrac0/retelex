# C12-origin-claim-acceptance verifier notes (2026-09-26)

## Code reading (snapshot rtl/net_unit.v)
- 794-804: `if (o_net && sp_fresh && sp_m && !claimed)` over d_held trunks -> claimed, trunk, dmo = others.
  o_net = N_NET | N_WAITCL. Nothing checks f2 (b counted); `guarding` only picks glare counting.
  One probe sample (1 ms pass) of M suffices; M is never re-checked (C11). CONFIRMED by reading.
- Claim in N_NET is kept through f2 (866-873): N_WAITCL, then N_DONE at o_last (881). So an early
  claim goes through to connect. Spec (new exchange/network.md 4.1 table) says the same:
  "claim  the FIRST M seen on a held trunk" -- RTL matches the spec; the spec itself (6) says
  "a claim needs two more digits, so M on a held trunk inside the guard is glare" but draws no
  consequence for M outside the guard before b.
- Legit claim latency vs origin f2 (reasoning): far ID starts from the same make, seen ~0.3 ms later
  (fwd path) +/- 1 ms probe phase at each end; return path CLAIM word (UREQ wait 156 us + 17 bit-times
  265 us) + port frame + card 2-FF sync + origin probe turn (0-1 ms). Estimate: claim seen at origin
  f2 -0.5 .. +3 ms. To be measured (instrumented fix copy, tb_net/tb_chain).
- Transit resolvers (net_unit 686-692) have the same one-sample, any-time acceptance (R_LEG) --
  not in the finding; an early claim through a transit still reaches the origin before b, so an
  origin-side check covers finding 1 for transits too; a glitch on a transit leg (finding 2) does not.
- Carriers: baseband A = RC + '14 + 2 FF at frame edge (no data errors; an impulse over the Schmitt
  threshold). local_trunk: A is a clocked bit, NO RC (local_trunk.v:30-33): one bit error = one
  frame of A=1, sampled by the port's 1 ms turn 1 time in 8. Slips repeat/drop a bit: cannot make a
  1 from a steady 0.

## Sims queued (jobS/jobF1/jobF2 via sim.sh; progress.txt)
- rtl_fix/net_unit.v (fix.patch): ONE small change covering both findings: the claim is M standing
  N_CL=4 samples on the first-risen held trunk (cl_n 3 bits, cl_j 2 bits); if it stands before b
  (f2=0) and did not rise inside the guard (cl_g latched at the rise), `early` -> nogo; inside the
  guard -> glare as before; after b -> claim. C12_TRACE prints rise/accept/f2 times (lead of legit claims).
- tb_c12.v (NEW, real timers): Y(31)-A11 A(22) A12-X(13); A20 dials 1 3 1 2 1 (Y21).
  S1 control; S2 1 ms A=1 glitch on A12's receive wire between e and b (finding 2);
  S3 A=1 held on A12 from 300 ms after e (finding 1, stand-alone early claim).
- jobS: tb_c12 + auditor tb_mc2 on snapshot. jobF1: same on fix. jobF2: tb_net, tb_chain, tb_lfull on fix.

## Results
- c12_snap.log (SNAPSHOT, real timers): S1 control PASS (f2 at 2792, Y's reg 2793, A claimed 2794:
  legit claim seen 2 ms AFTER f2). S2 REPRODUCES claim-on-one-sample: 1 ms of A=1 on A12 at 11105
  (outside guard, before b) -> A claimed trunk 12 in N_NET, dirs 1100 -> 1000 (A11 toward the owner Y
  dropped), done A20<->A12 at o_last (13695), Y never claims, Y21 not rung; 3 FAILs. All idle after
  hang-up (no stuck state). S3 REPRODUCES origin-accepts-early-claim stand-alone: A=1 held on A12 from
  300 ms after e -> claimed 20108 in N_NET (b at 20797) -> A20 connected to A12 (X claimed nothing) at 22697.
- mc2_snap.log (auditor tb_mc2 on SNAPSHOT, real timers): IDENTICAL to work/audit/monclaim/run_mc2.log
  (apart from walltime lines): X claims at 1894, A claimed=1 at 1895 in origin state 4 (N_NET), b at
  2893 (state 5), X22 rung 3894, done 4793; 3 FAILs.
- net_fix.log (tb_net on rtl_fix, C12_TRACE): 88 checks, 0 errors, PASS. 7 legit claims at origin 22:
  every one rose 2.156-2.172 ms AFTER f2 (direct neighbour, baseband), accepted 3 ms later; 0 EARLY.
- chain_fix.log (tb_chain on rtl_fix): 32 checks, 0 errors, PASS. Legit claims rose after f2 by
  +4.16 ms (22, two hops), +4.17 ms (24, two hops), +2.17 ms (23, one hop); 0 EARLY.
- lfull_fix.log (tb_lfull on rtl_fix, local trunk, glare): 40 checks, 0 errors, PASS. Glare still
  taken as the claim: both origins' rises inside the guard (tmr 2 and 0), accepted 3 ms later, the
  documented "joined" checks pass. Legit claims rose 1.14-2.25 ms after f2 (9 claims). 0 EARLY.
- Legit-claim lag after f2 over all three benches (lag.py): min 1.14 ms (local trunk), 2.16 (baseband
  neighbour), 4.17 (two hops). No legit claim ever came before b; 4-sample stand gives ~3 ms more slack.
- c12_fix.log (tb_c12 on rtl_fix): 12 checks, 0 errors, PASS. S2: the glitch gave ONE rise sample
  (11104, then low) -> ignored; Y claimed at b, A kept A11, Y21 rang. S3: rise 20107 (N_NET, tmr 1301,
  outside guard) -> EARLY at 20110 -> N_DROP, nogo at 20111; A20 never connected to A12; all idle after.
- mc2_fix.log (auditor tb_mc2 on rtl_fix): X's stale cell still claims at 1894 (C03 root untouched);
  A: rise 1894 (N_NET, tmr 1191) -> EARLY 1897 -> nogo 1898; X's register freed 2156 (CLR of the
  break); X22 NOT rung; A21 hears 0/0 (cannot-complete zeros), never X22. 8/9: the one FAIL
  "A21 is not talking to X22" is the bench artefact the C03 verifier found (the bench lifts X22
  anyway, X gives it dial tone, busy_x[22] && rx_a[21]==0 trips on NOGO's zeros).

## Verdicts
- origin-accepts-early-claim: CONFIRMED (mechanism, real timers). RTL matches spec's table ("the FIRST
  M seen"), so it is a hardening gap; no conforming trigger of its own -- it turns upstream miscounts
  that claim before b (C03 (1,e), C07 link hit before e at an e=1 exchange, glare past guard reach)
  into wrong numbers. Fix closes the (1,e) variant end to end (mc2_fix). Keep medium as 2nd line.
- claim-on-one-sample: CONFIRMED, low. Reproduced with an injected 1 ms A glitch (S2). Needs a carrier
  fault; local_trunk has no RC on A (1 bit error, 1 in 8 sampled). Transit resolvers' R_LEG has the
  same one-sample acceptance (not in finding, not fixed).
- One root cause: net_unit.v:795-804 takes one unqualified sample (no persistence, no order vs b).
