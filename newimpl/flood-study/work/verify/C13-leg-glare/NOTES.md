# C13-leg-glare verification notes
(started 2026-09-26)

## Plan
- tb_fx (fwd auditor's bench, copied to verify dir with sc7 "late far M" variant and an arming monitor on B's probe)
  build obj_fx from snapshot RTL; run sc3 and sc7 dly=500/1000/1500
- tb_pchain sc=1 +trace on snapshot (collapse)
- F3 fix (origin re-checks claimed trunk's M until N_DONE) in rtl_f3/net_unit.v; tb_pchain, tb_chain, tb_net(, tb_lfull)

## Queue (sim.sh; ~40 jobs waiting at 16:40)
- job_fx.sh: build tb_fx (snapshot) + sc3, sc7 dly=300us, sc7 dly=1200us  -> run_fx_*.log
- job_pchain.sh snap / f3: tb_pchain +sc=1 +trace  -> run_pchain_{snap,f3}.log
- job_f3reg.sh: tb_chain + tb_net on F3 copy -> run_f3_{chain,net}.log

## Arithmetic (residual-glare-rate)
- Auditor's rates = P1*lamX*lamY*2D with an EXTRA x2 (reproduced all their numbers only with the x2).
  Pair rate for |tX-tY| < D (window D_X+D_Y = 2D) has no extra 2 -> rates overstated 2x:
  2ch: 0.2E 1/4016h, 0.5E 1/342h, 1.0E 1/66h ; 8ch: 2E 1/1915h, 4E 1/27h, 6E 1/5h, 8E 1/2h.
- D ~ 0.5 (rest of confirm pass) + 0.156 (WAIT) + 0.133 (word) + 0.5 (E capture) + 0.031 (card) = 1.32 ms: agree.

## Reading (done)
- net_unit.v resolver watch 682-690: R_LEG on ANY sp_m on a held leg; w_res 691-706 drops other legs, writes way back (non-rs_two).
- F_WRITE 725-744: one leg (rs_two) -> in-port patched both ways AT FORWARD TIME -> upstream origin sees the leg's M directly.
- origin claim 795-804: first M on a held trunk = claim; glare counted only if `guarding`. No check after claim.
- w_claim 654-668: in-port -> 00 + CLAIM; drops legs of rs_mine only (resolver freed at R_LEG in rs_two -> none).
- port.v: E fall (re-point from a source with M up to 00) -> fE falls T_REL later -> port clears (incl. CLM).
- Docs: new network.md s5 "At a transit a glared leg is its resolver's claim; not run"; decisions.md: glare taken as claim + joined is a DECISION.
  counters.md: glare "never on a tie or at a transit" measured.
- Monte Carlo (baseband, no carrier delay): of transit glare events ~51% have a B-probe sample of the leg with BUSY 1, M 0
  before the far M -> fwd auditor's "armed leg" fix misses ~half; with a carrier delay > ~1 ms it misses ~all.
- F3 (origin: claimed trunk's M falls before N_DONE -> NOGO) is a catch-all: glare M is the stranger's hook, which breaks
  when the stranger dials; a real claim is a steady CLAIM (a_rx = e||clm). Caveat: single-sample; debounce ~HIT for MF8 bit errors.

## F3 revised -> F3' (before any job started, 18:25)
- C11 verifier (work/verify/C11-claimed-trunk-loss/NOTES.md) found a ONE-SAMPLE "claimed trunk M low -> NOGO" races the
  caller's own hang-up (far port's T_REL == register CLR): NOGO written onto a releasing caller, left BUSY.
- So rtl_f3/net_unit.v is now F3': abandon only if the kept trunk's M is low >= 4 samples AND THEN RISES again before
  N_DONE (a stranger's dial break; a release never comes back). Hang-up -> no rise -> gone handles it. Cost: 3-bit
  counter + 1 FF + comparator already there.
- 18:42 job_pchain f3 got slot 5; F3' build rc=0 (141 s)

## RESULT run_pchain_f3.log (F3', tb_pchain +sc=1 +trace, scale 8) -- 361 s
- pass 1 (collapse case): glare at try 0 as before; C20's first break ends 2192 -> A abandons 2193.156 (A20 -> 03
  cannot-complete), C abandons 2194.156 (C20 -> 03); B11/B14 release 2226; B's monitor never claims. Clean double
  cannot-complete instead of both callers latched to released trunks (snapshot: A20->11, C20->11 dead).
- pass 0 (stranger departs: C's guard abandon, steady fall): F3' does NOT fire (no rise) -> A20 -> 11 dead as on
  snapshot. That branch is C11's claimed-trunk-loss; needs C11's steady-low abandon (with the gone race handled).
- The "B21 hears A20" oks are false passes (B21 off-hook hears dial tone), as the auditor said.
- 20:03 job_f3reg got slot 5
- F3' tb_chain: 32 checks, 0 errors PASS (base 32/0) run_f3_chain.log
- F3' tb_net: 88 checks, 0 errors PASS (base 88/0) run_f3_net.log (1102 s). objs deleted by job.
- 21:57 job_pchain snap got slot 2
- RESULT run_pchain_snap.log (snapshot, +sc=1 +trace, 270 s): 18 checks 4 FAIL, trace compared to auditor's
  work/audit/proto/run_pchain_trace.log (see diff line below). pass 1: B11 -> 0 clm 1 at the claim, B11 released 33 ms
  later, then A11, B14, C11; A20 -> 11 and C20 -> 11 on released trunks. Confirmed.
  diff vs auditor trace: IDENTICAL

## RESULT tb_fx (snapshot, REAL timers) -- 22:25
- run_fx_sc3.log: identical to auditor's run_fx_sc3.log (only my VERIFY lines added). 8 checks 4 FAIL. Leg NOT armed
  before M (far M rose 41.630, before B's write 42.424) -> the fwd auditor's armed-leg fix WOULD catch sc3.
- run_fx_sc7_d300.log: far M 300 us after B's leg write. B's probe sampled S40 BUSY 1 M 0 at 42.521 (97 us after the
  write) = ARMED; then M -> R_LEG at 43.521, legs 74/10 dropped, 30 -> 40 at 44.073: joined, n_glare 0.
- run_fx_sc7_d1200.log: same, armed, joined, uncounted.
=> the armed-leg fix misses glare whose far M lands after the leg's first BUSY turn (~51% at baseband by MC; ~all with a
   carrier delay), and does nothing for a one-leg forward (way back patched at forward time).
All obj dirs deleted by the job scripts.
