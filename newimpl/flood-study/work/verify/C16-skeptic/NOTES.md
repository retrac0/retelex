# C16 skeptic review notes

## Mechanism (read-only, snapshot rtl/)
- word_rx/probe timing re-derived: marker S_IDLE on T's fresh (edge T->T+1) -> S_READ; select at T next pass;
  done at a_stb of frame T+8; fresh(T+8) published at edge T+8->T+9 -> seen.  Blind T+1..T+7, cycle = 2 passes,
  every other port seen once per 2 ms. Verifier right (7, not 8).
- Blindness is NOT absolute with other traffic: when the register is released at a random scan phase, a blind
  line L=T+j is caught before T with prob j/64 per release.  Absolute only on a quiet exchange (the bench).
- Trunks live in block 1 (ports 11-17; 06-07 single-channel): trunk 1k blinds 1k+1..1k+7, so only lines 20..26
  are ever exposed (line 20 to all seven trunks, 26 only to 17).  Trunks at 06/07 blind no lines.
- Normal trigger (called party first): only at the terminating exchange's incoming trunk, window T_REL+2*link.
  At transit incoming ports and origin trunks the window is ~2*link.  Confirmed by reading port.v:147,153.
- baseband_card: a_tx gated by link_up&&settled, word gated by same; failsafe receivers read A=0 on an open
  conductor (baseband.md 3.3) -> stuck-at-1 A needs a driver/short fault, not an open wire.
- Sweep: back-to-back 9-frame reads keep /HW busy; another reader's win==0 only at the sweep's own select
  frames, so the marker WAITS on the sweep (run_real13_all.log: mk=4 16907->16916 during the 16906-16917 sweep).
  Sweep delayed only when a marker select lands in a gap (sweep start, classifier interleave): <=1 pass.  Agree.
- Classifier: +<=1 pass per queued seizure when the marker's window covers the port's turn (trunks cluster in
  block 1, so likely).  ~1 ms against ~19 ms/seizure.  Feeds C05's lateness marginally; not a finding here.
- att is not taken in S_READ, so a re-read delays a claim's attach by <=1 pass (<=~11 ms behind a sweep):
  negligible against the >=590 ms before h.

## SECOND PATH the auditors and verifier missed: word 0 (OOS) with M up
- mini_marker.v:365 sends word==0 to S_IDLE exactly like a trunk, unremembered -> same 2-pass re-read loop.
- A plain line card's a12 is a strap to a row-c ground (cvsd_line_card.v:195); the pull-up is at the port
  (block.v:136, mainboard.v:106): an open a12 (bent finger, cold joint, strap forgotten on a hand-built card)
  reads 00 = OOS, while the hook (a6) works.  extensions.md: an OOS port's lift is "ignored".
  Handset off (or receiver left off) -> marker re-reads it every 2 ms -> L+1..L+7 blind, and these are LINES.
- The verifier's fix sets tk only on rd_trunk (fix.patch), so this path stays OPEN.  Extend the set to
  rd_trunk || rd_word==0; the "glitched zero read" objection is weak (a working line pulls all 8 frames low;
  a wrong set costs only that attempt, cleared at hang-up).

## Fix, as hardware
- tk set lands at rd_done = mid-frame T+8, not in T's own turn: a serial delay line ('164s / CD4031) cannot
  take it then.  Needs a pending FF applied at T's next turn and ORed into the skip gate (p_port==called '688
  already exists).  "plus a gate" is a little light.  RTL models it as random access.
- Cheaper, proportionate: ONE-ENTRY memory -- a FF "called was refused and M has stood since", skip
  p_port==called while set, clear on M low at called or when called is overwritten.  ~half a package, covers
  every single-port case (called-first window, stuck-A fault, OOS line off-hook); two refused ports at once
  degrade to today's behaviour.
- Fix regression-run only on tb_net, tb_mc, tb_c16; tb_chain/tb_lnet/tb_lfull/tb_lchain not re-run.

## Realism
- Normal trigger at B: ~12 called-first windows/busy hour (48 lines), each 256 ms; exposed lines avg ~4 of
  20..26; P(lift in window) ~3e-4 -> ~3e-3 affected lifts per busy hour; delay 0-256 ms, imperceptible.
- Burst: each flood arrival is unheld ~2-3 ms, ~19 ms per queued seizure; tens of ms at most.  info.
- Fault: stuck-HIGH A needs a driver fault or short (an open A conductor reads 0: failsafe receivers,
  baseband.md 3.3), and must arise during a call (idle onset -> phantom seizure C08, held BUSY, no re-read).
  Then 0..7 lines (by trunk position) cannot originate; terminating calls still work; escape j/64 per
  register release.  OOS-line path hits up to 7 lines anywhere in blocks 2-7.

## Verdicts
- F1 marker-rereads-unheld-trunks: confirmed-overstated, severity info on its own trigger (verifier: low).
  "share st" is wrong (verifier right).
- F2 marker-reread-loop: confirmed-overstated, low; plus the missed OOS path, which the fix leaves open.
No simulation run.
- C01 link: the verifier's "far port wedged with CLAIM" in its reachable form (C01 late refusal) mostly ends as
  C01's phantom seizure at the near end (st cleared by the backward-A dip between B11's release and the late
  CLAIM write, so A's classifier holds A11 BUSY: no re-read).  It reaches C16's forever loop only if that dip
  is shorter than one scan pass and is missed.  Closing C01 closes it.
