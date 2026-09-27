# C19-rings verification notes

## Reading (RTL snapshot)
- net_unit.v:84 STRAP_N param; :505 fwd_mask = ~STRAP_N & ~(1<<cls_dir); :616-618 forward only if !STRAP_N[cls_dir] and fwd_mask!=0.
- origin: net_unit.v:849 h_mask <= 4'b1111 -- origin seizes every direction, strapped or not. Confirmed.
- no hop count, no loop detection anywhere in net_unit.v (grep).
- Prior evidence (hub load study, work/load/hub/NOTES.md G1-G4, s8, snapshot RTL): triangle A-B-C + spoke D.
  G1 unstrapped: every call circulates; stops only on BUSY-FWDR (s8 artefact), BUSY-NORES, nomon; owner claims TWICE
  every call, direct copy's claim first (0.3-1 ms), 2nd refused (03); no wrong number. G3 unstrapped under load:
  units exhausted (A 79 seizures vs 42), N_TCLAIM 20 losses, no wrong number. G2/G4 both-ends strap: double
  delivery only between the strapped ends. => finding 1's "bounded only by resources" is already reproduced (s8).
  NOBODY ran a ONE-END strap.
- 22:5x launched jobA (tb_hub1.sv = hub bench + HUB_STRAP1: L1(B)'s E strapped only) and jobB (control, obj_ringst,
  both ends), same pairs B20D21,B22A21,D22B23,C23D24, gap 1500, dur 12000 (each pair twice). Logs run_r1_onestrap.log,
  run_r2_bothstrap.log.
  Prediction (RTL reading): one-end at B: B->D and B->A delivered twice (D, A claim twice); D->B delivered twice at B
  (NEW: calls TO the strapped end, from anywhere, double at it -- auditor missed); C->D once. Both-ends: all once.
