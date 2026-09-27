# C15 skeptic (mechanism + realism) notes
Started 2026-09-27. Read-only review of C15-one-register and the verifier's verdict.

## Code re-derivation (snapshot, read-only)
- mini_marker.v:273-282: take needs !r_busy and IDLE/TAKE/DRAIN; refuse needs r_busy, !rd_done, state!=WATCH. In S_READ(caller) r_busy=0 so a claim WAITS, then takes in S_TAKE/IDLE. S_YIELD (origin), S_COLLECT, S_PROBE, S_READ(called), first DRAIN tick: refused. CONFIRMED exactly as the auditors say.
- net_unit.v:881: N_DONE only from N_WAITCL (needs f2 = b counted) and o_last. N_DONE writes caller<-trunk (818-822). Caller on SILENCE since the key (mini_marker 428). CONFIRMED.
- Fix diff (rtl_fix/net_unit.v): only 881 + o_last removed. Since N_DONE is still only reachable from N_WAITCL, glare inside the guard still waits for e b (own code / service digits still checked). Correct and minimal.
- WATCH exit: r_release at WATCH->IDLE; pulse_reg busy drops one edge later, so att_refuse fires on the first IDLE/DRAIN tick. = C01 (watch-exit-refusal / late-refusal-no-edge-hold). Consequence for C15: 'graceful, nothing held' is false on the WATCH path (C01's stuck CLM hold). Not a new finding; a dependency.

## Second paths / realism
- Remaining party re-seizure: when one party clears, the other's port releases 256 ms later and, still off-hook, is M.!BUSY -> the marker gives it the register and dial tone (documented: old marker.md 186-187, mvp.md 108). Held until hang-up (+CLR) or NODIG 10 s. One per answered call at the exchange of whoever clears second. NOT in reg1.py nor exch.py net. Estimate +0.03-0.06 E at 48 lines/3 per h -> refusals ~22% -> ~25-27%.
- Retries: a refused claim is still 'claimed' (CLM), so its flood costs every link/monitor/resolver as much as a success; callers redial -> attempts x1/(1-p) ~ x1.25 at p=0.2, on origin registers and on every link's flood load.
- No event word for a refused claim (counters.md 9.2 has o01 for a local caller waiting, glare, no-trunk; RTL emits only 04 and 10). The loss is invisible to the operator.
- Rotary humans pause >0.8 s (model's fixed 0.8 s is the 10 pps keypad sender speed); model's occupancy optimistic for rotary. 3 calls/h/line is business-level; residential ~1-1.5 -> ~8-10% at 48 lines.
- Crossing pair on the fix: both still refused iff the two b digits are counted within ~ the claim's return delay (~1.2 ms each side on a direct link, from fixR timestamps: monitor +1.0 ms, CLAIM word +0.29, back at origin +0.9). A few-ms window: negligible, but 'at most one fails' is not strictly true.
- Realistic crossing (call-back after a dropped call: A20<->B20 dial each other): both lines are busy anyway, so the double refusal loses nothing; the S2 4-distinct-lines case is ordinary occupancy.
- exch.py Net.claim/answered: confirmed the owner's register is never taken (only reg[origin].give).

## Verdicts (mine)
- F1 origin high -> agree with verifier: confirmed-overstated, medium.
- F2 monclaim medium: confirmed, medium (dup).
- F3 protocol medium: confirmed, medium (dup).
- F4 refusal-heard-after-hs low: confirmed, low.
- Fix (1) right; docs to change are 4.1, 4.3 worked example (done at 5828 -> ~3311), 5 Glare ('connects at its caller's last digit' -> at b), tb_net 11. Add an event code for claim refused. Coordinate with C01 fix (att_refuse must not fire on the release tick: gate with !r_release).
