# C03 skeptic review (lens: realism and severity)
Started 2026-09-27. Read-only; at most one short sim.

## Read so far
- net_unit.v 584-594 (C_HOLD watch -> C_UNHOLD writes hold away, cell untouched), 595-626 (w_cls gives
  m_free1 cell), 628-651 (cells freed only on mismatch / claim / d_clr). Confirmed by reading.
- pulse_rx.v: while !arm m_d tracks m; armed cell counts a break at HIT (cnt=1, or 1 after done);
  make >= ID with cnt!=0 -> dig_stb. CLR = counter tap (digital, exact 256).
- port.v: busy = bsy|fe|(fm&!m); detectors are RC+'14 in hardware (fabric.md 3.5 "up in 16, down in 256");
  monitor CLR/ID/HIT are '4040 taps (digital, exact). Classifier watch is digital: T_ARM+2 = 18 ms after the
  hold write (~20-21 ms after the rise).
- Control log run_r_snap256.log: break 680; A11 free at A 936; X11 free at X 936 (same ms); X cell CLR 938.
  So at NOMINAL the cell lags both ports by ~2 ms; the only margin is the free->re-write time of A's sweep.
  A11 = port 9, visited at step 8 of the stride-9 sweep (~1.1 ms in) -> ~10-13 ms min for THIS port; a port
  visited late in the stride order can be re-written ~1.5-2 ms after it frees -> margin ~0 ms (C20 says
  0.1-0.3 ms). So "5% short" is generous: ANY short RC at the dropping end opens finding 3 for some ports.
- HC14 threshold spread (datasheet VT-/VT+ at 4.5 V) alone gives roughly +-35% on an RC-to-Schmitt time;
  plus C tolerance. So ~half of ports release before the far cell's digital CLR. Finding 3 is ordinary.
- NEW VARIANT (code reading, not run): abandon AFTER e (cell in M_WANT_B at exchanges with OWN_E = e_old):
  hang-up break -> cnt=1 (done->1), re-seizure make -> digit 1 -> if OWN_B == 1 the cell claims at the
  re-seizure's ID, before the new caller dials anything, whatever the new call's digits. Exposes every x1
  exchange (21, 31, ...), not only backbone 1x. Only via finding 3's route (a <T_ARM seizure has no digits).
- Abandon mid-e (k pulses then hang-up) -> stale digit k+1 -> exposes OWN_E = k+1 exchanges.
- Trigger frequency: finding 3 fires on ANY flood dropped before b (caller hang-up, T_KEY 5 s, guard) on every
  tree link whose dropping-end RC is short; finding 1 needs glare (last free channel, ~1.35 ms window; C13:
  ~1e-4/call loaded) or a hang-up inside a ~16-20 ms window. Finding 3 is the dominant real path.
