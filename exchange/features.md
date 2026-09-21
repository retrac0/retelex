# The exchange — features are lines

Operator, outside line, tones, recorded announcements, a radio anyone may
listen to, a conference: each is a card in a channel slot, and the marker
reaches it by hunting a class (`marker.md` §3) or by its number. A
conference is eight ordinary line cards and a block of their own
(`conference.md`). This is how the Bell System built such things — as trunk
circuits — except that what is switched here is CVSD.

> **Status: proposed.** Measured in simulation: every card's *behaviour as a
> port* (`exch.py calls`), the announcement's bit stream and seams
> (`exch.py announce`), and the conference bridge's speech detector, floor and
> switch (`exch.py confer`, `conference.md`); `exch.log` is the run. *Source*,
> *data line* and *restricted* are proposed class codes in `fabric.md`
> §3.5, not yet in `marker.md` or the `calls` model. Class *conference* is
> **retired**: a leg is a line (`conference.md` §6). None of the cards has a
> circuit yet, and nothing has been on a bench.

---

## 1. The register is not a line

It was, while registers had to hear tones. **All-pulse, a register needs only the
caller's hook**, and that is on the M highway for the reading: `register.md` §4
as it stands, its line-select '151 replaced by the marker's kind of probe,
≈ 10 packages, all 74HC, no port (`marker.md` §4). A DTMF receiver would be a
second writer to the same store (`register.md` §7) and would need the caller's
`C` — a port again; it is not fitted.

---

## 2. Tones (class 5, class 6) — analog

A tuned oscillator pair into one encoder half of `mf8-spec.md` §12.1. Cadence
mutes the encoder's **input**, not its output, so the off periods are the codec's
own `1010` and nothing clicks. `A_TX` is tied low. A tone card is never busy:
the marker writes only the listener's latch, and any number may listen.

`RBT`, the ringback bit stream, comes from **the same card with one part added**:
⅛ of a 74HC244 and 33 Ω from the encoder's own node, out of the rear connector
and punched to the `RBT` conductor in the wiring field. `C_TX` is untouched, so
the card keeps its own channel as well (`tone-card.md` §1, §5). `RBT` is carried
with the clock card's shelf-wide references and is the one of them the clock card
does not drive (`mainboard.md` §2.1); with no ringback card fitted it sits
at `FILL` and a caller hears silence while the far phone rings (`mvp.md`).

**Which port ringback sits at is free**, because nothing is ever switched to it:
the tone reaches a caller through the called port's cell, not through a
connection (`marker.md` §5). A slot with no port circuit costs least
(`tone-card.md` §5.1). Dial tone, busy and cannot-complete are switched: the
marker points the caller's latch at them.

**The three switched tones live at 01, 02 and 03** (`protocol.md` §5) —
dial, busy, cannot-complete — undialable because 0 is the operator key, and
clear of every MF8 trunk group. `tone-plan.md` settles the frequencies and
cadences. Busy and cannot-complete differ in timbre as well as speed; each is a
*source* reached by address, not another class, and the marker already computes
the free test that steers busy vs cannot-complete. The generator is a tolerance
both an oscillator card and a ROM card meet; the cadence trick above **must not**
be used at a warble rate: a square there costs 23 dB and fifty spurious lines
(`sim/tones.py warble`).

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
decoder cold. At four cut points the error against the same bits decoded in
place peaked between −75.7 and −33.2 dB re speech rms, below −30 dB from the
first sample. Four were too few. The conference bridge's switch
(`conference.md` §4) is the same cold start, measured at 400 instants inside
words: the speech fades in over 16 ms median, 28 ms worst, without a pop. The
memory is the syllabic filter's, not the 1 ms integrator's. Record the silence.

---

## 4. Operator (class 2) and the console

**Two things on one desk** (`operator.md` §1): the **position** is a phone on a
line card whose word says operator (`extensions.md` §2.2); the **console** is
keys on the control bus. 0 hunts class 2 in fixed order from 00; **04 is the
default home**, not a requirement (`operator.md` §2). 05 is the nominal night
announcement or backup; 06–07 take more operators or single-channel trunks
(`protocol.md` §5). Further positions may sit in any dialable line slot.

**Transfer is console-only for now** (`operator.md` §3, `console.md` §7). Phone
flash is deferred (`operator.md` §5).

**The console is separate, and optional**: keys that drive the marker's control
bus by hand, with lamp fields beside it if fitted (`observers.md`,
`hookbusy.md` — not “off the M and `BUSY` highways”; there is no `BUSY`
highway on the cable). **Build it first.** Fabric plus console is a working
manual board, and the bring-up tool for everything that comes after.

