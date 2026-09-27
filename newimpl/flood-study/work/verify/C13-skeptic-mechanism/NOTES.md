# C13-leg-glare -- skeptic review, MECHANISM lens (2026-09-27)

Read-only on the snapshot; my files only here.

## Reading results (done)
- net_unit.v:682-690 resolver watch: R_LEG on ANY sp_m on a held leg; no BUSY/arming/age term. Confirmed.
- :691-706 w_res: drops other legs; multi-leg writes way back in <- leg (701-705); rs_two writes nothing. Confirmed.
- :725-743 F_WRITE: one leg -> in-port patched <- leg at forward time. Confirmed.
- :795-804 origin: first M on a held trunk = claim, glare counted only if `guarding`; never re-checked. Confirmed.
- :656-668 w_claim: in-port <- 00 + CLAIM regardless of what it listened to. Confirmed.
- port.v:106,173 E = e_cap of the SOURCE's M; re-point to 00 -> e_cap 0 (port 00 unfitted) -> fE falls T_REL later
  (183-187) -> rel clears addr/bsy/CLM (193). Confirmed: any re-point of a port with E up is a release T_REL later.
- mine (430-441) covers the candidate from F_WRITE/N_SEIZE; during H_CONFIRM the next visit of the port is a full
  pass later, after fst=F_WRITE, so the classifier can't take the glared channel. No hole found.
- mini_marker reads the word and leaves trunks to the unit (mini_marker.v:360-367): no marker-side glare path.
- Rings: strap stops forwarding into a strapped link (network.md 7): no self-glare of one flood. Not a path.

## Second path (missed by both)
- The collapse is NOT specific to one-leg forwards. Multi-leg: w_res writes in <- glared leg (701-705), so the in-port's
  E is the stranger's hook; the transit's OWN monitor (still held on the in-port) claims at b if the transit is the
  destination -> w_claim re-points to 00 -> self-release T_REL later -> same double stranding as pchain pass 1.
  The discriminating condition for (ii) is "the glaring transit is the call's destination", not the leg count.
  Verifier's "one-leg forwards are the normal case ... so this is the common transit form" misframes it.

## F3' evidence is lock-step (from the verifier's own run_pchain_f3.log)
- tb_pchain forks dial_a and dial_c on the same tick: 'M at B11 0' and 'M at B14 0' both at 2180.258.
- A fires 2193.156 on C20's make; A's abandon reaches C11 at 2194.149 ('M at C11 0'); C fires 2194.156 on A20's make
  seen in the 1 ms (2193.149-2194.149) before the abandon arrived. Margin < one probe pass.
- Reasoning: F3' at Y fires at the end of X's first break; Y's write-away makes X's kept trunk go STEADY low within a
  few ms, so X's F3' never fires unless the two callers' first makes are within ~the abandon's propagation (~2 ms).
  => F3' alone: one NOGO + one stranded (C11's claimed-trunk loss) in almost every real glare. C11's steady-low is
  essential in every glare, not only "when the stranger leaves".

## Cheaper discriminator the verifier did not weigh
- The origin already computes `guarding` and the doc (network.md 5, 6) says no real claim can come inside the guard.
  M on a held trunk inside the guard -> count + drop that trunk (dmo) / NOGO if none left, instead of claiming.
  At real timers the upstream origin sees a transit's glare ~12-30 ms after its seizure, inside 128 ms.
  Immediate, needs no dial break, no MF8-outage sensitivity. F3'/C11 stay as the backstop past the guard's reach.

## Rate arithmetic
- Re-derived: rate = P1 * lamX * lamY * (D_X + D_Y). Verifier right, auditor's extra x2 is wrong.
  N=2, A=0.2: P1=0.1639, lam=0.0125/s, 2D=2.7ms -> 6.9e-8/s = 1 per 4017 h. Matches verifier.

## Planned single run
- tb_pchain (copy here) on RTL_f3.list, pass 1 only, C20's dial delayed (cdly ms) -> expect A20 stranded on A11, C20 NOGO.

## Second path, wider (01:50)
- The collapse needs only that the call's DESTINATION D sits anywhere UPSTREAM of the glared link, not that D is the
  glaring transit. The glare M climbs the tree: each transit between the glare and the origin takes it as R_LEG on
  its leg and points its in-port at that leg (rs_two: already at forward time; multi-leg: w_res 701-705). So D's
  in-port listens to a leg carrying the stranger's hook (E up); D's monitor, still held on the in-port, claims at b;
  w_claim re-points to 00 -> fE falls -> D's in-port self-releases T_REL later -> the path unwinds under both callers.
  Chain O-D-T-X, glare on T-X: D collapses. So of the transit glares on a call's flood tree, the ones in D's subtree
  (about half in a chain with a uniform destination) are collapses, not the documented join.
- Hence finding 2 is understated in scope; finding 1's "join" holds only when D is not upstream of the glared link.

## Fix view
- F3' (+C11 steady-low) turns joins/collapses into two cannot-completes; it cannot save D's call in the collapse case.
- Transit leg-age rule (M on a leg younger than the guard = glare: count, drop that leg, keep the others) + defer the
  one-leg way back to w_res (drop the `popc==1` patch at 732-736 and the `!rs_two` at 701) stops the glare M climbing,
  so D's call completes; the glare costs only the glared branch.
- Origin: M inside `guarding` -> count, drop that trunk (dmo), NOGO if none left; the doc already says no real claim can
  come inside the guard. F3'/C11 stay as the backstop past the guard's reach.

## RESULT single run (01:55): run_pchain_f3_cdly150.log  (F3' copy, pass 1 only, C20 dials 150 ms after A20, scale 8)
- Glare at try 0 as before (B14 and C11 both written 787.288; B11 -> 14 at 787.422).
- A20's first make reaches C11 852.152 -> C's F3' fires 853.159: C11 -> 0, C20 -> 3 (cannot-complete).
- A's kept trunk then goes STEADY low (C20 not dialling yet): A's F3' never fires. A11, B11, B14 release 886.003.
- B's monitor clears 919 (B11 released under it) although A20 dialled B's code.
- A claimed, o_last at 1308: A20 -> 11, A11 released: STRANDED. 'FAIL A20 reached B21'.
=> F3' alone: one clean cannot-complete + one stranded caller. The verifier's double cannot-complete was lock-step
   dialling (both breaks at 2180.258 in their log; C's fire landed in the 1 ms before A's abandon reached C11).
Build 23 s, run 62 s; obj dir deleted by job.sh.
