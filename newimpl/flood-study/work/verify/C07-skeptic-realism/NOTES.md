# C07-link-outage-pulse -- skeptic review, REALISM AND SEVERITY lens

(started 2026-09-27)

## Read so far
- baseband_card.v:109 link_up = far TX_CLK edge within DEAD (47 us); :154 a_tx forced 0 while !link_up.
  pulse_rx.v:84 needs 8 consecutive 1 kHz samples of M=0 -> an outage must be >= ~7-8 ms to count. Agree
  with verifier: DEAD 47 us irrelevant; finding 3's 47 us trigger is not a pulse.
- port.v T_REL is an RC in hardware (+-35% per C03 notes), CLR is digital: the pulse/fresh-seizure boundary
  is T_REL(RC) ~170-345 ms, not exactly 256.
- Carriers: baseband = one room (74HC) or between racks (RS-422); local trunk = one room/adjacent racks;
  MF8 = "the usual case" (old network.md 1.1), not in RTL; MUTE clears A hold; LOF recovery 0.2 ms, false-lock
  release mutes 0.5-2.7 ms; carrier-detect timeout forces LOF.  So MF8 needs >= ~7 ms of no carrier/garbage.
- pots-trunk (proposed): tone absent = A 1, so a cut during a make inserts nothing; a cut during a break
  DELETES it (break turns to make); link down forced after 100-200 ms. It cannot meet a "4 ms release" rule.
- Audit fix entry: dn counts LOCAL frames while !link_up, resets on ANY frame with link_up.  Verifier's mut
  adds !a_s2 to the clear and !poison to the word.  Both keep that entry.
- CONCERN (new): an intermittent (chattering) clock contact -- open stretches < 4 ms separated by brief
  closures -- resets dn each closure, so poison never sets, while the 1 kHz probe can miss the brief
  closures and see >= 8 consecutive zero samples = a counted pulse.  Chatter is the commonest physical form of
  "a disturbed connector".  Entry needs hysteresis (reset dn only after link up continuously >= ~2 ms).
- Gap (verifier calls it out of reach): A conductor alone open -> A=0 with link_up true -> not caught.  Not out
  of reach: a complementary A pair (A, /A; both 0 = fault -> poison) catches every single open that matters,
  one conductor + a gate.  Judgment call on cost.
- Trade: RIDE 4 ms drops ESTABLISHED calls on any 4-256 ms hit, which today are clicks.  Talking occupancy
  >> dialling occupancy, so per hit event the fix drops several talking calls to save ~0.1-0.4 wrong numbers.
  Consistent with CEPT CAS practice (fault -> release), opposite of Bell T1 (freeze 2.5 s).  Freeze-short is
  not a safe alternative (contact order: A pin may open before CLK; freeze shortens breaks inside the
  network.md break budget).

## RESULT: one short run, tb_chat.v (card + pulse_rx only) on the VERIFIER's rtl_mut card -> run_chat_mut.log
- sc A: CLK pin chatters 30 ms (open, 0.2 ms closures every 3 ms, between probe samples), A pin fine:
  pulse_rx COUNTED A BREAK at 159 ms, DIGIT 1 at 309 ms; card NEVER poisoned.
- sc B: CLK+A pins chatter together, same: break 609, digit 759, never poisoned.
- sc C control: clean 30 ms cut of CLK: POISONED at 1004.02 ms (4 ms, RIDE), held, CLEAR at 1257.
- => the fix's entry (dn reset by any frame with link_up) is defeated by contact chatter; the 1 kHz probe
  misses sub-ms closures.  With random closure phase (0.25 ms of A=1 per 3 ms), P(8 zero samples in a row)
  per window ~0.5, so a 30 ms mostly-open burst counts almost surely.  Fix: hysteresis -- reset dn only after
  link_up has held continuously >= ~2 ms (another counter stage / RC), or gate a_tx by that "stable" up.
- obj dir deleted.  (Build 14 s, run 8 s.)

## Rate arithmetic (reference net as C03: 10 exchanges, tree, 9 links, 500 floods/BH)
- Every flood crosses every tree link pre-claim for ~3 s (key pause + e + pause + b + ID); path links add
  ~3 s of h s for ~140 claimed calls/BH.  ~1900 s/BH -> P(some caller in a vulnerable phase) ~0.4.
- P(wrong connection | inserted pulse) ~0.2-0.4 (key pause -> (1,e): hub codes, high match; e+1/b+1 on a
  dense plan; h s after claim ~0.7).  => ~0.1 wrong numbers per 8-256 ms outage event on a busy link.
- In-room outage events ~1e-4 per link-BH (a few per link-year) -> ~1e-5/link-BH, ~2e-5/exchange-BH,
  ~4e-7/call: ~10x rarer than C03.  Flapping outdoor MF8 pair: several per hour while it lasts.
- Finding 2: reseat/power-cycle within the remaining 2-4 s of dialling; ~0.05 wrong per event.
- Fix price: a busy link carries ~1-3 talking calls; each 4-256 ms hit now drops them (today a click):
  ~10-30 dropped calls per wrong number avoided.  Optional cure (~1 package): poison only if A moved either
  way in the last NODIG (10 s); a quiet circuit keeps today's ride-through (no counter listens then).
- Power-up: the fix resets poison to 0, but a re-seated card's clock vanishes at the far card, which poisons
  and (both-ways clear) holds the caller off -> OK.
- Residual: B clears while A (origin side, caller up) stays poisoned; B's hunt can take this trunk and lose
  one flood leg (clean cannot-complete) until A's origin drops.  Low.

## Verdicts
- link-outage-dial-pulse: AGREE confirmed-overstated, medium.
- link-return-fresh-seizure: AGREE confirmed-understated (consequence: wrong line), medium (level unchanged).
- link-hit-extra-pulse: AGREE duplicate, confirmed-overstated, low.
- Fix: right direction, verifier's both-ways clear + word gate needed; INCOMPLETE: chatter defeats the
  entry (measured), A-alone opens (complementary A), MF8/local/pots, spec must cover deletions; price optional.
