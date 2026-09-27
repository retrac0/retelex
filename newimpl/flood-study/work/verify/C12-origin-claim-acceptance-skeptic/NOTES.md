# C12 skeptic notes (2026-09-27)
- started; read findings json, verifier NOTES, fix.patch
- RTL read: net_unit.v 794-804 claim = one sp_m sample on any d_held trunk in N_NET/N_WAITCL; no f2 check. CONFIRMED.
- CORRECTION to verifier: frame = 15.6 us (64 kHz TX_CLK; 64 bit-times per 1 ms pass). A one-frame A error
  on local trunk is seen by the 1 ms probe 1 time in 64, not 1 in 8.
- Stuck-A=1 far card trigger mostly BLOCKED: sweep rejects a trunk with M at its select/confirm (h_m, H_CONFIRM),
  and the classifier would take it as a seizure. Only a card failing within the ~3 s window matters.
- Spec (exchange/network.md 4.1 table l.203): "claim the FIRST M seen on a held trunk" -> RTL follows spec; hardening gap. CONFIRMED.
- Legit-claim lead vs f2 (analysis, RTL constants): lag = (p-q)/64 + c0 + u + w, u,w in [0,1), c0 ~0.32 ms
  (WAIT 640 clk=156us + 17x32 clk=133us + 2x 1-2 frames) or ~0.17 if the far unit already holds the bus;
  p = caller port, q = far trunk port; lag == r/64 (mod 1 ms), r = origin trunk port.
  Checked against lfull_fix C12T trace: lag = r/64 + 0.015 + k exactly (1/64 per port, 1 ms jumps). 
  Worst legit lead: p=01, q~76 -> about -0.6..-0.8 ms (claim seen BEFORE f2). Benches never show it:
  tb_net/tb_chain run all exchanges on ONE clock and have callers 20-27 above trunks 10-17 (p>q).
  => verifier's "never before b" is a bench artefact; the no-slack variant (b) would nogo real calls;
  the 4-sample fix (3 ms slack) is safe with >2 ms margin.
- Second path (worse for snapshot): C07 outage 8-256 ms in the e->b pause is counted as b=1 by every
  monitor beyond -> exchange (e,1) claims before b (wrong exchange); if the dialled b is 1 the TRUE owner
  claims early and its register takes b h as h s (wrong line at right exchange). Both are early claims ->
  the C12 fix makes them nogo. Verifier listed only the pre-e (1,e) case.
- Stuck-A=1 card is blocked by the sweep (never seized); not a realistic trigger.
- mc2_fix.log checked: X still claims at 1894 and holds its register to 2156; A EARLY 1897 -> nogo 1898.
- No sims run (read-only review).
