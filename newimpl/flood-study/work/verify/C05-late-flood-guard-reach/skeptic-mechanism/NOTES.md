# C05 skeptic review (lens: MECHANISM) -- notes
Started 2026-09-26. Read-only; at most one short sim.

## RTL re-derivation (snapshot)
- cls_seen (283-284) needs C_IDLE, M up, BUSY clear, !st. st cleared by any M-low sample (566-567). CONFIRMED.
- C_HOLD (584-588): cls_ms counts tick_1k from the hold push; any M-low sample -> C_UNHOLD; exits at cls_ms>17 -> 18 ticks. Hold push ~1.8 ms after rise => watch = rise+1.8..~rise+19.8. CONFIRMED.
- C_UNHOLD (590-594) writes src00 bsy0; f_cancel only if fst!=F_IDLE (and F_WRITE ignores it: C09).
- port.v:147 busy = bsy|fe|(fm&!m)|mute. fe=0 (listening to 00, unfitted). At the make m=1 -> busy 0 -> cls_seen + R_GONE on the same sample. CONFIRMED.
- pulse_rx arm: m_d loaded while !arm, t from arm; a break in progress at arm counts if >=HIT remains. A cell attached at the make after break 1 counts e-1. CONFIRMED.
- Verifier logs d124 and l1 d104 read: timings match the claims (unhold 35.68 / 56.68, re-seize 96.5 / 117.5, fwd cancel at 42.0 / 61.0, re-forward 107 / 128).
- Bench injects the break at B directly (sm), no per-transit relay lag of the break (0-1 ms/hop, avg ~0.5). Depth arithmetic shifts <1 hop. Not material.
- new network.md 6 budgets "the last exchange's monitor attaching" (2-3.5 ms) only; watch not counted. network.md 3.4 rule 1 'up to 20 ms behind a busy classifier' -- but a cell 20 ms late then gets its OWN 18 ms watch (l1 d104: exposure to rise+38).

## Second paths / disagreements found (reasoning)
1. VERIFIER'S CHEAP STOPGAP IS WRONG (lateness bit alone, 'M at the last visit'): in l1 d112 the snapshot log
   (work/audit/fwd/run_fx_sc6_l1_d112.log) shows E30 BUSY->0 at 108.020 (the make; fm&!m held BUSY through the
   break), cell at 109.514 = pickup at the FIRST visit of the make. At that visit M was LOW at the previous visit ->
   the bit reads it as a fresh rise -> cell -> e-1 -> wrong number persists. The bit only marks pickups inside a
   standing make: the initial make (harmless: cell arms before break 1) -> so it LOSES the cell of every 2nd
   seizure of a burst (lost ownership) and closes nothing. cls fix's own late bit (cls_late<=ml) has the same hole;
   cls fix closes l1 d112 via its rise queue + watchers off the classifier + BUSY-qualified st, not the late bit.
2. SCAN-ORDER PRIORITY (cls slice N4, run_c3_sc7.log, measured): C_HOLD exits one clk after tick_1k (scan 00),
   so the next port taken is the LOWEST-numbered waiting, not FIFO. 47 waited 188 ms behind 11..16 arriving later;
   wrong number (POOL8). Verifier's 'k-th waits 19(k-1)' understates; on NMON=NRES=2 stuffing mostly self-limited
   (cells/resolvers exhausted), bites with larger pools (network.md 10 says pool must be resized).
3. Transit misread on the snapshot also LOSES the true owner beyond it: original forward dropped at the make
   (R_GONE), re-forward carries e-1 -> owner's cells: first sees break then CLR; fresh one counts e-1. Verifier lists
   this only as a Fix-1 cost. (Wrong number still needs (e-1,b); in a tree it is in its own window anyway.)
4. Same terminal mechanism (st cleared by a dial break -> make taken fresh -> e-1 cell + mid-digit re-forward) has
   non-late triggers: cls sc3 (word read hit -> unheld with st set -> first break clears st) at ANY depth/conforming
   dial; o6 sc6 (called party hangs up first). C_LOW closes none of these.
5. C_LOW with ID: lows of 128-256 ms inside the watch (C07 outages) unhold at 128 then re-seize at M's return
   (fm armed -> BUSY via fm&!m until then) -> same mechanism. CLR (C04 verifier's choice) closes it; costs a 256 ms
   classifier block on a real death. Either way C_LOW blocks the classifier ID/CLR on a real death (snapshot: 0),
   at every flood-front exchange of every guard-abandoned call; widens finding-2 late pickup for OTHER fast callers.
   Conforming callers still safe (581 ms).
6. F4' (cls fix2: st set on ANY BUSY sample, cleared only M low & BUSY low; 0 gates) closes l1 d112 (fm armed at
   rise+16, break at +17 -> BUSY through the break -> st set -> make not fresh -> lost copy) but not breaks <16 ms
   after the rise (fm unarmed: no BUSY in the break).
- 00:07 queued ONE run: run_late.sh (snapshot + lateness bit alone, tb_fx sc6 l1 d112) -> run_late_sc6_l1_d112.log
7. e = 1 variant (reasoning): the re-seized cell arms at the make after e's ONLY break; pulse_rx gives no digit for
   cnt 0, so the cell counts b as e and h as b -> victim is exchange (b, h), not (e-1, b). Same for the mid-digit
   re-forward downstream. e = 0 -> 9 -> isvc -> released (lost, not wrong). Verifier's victim set '(e-1,b)' misses it.
8. C04 verifier already noted the mid-path lost-call mode (victim set unchanged) and used CLR for C_LOW.
9. monclaim run_real13_all.log:260-264 re-read: 2/21/40/59/78 ms (simultaneous rises, so port order = arrival order there).
- 00:28 run_late still queued (~10 sim.sh jobs waiting, slots held by long load/tb_net runs)
- RESULT run_late_sc6_l1_d112.log (snapshot + lateness bit alone, real timers, 117 s; obj removed):
  '109.514 SKEPTIC hold 30 late 0 -> cell' (pickup at the make's first visit, M low at the last visit),
  CLAIM on 30 at 1437.286, B21 rung at 3138.5: 6 checks, 2 errors FAIL -- identical outcome to the snapshot.
  The verifier's 'cheaper stopgap' does NOT turn this wrong number into a lost call. SETTLED.
