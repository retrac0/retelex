# C06 pre-seizure-break -- verifier notes

## Static reading (snapshot rtl/)
- r_brk = pulse_rx brk_stb: one tick, fired HIT ms INTO a break (pulse_rx.v:81-88), not at its start.
- flood_go comes 1-2 ticks after the key's dig_stb (mini_marker.v:415-433; att_take needs !r_busy, so nothing delays it by ms).
- net_unit.v:862 is the only reader of r_brk (N_NET/N_WAITCL, `guarding && r_brk`); tmr zeroed at the seizure push (:815).
  N_WANT/N_HUNT/N_SEIZE (:846-857) ignore r_brk. Mechanism as claimed.
- Hole condition: key's dig_stb + x = e's break start, r_brk at +x+HIT, push at ~+10.3 ms (sweep 9 + confirm 1).
  => hole iff x + HIT < ~10.3 ms (+ up to ~10 ms if a forward sweep is running, + a pass per classifier read cutting in).
  Scale 8 (HIT 1): x in [0, ~9] ms.  Real (HIT 8): x in [0, ~2] ms, i.e. key-to-e make 128..~130 ms (..~140 behind a forward sweep).
  Auditor's "[128, 140-160]" ignores the HIT delay of r_brk: overstated upper bound.
- e must be 1 pulse: a 2nd break of e lands in N_NET within the guard -> NOGO (safe).
- New network.md s6 promises: a caller pausing under ~267 ms is ABANDONED (cannot-complete, never a wrong number). RTL breaks that promise in the band above.

## Runs queued (all via sim.sh; slots busy with load runs)
- obj_orig / run_orig_s3.log: auditor tb_orig +scen=4 on snapshot
- obj_rt / run_rt.log: tb_c06rt.v (mine) REAL timers, key make 128,129,130,131,132,133,135,138,720 ms then e=1, b=3, h=2 (means 13; wrong if B=32 claims)
- rtl_fixb/net_unit.v = auditor's o_brk fix ONLY (their rtl_fix also carries fix c `lost`, another cluster)
- obj_orig_fixb / run_orig_s3_fixb.log; obj_net_fixb / run_net_fixb.log (tb_net on fix b)

## Other static points
- tb_net scenario 7 tests a break only AFTER busy_a[T11] (after the push): the pre-push band is untested by the committed benches.
- Faults: a line hit in the window is counted by the origin register but missed far away -> the far end sees the TRUE e b; not a wrong number of this kind. Harmful trigger needs the caller's genuine single-pulse e starting within ~2 ms of the key's recognition.
- Fix: o_brk sticky, set in N_WANT/N_HUNT/N_SEIZE; N_IDLE window (dig_stb -> flood_go) is 1-2 ticks, r_brk needs HIT ms: not a gap. Equivalent zero-flop alternative: abandon if the register is `counting` at the push (needs a ribbon wire) -- no cheaper.
- Width law: the break must start after the key's dig_stb (else the key absorbs it); its r_brk is HIT later. Hole iff start < push - HIT,
  so the band is (flood_go->push latency) - HIT wide: ~10.3-8 = ~2.3 ms at real timers, ~12 ms behind a running forward sweep; ~9 ms at scale 8 (HIT 1).
  The old docs (monitor.md 3.2) budgeted "the seizure (2 ms)" after recognition: with a 2 ms latency < HIT there was no band at all.
  The sweep (10 ms, not in the old budget) is what opened it.
- tb_c06rt trimmed before its build started: key makes 128,129,130,131,132,134,138,720; obj_rt_fixb/run_rt_fixb.log queued too
- 13:16 killed the queued tb_orig snapshot job (outer timeout 3600 would have expired in the queue); requeued with 12000

## RESULT run_rt_fixb.log (fix b only, REAL timers) -- 37 s sim, 950 s wall
- key make 128: key not recognised at this sampling phase (key+e merged to "2": no flood). Bench quantisation, not a finding.
- 129, 130: flood_go -> e's r_brk 9.0 / 10.0 ms, in N_HUNT (push would be at +10.0) => THE HOLE BAND; fixed RTL abandons at h_done (NOGO, no seizure).
- 131, 132, 134, 138: push at +10.000, r_brk after it in N_NET -> guard NOGO (as on the snapshot).
- 720: normal; nobody claims 13; NOGO 2 s after b. Nothing left busy after any trial.
- So at real timers, uncontended: flood_go->push = 10.0 ms, break-start->r_brk = HIT + ~1 ms => band = key-to-e make of 129-130 ms (2 ms wide).

## RESULT run_orig_s3.log (auditor tb_orig +scen=4, SNAPSHOT, scale 8) -- 145 s wall
- REPRODUCED: S3a control ok (nobody claims 13). S3b: flood_go 1359.002, seizure push/write 1369.286 (10.3 ms), B sees the rise 1375.158 (end of e's pulse),
  B claims 1692.285 (after A's 3rd digit), A CLAIMED guarding 0, N_DONE at ndig 4, B21 rings, A20 follows B21 4/4. 2 FAILs as in the auditor's log.
- 13:45 snapshot RT first attempt died rc=127 (/usr/bin/time missing); binary rerun queued
- 14:21 fixb tb_orig + tb_net merged into one queued job (job_fixb.sh, rc in job_fixb.rc)
- 15:41 snapshot RT rerun requeued without an outer queue timeout (inner timeout 5400)

## RESULT run_rt.log (SNAPSHOT, REAL timers) -- 37 s sim, 505 s wall
- key make 129: e's r_brk at flood_go+9.0 ms in N_HUNT (ignored); push +10.0; B sees the rise 51.2 ms after the push (end of e's 60 ms break);
  B CLAIMS at 7087 (after A's h), A CLAIMED guarding 0 -> wrong number to 32 for a call dialled to 13.
- key make 130: same, r_brk +10.0 (same tick as h_done), B claims, A CLAIMED.
- 131/132/134/138: r_brk after the push -> guard NOGO. 720: nobody claims, NOGO 2 s after b. 128: key not recognised (merged).
- CONFIRMED AT REAL TIMERS: band = key-to-e make 129-130 ms (uncontended), 2 of 7 valid trials wrong; fix b turns both into NOGO (run_rt_fixb.log).
- 16:52 fixb job requeued without outer timeout (inner timeouts on builds 900 and runs)

## Static regression argument for tb_net on fix b (the combined job waited 4 h in the sim.sh queue)
- Fix b changes behaviour only when the REGISTER's r_brk fires while nst is N_WANT/N_HUNT/N_SEIZE (<= ~10-22 ms after flood_go).
- tb_net's dial_a adds 8 + 100 ms of make after every digit, so every next break starts ~92 ms after the key's dig_stb (ID 16): never in that window.
  Scenario 7 breaks only after busy_a[T11] (after the push, N_NET): unchanged. So tb_net's stimulus never reaches the changed logic.
- 21:22 fixb tb_orig+tb_net job cancelled unstarted after 4.5 h in the queue; fix b tested only by run_rt_fixb.log (real timers) + auditor's run_fix2.log (scale 8, fix b+c)
