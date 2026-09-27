# C10 skeptic review (mechanism + realism) -- running notes

Read-only review of work/verify/C10-resolver-muted-incoming.json and the verifier's verdict.

## Mechanism re-derived from snapshot rtl/ (all confirmed)
- local_trunk.v:187-189 dead link: a_tx=0 x8, mute_blk=1; port.v:147 BUSY ORs mute_blk.
- net_unit.v:688-689 R_GONE needs rs_in read !BUSY -> blocked for the whole outage.
- legs listen to B10 (E = B10's M = 0) -> fE falls T_REL later -> rel clears latch (port.v:183-193). Legs free, sweepable
  (sweep checks only M/BUSY at select, :756-759, :781), still `mine` (:436), still R_LEG-able (:684-687).
- R_LEG writes the way back B10 -> leg bsy 1 (:701-705) only for rs_two=0 (multi-leg forward). ONE-LEG forward: R_LEG
  writes nothing (drops none, no way back) -> harmless; only R_GONE at the mend can hurt it.
- B10's stale latch lasts until the claimed leg's M falls for T_REL (fE fall) -> lives as long as the call on the old leg.
- Logs read: audit/fwd/run_fx_sc2var{0,1}.log agree with the mechanism.

## Second path missed by auditor + verifier (worse than "phantom seizure at W")
- The forward B held when the link died is the ORIGINAL call's flood (W's origin trunk ch0, or W's resolver leg).
  That call is still pending at W for up to ~b + T_CLAIM (or T_KEY) after the outage starts: W's ch0 still d_held
  (W side: ch0 latched to W caller, fe up, BUSY via bsy + mute).
- At the mend, B10's A = E30's M (stale way back) -> W ch0 M rises -> W origin claim watch (net_unit.v:795-804) takes
  it as THE claim (past the guard, not glare) -> N_DONE at o_last -> W caller listens to ch0 = B10 = E30's C.
  W caller hears one side of an unrelated call (ringback then a stranger), is not heard. Via W's resolver instead:
  R_LEG at W -> way back -> upstream origin accepts -> same.
- Needs: outage start under a forward; M on an old multi-leg leg within ~0.3..~5 s; mend after it and before the
  original origin gives up. Narrow: order 0.1-1 % of outages that start under a forward. Rare, but a crossed
  connection (privacy), not a cannot-complete.  Combines with C12 (origin accepts any M rise).
- If W's ch0 already free at the mend: the phantom seizure (as auditor) -> W holds, monitors, floods network-wide for
  the unrelated call's duration (C08-like, bounded by that call).  If the call on the old leg is still dialling
  (var1: the E caller's pulses), W's monitors count a suffix of the digits -> mis-parse claims possible (very rare).

## Cascade (covered by the fix)
- A stale R_GONE / R_LEG drop hitting ANOTHER resolver's current legs leaves that resolver with legs released from
  under it (they go free T_REL later) -> a second-generation stale resolver.  lb/lf covers it too.

## Realism
- network.md 3.5/10: resolver load ~0.19 E per transit -> a given incoming link holds a forward ~5-15 % of the time
  (verifier's range OK).  Trigger = LTU outage > T_REL starting under a forward from it.
- Old legs are B's OWN first sweep picks (lowest, or highest with g) -> B's next forward/origin reuses them; the first
  far CLAIM on one fires the stale R_LEG.  That, not var1's far seizure, is the common way in: the far end hunts
  from the opposite end (local-trunk.md: "from the glare end the key hunts from the top"), so the far end seizing
  B's first channel (var1's stimulus) needs a nearly full group.  Same consequence either way.
- Common case (new forward reuses old legs, claimed on one): stale resolver fires first (lower index), drops the
  other old legs (the new forward's own, dropped anyway) and writes B10 -> claimed leg; the new call completes.
  B10's stale latch then lives as long as that call.  Mend during it -> phantom (or crossed claim, above).
- Outcomes by likelihood: phantom network-wide seizure after the mend for one call's duration (resolver + monitor
  held at every exchange it floods to: at 0.19 E, NRES 2 -> 1 raises unforwarded floods ~1.4 % -> ~16 % there);
  cut pending flood branches (cannot-complete); rarely a crossed one-way connection.
- Severity medium stands (rare trigger, mostly clean failures / capacity loss; rare privacy path).

## Fix review
- lb/lf fix read (diff vs snapshot): sound. Dissolve/R_LEG/mine/claim/R_GONE all exclude rs_lf; lb/lf cleared at
  allocation; dissolve and w_res mutually exclusive (rs_act).  One-gate refinement (sp_busy || !rs_lb) is safe:
  a latched leg is always BUSY, so a legit claim never arrives on a !BUSY leg once lb is set.
- Residual not covered (general, not mute-specific; C13 territory): far end's RC faster than B's leg's RC -> far end
  re-seizes the channel while B's leg still latched/BUSY -> R_LEG takes it as a claim.  Window = RC spread (tens of ms).
- Residual: leg whose fE never rose (written < T_ARM before the death) stays latched until the mend (R_GONE) -- if
  the link never returns, a lost trunk.  Pre-existing, rare.
- Not fixed by either: B10 at the mend reclassified as a fresh seizure mid-dial (C07 link-return-fresh-seizure).
- COST understated: 8 FF per resolver is already 2 x '175 before set/qualify gating, the dissolve term and the extra
  !lf input on R_LEG, mine, claim-drop and R_GONE-drop per leg: ~5-8 packages per resolver, ~10-16 for NRES 2,
  not "~2 packages".  Matters on a two-layer card.
- Zero-part alternative (MUTE_BLK OR left out on TRUNK adapters) is consistent with mf8-unit.md:689-692 ("the BUSY
  force is what it asked for on a terminal"; word float is what network.md asked on any carrier) and fabric.md 5.2
  (already a jumper).  Closes the only known trigger for free; lb/lf is the general cure (stuck /HB driver etc.).
- Regression gap: the fix edits `mine`; tb_lfull (the bench that found the `mine` glare case) and tb_lnet were not run
  on it.  tb_lfull ~17 min wall at base; not run here (read-only brief).
