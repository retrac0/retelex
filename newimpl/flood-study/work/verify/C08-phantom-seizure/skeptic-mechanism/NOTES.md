# C08-phantom-seizure: skeptic review (lens: MECHANISM)

2026-09-27. Read-only. No simulation run: the disagreements below are about scope and about the fix, and settling either one would need a bench of several exchanges at real timers, which is not a short run.

## Re-derived from the snapshot (every cited line checked; the citations are accurate)
- A cell is freed only by a mismatching decided digit (net_unit.v:635-645), by d_clr (647-649) or by the claim (656-665). pulse_rx on a steady make lets t saturate at 511. dig_stb needs cnt != 0, and clear needs !m. Neither ever fires.
- A resolver is freed only by R_LEG (a leg's M), R_GONE (the incoming's BUSY clear, 689) or rs_mine. On a phantom the leg M is the far hold's backward A, which is 0, and the incoming's BUSY is bsy=1, so neither fires.
- Port: rel happens only on a fall of fM or fE (port.v:180/186). B11 has m=1 and fm=1. Its E is 00, or B14's M after the one-leg patch (732-735), and both are 0. It never releases.
- Link-up watches only the clock conductor (baseband_card.v:109/154; local_trunk.v:127/170/188).
- The auditor's log sc1 matches this. sc1 started clean: idle_all passed after sc0. The stale 'cla 1' flags are only unreset regs.
- Root cause 2 (killer trunk) is separate. B cannot see a rise on a stuck-1 M, held or not, and the same happens with stuck-0. Agree.

## New: the scope is understated (local-trunk case)
- The flood has no TTL, and transits have no timers, so a phantom flood reaches every exchange that a normal flood reaches.
- At real timers: classifier serialisation of about 19 ms per hold (C_HOLD exits at cls_ms=18, then a read of about 1.1 ms) against a forwarder busy for about 10-11 ms (64x9 frames + 1 ms confirm). So B forwards phantom #1 and #2 (NRES=2), as the verifier says.
- The same arithmetic holds at EVERY downstream exchange. The second flood arrives about 18-19 ms after the first. If it arrives inside C_HOLD it waits (st clear) and is classified after. The forwarder is already free and one resolver is left, so it is forwarded too.
- So every exchange that both floods reach over links with at least 2 free channels loses BOTH cells and BOTH resolvers for good. It can never claim again, and it never forwards again.
- One open A conductor on one local trunk, while HCLK runs, therefore kills network calls network-wide, silently. Nothing names the port.
- Even the single baseband phantom leaves every exchange it reaches with 1 cell and 1 resolver. At the network.md §10 load of about 0.19 E, Erlang B with one server loses about 16% of floods at each transit.
- Nuance: only channels IDLE at the fault become phantoms. A channel carrying a call has st=1 (M under BUSY) and is never re-classified. When its call ends it is left with M up and BUSY clear: a dead channel, no flood. The marker re-reads its word once a pass for good, which is harmless.

## New: the verifier's fix has an unconditional write hazard
- R_AGE for rs_two writes ent(in, 00, bsy=1) whatever the incoming's M is.
  - If the incoming has already released (M down, fM down), that strands it BUSY with no edge. This is exactly the hazard the classifier's T_ARM watch exists for.
  - C10 path: a local-trunk cut means MUTE_BLK, and R_GONE never fires. The incoming releases after T_REL and the legs release through fE. At 10-15 s R_AGE drops "legs" that may by now carry other calls, and re-holds a dead incoming.
  - With C10's rs_lf fix present, that path dissolves first. The remaining case is a mend race: R_AGE set when rel happens, plus or minus the write latency, a window of about 1-2 ms per 5 s strobe.
- Refinement: have the resolver's own once-a-pass watch latch the incoming's M. At R_AGE, if M is up, drop the legs and re-hold; the legs cannot have self-released, because their E is that M. If M is down, dissolve and write nothing. T_REL (256 ms) is much greater than the latch-to-write gap (2 ms or less), so no race remains.
- (c), the event word naming the port, should be mandatory. After the fix the port is parked in silence, and the far end's killer-trunk effect goes on.
- (d), a one-entry "failed last" skip register, does not help a local trunk, where all 8 channels are dead at once. A per-direction no-claim count feeding EV_NOCLAIM or an alarm, plus maintenance make-busy, is the practical remedy there.
- Cheaper Q13 variant: the minimum is 8.19 s against a legitimate maximum of about 7.26 s (T_KEY + T_CLAIM + T_REL). The margin is 0.9 s, and a change to the T_KEY or T_CLAIM straps breaks it. Prefer the strobe derived from T_KEY.

## Aside, not in this cluster
- An INTERMITTENT A conductor (a bouncing bad crimp) puts breaks on a seizure that has no origin and no guard. A monitor somewhere could decode a matching e b and claim, and the register would take random h s. That is a different mechanism (noise on A) and is not assessed here.
