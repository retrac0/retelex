# C07-link-outage-pulse -- verification notes

## Static reading (snapshot rtl/)
- baseband_card.v:109,154 a_tx = a_s2 && link_up && settled; local_trunk.v:127,132,188 same (all 8 ch).
  A cut of the A conductor itself also gives a_in = 0, so the break exists with or without the link_up gate.
- pulse_rx.v:84 counts any break of HIT (8 samples at 1 kHz); no notion of "who made the break".
- net_unit.v:283 cls_seen needs M && !BUSY && !st; 566-567 st cleared by an M-down sample; 647 cell clears at CLR.
- Short hits (< ~7 ms) are filtered by HIT (pulse_rx) and T_REL (port) -> DEAD = 47 us is irrelevant to the pulse
  finding; only outages >= ~8 ms count.  Finding 3's "47 us" drop is not a pulse.
- MF8 relock (mf8-spec.md 4.2): slip recovery 8-15 frames + 32-frame lock ~ < 1 ms, "a mute of a few ms":
  under HIT.  Only a real no-carrier/interruption >= 8 ms counts on MF8 -> auditor's MF8 relock route overstated.
- New exchange/network.md sec 2 carrier table: bounds shortened breaks / lengthened makes, never an inserted
  break; "Link down ... drops A, so a call in progress releases" -- the spec gap stands.

