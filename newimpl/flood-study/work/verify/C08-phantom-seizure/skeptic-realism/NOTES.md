# C08 skeptic review, lens: realism and severity
- started 2026-09-27
- Read: findings json, verifier verdict, verifier NOTES, net_unit.v (whole), port.v, pulse_rx.v,
  baseband_card.v, local_trunk.v, tb_pchain.v sc1 + run_pchain.log, rtl_fix diff, new network.md,
  baseband.md 3.
- Mechanism confirmed by reading (agree with verifier): cell freed only by d_stb mismatch / d_clr / claim;
  resolver only by R_LEG/R_GONE/rs_mine; held B11 has no edge. Stimulus ba_i[T11]=stuck||aa is a fair model.
- Trigger realism: benches model failsafe-HIGH (tb_tie.v:36 says "worst case"); baseband.md 3.4 and
  local-trunk.md:178 specify 26LS32 between racks, whose native open-input failsafe is output HIGH ->
  an open A PAIR reads A=1 while clock pair runs -> phantom. baseband.md 3.3 claims "A = 0 either way" on a
  cut: true only for whole-cable (link_up masks), NOT for the A pair alone. Doc gap.
- Zero-cost mitigation neither auditor nor verifier names: make A fail to IDLE on open (pair polarity
  swapped + the A path's '14 is inverting anyway; 74HC population: one pull resistor). Converts the likeliest
  trigger (open pair/conductor/connector) into stuck-at-0 = a clean dead channel. Timeout still needed for
  stuck driver / short to +5 V / failed '14.
- Traffic: network.md 10 says resolvers ~0.19 E per transit, NRES=2 -> 1.4% unforwarded (Erlang B).
  One phantom -> NRES_eff=1 -> B(1,0.19)=16% at every downstream transit; monitors similar at target.
  Local trunk (8 phantoms, 2 forwarded at real timers) -> both cells + both resolvers at B and at every
  exchange downstream -> 100% of network calls into/through B's subtree fail, silently, until repaired.
  Not a wrong number -> high (not critical). Verifier's high is right.
- Killer trunk (finding 2): agree separate root cause, medium. Note: also reached by stuck-at-0 (the doc's
  own intended failsafe) and the same deterministic hunt makes ANY one-way-dead or C-dead channel a killer.
  Auditor's (d) 'failed last time' register misfires: a vacant code (misdial) also ends in no-claim at
  T_CLAIM, in every direction; one-shot skip halves the failure rate, sticky skip excludes good trunks.
  Protocol has no seizure ack; real remedy = per-trunk ineffective-attempt counter/event (maintenance).
- rtl_fix review: R_AGE only from R_NONE; watch's R_GONE/R_LEG assigned later in source wins same tick;
  expiry in (2T,3T] = 10-15 s vs legit max ~7.3-7.4 s (cell in M_DONE waiting on att: T_KEY+ID+T_CLAIM+CLR).
  Re-hold of incoming correct for the stuck case. NIT RACE: if the fault is mended and the incoming port
  releases (fM fell) in the <=1 ms before its next turn and a strobe lands there, R_AGE re-holds a port
  with M=0, fM=0 -> BUSY with no edge, lost for good. ~1 ms / 5 s = 2e-4 per mend. Guard: re-hold only if
  the incoming's M was seen up at its last turn (1 FF/resolver) -- negligible.
- No event word in rtl_fix: after expiry the faulty channel is parked BUSY at B and a killer at A, silent.
  An EV at expiry naming the port is nearly free (ev_* path exists) and is the only locator. Recommend.
- Intermittent form of the same conductor fault = the proto slice's tb_pflap finding (outage counted as a
  dial pulse -> wrong number): separate cluster, worse, not touched by this fix.
- monitor.md 4 traffic: leaf monitor load 0.09-0.26 E; NMON 2->1 at that load = Erlang B 8-21% of calls to
  that exchange lost (vs 0-2.6%). ~43 network calls/exchange/BH on monitor.md's 48-line/3-calls/30% model.
- Stuffing does not save it: local trunk gives min(8,NRES) forwarded phantoms at real timers, and 8 exceeds
  any plausible NMON/NRES.
- 26LS32: one wire of a pair open usually still receives (the driven wire still crosses the bias);
  stuck-1 needs the PAIR open (half-seated connector, damaged pair). Single-ended baseline: one conductor,
  but the input pull is unspecified; a floating RC+'14 input can flicker = pflap-type pulses (worse).
- 4-wire population (baseband.md 3.3 bottom row, no clock conductor) + fail-high = a pulled cable is N
  phantoms. Doc accepted "one call per attempt" assuming A=0 on a cut.
- No sim run: no disagreement a single run would settle. Fix effect on the phantom still unsimulated.
- VERDICTS: F1 confirmed, high (agree). F2 confirmed, medium (agree). Fix: verifier's rtl_fix correct and
  hardware-cheap; add event word, specify fail-to-idle A receivers, nit mend race; auditor's (d) misfires on
  vacant codes.
