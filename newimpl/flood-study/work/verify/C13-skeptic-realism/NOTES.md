# C13-leg-glare skeptic review (lens: realism and severity)
started 2026-09-27. Read-only. Snapshot RTL only.

## Results as they come
- Read net_unit.v 560-906, port.v release, network.md s5, decisions.md glare rows, traffic.md s8 design point.
- Classifier gap check (far M between B's confirm visit and leg write): NO gap. The probe sees a port once a pass;
  the candidate's next turn after its confirm visit is after the confirm pass ends, when `mine` already covers it
  (f_cand in F_WRITE, rs_held after w_fwd; o_cand in N_SEIZE, d_held after). OK.
- F3' (rtl_f3 diff): 3-bit counter, fires on low>=4 samples THEN rise, not gated on anything but !o_gone.
- tb_pchain F3' pass 1: A20 and C20 are forked to dial in LOCK-STEP (tb_pchain.v:325-326). 'M at B11 0' and
  'M at B14 0' both at 2180.258: the two callers' first breaks coincide. That is why BOTH origins fired F3' (A 2193.156,
  C 2194.156). With independent callers (first breaks |dt| > ~5 ms, i.e. nearly always), the origin that sees the
  stranger's break first abandons; its drop makes the other origin's M a STEADY low (no rise) -> F3' never fires there
  -> that caller is C11's dead-air/latent listen-in. So F3' ALONE gives one clean cannot-complete + one C11 strand
  per event, not two clean ones. C11's steady-low abandon (C11 verifier's 'alt': 128 ms persistence, N_DONE gated on
  lost==0) is REQUIRED in the main case, not an optional side branch.

## Rate on the design network (rate.py -> rate.out; arithmetic, no sim)
traffic.md 8.5/8.6 tree (3 tandems in a chain, 2 sub-hubs each, 3 mids each, 2 leaves each = 63 exchanges, 857
network calls/h, 48 s calls, 2.73 s flood). Every flood crosses every link, so a link's seizure rate is the network
call rate, split lamX = r*nX, lamY = r*nY. Glare = P(N-1 busy) * lamX * lamY * 2D, 2D = 2.64 ms (no extra 2: verifier right).
- Design load: tandem-tandem link (12 ch, 5.81 E, 0.93% blocked): 1 per ~434 busy h each; network total ~1 per 195
  busy h; ~8e-5 per exchange per busy hour; 6e-6 per network call (x2 callers). Outer links negligible (12 ch) or
  1 per ~1900 h (6 ch mids).
- 2x overload: network ~1 per 3 busy h, 1.7e-4 per call -- noise beside the ~12% the network already loses.
- WHO GLARES: on the tandem link the X-side seizure is an origin only 1/21 of the time, Y-side 1/42: ~99.9% of backbone
  glare involves a transit; on a leaf link ~98% is origin vs transit. So transit glare is THE glare of a flood network;
  the documented origin-vs-origin case (counted on the right trunk) is the exception.
- In the design tree every transit has >= 3 directions: NO one-leg forwards. rs_two/one-leg only in chains. The
  collapse needs only 'the call's owner is on the path from its origin to the glare transit' (monitor claim re-points
  an in-port already turned to the glare leg by R_LEG / the one-leg patch), ~4/62 per side on the backbone.
- Glare reserve on the backbone: non-g side effectively 11 of 12 at 5.81 E -> B 1.94% vs 0.93%: doubles backbone loss
  for half the floods to remove ~1 event / 200 busy h. Not worth it (agrees with 'none needed at design load').

## Subscriber experience / wrong number check (reasoned at real timers)
- Join (~85-90% of events): at each caller's last digit an open line to another caller who also just dialled; nobody
  rung; obvious; both redial. No wrong party.
- Collapse / stranger leaves (~10-15%): dead air after dialling; ports latched to released channels (C11 mechanism),
  latent one-way listen-in only if the channel is reused and a conversation starts before the caller gives up: <~1% of
  such events at a leaf (A's own next call ~0.004/s takes A11 first; ringing+dialling take >10 s).
- Owner's register cannot take a wrong h s: claim at b_last+~128; in-port self-release +256; next upstream port
  +256 -> the in-port's M falls steady at ~b_last+640 ms, before a conforming h (>= b_last+720); faster dialling gives
  a steady low -> gone, never a completed digit.

## Fix assessment
- C11-alt ALONE (128 ms steady-low persistence + N_DONE gated) closes the collapse (pass 1: after B11's self-release
  A sees steady low; A drops; then C sees steady low) and pass 0, and keeps documented joins (C11 verifier: lfull 40/40,
  net 88/88). Reasoned for tb_pchain, not run.
- F3' is only needed to turn JOINS into cannot-completes (a policy change); alone it strands the first dialler (above).
- Root fix at the transit (auditor (b)): per-resolver age gate. Max baseband delay from B's leg write to the far glare
  M at B's probe ~ 1.03 + 1.3 + 1.03 + 1 turn ~ 4.4 ms; a real claim cannot come < ~850 ms after any leg write (needs
  e, a >= 720 ms pause, b, ID). So a gate of 16-128 ms is safe with margin for carriers. Count at the transit (EV_GLARE
  naming the leg: the right link) and write that leg away, keep the others. Chains also need the one-leg way back
  deferred to R_LEG (removes the popc==1 patch; conflicts with C14 option (b) that would free one-leg resolvers).
  Pair with the origin: inside the guard, write the glared trunk away and count instead of claiming (the guard test
  exists; a few gates). HW ~ half a package a resolver + ~1 package for the event/leg register.

## Verdicts (final)
- leg-glare-joins-uncounted: agree, confirmed-overstated, LOW. Real, and the dominant glare of a flood network; join is
  documented; counters misattribute (origins' first trunks, or nothing past the guard).
- forward-glare-collapse: confirmed-overstated, LOW (verifier said medium). Rare (~1e-6/call at design load), no wrong
  party rung, dead air + <1% latent listen-in (C11's harm). Not specific to one-leg forwards (design tree has none;
  hubs collapse the same way). Verifier's F3' 'both clean' is a lock-step-dialling artefact; C11-alt alone fixes it.
- residual-glare-rate: agree, confirmed-overstated, LOW; factor-2 correction right (0.5 E 2-ch -> 342 h checked);
  flood-network rate on the design tree in rate.out.
No simulation run. Files: NOTES.md, rate.py, rate.out.