- Glare/origin: net_unit.v 791-804: ANY M on a held trunk while o_net and !claimed is the claim -- the stale
  cell's claim at the new call's e (or at the re-seizure's ID in the M_WANT_B variant) is accepted at once
  and the other legs dropped; so the true owner never sees b. Silent at the network (no EV_, outside guard).
- RC partial charge: a seizure that stood only ~16-60 ms charges the RC partly; its release is shorter
  (~110-240 ms at typical thresholds) at BOTH ends -> fresh classification + stale cell at nominal parts.
  Widens finding 1's window from <~20 ms to ~<60 ms of seizure life. Still rare (hang-ups in that window).
- Slow-arming RC: classifier's digital watch ends ~20-21 ms after the rise; a port whose fM RC arms later
  (slow '14 VT+, high C) and a seizure dying between the two -> hold never cleared (stuck BUSY, C08-like)
  and the cell stale until CLR / fix (b). Fix (a) completeness caveat: set the watch to the RC's max up-time.
- C04 verify notes: C04's trigger is NON-conforming at real timers (first break within guard+18 ms). So in the
  C03/C04 conflict C03's fix should win; fold the 18 ms watch into the guard's reach budget for C04.
- 01:16 queued ONE run: run1.sh (tb_c03b, M_WANT_B variant, snapshot, A T_REL 200, A T_KEY 2000)

## Rate arithmetic (order of magnitude; reference net: 10 exchanges in a tree, 9 links, 500 floods/BH)
- Finding 3: pre-b abandons ~3% -> 15/BH. Unresolved far cells per abandon: pre-e all 9 legs; post-e ~1.25.
  P(dropping-end RC frees before far digital CLR) ~0.5; mean window ~25 ms; next flood same side same
  channel ~0.07/s x 0.025 s x 0.7 = 1.2e-3. Match: pre-e (1,e_new) needs X=1b and e_new=b ~0.03;
  post-e (M_WANT_B) needs X.b=1 ~0.125. => ~2e-3 wrong numbers/BH network, ~2e-4 per exchange-BH,
  ~4e-6 per call. Scales ~lambda^2 x size: 20 exchanges at 2x traffic -> ~0.07/BH network (a few a week).
- Finding 1: sub-~20 ms seizures: hang-up just after the seizure ~1e-4/flood (x ~5 legs), glare ~1e-4/call
  only when links are near full (C13). Re-seizure within 256 ms ~1.25e-2, match 0.03 -> ~2e-7 per call,
  ~1e-5 per exchange-BH. ~20x rarer than finding 3.
- Finding 2: stale cell holds 256 ms vs a normal flood ~1 s at every exchange -> negligible added blocking.
  Only an intermittent A conductor (bouncing idle channel, blips < T_ARM) could keep both cells stale:
  X then owns no call (clean cannot-complete). Low. Fix (a) closes it.
- Subscriber experience: the far caller is connected to a stranger at the wrong exchange (X's line b h or
  e b); the stranger's phone rings and is answered; no event at any exchange. Indistinguishable to the
  caller from their own misdial (redial works). Data calls: a modem connected to the wrong line.

## Adjacent (outside this cluster, not simulated)
- The origin drops its trunks on a hang-up only at r_gone = register CLR (256 ms digital, pulse_reg.v:139)
  and N_DROP writes every d_held trunk to 00 (net_unit.v:821-828). A trunk whose own fE RC is short has
  already released itself and may have been re-seized by the forwarder (the sweep ignores `mine`): the late
  N_DROP then cuts an unrelated flood's leg. Same RC-vs-counter root. Resolver R_GONE writes likewise.

## Run result (run_b_snap200.log, snapshot, A T_REL 200, X = 31, A T_KEY 2000 for sim time only)
- A's origin drops at T_KEY (2630); X's cell was in M_WANT_B (cnt=3 = e). Drop break counted cnt=1 at 2640.
- A11 free at A 2831 (201 after the drop); Y's flood on A13 at 2832; A re-seizes A11 at 2844-2845.
- 2974 (130 ms after the re-seizure, BEFORE Y's caller dials anything): X's stale cell st 2 -> 3, claims:
  X11 bkA=1, X's register attached, and at 2975 A patches A13 to A11 -> Y sees the claim.
  => M_WANT_B variant CONFIRMED: an exchange with b = 1 (not a backbone code) claims the re-seizing flood
  whatever its digits. Verifier's "a wrong number needs an OWN_E = 1 exchange" is too narrow for finding 3.
- Rest of run: X's register read Y's e b = 2 4 as h s; X24 rung (X2x busy=00010000). 8 checks, 3 FAILs
  (claim before any digit, register attached, X24 rung); both exchanges idle afterwards. obj dir deleted.
  Fix (b) would free that cell at 128 ms of break, before the re-seizure at +214 (code reading; not run).
- Stride check: sweep visit k of port p = 57(p-1) mod 64. A11 (p=9) step 8, so ~10-13 ms from free to
  re-write; a trunk at 13 (p=11) is step 58: ~2 ms, i.e. ~1 ms of nominal margin against the far cell.

## Verdicts
- stale-cell-after-unhold: agree, confirmed, high (consequence-weighted; rate ~1e-5/exchange-BH, the rarer route).
- stale-cell-starves-monitors: agree, confirmed-overstated, low.
- rc-tolerance-reseize: DISAGREE on severity: confirmed-understated, HIGH (not medium). Ordinary trigger
  (any pre-b drop x half of ports), wider exposure (M_WANT_B variant: any x1 exchange, claims whatever
  is dialled; run_b_snap200.log), ~20x finding 1's rate. Principal real-hardware route to the wrong number.
- Fix: (a)+(b) right for 74HC and minimal; port compare redundant. Gaps: port-level lost flood (C20);
  RC partial-charge residual for seizures dying ~20-35 ms (negligible); C04 conflict -> keep C03's
  immediate write-away, do not adopt C04's C_LOW, budget the watch in the guard (C04 is non-conforming).
