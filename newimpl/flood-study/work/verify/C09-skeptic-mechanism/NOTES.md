# C09 skeptic review (mechanism + realism lens) -- notes, 2026-09-27
Read-only unless one run settles a disagreement.

## Mechanism re-derived from the snapshot (no sim run)
- CONFIRM phase is structural: last sweep read = port 70; word_rx's done comes at the a_stb of the
  8th frame after the select = mid 00's bit-time; probe publishes 00 at the end of that bit-time,
  so CONFIRM counts 00..77 and h_done is registered on 77's sp_fresh, the same edge as the watch's
  C_UNHOLD. Next edge: w_cls pushes unhold + sets f_cancel; F_HUNT reads old f_cancel=0 -> F_WRITE.
  Next edge: w_fwd (no f_cancel term) pushes leg + way back. CONFIRMED as claimed.
- Stuck: 77 addr 13 bsy1, m=0 (cm never reached T_ARM), e=13's M=0; 13 addr 77 bsy1, m=0, e=0.
  No rel. Resolver: R_LEG needs 13's M, R_GONE needs 77 !BUSY. CONFIRMED.
- Only socket 77 exposed (next fitted sample, 01, is 64 ticks after h_done). Other ports need
  F_WRITE blocked >= 2 bit-times: one-leg cnt_fwd = 2 -> room < 2 -> >= 15/16 queue (verifier said
  13/16; 14/16 is the 3-leg figure, and 3 legs are harmless). Or an UNHOLD blocked by room 0 across
  h_done (16/16).
- CONSEQUENCE CORRECTION: a stuck 77 is BUSY, so it can't be classified/forwarded again until it
  heals; no other port reaches the window short of a full queue. "Second occurrence exhausts NRES"
  (auditor) / "right while both pairs unused" (verifier) is practically unreachable.
- Heals from either end (A reseize: 77 fM arms, falls, rel, R_GONE; C seize: R_LEG frees resolver,
  later 13 fM / 77 fE fall). Long-run fraction of time degraded ~= per-use trigger probability
  (trigger needs a use of the channel; healing needs the next use), independent of channel usage.
- Glare-as-claim trigger: origin glare comes 1-5 ms after its seize; drop reaches neighbour 2-5 ms
  after its rise -> cancelled in F_WANT/F_HUNT. Only a residual-glare-through-a-one-leg-patch chain
  lands near h_done. Negligible next to the abandon trigger.
- Interaction: while stuck, B's monitor cell on 77 stays held for CLR (256 ms). A reseize of the
  channel inside that window is counted one digit out of step by the stale cell = C03's wrong-number
  mechanism. Covered by C03's fix (free the cell at C_UNHOLD), not by C09's.
- Fix: the verifier's copy (rtl_fix) = !f_cancel on w_fwd + F_WRITE exit on f_cancel. Complete for
  the race (w_cls outranks w_fwd; anything that blocks w_cls blocks w_fwd). In 74HC the push strobes
  ARE w_fwd, so the w_fwd gate is the load-bearing one; the exit is needed too or the forwarder
  hangs in F_WRITE (f_cancel only clears at a new forward's start, which needs F_IDLE). Neither is
  optional in hardware.
- Out of cluster (hardware only): the watch is a counter (ends 17-18 ms after the hold, ~18-20.5 ms
  after the rise); the arming is an RC + '14 (16 ms nominal). An RC slower than the watch leaves a
  seizure that dies between them held BUSY with nobody to clear it. The RTL shares one T_ARM
  parameter, so it can't show this.
