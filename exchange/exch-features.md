# The exchange — features are lines

Operator, outside line, tones, recorded announcements, a radio anyone may
listen to, a conference: each is a card in a channel slot with a class mark,
and the marker reaches it by hunting the class (`exch-marker.md` §3) or by its
number. A conference is eight such cards and a block of their own (§7.3). This is
how the Bell System built such things — as trunk circuits — except that what is
switched here is CVSD.

> **Status: proposed.** Measured in simulation: every card's *behaviour as a
> port* (`exch.py calls`), the announcement's bit stream and seams
> (`exch.py announce`), and the conference bridge's speech detector, floor and
> switch (`exch.py confer`); `exch.log` is the run. Sources (§6) and the
> conference bridge (§7) add two classes, which are **proposed with the class
> codes of `exch-fabric.md` §3.5 and not yet in `exch-marker.md` or the `calls`
> model**. None of the cards has a circuit yet, and nothing has been on a bench.

---

## 1. The register is not a line

It was, while registers had to hear tones. **All-pulse, a register needs only the
caller's hook**, and that is on the M highway for the reading: `register.md` §4
as it stands, its line-select '151 replaced by the marker's kind of probe,
≈ 10 packages, all 74HC, no port (`exch-marker.md` §4). A DTMF receiver would be a
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
does not drive (`exch-mainboard.md` §2.1); with no ringback card fitted it sits
at `FILL` and a caller hears silence while the far phone rings (`mvp-ex.md`).

**Which port it sits at is free**, because nothing is ever switched to it: the
tone reaches a caller through the called port's cell, not through a connection
(`exch-marker.md` §5). A slot with no port circuit costs least; slot 0 or 4 of a
block fitted as trunk group 2 or 3 — ports 20, 24, 30, 34 — costs nothing and is
dialable as a test line (`tone-card.md` §5.1).

Dial tone is at port 10 and cannot-complete at 14 (`exch-protocol.md` §5). Both
are in block 1.

**Which tones, and a fourth.** `tone-plan.md` settles the frequencies and
cadences, and proposes **busy at port 11** — free wherever block 1 is not a trunk
group, never dialable because 1 is a first key — so that busy and
cannot-complete differ in timbre as well as speed instead of sharing one tone.
It is another *source* reached by address, not another class, and the marker
already computes the free test that steers it. It also specifies the generator
as a tolerance both an oscillator card and a ROM card meet, and measures why the
cadence trick above **must not** be used at a warble rate: a square there costs
23 dB and fifty spurious lines (`sim/tones.py warble`).

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
first sample. Four were too few. The conference bridge's switch (§7.2) is the
same cold start, measured at 400 instants inside words: the speech fades in over
16 ms median, 28 ms worst, without a pop. The memory is the syllabic filter's,
not the 1 ms integrator's. Record the silence.

---

## 4. Operator (class 2) and the console

**The operator is a phone at port 04**, on a line card whose word says operator
(`ex-extensions.md` §2.2). 0 hunts class 2 in fixed order
from 00, and 04 is the first class-2 port the hunt meets. So a second position
and a night announcement are just more class-2 cards further along, in any of
the line slots (`exch-marker.md` §3). The operator is not at 00 because a
cleared latch listens there (`exch-protocol.md` §5).

**The console is separate, and optional**: a busy-lamp field — '259s and LEDs off
the M and `BUSY` highways — and keys that drive the marker's control bus by
hand. **Build it first.** Fabric plus console is a working manual board, and the
bring-up tool for everything that comes after.

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

`exch-marker.md` §2 does exactly that for classes 5 and 6, so a radio whose word
says class 6, at 75, is dialled as 75 today. What it lacks is a class of its own: at
class 6 it would also be hunted as cannot-complete if the card at 14 were
pulled. **Proposed: one class, *source*, for everything that talks and never
listens, the two tones included.** The marker reaches dial tone and
cannot-complete by their fixed addresses, 10 and 14, not by a hunt, so no source
is ever hunted and the class means only "one write" (`exch-fabric.md` §3.5).

