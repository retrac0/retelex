# C20-misc skeptic review notes (2026-09-27)

Lens: mechanism + realism/severity. Read-only on snapshot.

## F1 claim-legs slot collision (read net_unit.v 283-284, 358-367, 470-498, 584-622, 656-745)
- Verifier's argument holds for the case "old resolver exists when P is seen free": the resolver watch
  (681-690) and cls_seen (283) read the same sp_fresh/sp_busy of P, so R_GONE lands at or before the visit
  that re-classifies P; the new resolver needs a hunt (~10 ms) and w_res clears the old one first.
- SECOND PATH the verifier missed: the old resolver can be CREATED AFTER P's re-classification visit.
  C_UNHOLD (590-594) sets f_cancel while fst==F_WRITE, but F_WRITE ignores f_cancel (725; = C09) and w_fwd is
  below w_cls in priority, so R1 (rs_in=P) is created one tick later on a port that is already free. If P's
  next visit sees P free and re-seized BEFORE R1 exists, the new hold makes P BUSY at every later visit, R1
  never sees R_GONE, and a second resolver R2 for P follows 10 ms later -> two rs_mine resolvers.
  Needs: C_UNHOLD inside F_WRITE (sub-ms), w_fwd held off >= ~1 ms after it (queue room < cnt_fwd for 1 ms
  = 13+ words queued), AND the far end re-seizing within ~1-2 ms of abandoning (possible only if its port's E
  stood < T_ARM, i.e. the far origin dropped within 16 ms). Not reachable in practice. Closed by C09's fix.
- Consequence if reached is WORSE than auditor said: R1's legs stay up listening to P and carry the caller's
  digits in the same directions as R2's; a far claim on an R1 leg makes R1 (R_LEG) rewrite P onto R1's leg
  under R2's connection. Still no plausible trigger. Verdict: not-a-bug / info (agree), with the caveat.
- Auditor's fix (one rs_mine per tick) is not a fix (agree with verifier). A correct cheap RTL guard: in
  w_claim, set the extra resolvers to R_GONE instead of freeing them, or assert.

## F2 WAIT (ctl_write.v 69-113, ctl_queue.v 145-181, net_unit.v 219-232)
- Re-derived: marker oe edges 0..547 (s_req at 0, ctl_write busy 1..546, s_busy_d -> t IDLE at 547); unit
  want_bus after the push edge, granted at +640, oe at +641 -> gap 94. Agree with verifier's 94.
- HCLK = cell clock 512 kHz (8 master ticks), HCLK/4 = 128 kHz = SCLK: same word time. A free-running SCLK
  adds at most one bit-time (32 ticks) of phase wait: still inside 94.
- Verifier's PW=9 residual is weaker than stated: at PW=9 ctl_write.v:80 still shifts n=16 and ctl_queue's
  15-bit entry has fixed fields (head[11:6], head[5:0]); exch.vh:7-11 says PW and the fold are one decision.
  WAIT would not be the first thing to break. info.
- F1 extra: for a ONE-leg forward, C09 says the way-back write re-holds P BUSY for good, so R1 is stuck but
  P can never be re-classified -> no second resolver. The F1 path needs a multi-leg forward + w_fwd delay.

## F3 port 00 (port.v 88-153, site_net.v 95-133, block-stack.md:332, numbering.md:30)
- Agree: loud outage at X, no steady-state wrong number (run_z.log read). Scope understated by verifier:
  * transient: when 00 goes off-hook every flood X is HOLDING (latch 00) sends backward A = 1 -> the origin /
    upstream resolver takes it as the claim (net_unit.v:795-804, 682-687), drops its other directions, and at
    o_last patches the caller to the trunk: one-way to the phone at 00 (C via hc[0] slot 0). ~1 per incident.
  * steady: idle X trunks send 00's M forward -> neighbours hold, give a MONITOR (never freed: no digits, no
    256 ms break) and FORWARD -> phantom floods radiate, exhausting NMON=2 cells and NRES=2 resolvers at every
    exchange they reach -> network-wide loss of incoming calls while 00 is off-hook. Clears on hang-up + unwind.
  * trigger broader than "a card at 00": JP1 POS shunt reads 0, open reads 1 (block-stack.md:332); a port card
    moved from slot 0 of another block into a block-0 socket keeps POS=0 and drives bit-time 00. Maintenance slip.
