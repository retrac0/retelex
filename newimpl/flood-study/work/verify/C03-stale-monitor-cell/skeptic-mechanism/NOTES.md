# C03 skeptic review, lens MECHANISM (2026-09-27)

Read-only on the snapshot; at most one run.

## Code re-derivation (snapshot)
- net_unit.v:584-588 C_HOLD watch; 590-594 C_UNHOLD writes hold away + f_cancel, never touches
  m_held/m_armed/m_st. Cell given at 611-615 (m_free1). Freed only at 635-639 mismatch, 666-668
  claim, 647-649 d_clr (pulse_rx.v:93, CLR). CONFIRMED.
- Nothing blocks it: C_READ/C_ACT never re-check M; the cell arms at its first probe sample
  (629-632) with m_d=m, so whether M is still up or already down at arming, pulse_rx counts
  cnt=1 at HIT (84-90). Re-seizure make >= ID -> dig_stb cnt=1 (96-99). Stale "1".
- port.v:147 busy = bsy|fe|(fm&!m): a seizure < T_ARM leaves neither detector armed; after the
  drop write (seizing end) and the C_UNHOLD write (far end) both ports are free at once.
  st[] cleared by the M-low sample (566-567) -> re-seizure re-classified (283-284), 2nd cell.
- Blocking condition for the (1,e) phantom: if the gap < HIT (8 ms at the cell's 1 kHz),
  no pulse is counted and the stale cell counts the new call CORRECTLY (twin cell). Needs the
  far end to re-seize within ~8 ms: sweep+confirm ~>=1.3 ms, so possible but narrow; then two
  cells on one port reach M_DONE on the same tick if the code matches -> second CLAIM on the
  same port after att_ack (w_claim re-fires; cl_st back to IDLE). Rare side path.

## Nominal margin of finding 3 (rc-tolerance-reseize)
- Verifier: "nominal safe only by ~13 ms (sweep); ~5% short RC opens it". That 13 ms is the
  bench's case (fresh sweep, port o11). Minimum: a sweep already running visits the freed
  port late (stride 9: o70=56 is step 63) -> s_min ~ read + 1 ms CONFIRM + WAIT + word
  ~1.3 ms (C20 release-margin-thin computes the same, 0.13-0.29 ms port margin).
  Cell-level: cell sees the fall and the rise through the same probe phase; condition for
  the stale count is dA + s < (b_n0 - T0 - d) < 1 ms -> impossible at nominal by >=0.3 ms.
  So nominal is safe by ~0.3-1 ms at worst port positions, not 13 ms: ANY dropping-end fE
  RC more than ~0.5% (1.3 ms) short opens a window of (256 - RC_A - s) ms for late ports.
  fabric.md 3.5/8: diode+2R RC into a '14, threshold spread "not measured". Coin flip per port.

## Second path missed by auditor AND verifier (finding 3 variants)
- Verifier: "A wrong number needs an OWN_E = 1 exchange". True for the C_UNHOLD path only
  (a < T_ARM seizure carries no digits: the stale cell is at M_WANT_E, cnt=0 -> phantom 1).
- The RC path (post-T_ARM abandon) leaves the cell in WHATEVER state the abandon found it:
  * abandon in the pause after e, at an exchange whose e matched (M_WANT_B, done=1):
    break -> cnt=1 (done ? 1), re-seizure make >= ID -> digit 1 -> OWN_B==1 -> CLAIM at ID of
    the re-seizure, BEFORE the new caller dials anything. Exposed: every exchange e1.
    The new call goes to X's line (e_new b_new) whatever was dialled.
  * abandon mid-digit (after k pulses, during a make): cnt=k+1 -> phantom k+1 as e (any
    OWN_E) or as b (claim at once for OWN_B=k+1).
- Planned single run to settle: tb_c03b (variant of tb_c03r), X = 21; A a transit: Y floods on A13 (forwarded A11), dials 2, hangs
  up in the pause; A T_REL 200; Y's flood re-seizes A11; far caller dials 2 5 3 4.
  Expect on the snapshot: X claims ~128 ms after the re-seizure, X25 rings.

## RESULT of the one run (tb_c03b, snapshot, A T_REL 200, X = 21 nominal) -- run_b_snap200.log
- 46 ms X gives cell 0 to X11 (flood 1 via A13->A11). Y dials 2: cell st=2 (M_WANT_B) cnt=2.
- 1243 hang-up in the pause; 1252 cell cnt=1 (HIT; done ? 1). 1443 A11 free at A (201 ms).
- 1456 A forwards flood 2 (A12) onto A11; X11 still BUSY (fM nominal), st set, not re-classified.
- 1586 (130 ms after the re-seizure, NO digit dialled yet) stale cell st=3 -> CLAIM, bkA=1,
  X's register attached. Y's caller dials 2 5 3 4 -> X's register reads 2 5 -> X25 rings.
- 3 SAFETY FAILs. CONFIRMED: the RC path does NOT need OWN_E = 1; an exchange e1 claims ANY
  re-seized call, whatever is dialled, when the abandoned call had matched its e.
- obj dir deleted.

## Other mechanism notes
- Twin cell (gap < HIT): stale cell counts the new call correctly; if the code matches, two
  cells on one port want on the same tick; w_claim serves one, then after att_ack fires a
  second CLAIM on the same port; mini_marker att_refuse (r_busy) writes it to NOGO. Rare;
  closed by fix (a).
- k short seizures on one channel inside CLR: oldest stale cell hears k -> OWN_E = k exposed.
  Rare; closed by fix (a).
- Adjacent (not C03): a drop WRITE after self-release -- origin N_DROP at the register's CLR
  (digital) and resolver R_GONE at rs_in's fM (RC) -- can land on a trunk whose own fE (RC,
  short) already released it and the forwarder re-seized: the new leg is killed (and is a
  short seizure downstream). Same RC-tolerance root; neither fix covers it.
- Spec: monitor.md 6's cell has only Q3/Q7 taps (no 256 tap); network.md (new) 3.4 says
  "256 ms of break (the trunk released) frees the cell" -- that equation is the defect.
  Fix (b) uses the Q7 tap that exists.
- C20 release-margin-thin ("not reachable with baseband/local trunk") ignores RC tolerance;
  the port-level lost call that fix (b) leaves is RC-vs-RC, reachable at ordinary tolerance.