| | |
|---|---|
| The card | whatever makes the sound, into one encoder half of `mf8-spec.md` §12.1: a receiver for a radio. A recording needs no codec: §3's ROM player, looping. `A_TX` tied low |
| A caller | dials its number and hears it at once. It is never rung, because a source listens to nobody and its E is never high. The caller leaves by hanging up, and the source never learns anyone called |
| How many | no limit. Each listener costs its own latch, which it had anyway. From another exchange, `1 e b h s` as usual: each distant listener holds one trunk channel |
| `A_TX` low | a listener never sees answer and is never released by the source: a dead radio gives silence, not a cleared call. A source cannot hold M high to say it is alive, because M high on an idle port is a seizure to the scanner |
| A looping message | callers join mid-message. A message that must start from the beginning for each caller is §3's announcement card at a line class: it answers when rung and takes one caller at a time |
| A speaking clock | a ROM of words and a time-of-day counter that picks them. That is a card, and none of the exchange's business. The words for 60 minutes do not fit §3's 8 s: a 512 kB part holds 64 s |

---

## 7. Conference: a bridge with no codec in it

**CVSD bits cannot be added.** Summing needs every party decoded, summed and
encoded again. That is a codec pair on every leg, a codec tandem for every party
(−4.8 dB, `exch-protocol.md` §2), and every open microphone's noise in the sum.
The meet-me bridge first written here was that. **Bits can be switched.** One
party talks at a time. The bridge chooses who, and every other party receives
that party's bits exactly as sent: no codec, no tandem, and no added noise
however many legs are open. This is a voice-switched speakerphone, done on the
bit streams.

### 7.1 How it works

```
 legs      eight cards in a conference block (§7.3), class conference, joined by the block's own ribbon:
           the party bus.  Each is an ordinary port.  Its caller listens to it and it listens to its
           caller: a two-way connection
 detector  on the caller's bits: runs of three equal bits, counted over a 16 ms window (TICK / 16).
           8 or more in a window = the caller SPOKE
 silent    8 windows, 128 ms, without speaking
 floor     one leg at a time.  The holder keeps it until it is silent AND another leg has spoken; then the
           first leg in slot order that spoke takes it.  No holder yet: the first leg to speak
 bus       DATA  the holder's C_RX, driven by the holder alone      HELD  a leg holds the floor
           KEEP  the holder is not silent                            ASK   a leg other than the holder spoke
           PRI   a daisy chain in slot order
 strap     cuts all five between legs 3 and 4: one bridge of eight, or two of four (§7.3)
 C_TX      HELD and not mine → DATA;  otherwise FILL.  The holder's own caller hears silence
 A_TX      = A_RX: a leg answers the moment it is called and drops when its caller does
```

**Why runs of three.** A CVSD encoder sends three equal bits in a row when its
step is too small for the signal it follows. The density of those runs is what
drives the decoder's syllabic filter (the law's run length is 3), so it is the
loudness of the signal, read from the bits without decoding them. The detector
is a shift register, two gates and a counter.

**Why the floor stays with the last talker.** The floor passes only when
someone else talks, so a holder's own next word after a pause is never clipped,
and a silent bridge does not switch at all. It also protects against echo: a
listener whose line echoes the holder's voice "speaks" only while the holder
does, and the floor never passes while the holder is talking. With only one
direction ever open, there is no loop through two hybrids to sing.

### 7.2 Measured

`exch.py confer`, with talkers of this repository's own test set and room noise
45 dB below nominal speech in every microphone.

**The detector.** Percentage of 16 ms windows whose count reaches 8:

| | windows reaching 8 | "talking": 16 ms rms within 30 dB of nominal |
|---|---|---|
| speech at nominal | 66.0 % | 73.5 % |
| 10 dB down | 46.5 % | 64.1 % |
| 20 dB down | 19.8 % | 43.9 % |
| 30 dB down | 1.4 % | 21.7 % |
| room noise alone, 20 dB down | **100 %** | |
| room noise alone, 30 dB down | 0.10 % | |
| room noise alone, 40 dB down, or `FILL` | 0 | |

