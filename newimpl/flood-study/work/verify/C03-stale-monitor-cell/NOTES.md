# C03-stale-monitor-cell verification notes
(started 2026-09-26)

## Code reading (snapshot)
- net_unit.v:590-594 C_UNHOLD writes hold away, never touches m_held/m_armed/m_st. Cell exits only on
  mismatch (635-639), claim (666-668), d_clr=CLR 256 ms of break (647-649). CONFIRMED by reading.
- pulse_rx: short seizure's death = break >= HIT -> cnt=1; re-seizure make >= ID -> dig_stb digit 1.
- port.v:147 busy = bsy|fe|(fm&!m): a DROPPED trunk whose fE had armed stays BUSY T_REL at the
  dropping end -> the dropping end cannot re-seize for 256 ms. Only a seizure < T_ARM (fE never armed)
  frees at once at BOTH ends -> that is the unique hole (C_UNHOLD path). So a post-T_ARM abandon is
  protected by the port's own fE release guard (C20 release-margin-thin covers its thin margin).
- Stale cell reads '1' with any conforming dial (make >= ID before e). So (1,e) variant hits only
  OWN_E=1 exchanges = numbering.md 5 "00-17 backbone (tandems, hubs)" by convention. (e+1,b) needs
  first break within ID of re-seizure: not with conforming dial inside guard reach.
- Auditor tb_mc2 trigger: A20 breaks ~142 ms after '1' make (non-conforming pause, or hang-up
  coincidence) and A21 keys 1 within ~37 ms of dial tone (data device only). Plausible but strained.
- Starvation: normal flood holds a cell ~1 s (until e resolves); stale cell 256 ms -> added blocking is
  smaller than normal traffic's. Overstated.
- Fix (a) port compare redundant: in C_HOLD no other w_cls can occur and the cell cannot be freed or
  re-given within T_ARM, so cls_cell alone suffices (1 FF/cell).
- Interaction: C04's proposed fix (C_LOW: unhold only after M low >= ID) would make fix (a) fire only
  after 128 ms; a re-seizure inside that 128 ms continues the old hold AND the stale cell -> hole reopens.

## Sims queued (12:46)
- run1.sh: tb_c03g (NEW, conforming trigger: glare-as-claim at origin A drops A11 in ~1-2 ms; Y's
  flood on A13 forwarded by A onto A11 60 ms later; dials 3 2 2 1 at 60/40/800) on snapshot + monclaim fix.
- run2.sh: auditor tb_mc -DREAL sc=1, sc=3; tb_mc2 (real) on snapshot.
- run3.sh: tb_c03r (NEW, finding 3): A's T_REL=200 (RC 22% short), A20 hangs up 50 ms after seizure,
  Y's flood on A13 at break+202 forwarded onto A11; snapshot, fix, and control T_REL=256.
- Auditor's run_fix_mc2.log "FAIL SAFETY: A21 is not talking to X22" is a BENCH ARTEFACT: the check
  is !(busy_x[P22] && rx_a[P21]==0) and X22 went off-hook as a caller (X gave it dial tone); the
  printed lines show A21 hears 0 both times. Fix run is safe.
- tb_mc -DREAL sc=1 rerun on snapshot: 3 FAILs (claim, reg attached, X22 rings), identical to auditor run_real13_sc1.log
- tb_mc -DREAL sc=3 rerun on snapshot: both cells held by blips, T15 (dialled 1 3) never claimed, X25 not rung: reproduces starvation at real timers
- tb_c03g on SNAPSHOT (run_g_snap.log): REPRODUCED with a conforming trigger at real timers.
  630 A seizes A11/A12; 632 Y's glare M on A12 -> A claimed (glare#=1), drops A11 after 2 ms;
  X: cell 0 on X11 at 633, hold 633, C_UNHOLD 634, stale cnt=1 at 642; 692 Y's flood on A13,
  A forwards onto A11 at 704 (72 ms after drop); X second cell 707; stale cell st=2 ('1') at 835;
  dial 3 -> 1693 stale cell claims, X reg attached, Y sees backward A on A13; reg reads 2 2 ->
  X22 rung at 3694. 3 FAILs (claim, reg, X22 rings).
- tb_c03g on monclaim FIX (run_g_fix.log): SAFE (no claim, no reg, X22 not rung); only the
  OBSERVE "cell still held" fails, as intended.
- tb_mc2 rerun on snapshot (rerun_mc2.log): identical to auditor's run_mc2.log (3 FAILs; A21 hears X22 1 then 0).
- tb_c03r snap, A T_REL=200 (run_r_snap200.log): REPRODUCED finding 3. A20 hangs up 49 ms after
  seizure (inside guard, after T_ARM), A11 free at A 201 ms after break (its short fE), Y's flood
  forwarded onto A11 214 ms after the break: X11 still held, X's old cell still counting ->
  X claims, reg attached, X22 rung. 3 FAILs.
- tb_c03r FIX, A T_REL=200 (run_r_fix200.log): SAFE (fix (b) freed the cell at 128 ms); X11 still held at the re-seizure -> the new flood is invisible at X (lost, not wrong).
- tb_c03r CONTROL snap, A T_REL=256 (run_r_snap256.log): PASS. A11 free 257 ms after the break,
  re-seized at 270; X's cell CLR'd ~256 and X11 released -> fresh classification. Nominal margin is
  only the far sweep (~13 ms): an RC >= ~5% short at the dropping end opens finding 3.
- run4 queued: tb_c03g on C03 fix (a)+(b) MERGED with C04's C_LOW fix (merge/net_unit.v). Expect the
  hole to reopen: C_LOW keeps the hold and the cell through a 72 ms gap (no C_UNHOLD, break < ID).

## Draft verdicts (14:25)
- stale-cell-after-unhold: CONFIRMED, high. Conforming trigger at real timers (tb_c03g: glare at origin
  + transit forward 72 ms later). Only OWN_E=1 exchanges (backbone 10-17) in the (1,e) variant;
  (e+1,b) variant needs a non-conforming fast dialer (overstated part).
- stale-cell-starves-monitors: CONFIRMED-OVERSTATED, low (sc=3 real reproduces, but a normal flood
  holds a cell ~1 s at every exchange; a stale one 256 ms).
- rc-tolerance-reseize: CONFIRMED-UNDERSTATED, medium: tb_c03r reproduces with dropping-end T_REL
  22% short + conforming hang-up; nominal margin only ~13 ms (sweep) -> ~5% RC spread suffices.
- One root cause: cell's only end-of-seizure signal is CLR 256 ms of break; the trunk can be
  re-seized sooner (at once after C_UNHOLD; or after a short far RC).
- Fix (a) cls_cell: complete for C_UNHOLD path on snapshot; port compare redundant.
  Fix (b) longbrk: closes finding 3's wrong number (tested). Port-level lost call remains (C20).
- run4 first attempt: outer timeout 5000 s expired while queued for a sim slot (never ran). Relaunched 15:16 with 10800 s.
- run4 (run_g_merge.log, run_g_merge_lowid.log): C03 fix (a)+(b) MERGED with C04's C_LOW fix
  (C_LOWT = CLR, and = ID): the hole REOPENS in both. X never writes the hold away (M back up at
  72 ms -> C_LOW returns to C_HOLD), only the stale cell watches, claims on 3, X22 rung. 4 FAILs
  (incl. OBSERVE C_UNHOLD). Fixes for C03 and C04 conflict: whoever merges must add a seizing-end
  release guard (do not re-seize a trunk dropped before its fE armed for >= CLR) or pick one.
