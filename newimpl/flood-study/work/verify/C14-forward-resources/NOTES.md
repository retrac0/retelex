# C14-forward-resources verification notes

- Cited lines in net_unit.v (snapshot) all match: 505-508 fwd_mask/nf_busy/nf_empty; 545 n_nofwd; 609-622 hold/monitor/forward gate; 659-665 claim drops legs; 681-708 resolver watch/act; 714-744 forwarder, rs alloc for one leg too (rs_two).
- NEW exchange/network.md (rewritten 2026-09-26) §3.5 ALREADY documents: resolver taken for every forward incl. chain one-leg ("A chain transit needs one as much as a hub: a leg written after the caller's A has gone has no edge left to release on"); one forwarder; "held and watched but never forwarded"; silent loss; §10 Open "Resolver sizing, and silent loss at a transit". The doc contradictions cited are against the OLD network.md 3/3.2 (exchange-docs/), superseded.
- RTL header comment (net_unit.v:69-71) also documents "One forwarder: a seizure arriving while it is hunting is held and watched but not passed on."
- Prior load-study evidence (work/load/): hub/NOTES.md s1_burst at REAL timers: 3rd flood at hub gets mon=0 AND BUSY-NORES (both resolvers held) -> not forwarded; no BUSY-FWDR at real timers (the ~19 ms T_ARM watch spaces classifications past the 10.6 ms forward). transit/NOTES.md T9 (real timers): 9 crossings incl. 6 with <=8.6 ms gaps, 0 FWDBUSY; at s8 all 10 such lost. => forwarder-busy loss is a scale-8 artefact except behind a local origin sweep (sc5d).
- hub: one origin bank (one register) an exchange => at most one flood pending per source exchange: Engset, not Erlang; NRES = number of source exchanges removes resolver loss (LB3 NRES=3: NORES 0). Design load 3-leaf star: NRES=2 loss ~5e-4.
- hub real timers: resolver hold claimed 1838 ms vs doomed 4486 ms (2.44x) -> doomed-floods mechanism measured.
- overload/transit studies: registers (C15) saturate long before links or unit pools (nofwd_busy 0, nomon 0 on chains; links never full). Hub LC overload: NORES 26%.
- transit fix (work/load/transit/fix/net_unit.v, pending slot PF_MAX 24 ms): tested only on t4_cross_s8 (10/10 recovered). Not on tb_net -> my job B runs tb_net + tb_fx sc4/sc5 on it.
- Jobs launched: jobA (snapshot tb_fx sc4, sc5; NRES=3 sc4), jobB (pending-fix tb_fx sc5, sc4; tb_net). Progress in job.progress.
- Arithmetic (43.2 floods/h an exchange, resolver hold 2.9 s, transit's own floods take no resolver; Engset with one flood per source exchange):
  8 exch: A=0.244 E; NRES2 Erl 2.33% / Engset 1.58%; NRES3 0.19/0.08%; NRES4 ~0.
  20 exch: A=0.661 E; NRES2 11.6/10.8%; NRES3 2.5/2.0%; NRES4 0.41/0.27%.
  Monitors (hold ~1.7 s): 8 exch 0.14 E: NMON2 0.9/0.6%; 20 exch 0.39 E: NMON2 5.1/4.6%, NMON3 0.66/0.51%.
  => auditors' Erlang figures hold within ~1.5x; "1-(1-B)^k over k transits" overstates: every flood reaches every transit, so the pending sets at successive transits are nearly the same floods (strongly correlated), and a flood dropped upstream never loads the transits beyond.
- sc5d (auditor log run_fx_sc5.log:440-483) mechanism: origin sweep 7688.0-7700.0, 1st flood (41) classified 7689.6 -> F_WANT waits; forward sweep 7700-7712; 2nd flood (30) classified 7708.5 (after 41's ~19 ms T_ARM watch) while fst=F_HUNT -> nf_busy. Window at real timers: 1st flood classified within ~5 ms after a local origin sweep starts AND 2nd flood within ~20 ms of the 1st: ~1e-8 /s at design rates => negligible (not a bench artefact, but practically unreachable).
- Leaf sweeps: STRAP_N is used ONLY in the forward decision (net_unit.v:505-506, 616-618); origin sweep uses h_mask 1111. So strapping a leaf's absent directions makes fwd_mask 0: no sweep, no n_nofwd, zero parts (vs the auditor's '175 "directions present"). Not simulated.
- A classifier read during a sweep waits at most the sweep's current read (<= 9 frames ~0.14 ms: cls_issue has priority over h_issue), not ~1 ms; a marker read (own word_rx) may wait for its port's turn to align with the free frame (stride 9, 64 mod 9 = 1): up to ~9 ms. Both negligible.
- RESULT jobA sc4 (snapshot, REAL timers, NRES=NMON=2): run_fx_sc4.log IDENTICAL to audit/fwd/run_fx_sc4.log except walltime. n_nofwd 0->1 at 111.295 (W12), 1->2 at 152.123 (N77); 12 and 77 held src 00 bsy 1; mon_held stays 11 (3rd/4th unwatched too); freed resolver reused by N76; all released; 10/10 PASS.
- jobC launched: tb_chain (s8) with leaves strapped (A 1011, C 0111) + counters, and the same counters without straps.
- RESULT jobA sc5 (snapshot, REAL): run_fx_sc5.log IDENTICAL to audit log except walltime. 5a hops 12.1-13.9 ms, 5b behind a T_ARM watch 30.4 ms (or 12.4 when watch ended), 5c behind an origin sweep 18.4-23.4 ms, 5d: 2nd flood (30) classified 7708.495 while forwarder in F_HUNT -> n_nofwd +1 (both resolvers FREE: rs_busy 00 -> 01 only at 7711.986). 4/5 checks, the 5d check FAILs as the auditor reported.
- RESULT jobA NRES=3 sc4 (tb_fx_nres3.v = tb_fx with .NRES(3); REAL): 3rd flood W12 FORWARDED at 122.0 (legs 76, 42, 32), 4th N77 not (n_nofwd 0->1 at 152.1). The 2 FAILs are the bench's NRES=2-specific checks (n_nofwd +2; N76 "fifth flood" was now W12's leg 76, so sm[76]=1 acted as a claim on that leg: R_LEG, 12 patched to 76, legs 42/32 dropped). All released after; no clash, no queue overflow. => stuffing NRES closes exactly the resolver share, as expected; a 4th concurrent flood still lost at NRES=3.
- RESULT jobB pending-forward fix (work/load/transit/fix/net_unit.v), REAL timers:
  sc5d: 2nd flood (30) classified 7708.495 (n_nofwd still counted there, so the bench's n_nofwd-based check still prints FAIL: check artefact under the fix), kept pending, forward started 7711.986 as soon as the first forward wrote, legs 76/42/12 written 7722.0-7722.5 (both resolvers used). => closes the forwarder-busy loss; hop for that flood ~32 ms.
  sc4: identical outcome to snapshot (10/10 PASS): pending slot cannot help when resolvers stay held for seconds (PF_MAX 24 ms).
- RESULT jobB tb_net on the pending-forward fix copy (s8): 88 checks, 0 errors, PASS (runpf_net.log; base-net 88/88).
- RESULT jobC tb_chain (s8), same counters both runs:
  no straps (tb_chain_counters.v): n_nofwd A 3, B 0, C 4; forwarder sweeps at leaves A 3, C 3 (B 3); 32/32 PASS.
  leaves' absent directions strapped (tb_chain_leafstrap.v: A STRAP_N 1011, C 0111): n_nofwd A 0, B 0, C 0; leaf sweeps 0/0 (B 3); 32/32 PASS.
  => zero-part fix for leaf-sweeps-for-nothing works and breaks nothing on the chain bench.
- All obj dirs deleted by the job scripts.
## VERDICTS (final)
- forward-needs-resolver-and-idle-forwarder: confirmed (medium). Resolver half reproduced at real timers; forwarder-busy half reproduced (sc5d) but needs a local origin sweep coincidence (~1e-8/s at design): negligible. Doc contradiction is with the OLD network.md; new network.md 3.5/10 documents exactly this. Fix bullet 4 (transit claim-to-refuse) unsafe even on a chain (owner may be upstream).
- chain-forward-holds-resolver: confirmed (medium), DUPLICATE of the above; its fix analysis is the right one (one-leg forward needs its leg remembered). "1-(1-B)^k over k transits" overstated (pending sets correlated).
- leaf-sweeps-for-nothing: confirmed (low). Zero-part fix: strap the leaf's absent directions; tested tb_chain 32/32, leaf sweeps 3/3 -> 0/0.
- doomed-floods-hold-longest: confirmed-overstated (low). Hold ratio measured 2.44x at real timers (hub study) but load studies show registers (C15) saturate first; T_CLAIM 2 s is new network.md 2's carrier allowance.
- monitor-pool-exhaustion: confirmed (medium/low: documented limit, NMON parameter). My sc4 re-run: 3rd/4th floods got no cell.