- 23:0x launched jobC_one / jobC_both: tb_ring4.v (own bench: 4-ring X-Y-Z-V on baseband ties, s8; L=X-Y strapped at
  X only (default) or both ends (+define+BOTH); X's L trunks on block 0 (04,05), its other ring trunks on block 7
  (74,75) so the origin samples the two ways ~0.9 ms apart). one: X20 -> Z21 (opposite member; the auditor's case),
  both: X20 -> Y21 (between the strapped ends: the DOCUMENTED design's double delivery). 6 phase sets each (site
  reset offsets + dial offset). Purpose: is the claimed "refused copy can win by a millisecond -> cannot-complete"
  reachable? Logs run_r4<cfg>_b<B>_p<i>.log, summary jobC_<cfg>.out.
## Analysis (reading), before sims
- F1 (unstrapped ring): mechanism right. No hop count / origin identity exists in a pulse flood (the trunk carries only
  C and A), so nothing can recognise a returning flood; STRAP_N is the only breaker. Bound at REAL timers (no
  BUSY-FWDR there, per C14 verifier / hub study): each exchange forwards the first NRES copies; in a ring of N with CW
  and CCW copies, lap 1 of both uses both resolvers everywhere, so lap-2 copies die one hop into lap 2:
  longest copy path ~N+1 hops (N+2 from a spoke). Latest copy age ~ (N+1)x13 ms + ~2x19 ms (T_ARM watch serialising
  simultaneous arrivals). First break of e at a CONFORMING dial (720 ms IDP) comes >= ~580 ms after the seizure,
  so a lap copy is late only for N >~ 40. "Rings of about 8" assumes the caller breaks at the 128 ms guard edge
  (IDP ~267 ms: non-conforming). => wrong-number sub-claim overstated; resource burn + double claims real.
  Minor: monitors are not held "until the claim" -- a cell frees at the e (or b) mismatch.
- F2 (one-end strap): RTL confirms (616 no onward from strapped; 505/618 never into strapped; 849 origin h_mask 1111).
  Hand trace, ring with L=X-Y strapped at X only: (a) X's calls: every ring member (and spokes behind them) gets two
  copies [auditor]; (b) NOT in the finding: every call from ANY exchange TO X arrives at X twice (Y forwards into L,
  X holds it on its strapped port and its cell claims) => double claim at X for all incoming network calls;
  (c) calls from Y: X twice (same as both-ends). New network.md §7 now says "Strap both ends" but gives the old
  reason ("the other floods into a link that goes nowhere"), which misses (a) and (b).
- The consequence "refused copy can win" = origin takes the FIRST M sample (network.md 4.1), owner gives the register
  to the FIRST cell claim; both quantised to 1 ms scans (port bit-time p/64 ms) and the fabric crossing of A at each
  transit (0-1 ms); the claims are ~0.3-1 ms apart. Where the two orders disagree the caller gets the refused copy
  (03) and the register copy is dropped: cannot-complete, never a wrong number. tb_hub's triangle cannot show it
  (phase gaps ~0.25 ms < claim spacing); tb_ring4 is built to.
## RESULT jobC_one (tb_ring4, one-end strap at X, X20 -> Z21, s8; 6 phase sets) -- runs 56-66 s wall each
- EVERY run: Z (opposite member) classified TWO copies (Z11 via Y, Z14 via V), claimed twice: 11 TAKEN, 14 REFUSED.
  X's own flood also came back to X (X SEIZE 75, NOFWD-EMPTY) -- the auditor's double delivery CONFIRMED.
- p1-p4, p6: X kept 04 (the register copy): call rang.  p5 (dx670 dy20 dz540 dv180 dd830): Z CLAIM 11 at 390.545,
  CLAIM 14 at 390.969 (0.42 ms later, same-tick cells), X ORIGIN TAKES claim on 74 (the REFUSED copy) at 391.628:
  Z21 never rang, X20 hears 0 (03 cannot-complete). => "refused copy can win" REPRODUCED, 1 of 6 phases, in a
  geometry chosen to open the window (X's two ways sampled 0.9 ms apart). Race window is wiring timing (claim
  spacing via cable B + att, tick/scan 1 ms, fabric crossing 0-1 ms), none of it scaled -> same odds at real timers.
- All idle after; clash 0.
## RESULT jobC_both (tb_ring4 +define+BOTH, X20 -> Y21 between the strapped ends: the DOCUMENTED design; 12 phases)
- 12/12 rang; Y claimed twice every time (04 direct TAKEN, 07 long way REFUSED); X kept 04 every time.
- The long copy's pulses cross two transit fabrics (0-1 ms each) on the way in, so its cell reached b a tick or two
  later in 11/12 (second CLAIM 1-2 ms after the first; X had already taken the direct claim before it was written).
  p12: both cells in one tick (claims 0.29 ms apart) -- X still took the direct one.
  => with both ends strapped the direct copy (1 hop) reliably beats the long way even in the adverse geometry; the
  one-end strap turns this into double delivery between EQUAL paths, where the race is live (jobC_one p5).
## RESULT jobB (control: hub triangle, obj_ringst = both ends strapped, s8), run_r2_bothstrap.log, 1769 s wall
- pairs B20D21, B22A21, D22B23, C23D24, each twice: 8/8 OK; claims A2 B2 D4 = ONE claim per call (no double
  delivery anywhere: B's calls reach A and D once, D's calls reach B once). INVARIANT 50/50, safety all 0.
## RESULT jobD (tb_ring4r = tb_ring4 at REAL timers: T_ARM16 T_REL256 HIT8 ID128 CLR256 GUARD128 KEY5000 CLAIM2000;
##   dial 10 pps 60/40, 720 ms pauses; one-end strap; X20 -> Z21), run_r4real_b4_p5.log, 322 s wall
- p5 phase set at REAL timers: Z CLAIM 11 at 2760.538 (TAKEN), CLAIM 14 at 2760.963 (0.425 ms later, REFUSED);
  X ORIGIN TAKES claim on 74 (the refused copy) at 2761.622; Z21 never rings (hi 0/1500), X20 hears 0.
  => the cannot-complete from one-end double delivery is reachable at real timers with conforming dialling.
- At real timers every copy is forwarded (no BUSY-FWDR): Y, Z, V forward 2 each; X gets its own flood back twice
  (X75 via V, and X05 on its strapped E via Y); Z's second copy 32.7 ms after the first.
- jobD p1 (control phases, REAL): cells a tick apart (2759.998 / 2760.998), X took 04: rang -- same as s8 p1.
## RESULT jobA partial (hub triangle, tb_hub1 +HUB_STRAP1: B's E strapped only, s8), run_r1_onestrap.log
- B20->D21 (from the strapped end): D classified D10 (via A) and D11 (via C->A), CLAIMED BOTH (419.984, 420.275);
  A got A17+A37, C got C30+C10; B's own flood came back on B10 and on its strapped B37. => every member twice.
- B22->A21: A claimed A17 and A37 (1838.0, 1839.0).
- D22->B23 (a call TO the strapped end): B classified B10 (via A) and B37 (via C, on its strapped port), CLAIMED
  BOTH (3378.664, 3379.664). => the extension (b) CONFIRMED; the auditor's finding missed it.
- C23->D24 (from the unstrapped end): D once (single claim). Control as predicted.
- Calls completed OK so far (origin took the first claim, the direct/register copy).
## RESULT jobA final (run_r1_onestrap.log, 1788 s wall): 8/8 OK, INVARIANT 50/50, safety 0.
- claims A4 B4 D6 = 14 for 8 calls (both-ends control jobB: 8 for 8): every call from or to B (the strapped end)
  was claimed twice; C->D once. Forwards A12 C10 (control A8 C0). No flip in this triangle (phase gaps ~0.25 ms).
## VERDICTS
- F1 unstrapped ring: confirmed-overstated (low). Circulation + resource burn + double claims real (hub G1/G3, s8;
  real timers forward even more). Late-copy wrong number needs ~40+ exchanges at conforming dial timing.
- F2 one-end strap: confirmed-understated (low; misconfiguration). Double delivery of the strapped end's calls
  everywhere reproduced (tb_ring4 6/6, hub 4/4); ALSO every call TO the strapped end double at it (hub 2/2, not in
  the finding); the refused copy won the origin in 1/6 phases -> cannot-complete, at s8 AND at real timers
  (tb_ring4r p5). Both-ends control: 12/12 + 8/8 fine.
- One root cause: no identity/hop count in a pulse flood; STRAP_N the only breaker; duplicates resolved by two
  independent first-come races (owner register, origin first M sample).
- All obj dirs deleted.
