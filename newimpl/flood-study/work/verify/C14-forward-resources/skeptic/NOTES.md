# C14-forward-resources: independent skeptic review (mechanism + realism)
Read-only on the snapshot. Results appended as found.

## Mechanism re-derivation (snapshot rtl/net_unit.v)
- Forward admission only at the classifier's C_ACT write (:616-617): !STRAP_N[cls_dir] && fst==F_IDLE && rs_free_any
  && fwd_mask!=0. Only F_WRITE allocates resolvers (:737-741) and there is one forwarder, so a resolver free at
  classification is still free at F_WRITE (w_fwd's rs_free_any never fails). No retry, no queue. CONFIRMED.
- Resolver frees: R_LEG (M on a held leg), R_GONE (incoming BUSY clear), rs_mine (claim here). CONFIRMED.
- Release is NOT cascaded hop by hop: every leg listens to the incoming, so when the origin drops, M falls at every
  downstream incoming within ms; each port's fM falls one T_REL later in parallel. So R_GONE hold = claim + ~0.26 s
  at any depth (auditors' "+0.26 s" right).
- "Decided once" is REQUIRED FOR SAFETY, not an oversight: a leg written after the caller's first break gives the
  downstream monitors a rise mid-digit -> they count the tail of e as e -> wrong-number risk (monitor rule 1). So
  any retry must (a) drop on any M-low seen and (b) be bounded inside the guard's hop budget. The transit agent's
  pending slot does both (drops on !sp_m, PF_MAX 24 ms). A retry that waits for a RESOLVER (seconds) is unsafe.
  => the resolver half has exactly one remedy: stuffing (or cheaper resolvers).
- Forwarder-busy: classification spacing >= ~18.2 ms (C_HOLD 17-18 ms + read at the port's next turn ~1.1 ms),
  forward service 10-11 ms (port 1's turn <=1 ms + 9 ms sweep + 1 ms confirm + write). Only an ORIGIN sweep
  (F_WANT waits hst idle and nst!=N_WANT) can push the forward past the next classification. Other delays
  (classifier read mid-sweep <=2 ms, a marker select <=1 ms) cannot close a 7 ms margin alone.
  Window: 1st flood classified in ~[s, s+4 ms] of a local origin sweep start s, 2nd flood arriving within ~20 ms.
  Reference hub: 0.0058/s x (0.078/s x 4 ms) x (0.078/s x 20 ms) ~ 3e-9/s. 20 exch ~5e-8/s. NEGLIGIBLE (agree).
- Second forwarder-busy path found: C_UNHOLD (a seizure that dies inside T_ARM) frees the classifier EARLY, but
  F_HUNT ignores f_cancel until h_done (:720-724), so the forwarder stays busy for a dead flood's full sweep and a
  next flood classified then is lost (nf_busy). Needs a seizure dying within 16 ms of its hold (guard abandon by a
  non-conforming fast dialler, a link bounce) plus a 2nd flood within ~10 ms: rarer still. Not material.
- F_WRITE vs w_cls: w_cls has priority, and a classification landing on the forwarder's F_WRITE tick is nf_busy.
  Same spacing argument: unreachable at real timers without an origin sweep in front.

## Additional paths / corrections found
- RING STRAP DOUBLES MONITOR USE (new, not in the findings or the verifier): a seizure on a strapped direction is
  held and given a cell (:612-615 ignore STRAP_N), and network.md §7 says the two strap ends receive each other's
  calls twice. So one flood takes BOTH NMON=2 cells at a strap end. Evidence: C19-rings/run_r4both_b3_p1.log
  (both ends strapped, the documented design): Y SEIZE 04 (direct) and Y SEIZE 07 (long way) each with a cell,
  claims "want 01" and "want 10". Triangle A-B-C with A-C strapped: at A up to 3 concurrent seizures from 2
  sources (C twice, B once). A B->A call is unwatched whenever C's flood is in its cell window:
  ~0.012/s x 1.3-2.6 s ~ 1.6-3.1 % at design load, where a 3-chain loses 0. NMON=3 removes it.
- MONITOR HOLD depends on numbering: a cell is held to b's ID (~2.6 s, same as a resolver) when e matches. The doc's
  own worked chain 22-25 shares e=2 everywhere (network.md §4.3: "2 is every monitor's e"), and the reference
  network's leaves share e by hub (21-23, 31-33). So the verifier's "monitor load lower than the resolvers'" holds
  only for networks with distinct e; with shared e, 8 exchanges ~0.22 E, NMON=2 ~1.3-1.9 %.
- ONE-REGISTER BOUND: one origin bank per exchange => at most one pending flood per source exchange at any transit,
  so NRES >= (exchanges whose floods reach it) is lossless (3-chain, 3-leaf star ~1e-3). Also holds for NMON,
  plus one per strapped neighbour. Breaks when registers are pooled (C15 fix): then registers x sources.
- NEW network.md §10 is WRONG on the forwarder: "the one forwarder loses about the flood rate x 11 ms more". At real
  timers §3.3's own watch spaces classifications >= 18 ms > the 10-11 ms forward, so the loss needs a local origin
  sweep in front: ~1e-8/s, not ~0.1 % of floods. The rate x 11 ms figure is the scale-8 bench behaviour.
- PENDING-FORWARD FIX: safe (drops on M seen low, PF_MAX 24 ms) but buys ~nothing at real timers and makes that
  flood's hop up to ~50 ms (20 watch + 22 behind origin+forward sweeps + 11 own), past §6's 22-30 ms slow hop that
  the guard must cover. Not worth a board; fine for benches.
- CLAIM-TO-REFUSE unsafe for a more general reason than the verifier's: the origin takes the FIRST M on any held
  trunk as THE claim and drops every other direction (:796-800). A transit refusing in one branch kills a call
  whose owner is in another branch of the origin (or upstream on the same trunk path).
- OBSERVABILITY: nothing on the bus counts nf_busy/nf_empty/no-cell (n_nofwd is a bench port). The event word
  exists (w_ev, EV_NOTRUNK); counters.md §7 already asks for "a transit's congestion" code. Two flags + codes:
  the only way to size NRES/NMON from live traffic. Missing from the verifier's fix.
- FAULT amplifier: an accidental/faulty '1' (fumbled cradle, flapping line) floods and holds a resolver at every
  transit and a cell at every exchange for T_KEY 5 s + T_REL (longer than a doomed T_CLAIM flood). A line that
  repeats it (hang-up break, off-hook, short break) every ~6 s occupies ~1 resolver per transit and ~1 cell per
  exchange network-wide ~90 % of the time: NRES=NMON=2 become ~1 for everyone. Plausible but rare; unreported.
- COST: verifier's "a resolver is about 4.5 packages" is old network.md's figure for a shared '688 time-multiplexed
  over an 8 ms scan (125 us a visit). The RTL watch is parallel (5 compares a resolver + rs_mine). At the new
  1 ms pass a port-time is 64 master ticks: NRES=4 needs ~28 compares a port-time: a shared comparator still fits,
  but it has to be drawn; built with parallel '688s a resolver is ~10 packages.

## Verdicts (skeptic, final). No simulation run.
- forward-needs-resolver-and-idle-forwarder: confirmed, medium; agree with verifier. Resolver half real at real
  timers (reference 8-exch network, NRES=2: ~1.5-2.3 % of floods per hub, ~1 cannot-complete per exchange per busy
  hour); forwarder half ~1e-8/s. "Decided once" is required by monitor rule 1: stuffing is the only safe remedy.
- chain-forward-holds-resolver: confirmed, medium, duplicate of the above; agree. 1-(1-B)^k overstated; doc
  contradiction is against the superseded network.md.
- leaf-sweeps-for-nothing: confirmed, low; agree. Leaf strap = zero parts.
- doomed-floods-hold-longest: confirmed-overstated, low; agree. T_KEY (accidental '1') holds longer still.
- monitor-pool-exhaustion: confirmed, medium; agree on verdict and severity, but the verifier's load is too low for
  shared-e numbering (the docs' own examples), and it misses the ring-strap double cell.