## Runs
- Bench: tb_c07.v = audit's tb_pflap.v + `+pause=` plusarg (680 -> a 720 ms interdigit make, conforming;
  the audit ran 640) + sc4 (link returns MID-DIGIT: 1 4 3 2 1, wrong line expected) + sc5 (ONE-WAY A->B 40 ms
  outage in b's last make, 1 2 2 2 3).  Icarus parse clean on all three lists.
- rtl_mut/baseband_card.v = audit fix + ECHO (poisoned card stops its TX_CLK 8 ms so the far card poisons too)
  + word gated by !poison.  Reason: audit fix poisons only a card whose OWN link_up fell; one-way outage
  toward B poisons B only, A (origin, caller M up) never poisons -> when B clears (link up + its a_rx idle
  300 ms; B's a_rx is 0 before a claim) A's caller M reaches B as a fresh seizure mid-number.
- Jobs launched (job.sh via sim.sh): A orig sc15 p600 + sc62 p680; B fix sc62 p680 + tb_net; C mut sc62 p680 + tb_net.
  Logs: run_<tag>_sc<sc>_p<p>.log, run_net_<tag>.log.

### RESULT fix (audit's rtl_fix card), sc62 p680 -> run_fix_sc62_p680.log (852 s wall)
- sc1 ok (no claim), sc3 ok, sc4 ok (mid-digit return: no claim), sc2 call dropped (FAIL "B21 rings" is the
  designed price), sc5 ONE-WAY outage: FAIL -- B claims at 4109.9 ms = end of s's 3rd pulse + ID:
  B's poison cleared 300 ms after its link returned, A never poisoned, A20's M = fresh seizure in b's pause,
  B counted h s = 2 3 as e b.  HOLE IN THE AUDIT FIX CONFIRMED.
- tb_net on the audit fix card: 88 checks, 0 errors, PASS (run_net_fix.log, 699 s).  Scenario 10 (every link
  cut, then idle_all 400 ms > CLEAR 300 ms) is the only one that poisons; idle_all's 400 ms is what lets 11 pass.

### RESULT orig sc15 p600 (the audit's exact reproducer) -> run_orig_sc15_p600.log
- Identical to work/audit/proto/run_pflap.log line for line (every OBS time the same): sc1 claim at 2159.4,
  B21 rang; sc2 B22 rang; sc3 claim at 2989.7.  17 checks, 5 errors.  REPRODUCED.

### RESULT orig sc62 p680 (conforming 720 ms interdigit) -> run_orig_sc62_p680.log
- sc1 FAIL (claim 2319.3, B21 rang), sc2 FAIL (B22 rang), sc3 FAIL (claim 3229.6), sc5 one-way FAIL (claim
  2319.8) -- conforming dial changes nothing.
- sc4 (link back 5 ms into e's 2nd make, 1 4 3 2 1): NO claim, nothing rang, PASS.  My wrong-line-by-mid-digit
  return did NOT reproduce.  Tracing why (TRACE_B build).
- TRACE (run_tr_sc16_p680.log): my sc4 arithmetic was wrong: the cable came back at 1285 = 5 ms into e's 3rd
  BREAK (e starts at 1080, not 1120).  B saw the fresh rise at 1340 (end of that break), took a hold and a
  monitor in 2.3 ms, counted e's 4th pulse only: d_stb cnt 1 at 1570 -> not B's e (2) -> dropped.  So it IS
  counted from mid-number; it just did not match.  Fixed the return to pause-155 (5 ms into e's 2nd make)
  and rerunning sc4 (traced) on the snapshot.
- CHANGED the variant before job C started: rtl_mut/ is now the audit fix + clear only when idle BOTH ways
  (`poison && link_up && !a_rx && !a_s2`, one gate input) + word gated by !poison.  Simpler than an echo: a
  card that poisoned alone stays poisoned while the far caller's M is still on its input, so it never lets it
  back in as a fresh seizure; a poisoned far card sends A = 0, so two poisoned cards never wait on each other.
  The echo variant (stop TX_CLK 8 ms on poison entry) is kept in rtl_echo/ untested.

### RESULT mut (audit fix + idle-both-ways clear + word gate), sc62 p680 -> run_mut_sc62_p680.log (1066 s)
- sc1 ok, sc3 ok, sc4 ok, sc5 ONE-WAY ok (no claim; both idle after), sc2 call dropped (designed price).
  18 checks, 1 error (the sc2 "B21 rings" check, which any outage-is-a-release fix fails by design).
- NB sc4 return is now at 1225 = 45 ms into e's 2nd BREAK (my "5 ms into the 2nd make" comment is off by
  20 ms: e's 2nd make is 160..200 ms into e); the fresh rise is at 1240, the start of e's 2nd make, so B
  counts pulses 3,4 -> e' = 2 either way.
- tb_net on the mut variant: 88 checks, 0 errors, PASS (run_net_mut.log, 722 s).
- T2 (traced sc4 rerun) lost its place: outer timeout 9000 s expired while queued; relaunched.

## Draft verdicts (pending the traced sc4 rerun)
- link-outage-dial-pulse: confirmed-overstated, medium (auditor: high).  Mechanism exact, reproduced identically
  and at conforming dial; trigger is a FAULT (whole-link interruption 8..256 ms while dialling).  "DEAD 47 us"
  and "MF8 re-sync" routes overstated: < ~7 ms never counts (HIT), MF8 slip recovery ~1 ms.
- link-return-fresh-seizure: confirmed, medium (upgrade to understated if traced sc4 shows a wrong LINE).
- link-hit-extra-pulse: duplicate of finding 1; its 47 us trigger is not a pulse; its fixes don't work.
- One root cause.  Audit fix incomplete for one-way outages (sc5); idle-both-ways clear + word gate closes it,
  tb_net 88/88.

### RESULT traced sc4 on the snapshot, corrected timing -> run_tr_sc16_p680.log
- Cable back 1225 (in e's 2nd break); fresh rise 1240; B holds and arms a monitor in 3 ms; d_stb cnt 2 at 1570
  (e' = e's pulses 3,4 = B's e), cnt 3 at 2550 (b) -> claim 2550.3, A's origin takes it 2551.2, B21 RANG.
  A20 dialled 43-21 and got 23-21: a WRONG LINE from a >= T_REL outage ending mid-digit.  Finding 2 understated.
- The mut variant's sc4 (run_mut_sc62_p680.log) used this same corrected timing: no claim.
- obj dirs deleted.