- Severity low stands (plausible maintenance fault, loud: every idle phone at X rings; clears on hang-up).
  Fix: model lint as verifier says; on the board a debugger lamp "anything pulled /HA or /HB in bit-time 00"
  is ~free and makes it self-announcing. Masking the E capture at 00 would be WRONG (freezes e_cap: a port
  cleared by fM with E still 1 would ring for ever).

## F4 release margin (port.v 144-193; fabric.md 5.2-5.3, 8; net_unit.v 283-284, 566-570, 750-785)
- Agree with verifier's mechanism and sims (read run_n11_full, run_s240_full, run_n70_scan).
- RC spread is much larger than the 6% simmed: 74HC14 VT- at 4.5 V spans roughly 0.9-2.0 V (datasheet
  min/max; from memory, order right), so an RC-to-Schmitt fall time spans ~0.68x-1.39x nominal, before C
  tolerance. Two ports' T_REL can differ by up to ~180 ms; typical tens of ms. Every sweep placement's
  2-15 ms margin is inside that.
- ASYMMETRY (new): the still-counting end is stuck only if its BUSY is a term that does not cancel when M
  returns: the unit's hold latch (bsy) or fE. fm&!m cancels itself (m back up -> BUSY 0 -> classified).
  Flood-branch drop: far end = hold latch, near end = fE -> both orders bite. Call end (claimed trunk):
  exactly one order bites (the end whose last detector is fE). So every trunk release is exposed, not only
  abandons.
- Rate (tree net 10 exch, 500 floods/BH, ~9 releases/flood, sigma(T_REL) 8%): E[window] ~17 ms, hunt rate at
  the freed end ~0.14/s -> ~1.7e-3 per release -> ~7/BH network, ~0.7 per exchange-BH; ~half lose the call
  (cannot-complete after T_CLAIM) -> ~0.5% of floods at that load; scales ~lambda^2, rare at hobby load.
  Clean failure -> medium. But it is the enabling race for C03 rc-tolerance-reseize (wrong number, high).
- SECOND PATH, same root, worse (reading only): resolver R_GONE write-away (net_unit.v 688-689, 691-698).
  Leg L listens to P; P's M falls; L self-releases on ITS fE, P frees on ITS fM; if L's RC is shorter by more
  than the hunt latency, this exchange's own sweep (759 does not exclude rs_held/d_held) re-seizes L for the
  next flood, then R_GONE at P's free writes L to 00. Fires on the NORMAL unwind of every unclaimed branch.
  The new holder keeps L in rs_held/d_held; `mine` masks L from the classifier; a later far seizure of that
  channel shows M on L and is taken as the claim (R_LEG / origin claim watch) -> the new caller is patched,
  one-way, to a stranger's flood. N_DROP after abandon (r_gone 256 digital vs trunk fE RC) same shape.
- Fix: doc line insufficient (agree). Hold-off is the right class but verifier's "G about 64 ms" contradicts
  its own condition: G must exceed the RC skew, ~200 ms from the near port's free (rest 200-400 ms), and
  >= 256 - T_REL_min to also close C03. Cheaper alternative: trunk card presents NONE until both A
  directions have been low for G (> T_REL_max ~400 ms digital, ~600 ms if an RC), reusing the card's
  power-up hold-off; covers main, mirror, write-away, carrier asymmetry; must go into network.md 2 carrier
  contract (MF8/local trunk per channel). Plus a one-gate digital complement: drop a candidate at H_CONFIRM
  when `mine` is true at its turn (779-782), closing the write-away family whatever the RCs.
- No sim run: nothing here is settled by one run (the RC spread is a datasheet question).

## Final verdicts (skeptic)
- F1 not-a-bug / info (agree). Verifier's "no timing reaches it" has a gap: via C09 (F_WRITE ignores f_cancel)
  plus a >=1 ms w_fwd delay plus a far re-seize within ~2 ms. Not reachable in practice; C09's fix closes it.
- F2 confirmed-overstated / info (agree). 94-tick gap re-derived. PW=9 residual moot: ctl_write n=16 and
  ctl_queue 15-bit entry also hard-code PW=6.
- F3 confirmed-overstated / low (agree on label). Scope wider than the verifier says: transient hijack of floods
  X holds (one-way to 00), network-wide phantom floods holding monitors/resolvers; trigger includes a card
  moved into block 0 still jumpered POS=0.
- F4 confirmed-understated / medium (agree). Exposure: every trunk release (asymmetry analysis), RC spread
  tens of ms. Fix: hold-off sized >= ~200 ms (not 64), or card-level word gate; plus mine-at-confirm gate.
  Write-away path (R_GONE / N_DROP) is a candidate separate finding, possibly high; needs a bench.