**The hangover.** A three-party conversation: B says "mm-hm" while A talks,
then answers 100 ms after A stops. Separately, all 126 ordered pairs of seven
talkers, each with one talking over the other for 3 s:

| silent after | B's "mm-hm" heard | B's answer switched, after its onset | floor changes in 3 s of double talk (mean / most) | interrupter carried | holder cut off |
|---|---|---|---|---|---|
| 64 ms | 0 | 7 ms | 3.6 / 8 | 61 % | 34 % |
| **128 ms** | **0** | **7 ms** | **2.2 / 5** | **54 %** | **38 %** |
| 256 ms | 0 | 135 ms | 1.1 / 3 | 41 % | 34 % |
| 512 ms | 0 | 423 ms | 0.5 / 3 | 26 % | 28 % |

A reply loses whatever is left of the hangover when it begins, counted from the
last speaker's last loud window, plus up to one window to detect it. At 128 ms,
a reply 100 ms after A stopped lost 7 ms; at 256 ms, it lost 135 ms. The price
of 128 ms is in double talk, where the floor changes about twice in 3 s instead
of once. 128 ms is also the silence counter's Q3; 256 ms would need a fifth bit.

**The switch.** At the switch, the listener's decoder stops following one
talker and starts following another from the state the first left it in. Over
400 switches between talkers 1–7:

| | back within −30 dB of the new talker's own decode, after | peak in 20 ms, heard ÷ own decode |
|---|---|---|
| **as the bridge does it**: the old holder silent for 128 ms | 16.1 ms median, 27.6 ms worst | −0.8 dB median, **+3.6 dB worst** |
| if the floor passed while both were talking | 14.4 ms median, 26.4 ms worst | +0.1 dB median, **+26.2 dB worst** |

**The hangover is also what keeps the switch clean.** After 128 ms of the old
holder's silence the decoder has relaxed to its smallest step. The new talker
fades in over about 16 ms and nothing pops. A switch between two talkers in full
voice would leave the decoder with the first talker's step, and the result would
be a pop up to 26 dB above the speech. At a word's start (the usual case in the
conversation) the switch was clean within 4 ms. Clear of a switch, what the
other parties heard was the holder's own decode, with any difference 84 dB or
more below it.

### 7.3 The circuit, and the block it sits in

| per leg | parts |
|---|---|
| the caller's last three bits; all equal | 74HC164, ½ 74HC86, ¼ 74HC02 |
| window: TICK ÷ 16; the runs in it, Q3 = spoke | 74HC393 |
| silence: windows since spoke, Q3 = 128 ms, held there | ½ 74HC393 |
| spoke latch; the floor | 74HC74 |
| `DATA` three-state; `HELD`, `KEEP`, `ASK` open-drain | 74HC125 |
| take and let go, the priority chain, the `C_TX` select | 74HC00, 74HC08 |

**≈ 9 packages a leg, all 74HC: no codec and no analog part.** Every leg
divides the same bussed `TICK` from `RESET`, so all windows end together, and
take and let-go are decided on the same edge from the same bus state. A leg
whose caller hangs up drops the floor with its `A_RX`.

**A bridge is not legs scattered through the line slots. It is a block of its
own, and the party bus never leaves it.** A conference block is a self-contained
unit — eight legs, the ribbon that joins them, and the block's own fabric and
supervision. To the exchange it is an ordinary block, and says nothing about what
is inside:

| what the block shows the exchange | what stays inside |
|---|---|
| `HC_OUT`, `HA_OUT`, `/BLK`: three pins and three shunt columns, its number set like any block's (`exch-mainboard.md` §1) | `DATA`, `HELD`, `KEEP`, `ASK`, `PRI`: the party bus, on the block's own ribbon |
| the common cable: the clocks, `FILL`, `TICK`, the serial control word | the legs' words and their `/ANS`, which are fixed and need no jumper |
| eight ports, dialled `h 0` to `h 7` | which leg holds the floor, and when it passes |