`operator.md` is the phone. `console.md` is the bus master: forced release,
service observing, connecting two lines, calling a port and supervising both
ends — and **transfer**. Two of those add a card to this document's list, both
blank boards with no codec: the **sink** (`console.md` §5.1), and the **ring
source** (`console.md` §6.3) — `A_TX` tied high, no word, `/ANS` low. A card
that sends no word has no class, so a hunt never takes it.

---

## 5. External trunk (class 3): the FXO card needs one change

`channel-cards.md` §3.5's FXO card sends `A_TX` = *ringing present*. On an extended
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

## 6. Sources: a port anyone may listen to

A radio, a speaking clock, a looping weather message: a card that talks, never
listens, and may be heard by any number of callers at once. **The fabric already
does this.** Any number of latches may point at one slot, at no cost and bit for
bit (`exch.py fabric` 3: 63 ports listening to one). The dial and cannot-complete tones
are such ports now. The marker's part is one rule, the one it already applies to
a tone:

```
 the called port is a source   one write: the caller listens to it.
                               No free test; the source is never BUSY and its latch is never written
```

`marker.md` §2 does exactly that for classes 5 and 6, so a radio whose word
says class 6, at 75, is dialled as 75 today. What it lacks is a class of its own: at
class 6 it would also be hunted as cannot-complete if the card at 03 were
pulled. **Proposed: one class, *source*, for everything that talks and never
listens, the two tones included.** The marker reaches dial tone and
cannot-complete by their fixed addresses, 01 and 03, not by a hunt, so no source
is ever hunted and the class means only "one write" (`fabric.md` §3.5).

| | |
|---|---|
| The card | whatever makes the sound, into one encoder half of `mf8-spec.md` §12.1: a receiver for a radio. A recording needs no codec: §3's ROM player, looping. `A_TX` tied low |
| A caller | dials its number and hears it at once. It is never rung, because a source listens to nobody and its E is never high. The caller leaves by hanging up, and the source never learns anyone called |
| How many | no limit. Each listener costs its own latch, which it had anyway. From another exchange, `1 e b h s` as usual: each distant listener holds one trunk channel |
| `A_TX` low | a listener never sees answer and is never released by the source: a dead radio gives silence, not a cleared call. A source cannot hold M high to say it is alive, because M high on an idle port is a seizure to the scanner |
| A looping message | callers join mid-message. A message that must start from the beginning for each caller is §3's announcement card at a line class: it answers when rung and takes one caller at a time |
| A speaking clock | a ROM of words and a time-of-day counter that picks them. That is a card, and none of the exchange's business. The words for 60 minutes do not fit §3's 8 s: a 512 kB part holds 64 s |

---

## 7. Conference

Moved to [`conference.md`](conference.md): architecture (mainboard block, private
party bus, two×4 or one×8), bit-switched floor, measured detector and switch,
circuit, marker, and what it is not.

---

## 8. Data and foreign codecs

A data card is a line. A call to it is set up like any other and the fabric
passes its bits exactly (`protocol.md` §4). In-band tones sit in the stream
until answer; E rising — `DSR` — marks it. A terminal can dial by pulsing `DTR`
(`marker.md` §7). Under the marker as it stands a phone that dials a data
port hears noise, and nothing prevents it. **Proposed: a class of its own, *data
line*** (`extensions.md` §2.2, §2.4). The marker will not connect a data line
to a voice port, or the reverse, and gives cannot-complete. A run of data ports
with their overflow bits set is a pool with one number. The check is made inside
one exchange: a call from another exchange arrives on a trunk.

A card facing another codec transcodes on the card: the FXS card already does,
and a DNVT card is two codecs back to back.

---

## 9. Not measured

- **Every circuit here.** Oscillators, the ROM player, the console. Conference
  circuits: `conference.md` §8.
- **Tone levels and twist** through the encoder half; `subscriber-line.md` §5
  measured DTMF through the codec, not these tones.
- **A ROM image's start against a free-running `FILL`** in gates; the seam table is
  the bit streams, not the counter's start logic.
- **The two new classes in the marker.** *Source* and *data line* are proposed
  here and in `fabric.md` §3.5. Class *conference* is retired: a leg is a
  line (`conference.md` §6). The `calls` model still has a conference leg as a
  line and tones as classes 5 and 6.
- **A CO's ring cadence ANDed with `RING_CAD`** at the operator's phone: the phone
  rings only when both are on. Feed the operator's ring from E alone when the
  caller is class 3, or accept it.
