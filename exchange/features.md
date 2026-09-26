# Features: tones, the operator, outside lines, sources, data and test lines

What the exchange fits besides subscriber lines, and what the marker does with
each. Every feature is a card in a channel socket; the class marker reaches it
by its number or by what its word says (`card-word.md`), and the port circuit
does the rest (`fabric.md` §5).

> **Built** (the marker's side): `newimpl/rtl/marker.v`, `word_dec.v`, benched
> by `tb_max`. **Proposed:** every card here; none is drawn. **Measured in:**
> `sim/exch.py announce`, `calls`, `fabric` (`sim/exch.log`). §3–§6 need the
> class marker (`top_max`): the mini marker refuses 0, 8 and 9 (`marker.md` §3).

---

## 1. Tones and ringback

The three switched tones are **addresses**, not classes:

| port | tone |
|---|---|
| 01 | dial tone |
| 02 | busy |
| 03 | cannot-complete |

What each is given for is `numbering.md` §4. Giving one is **one write**: the
caller's latch points at the tone port, whose own latch is never written, so
any number of callers hear it at once. With no card at an address a caller
hears `FILL`, which is silence. A tone card is a source (§5) with `A_TX` and
`/ANS` tied low; its frequencies, cadences, and the ROM and analog cards that
make them, are `common/tones.md`. Port 00 is never fitted: a cleared latch
listens there.

**Ringback is not switched**: a port being rung sends the bus's `RBT` in its
own cell in place of its card's `C` (`fabric.md` §5.2), and nothing is ever
connected to the ringback card. With none fitted a caller hears silence while
the far phone rings. The card is `common/tones.md` §8; its path onto the bus in
a block and its cadence are open (`common/tones.md` §9).

A **tone trunk** (a trunk that offers tone when seized, a caller at a leaf's
central) is `proposed/leaf-uplink.md`'s. `word_dec.v` decodes it; no bench
runs it.

---

## 2. Announcements: one ROM

A recorded message needs **no codec**: a ROM, an address counter and a shift
register put a CVSD bit stream straight on `C_TX`. The image is made with the
repository's own encoder, so what plays is what the codec would have sent
(`exch.py announce`).

| | |
|---|---|
| Size | 8 kB a second: **8 s fills a 64 kB part**; a 512 kB part holds 64 s |
| Quality | the codec's own: 16.96 dB segSNR on the 4 s of one talker used |
| As a line | on-hook until called; answers 300 ms after its `E` rises, plays, drops `M`, and the caller is back at dial tone 0.3 s after the message ends (`exch.py calls` 9c). With `/ANS` open it is rung like a phone and answers in the first burst; with `/ANS` low it answers at once |
| Answering to 04 | the night or all-busy message: in a slot after every other position, so the hunt reaches it last (§3) |
| As a source | a looping message in place of a tone: never busy, one write (§5) |

**The seams.** The port sends `FILL` until it answers, then the image, then
`FILL`; a loop joins the image's end to its start. `FILL` free-runs, so an image
can start on either phase of it. Peak within 20 ms of the seam, re speech rms:

| seam | in phase | a bit doubled |
|---|---|---|
| idle → image | nothing | −30.5 dB |
| image → idle | nothing | −30.5 dB |
| image → image | nothing | −30.5 dB |

**Record 0.25 s of silence at each end, make the image an even number of bits,
and start the address counter on the right half of `FILL`** (one gate): all
three seams are then exact. A doubled bit is an MF8 slip and as harmless.

An image cut out of running speech starts the far decoder cold. At four cut
points the error against the same bits decoded in place peaked between
−75.7 and −33.2 dB re speech rms. The conference bridge's switch is the same
cold start, measured at 400 instants: the speech fades in over 16 ms median,
28 ms worst, without a pop (`proposed/conference.md` §4). Record the silence.

---

## 3. The operator

**The position is a phone** on any station card (FXS or CVSD line card) with
`/ANS` open. It answers, talks and hangs up like any line. The console — keys
that write the control word by hand — is a separate, optional unit
(`proposed/console.md`); either works without the other.

**0 calls 04.** 04 is the pilot (`PILOT_0` in `marker.v`): a free voice line
there is rung. Otherwise the marker hunts, from 01 in slot order, the first
free port whose word answers to 04 (`card-word.md` §5, `marker.md` §4.5). 04
itself needs no word: a plain line card is the first position. Nobody free:
**busy tone** if 04 was a voice line not free, cannot-complete if 04 is empty
or out of service (`tb_max`: the operator rings, then the second position,
then busy tone).

| | |
|---|---|
| a second position, a night message | any card that answers to 04; 05–07 are line seats no number reaches (`numbering.md` §2), and any dialable slot serves as well |
| night service | the out-of-service switch on 04's word (`card-word.md` §3): 04 reads none, its phone can neither call nor be called, and 0 goes on to whatever answers to 04 |
| no position | 0 is cannot-complete, and so is a CO line ringing in (§4) |
| restricted callers | a 0-only card reaches the operator and nothing else (`card-word.md` §4) |
| a help point | a call nail to 04: lifting it is 0 (`card-word.md` §6.3) |
| from another exchange | `1 e b 0`: a one-key number after the code (`network.md` §4) |

**What needs the console.** Once the position is in a call its port is `BUSY`,
and a lift on a busy port is not a caller, so the handset alone cannot start a
second leg. Transfer, forced release, observing and ringing a busy or
unequipped port are the console's (`proposed/console.md` §3–§7); seeing who is
off-hook or busy is the lamps' (`proposed/lamps.md`).

---

## 4. Outside lines

An FXO card (`common/channel-cards.md`) whose word says class *outside line*,
with `/ANS` low so it answers at once.

**Out: 9.** The marker hunts from 01 in slot order, a read a pass, for the first
free outside line and connects it both ways; none free is cannot-complete
(`tb_max`: two lines taken in order, a third caller refused). The caller's
hook reaches the card as its `E` and the CO loop follows it: the CO's dial tone
comes back on `C`, and the caller's dial pulses go out as loop breaks.

**In: the exchange build of the FXO card.** The card as a line extender sends
`A_TX` = *ringing present*. On an exchange that fails (`exch.py calls` 11):

| `A_TX` | a CO line rings in, the operator answers after 8 s |
|---|---|
| ringing only | the call is set up on every burst and **torn down 220 ms into every gap** by the release rule; the operator's phone rings 2 s in 6 and the call never survives |
| **ringing held 5 s, OR loop closed** | one call: routed as 0, rings the operator, answered, held, released when the operator hangs up |

**The exchange build holds ring-detect across the cadence gap with a
retriggerable 5 s and ORs in its own loop closure.** The walk reads the line
when it comes round (up to a round, `marker.md` §4.2), finds `M` up on class
outside line, and routes it as 0 (§3) with no dial tone and no digits. It
takes the register only for the watch after the connect (`marker.md` §5).
The operator's `M` is the card's `E`, so answering closes the CO loop; the
operator hanging up opens it and both ports release by the ordinary rule
(`tb_max`: a CO line ringing in is routed as 0).

---

## 5. Sources: a port anyone may listen to

A radio, a speaking clock, a looping weather message: a card that talks, never
listens, and is heard by any number of callers at once. The fabric already
does this: any number of latches may point at one slot, bit for bit
(`exch.py fabric` 3: 63 ports listening to one).

**A dialled source is one write**: the caller listens to it. No free test; the
source is never `BUSY`, never rung, and its latch is never written (`tb_max`).
A source may be **nailed one way** — a paging amplifier listening to the radio
for good — and nothing writes the radio (`card-word.md` §6).

| | |
|---|---|
| the card | class *source*. Whatever makes the sound into one encoder half (`mf8/mf8-spec.md` §12.1); a recording is §2's ROM player, looping. `A_TX` and `/ANS` tied low |
| a caller | dials its number and hears it at once, and leaves by hanging up; the source never learns anyone called |
| how many | no limit: each listener costs its own latch. From another exchange, `1 e b h s`: each distant listener holds one trunk channel |
| `A_TX` low | a listener's `E` is the source's `M`. A source that raised `M` and dropped it would release every listener (`fabric.md` §5), so a dead radio gives silence, not a cleared call |
| a looping message | callers join mid-message. One that must start from the beginning is §2's card as a line, one caller at a time |
| a speaking clock | a ROM of words and a time-of-day counter that picks them; 60 minutes of words want a 512 kB part |

Under the mini marker a source is a line: the first caller's connect writes
it, and the next caller finds it busy.

---

## 6. Data lines

A data card is a line whose bits the fabric passes exactly. **A line with
option `D` is never switched** under the class marker (`card-word.md` §4;
`tb_max`). **A data circuit is a mutual nail** between two data cards with
`/ANS` low (`card-word.md` §6.2). **Switched data** — the SDU-1's 32 kb/s
insert-1 service (`common/sdu-1.md` §3.1), which dials like a phone — works
only with `D` clear, and is `card-word.md` §8's open item.

A card facing another codec transcodes on the card: the FXS card already does,
and a DNVT card is two codecs back to back.

---

## 7. Test lines

Three cards a tester dials like any line: `h s` at home, `1 e b h s` from
anywhere, so **every exchange and every trunk can be tested from any phone**.
Fitting them in the same slots at every exchange, say 75–77, lets a tester
remember them; that is a suggestion, not a rule.

| | the card | class | what it tests |
|---|---|---|---|
| **Milliwatt** | 1004 Hz at the codec's 0 dBm0 into one encoder half, as a tone card; `A_TX` low | source | the listener's decoder and analog path, for level |
| **Quiet termination** | a card carrying only its word; `C_TX` tied to `FILL`, `A_TX` low | source | the listener's idle noise: `FILL` decodes at −48.3 dB re nominal speech |
| **Loopback** | one 74HC74 clocked on `TX_CLK`: `C_TX` ← `C_RX`, `A_TX` ← `A_RX` | line | a caller hears their own voice; a data card gets its own bits back |

**A milliwatt means more here than in a voice-band exchange.** Bits are
switched, so the tone reaches a listener bit for bit however many exchanges it
crosses; what is read at a phone is that phone's card and nothing between. A
slip across MF8 is a −29 dB tick of about a millisecond, not a level error.
1004 Hz is not a submultiple of the bit rate; as a looping ROM image, 251
cycles are exactly 16 000 bits, 0.25 s, 2 000 bytes.

**The loopback re-times.** A card holds `C_TX` for the whole frame and samples
`C_RX` at the frame edge, so a bare wire would give a delay that depends on
slot order; the flip-flop gives two frames, 31.25 µs, whatever the slots.

- **For a voice caller** it is an echo test of the whole path.
- **For a data card** it is a bit-error test, bit-exact inside one exchange or
  over a tie on one clock card (`network.md` §8).
- **Across MF8** every crossing slips at the offset between the two crystals,
  so a tester counting slips through a loopback at another exchange measures
  it: slips a second ÷ 2 crossings ÷ 64 000 is the offset.

The loopback answers when rung and releases when its caller does; with `/ANS`
open it waits for the first ring burst, up to 4 s, and with `/ANS` low it
answers at once. The two sources answer nobody: a caller hears them at once.

---

## 8. Open

- **A CO line ringing in with no position free.** It is pointed at busy tone
  (or cannot-complete, with no position fitted) and stays `BUSY` until the CO
  stops ringing: the CO caller hears the CO's own ringback and is never
  answered, even when a position frees. Options: leave the line unwritten so
  the walk offers it again each round, or park it on a hold message (§2).
  Undecided; it matters to any exchange with CO lines and one operator.
- **A CO call cleared within 5 s of its last ring.** The held ring-detect keeps
  the FXO card's `M` up after the operator hangs up. Both ports release by the
  ordinary rule, the walk then finds the line ringing in again, and the
  position rings until the hold lapses. Reasoned from `port.v` and `marker.v`;
  not run.
- **Phone flash transfer** is not designed. A second leg from the handset
  needs held-party memory a '273 does not have; transfer is the console's.
- **Not measured:** every circuit here (the tone cards, the ROM player's start
  against a free-running `FILL`, the FXO card's 5 s hold, the three test
  cards); tone levels through the encoder half; the milliwatt's level and its
  ROM image's seam; `1 e b 0`, or any flood, through the class marker, which
  no bench runs beside a network unit (`marker.md` §7).
