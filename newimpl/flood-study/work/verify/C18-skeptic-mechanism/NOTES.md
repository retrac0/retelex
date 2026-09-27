# C18-late-claims skeptic review (mechanism + realism lens), started 2026-09-27
Read-only; snapshot RTL only. Verifier's dir: work/verify/C18-late-claims/.
## Results
(no simulation run; everything below is read from the snapshot RTL and the verifier's / C01 / C13 logs and notes)

### F1 late-claim-on-dropped-origin-trunk
- Re-derived: port.v:147 busy has fe; dropped origin trunk (E = caller in make after b) stays BUSY T_REL after
  dmo/N_DROP; claim M under BUSY sets st (net_unit:568), held while M up -> cls_seen (:283) false. Auditor's two
  triggers (ring skew >1.5 ms, claim after T_CLAIM) absorbed. Verifier right. (verifier cites port.v:148; it is :147)
- Failure needs owner's CLAIM write on its own in-port AFTER the in-port self-released (fM fall) and before its cell's
  CLR. m_want is set only on a make (d_stb), so a claim is late only if cl_st is held by an earlier att
  (net_unit:671-674) that the marker neither takes nor refuses (mini_marker:273-282): conformingly only S_WATCH
  stretched to hang-up+CLR by a local caller hanging up <SETTLE after a connect; NODIG chatter = fault.
- Second path (missed): the dropped copy need not be a ring's -- a different call's queued claim whose far caller hangs
  up after b+ID gives the same no-edge write (tree network suffices). Same rarity.
- Consequence on the snapshot's conforming route: WATCH exit -> r_release registered, r_busy still 1 next tick ->
  att_refuse fires (C01): claim 1 (live copy) REFUSED, claim 2 (dead port) TAKEN -> register sees no M, gone at CLR,
  writes port free (S_COLLECT r_gone). => transient phantom (~CLR+T_REL), not permanent. Permanent (verifier's tb_late)
  needs claim 1 taken + claim 2 refused: only the bench force on u_att, or a C01 "+fixatt" without a bound.
- RC: window = (T_REL_rc, CLR+1 tick); opens to ~(CLR - T_REL_rc) when the RC runs short, closes when long.
- Rate ~1e-6..1e-5 per exchange per busy hour. LOW: agree with verifier.
- Fix: M-gate right & most robust vs back-to-back claims (C01 CLR/2 bound + d_lbrk alone: 2nd claim at ~+128.5 ms,
  d_lbrk frees at ~+130 -> claims, its refusal lands ~+257 = after release, same hazard via the marker's write).
  M-gate alone leaves a stale want to CLR: RC T_REL < ~245 + far end re-seizes the trunk -> gate opens on the NEW
  seizure -> stale cell claims it at seizure -> new origin takes it (glare-in-guard = claim) -> B's register reads
  e b as h s -> WRONG NUMBER (argued; also on the snapshot; C03 family). Add d_lbrk. Root: C01 unbounded WATCH wait.

### F2 late-claim-after-resolve
- Confirmed in RTL and in run_pchain_snap.log (2130.203 R_LEG on glare, 2389.999 claim, 2390.284 B11->0 clm1,
  2422.999 self-release). Trigger: glare anywhere in the owner's forward subtree (M climbs via R_LEG / one-leg patch),
  not only its own leg; no false claim needed.
- Auditor's "two exchanges ring": unreachable. Collapse ~b+386 / b+642 < h (b+720); RC +20% b+744 still before any
  digit of h can complete (make+ID >= b+908).
- Same event as C13 forward-glare-collapse (ii). Rate (C13 realism arithmetic) ~1e-6 per network call at design load.
  Dead air x2, both stranded on released trunks (C11 latent listen-in <1%). No wrong party. => LOW (verifier: medium).
- Fix: cell-free at w_res safe for genuine claims (non-owner cells have mismatched before any genuine claim can come),
  closes R_GONE+stale cell. At the owner it hands the call to whatever raised the leg's M: glare -> join (verifier ran
  it); false claimer with owner's claim held in WATCH -> false claimer keeps h s (wrong number the collapse averted).
  Must ship with C13's leg-age gate + one-leg way back deferred to R_LEG. HW: reuse each cell's probe '688 at
  rs_in's scan turn instead of NMON new comparators.
