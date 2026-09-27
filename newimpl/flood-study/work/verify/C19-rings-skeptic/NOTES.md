# C19-rings skeptic review (read-only) -- notes as I go
- Read C19-rings.json, verifier NOTES, net_unit.v (all), mini_marker att logic, new network.md s7, tb_ring4r.v, logs.
- Cited lines check out (283 cls_seen, 505 fwd_mask, 616-618 fwd gate, 794-804 origin first-M, 849 h_mask 1111).
- F1 refinement: with NMON=2 the lap-2 copies are UNMONITORED at the exchange after the origin (both cells hold
  the lap-1 CW and CCW copies until e ends, >=580 ms). Oldest MONITORED copy at a non-origin = N-1 hops, same as
  the strapped chain. At the origin a miscounted returning copy can only claim the origin's own code, whose
  register is busy -> refused. => late-copy wrong number is not a ring effect at all (it is C05's guard reach).
- F2: verifier's commissioning criterion "exactly one claim at the owner" FAILS the documented design for calls
  between the two strapped ends (its own tb_ring4 BOTH control: Y claimed twice, 12/12). Must exempt those / use
  third-exchange calls. Discriminator: origin at the STRAPPED end sees its own flood back; the unstrapped end's
  calls look normal -> test from both ends.
- F2 collateral not in verifier: each X call takes BOTH monitor cells (NMON=2) at every ring member until e ends,
  so a concurrent flood for that member goes unwatched -> N_TCLAIM cannot-complete for OTHER subscribers.
- F2 interaction: refused copy's claim M landing on a trunk the origin just dropped -> C18 phantom seizure
  (already C18's finding; ring double delivery feeds it). Not seen in the verifier's 4 real/s8 logs.
- Race odds (reasoning): equal paths ~10-25%/call (claims 0.4 ms apart vs 2x U(0,1) ms backward jitter);
  1-hop difference a few %; >=2 hops ~0. Verifier's 1/6 fits.
- The strap is a jumper on the net_unit card beside e b: a card swap loses it silently -> after-maintenance test.
- CORRECTION to the C18 interaction above: port.v:148 busy = bsy || fe || ...; a dropped origin trunk stays BUSY
  for T_REL via fE, so a second claim landing within T_REL is M-under-BUSY -> st set, no phantom (C18 skeptic found
  the same). F2 feeds C18 only if claim 2 is delayed ~T_REL (claim 1 waiting out S_WATCH). Not a wrong number.
- C02 path checked: with claim 1 waiting in WATCH, the origin keeps copy 1 (its CLAIM M precedes att), drops copy 2;
  claim 2 (if written before its cell's CLR) gets the register on a dead copy -> cannot-complete. No wrong number.
- Drop-then-reseize worry: closed by the same fE hold (C20 release-margin-thin covers the carrier margin).
- Commissioning-criterion flaw confirmed from the verifier's own logs: jobC_both.out 'claims X0 Y2' in 12/12,
  owner_refused=07 every run; hub G2 notes the same for B<->C. The hub control pairs never include B<->C.
- F1 at light load is quiet (hub G1: 5/5 OK), so it can persist until the busy hour (G3 0.11 E vs G4 0.47 E).
- Race bursts: outcome set by site scan phases; relative drift 1 ms per 1000/dppm s (25 s at 40 ppm, 250 s at 4).
- No simulation run. Verdicts: F1 confirmed-overstated low (agree); F2 confirmed-understated low (agree).