**The party bus does not go on the primary bus.** The channel slot has one pin
spare, a14 (`ex-extensions.md` §2.1), and the mainboard cable is thirty-eight
signals that are deliberately identical at every tap (`exch-mainboard.md` §1).
Five more bussed signals would have to either borrow the slot's line-feed and
ringing pins — ninety volts of ringing beside a 74HC input, and a keying rule to
keep a line card out of the slot — or add conductors to a cable whose conductor
count is the one thing that document's §9 watches. Neither is worth paying for
something only eight ports in the exchange will ever use. **The block keeps its
own bus inside its own skin, and the primary bus stays exactly what it is.**

**Nothing external.** No subscriber line, so no −48 V, no ringing, no PTC, no
analog rails and no hybrid: the unit is 74HC at 5 V throughout, and
`exch-mainboard.md` §2.4's rule that −48 V and `RING` never leave a subrack does
not reach it.

**The strap: one bridge of eight, or two of four.** One strap block cuts all five
bus signals between legs 3 and 4, and carries the two overflow bits with them:

```
                70   71   72   73   │ strap │   74   75   76   77

  DATA  HELD   ──●────●────●────●───┤   ○   ├───●────●────●────●──
  KEEP  ASK                         │       │
  PRI          ──►────►────►────►───┤   ○   ├───►────►────►────►
  o bit          o    o    o    ·   │   ○   │   o    o    o    ·

  strap out, as drawn   two bridges of four, at 70 and at 74
  strap in              one bridge of eight, at 70: the cut closes, PRI runs through, 73's o is set
```

**One strap, not two things that must agree.** The segmentation of the bus, the
priority chain and the overflow bits the marker hunts on are all inside the
block, so all three move together and cannot be set inconsistently. Everywhere
else a hunt group is jumpers on each card (`ex-extensions.md` §2.4), where
getting one wrong is possible; here it is not.

**Two of four is the default, and the strap is the exception.** §7.5's worst
failure is one leg wedging a whole bridge: a caller in noise 20 dB below speech
never falls silent, so that leg holds the floor until it hangs up. Eight legs
give eight chances of it per conference and lose the whole bridge; four give four
and lose half the exchange's conference capacity. Two conferences at once is also
the commoner traffic — two three-party calls far outnumber one six-party call.
And §7.2 measured three parties, and pairs in double talk: four is a short step
from what was measured, eight is not.

**Cost.** ≈ 9 packages a leg, above, and ≈ 82 for the block's own fabric and
supervision (`exch-fabric.md` §5): **≈ 154 packages for eight legs, two bridges
and the ribbon.** The only part of it that is not an ordinary block is the
ribbon and its strap.

**Where it sits in the numbering.** Blocks 0 and 1 are never dialled — 0 is the
operator and 1 the network's key, so `h` is 2–7 (`exch-marker.md` §2). A
conference block takes one of those six: at 7 the bridges are 70 and 74, and the
exchange keeps 40 of its 48 dialable ports as lines. A second conference block is
another dialable block spent, and four bridges.

### 7.4 The marker's part

> **Proposed, not applied here** (`ex-groups.md` §5–§6): a bridge's legs
> *answer to* its number, so the run, its `o` bits and the marker's ≈ 2 packages
> go. Phones that answer to a bridge's number become its extensions, which needs
> the bridge to ring out and the second `DATA` line that §7.5 declined.

- **Class *conference*** (`exch-fabric.md` §3.5), in the leg's word, and **`/ANS`
  tied low** on the leg, so that it does not ring: E reaches the leg steadily,
  not in the ring cadence, and the caller hears no ringback. A leg that rang in
  cadence would take up to 4 s to answer, with ringback in the caller's ear the
  whole time.
- **A bridge is a hunt group: a run of adjacent legs on one segment of the party
  bus, and its number is its first leg's.** It is the hunt group of
  `ex-extensions.md` §2.4: every leg but the last sets the overflow bit of its
  word. Dialling any leg takes the first free leg from that one onward, in slot
  order, until a leg that is not free has the bit clear. No free leg →
  cannot-complete. **A conference block is two bridges of four or one of eight,
  by its strap** (§7.3), and an exchange may have more than one such block. **A
  run never crosses a block boundary**, because the party bus never leaves the
  block.
