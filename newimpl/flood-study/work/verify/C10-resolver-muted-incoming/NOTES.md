# C10-resolver-muted-incoming -- verifier notes

Finding: resolver-outlives-muted-incoming (fwd audit).  Reproducer work/audit/fwd/tb_fx.v +sc=2 +var=0|1, real timers.

## Code read (snapshot rtl/)
- local_trunk.v:187-189: link dead -> a_tx=0 on all 8, mute_blk=1.  port.v:147 BUSY includes mute_blk.
- net_unit.v:688-689 R_GONE needs incoming !BUSY -> cannot fire while muted.  No other exit but R_LEG (:684-687, any M on a held leg)
  or w_claim (:659, needs a monitor wanting the incoming -- the monitor dropped on d_clr).  No timer.
- legs latch src=incoming bsy=1; their E = incoming M (0 when muted) -> fE falls T_REL later -> rel clears latch (port.v:184-193).
  incoming's own latch also clears (fM fall) but BUSY stays via mute.  => legs free, sweepable, still `mine` (:436), still R_LEG-able.
- baseband_card has no mute (a_tx gated by link_up only) -> baseband cut not affected (incoming BUSY falls, R_GONE fires).
- MF8 not in RTL: only local_trunk reaches it in the snapshot.
- Auditor's log run_fx_sc2var0/var1 read: failures are the claimed ones (stale R_GONE at mend clears B20's trunks; stale R_LEG re-points dead B10 at E30).
  var1 :84 FAIL "B holds E30 as incoming" is a bench-check artefact (one-leg forward re-points E30 at S40), not part of the bug.

## Spec
- old network.md 3.2 (exchange-docs): "The resolver frees itself when the incoming trunk reads BUSY = 0, which dial pulses never cause."
  new exchange/network.md 3.5: "The incoming trunk's BUSY falls before any claim: it drops every leg and frees itself."
  local-trunk.md / mf8-unit.md / fabric.md 5.2: MUTE_BLK ORed into BUSY while link down.  RTL is faithful: the gap is in the spec.
- mf8-unit.md: the BUSY force is "what it asked for on a terminal"; on a trunk the word going NONE already keeps hunts off.
  fabric.md 5.2: the OR is "jumpered in when the header is stuffed for an adapter" -> alt fix: leave it out on a trunk group.

## var0 stimulus note
- the E party's "claim" at ~3240 ms is not what the called exchange would send: after the stale drop at 2051 E30 carries nothing,
  the E exchange's monitor CLRs and never sees b.  Real outcome: B20's call dies (T_CLAIM nogo).  The same M on E30 CAN come
  from an unrelated E seizure of E30 (E sees it idle): origin watch (net_unit.v:795-804) takes any M on a held trunk as the claim.
- var1 stimulus (E seizes idle E30 for B21, mend during the call) is fully realistic.

## Jobs
- jobNet.sh: tb_net on work/audit/fwd/RTL_fix.list  -> run_net_fix.log
- jobFx.sh snap work/RTL.list -> obj_fx_snap ; runFx.sh snap run_snap_sc2var{0,1}.log +sc=2 +var=N
- jobFxNm.sh: alt fix (site_fx_nomute.v: LTU mute_blk not into BUSY), snapshot RTL -> obj_fx_nm

## Fix review (static)
- auditor fix (work/audit/fwd/rtl_fix/net_unit.v) also carries the C09 F_WRITE f_cancel gate; separable.
- lb/lf per leg uses the legs' own RC detectors as the timer: legs release only when E (incoming M) stood down T_REL.
- keeps R_GONE for legs that never released (incoming died inside T_ARM of the leg writes: no fE edge) -- good.
- residual 1-pass window: on the FIRST free sample of a leg, rs_lf is still 0, so an M on it that sample fires R_LEG
  (way-back onto the dead/just-freed incoming).  One gate closes it: R_LEG needs sp_m && !rs_lf && (sp_busy || !rs_lb).
- rejected cheaper variant (1 FF/leg, dissolve on the first leg seen free): leaves a leg stuck latched if legs straddle T_ARM.
- alt zero-part fix: leave MUTE_BLK out of BUSY on trunk-group adapters (fabric.md 5.2 jumper) -- words already float NONE
  so hunts skip a dead trunk group; the BUSY force is for terminals (mf8-unit.md).  Testing as site_fx_nomute.v.
- 21:45 queue is heavy (other workflows): consolidated to 3 slot jobs: jobNet.sh (tb_net fix), jobAll.sh snap, jobAll.sh nm.
  (an earlier `timeout 1200 ./sim.sh` build was killed in the queue before it started -- no result lost)
- 22:11 snap var0 rerun: 18 checks 6 errors, identical to audit/fwd/run_fx_sc2var0.log (bar timing lines)
- 22:14 snap var1 rerun: 16 checks 5 errors, identical to audit/fwd/run_fx_sc2var1.log.  Reproduction confirmed at real timers.  tb_net fix now running.
- 22:23 tb_net on work/audit/fwd/RTL_fix.list: 88/88 PASS, output identical to base-net.log
- 22:45 alt fix (LTU MUTE_BLK not into BUSY, snapshot net_unit): var0 17/18 (only the MUTE_BLK-BUSY check fails, by construction):
  R_GONE at 346.145 as for a baseband cut, B20's trunks intact after mend, full two-way on the claim, no phantom.
  var1 14/16: MUTE_BLK check (by construction) + the known one-leg re-point bench artefact; no phantom M at W after the mend.
  obj dirs deleted.
- tb_ltu.v:454-464 and tb_lnet.v:243 assert MUTE_BLK busies the group -> the jumper alternative is a spec change (local-trunk.md,
  mf8-unit.md, fabric.md 5.2, two bench checks), and leaves the resolver's liveness tied to incoming BUSY only.

## VERDICT
confirmed (medium).  One root cause.  Reproduced identically at real timers (snap var0 6 errors, var1 5 errors = auditor's).
Overstated details: resolver lost "for the whole outage" -> only until the first M on an old leg or the mend (each exit writes stale);
var0's E claim after the cut is not what the called exchange would send (it lost the pulses) -- real var0 outcome is B20's call
failing (T_CLAIM nogo); the half-connect+phantom needs an unrelated E seizure of E30 inside B20's claim wait.  MF8 not in RTL.
Fix: auditor's lb/lf (tb_net 88/88 identical to base; sc2 var0 18/18, var1 all but the artefact; chain 32/32, lchain 48/48, sc4 PASS
by auditor).  Optional one-gate refinement (untested): R_LEG needs (sp_busy || !rs_lb).
