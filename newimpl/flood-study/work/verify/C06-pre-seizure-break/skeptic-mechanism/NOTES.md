# C06 skeptic (MECHANISM lens) -- notes

## Static re-derivation (snapshot rtl/), done
- pulse_rx.v:81-88: brk_stb once per break at t == HIT-1 (8 samples in). Confirmed.
- mini_marker.v:415-433 (and marker.v:420-427): flood_go + r_restart the tick after r_ndig>=1, room>=1 of an 8-deep queue: effectively immediate. Confirmed.
- net_unit.v:842-857: N_WANT / N_HUNT / N_SEIZE never read r_brk; :862 guard only in N_NET/N_WAITCL; :815 tmr=0 at push. Confirmed.
- Far side: baseband a_out = a_rx = E of the trunk port = caller's M via latch; far a_tx = M. Far classifier (cls_seen) + monitor (pulse_rx on the trunk) see a clean rise at the make; nothing requires M to have stood before the first counted break. No blocking condition found.
- Verifier's band (key-to-e make 129-130 ms uncontended) re-derived: push - flood_go (10.0) - HIT (8) ~= 2 ms. Agree.
- Contention: push can slip by a running forward sweep (<=10 ms), classifier reads that pre-empt the sweep (~1 ms each), queue room. Band up to ~15 ms (make ~129-145). Neither the auditor's 160 nor the verifier's 140 matters for severity.

## Disagreements to test (one run allowed)
1. "e must be a single pulse": false if the pulse period T >= 128 + (push - r_brk1) ~= 129-130 ms (<= ~7.7 pps).
   r_brk2 = r_brk1 + T falls past the 128 ms guard; the far counts e-1. Any e, not only codes 1x. pulse_reg.v's own comment treats 7 pps as a real dial.
2. "A line hit inside the window does not cause a wrong number": the far is right, but the ORIGIN counts the hit as digit 1:
   origin code check reads (1, e). If own code is 1x with x = dialled e -> O_LOCAL -> restart -> b h taken as a local h s: rings local line (b,h).
   A plausible fault with conforming dialling. Tiny window (~2 ms after the key's recognition) and only exchanges 1x.
- Plan: tb_c06sk.v, real timers, A = 13, B = 32; trials: (a) 7 pps e=4, key make 129 -> expect B claims (far counts 3 2);
  (b) same at 10 pps -> expect guard NOGO; (c) 25 ms hit at key make 129, then e=3 b=2 h=1 at 720 ms pauses -> expect A21 rings.

## Defence-in-depth idea (not a replacement for fix b)
- In N_WAITCL: `!claimed && r_brk` -> NOGO. A genuine claim comes within tens of ms of b's recognition; the caller's next break
  comes >= ~590 ms later for a conforming dial. Catches any whole-digit loss at the far end (claim one digit late), e.g. this
  cluster with e=1 and C05's e=1 variant. Does NOT catch the slow-pulse e-1 variant (claims on time) nor the hit/O_LOCAL variant.
- 01:22 queued job.sh (build+run tb_c06sk on snapshot) via sim.sh
- build ok (35 s). Own equipment check: pulse-gen.md's tester pauses a fixed 700 ms between keys (RC pot moves rate, not pause) -> the project's own sources never hit the band. register.md's envelope includes 7 pps (outside ES 201 187's 10+-1).
- old monitor.md 3.2 budget "the digit recognised (128), the seizure (2)": with 2 < HIT there was no band; confirmed verifier's reading.

## RESULT run_sk.log (SNAPSHOT, REAL timers, one run: 21 s sim, 224 s wall; obj dir removed)
- a) key make 129, e=4 at 7 pps (90/53): first r_brk flood_go+9.0 in N_HUNT (ignored), push +10.0; 2nd r_brk at tmr 142 (guard ends 128)
     -> no NOGO; B (32) counts 3 2 and CLAIMS a call dialled to 42; A CLAIMED.  => "e must be a single pulse" is FALSE for periods >= ~130 ms.
- b) control, same at 10 pps (60/40): 2nd r_brk at tmr 99, inside guard -> NOGO. As the verifier says for conforming rates.
- c) key make 129, a 25 ms line hit, then e=3 b=2 h=1 with 720 ms pauses; A's own code 13: hit's r_brk flood_go+9.0 in N_HUNT (ignored);
     origin reads (1,3) = own code -> local_go -> restart -> b h = 21 taken as local -> A21 BUSY and RINGS (E hi 2104/6200 ms).
     => a wrong number from ONE line hit with CONFORMING dialling (exchanges 1x only, dialled e == OWN_B, hit within ~2 ms of the key's ID).
     The verifier's "a line hit inside the window does not cause this wrong number" is right about the far end only.
- All idle after each trial.

## Verdict (final)
- Mechanism confirmed exactly as claimed; no blocking condition. Severity low (agree with verifier), band 129-130 ms uncontended (agree).
- Corrections to verifier: e need not be single (slow pulses, run a); a line hit CAN give a wrong number, origin-side, via O_LOCAL (run c).
- Fix b covers both new variants (their first r_brk is in N_HUNT in the log). Not run on fix b (one run only).