- **A bridge is reached only by its number.** No key is special to it: 8 stays a
  spare first key, and gives cannot-complete.
- **Across the network a bridge is dialled like any line**, `1 e b h s` from
  anywhere. If 55 on exchange 26 is a bridge, line 24 of exchange 25 dials
  `1 2 6 5 5`: the flood, exchange 26's claim on `2 6`, its register's `h s` = 55,
  then the same hunt. Each remote party holds one trunk channel on every link
  between it and the bridge.
- **The marker's part of the hunt** uses the free-running scanner, as every hunt
  does. A flip-flop is set when the scanner reaches the dialled port (a 74HC688
  comparing the scanner with the digit store), and cleared at a port that is not
  free and has its overflow bit clear. The first free port while it is set is
  taken: **≈ 2 packages**, and at most two scans, 16 ms. It is the same hunt for
  every kind of group.
- **A bigger bridge is more legs on one segment.** There is no sum to clip and no
  noise to add, so the limit is the block and its strap, not the audio: eight is
  the most one bridge can be, because eight is a block. The cost of a bridge is
  counted in dialable block numbers (§7.3), not in line slots, and what argues
  against spending more of them is §7.5, not the bit stream.
- **Nothing hunts onward unless its card says so.** Dialling a busy phone must
  not ring its neighbour, so a port overflows only if its word's overflow bit is
  set. A sales desk or a pool of data ports is a group in the same way
  (`ex-extensions.md` §2.4).

### 7.5 What it is not

- **Two at once.** The bridge picks one. An interrupter gets through only in the
  holder's pauses, in 54 % of its speech. Laughter and cross-talk come out as
  one voice at a time.
- **The holder hears nobody** while holding, not even someone trying to cut in.
  Sending the holder the previous holder's bits would need a second `DATA` line;
  not proposed.
- **A quiet caller**, 30 dB down, reaches the threshold in 1.4 % of windows and
  will seldom get the floor.
- **A caller in noise 20 dB below speech** never falls silent. Once that leg has
  the floor it keeps it, until that caller hangs up or the operator clears the
  leg's latch from the console. A limit on how long one leg may hold the floor
  would cure it; not modelled.

---

## 8. Data and foreign codecs

A data card is a line. A call to it is set up like any other and the fabric
passes its bits exactly (`exch-protocol.md` §4). In-band tones sit in the stream
until answer; E rising — `DSR` — marks it. A terminal can dial by pulsing `DTR`
(`exch-marker.md` §7). Under the marker as it stands a phone that dials a data
port hears noise, and nothing prevents it. **Proposed: a class of its own, *data
line*** (`ex-extensions.md` §2.2, §2.4). The marker will not connect a data line
to a voice port, or the reverse, and gives cannot-complete. A run of data ports
with their overflow bits set is a pool with one number. The check is made inside
one exchange: a call from another exchange arrives on a trunk.

A card facing another codec transcodes on the card: the FXS card already does,
and a DNVT card is two codecs back to back.

---

## 9. Not measured

- **Every circuit here.** Oscillators, the ROM player, the conference leg, its
  party bus and the block's strap, the console.
- **Tone levels and twist** through the encoder half; `subscriber-line.md` §5
  measured DTMF through the codec, not these tones.
- **A ROM image's start against a free-running `FILL`** in gates; the seam table is
  the bit streams, not the counter's start logic.
- **The conference with real phones**: handset levels, room noise and echo from
  real hybrids, rather than the test set's talkers with added noise; and how
  people take to a half-duplex meeting.
- **The two new classes in the marker.** Sources and conference legs are
  proposed here and in `exch-fabric.md` §3.5. The `calls` model still has a
  conference leg as a line and tones as classes 5 and 6.
- **A CO's ring cadence ANDed with `RING_CAD`** at the operator's phone: the phone
  rings only when both are on. Feed the operator's ring from E alone when the
  caller is class 3, or accept it.
