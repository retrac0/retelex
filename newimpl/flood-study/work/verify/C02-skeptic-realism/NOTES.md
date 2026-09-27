# C02 skeptic review (lens: realism and severity)
Started 2026-09-27. Read-only; no sims unless one settles a disagreement.

## Read (snapshot only)
- mini_marker.v:271-282 (att_take/att_refuse, S_WATCH exemption), 538-553 (WATCH exits), pulse_reg.v (settled =
  steady && nd_t>=SETTLE; nd_t reset only by attach/release/restart/dig_stb), pulse_rx.v (steady, arm at attach),
  net_unit.v:459-487, 598-675 (one claim handler; M_DONE cell clears on d_clr only), 840-885 (T_CLAIM 2 s from b at
  the origin; guard only before b). marker.v:268-273 same exemption; S_NAIL one tick; att_take IDLE/DRAIN.
- Verifier's logs: run_att2r_snap.log matches its summary (claim1 att 3689, claim2 want 8195, h 8863, attach 8959,
  counts 2 2, B22 rings). faults.py: no anchor on att_refuse (F37/F48 anchor elsewhere) -> deletion safe for faults.
- New docs carrying the rule: exchange/network.md:189, exchange/marker.md 4.8 (~l.269-271) and 5 (~l.295).

## Realism results
- Conforming WATCH: ~33 ms (settled); worst ~290 ms (abandon inside SETTLE -> CLR) / ~320 ms (flash then off-hook).
- Chatter must START within ~36 ms after s's dig_stb (+read/probe/words): a line already chattering never completes s
  (makes < ID) so never connects. Needs a coincidence, or a trigger tied to the connect (speculative: ringing onset
  ~16 ms after the connect, T_ARM, disturbing a marginal analog loop's feed).
- Bench chatter 1 ms/2 ms is driven straight onto M (site_net has no detector RC); the real CVSD detector (4 ms RC,
  7.6 ms to assert on-hook) would swallow it. Realisable equivalent: raw breaks >= ~8 ms, raw makes < ~26 ms. The
  mechanism is shape-independent, so the repro stands. CVSD detector reads random bits as steady off-hook: digital-line
  faults are unlikely to chatter; analog FXS line or a faulty phone is the plausible source.
- T_CLAIM (2 s from b, origin) bounds the wrong-number window: WATCH must end within claim 2's h AND within ~1.9 s of
  claim 2's want, else the origin has dropped (clean).
- 2-site: claim 2 needs A's single register freed (A20's h s) and A21's 1 e b: D >= ~5 s, capped by NODIG 10 s.
- Rate estimate (lambda_claim ~30/h): healthy exchange ~0; with a chattering line ~1e-7..1e-4 per busy hour.
- Human rotary pauses can be < 720 ms (ES 201 187 floor binds senders); margin claim-want->h maybe ~350-450 ms for a
  fast dialler. Still > ~320 ms conforming WATCH, but thin for a C01 +fixatt-only fix.

## Verdicts
- F1: agree, confirmed-overstated, low. F2: agree, confirmed-overstated, low (lone claim = late clean refusal).
- Fix: deletion correct, zero gates, complete (remaining waits <= ~2 ms: S_READ free register, full queue, one-tick
  u_local/u_done/u_nogo). Refusal in WATCH re-asserts restart via !bus_idle -> WATCH +<=32 ms, harmless.
  marker.v edit untested: run tb_max. "No service cost vs snapshot" true bar two claims in one 33 ms WATCH.
