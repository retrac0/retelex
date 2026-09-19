# The exchange — features are lines

Operator, outside line, tones, recorded announcements, conference, even the
registers: each is a card in a channel slot with a class mark, and the marker
reaches it by hunting the class (`exch-marker.md` §3) or by its number. This is
how the Bell System built such things — as trunk circuits — except that what is
switched here is CVSD.

> **Status: proposed.** Measured in simulation: every card's *behaviour as a
> port* (`exch.py calls`) and the announcement's bit stream and seams
> (`exch.py announce`); `exch.log` is the run. None of the cards has a circuit
> yet, and nothing has been on a bench.

---

## 1. Register (class 7)

A register is a line too. It sits in a channel slot, the marker points its latch
at the caller, and it **hears the caller through the ordinary fabric**: his dial
pulses, on its own `A_RX`. Finding a free register is a class hunt, and that
hunt is the pool. There is no sender (`exch-network.md` §4).

| | |
|---|---|
| Pulses | `register.md` §4 on `A_RX`, without its line-select '151: ≈ 9 packages, all 74HC |
| DTMF | not fitted. It would be a second writer to the same store (`register.md` §7), good for local calls only |
| To the marker | a ribbon: digit code, digit count, strobe |
| Releases | by itself: its E is the caller's hook (`exch-marker.md` §5.1) |
| Octal | three AND gates on the store's output (`exch-protocol.md` §5) |

---

## 2. Tones (class 5, class 6) — analog

A tuned oscillator pair into one encoder half of `mf8-spec.md` §12.1. Cadence
mutes the encoder's **input**, not its output, so the off periods are the codec's
own `1010` and nothing clicks. `A_TX` is tied low. A tone card is never busy:
the marker writes only the listener's latch, and any number may listen.

`RBT`, the ringback bit stream, comes from the same kind of card, which drives a
backplane line as well as its port (`exch-marker.md` §5).

---

## 3. Announcement (class 2, or class 6) — the one ROM

A recorded message needs **no codec at all**: a ROM, an address counter and a
shift register put a CVSD bit stream straight on `C_TX`. The image is made with
the repository's own encoder, so what plays is exactly what the codec would have
sent (`exch.py announce`):

| | |
|---|---|
| Size | 8 kB a second: 4.5 s is 36 000 bytes; **8 s fills a 64 kB part** |
| Quality | the codec's own figure for that recording — 16.96 dB segSNR for the 4 s of one talker used |
| As a port | on-hook until rung; answers 300 ms after E rises (M = 1), plays, drops M — and the release rule has the caller back at dial tone 0.3 s after the message ends (`exch.py calls` 9c) |
| As class 2 | the last operator position: the night or all-busy message |
| As class 6 | a looping cannot-complete message in place of a tone: a source, never busy |

**The seams.** The port sends `FILL` until it answers, then the image, then
`FILL`; a loop joins the image's end to its start. `FILL` free-runs, so an image
can start on either phase of it. Peak within 20 ms of the seam, re speech rms:

| seam | in phase | a bit doubled |
|---|---|---|
| idle → image | nothing | −30.5 dB |
| image → idle | nothing | −30.5 dB |
| image → image | nothing | −30.5 dB |

Record 0.25 s of silence at each end so that the image begins and ends in the
codec's own idle, **make the image an even number of bits**, and start the
address counter on the right half of `FILL` — one gate — and all three seams are
exact. A doubled bit is the slip of `mf8-backplane.md` §7 and as harmless.

An image cut out of running speech, with no silence round it, starts the far
decoder cold. The error against the same bits decoded in place peaked between
−75.7 and −33.2 dB re speech rms at four cut points and was below −30 dB from
the first sample: with a 1 ms integrator the decoder has almost no memory to be
wrong about.

---

## 4. Operator (class 2) and the console

**The operator is a phone** on any line card with the class jumper moved. 0 hunts
class 2 in fixed order, so a second position and a night announcement are just
more class-2 cards further along (`exch-marker.md` §3).

**The console is separate, and optional**: a busy-lamp field — '259s and LEDs off
the M and `BUSY` highways — and keys that drive the marker's control bus by
hand. **Build it first.** Fabric plus console is a working manual board, and the
bring-up tool for everything that comes after.

---

## 5. External trunk (class 3): the FXO card needs one change

`mf8-cards.md` §3.5's FXO card sends `A_TX` = *ringing present*. On an extended
line that is right. On an exchange it is not (`exch.py calls` 11):

| `A_TX` | a CO line rings in, the operator answers after 8 s |
|---|---|
| ringing only — the card as it stands | the call is set up on every ring burst and **torn down 220 ms into every gap**, by the release rule; the operator's phone rings for 2 s in 6 and the call never survives |
| **ringing, held 5 s, OR loop closed** | one call: routed as 0, rings the operator, answered, held, released when the operator hangs up |

**The exchange build of the FXO card holds ring-detect across the cadence gap
(a retriggerable 5 s) and ORs in its own loop closure.** Outgoing needs nothing:
9 hunts the card, the caller's off-hook closes the loop through E, the CO's dial
tone comes back on `C`, and the caller dials on in band.

---

## 6. Conference (class 1): meet-me

A leg card is one slot, one number, one codec pair. It answers when rung and
stays while its caller does. Neighbouring legs share an analog party bus; each
leg sends the sum less its own decoder's output. There is no marker logic and no
recall: **callers dial a leg.** Three callers, three legs: each connects, and
each leg releases when its caller hangs up (`exch.py calls` 14).

This is the one place a codec tandem is paid: `exch-protocol.md` §2's first
tandem, for every party.

---

## 7. Data and foreign codecs (class 1)

A data card is a line. A call to it is set up like any other and the fabric
passes its bits exactly (`exch-protocol.md` §4). In-band tones sit in the stream
until answer; E rising — `DSR` — marks it. A terminal can dial by pulsing `DTR`
into a pulse register (`exch-marker.md` §7). A phone that dials a data port
hears noise; nothing prevents it.

A card facing another codec transcodes on the card: the FXS card already does,
and a DNVT card is two codecs back to back.

---

## 8. Not measured

- **Every circuit here.** Oscillators, the ROM player, the leg card's summing bus,
  the console.
- **Tone levels and twist** through the encoder half; `subscriber-line.md` §5
  measured DTMF through the codec, not these tones.
- **A ROM image's start against a free-running `FILL`** in gates; the seam table is
  the bit streams, not the counter's start logic.
- **The conference bus**: levels, the number of legs it carries before the sum
  clips, and singing through two hybrids when analog phones join.
- **A CO's ring cadence ANDed with `RING_CAD`** at the operator's phone: the phone
  rings only when both are on. Feed the operator's ring from E alone when the
  caller is class 3, or accept it.
