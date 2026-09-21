# The exchange — four cards that only listen

`counters.md` built a traffic counter as a card that *only listens*: three of
the cable's thirty-eight conductors, no `/BLK`, no shunt column, no probe, and no
connection to the marker at all. **It is not the only such card.** Everything an
operator or a technician wants to see is already on the two cables, because the
fabric is a broadcast and the control bus is a broadcast, and nothing in the
exchange holds the state of a call anywhere else.

This document is four of them:

| | | |
|---|---|---|
| §2 | **the hook lamp field** | 64 lamps, one a port, off the A highways. ≈ 8 packages |
| §3 | **the busy lamp field** | 64 lamps, one a port, off `PB` and the word. ≈ 12 |
| §5 | **the port watch** | one port's latch, hook, `BUSY` and class, on two wheels. ≈ 10 |
| §6 | **the last-word display** | the last word on cable B, frozen on a strapped match. ≈ 5½ |

`features.md` §4 has the first two in one line — "a busy-lamp field — '259s
and LEDs off the M and `BUSY` highways" — and §1 of this document is why that
line is half right, which turns out to be the whole design.

> **Status: proposed. Nothing measured, deliberately**: none of this is in
> `verilog` (§9). The parts are a sketch from the block's front end
> (`fabric.md` §3.1), the counter card's (`counters.md` §1) and the
> console's watch (`console.md` §3.2). Every timing figure is arithmetic
> from `mainboard.md`'s own constants, not a simulation and not a bench.
> Nothing has been drawn.

---

## 1. There is no `BUSY` highway, and that is the whole difference

**A lamp field is a demultiplexer with LEDs on it.** The fabric has already done
the hard half: `fabric.md` §1.1 puts all 64 ports on eight wires, each port
once a frame, and **the port's address is where it appears — which wire, and
when.** A 74HC259 addressable latch is exactly the inverse of a '151
commutator: address it with the same count and hand it the wire, and its eight
outputs are the eight ports, held. It is the part the trunk receiver already
uses for the same job (`fabric.md` §1.1: "the trunk receiver's '259 is the
same demultiplexing done for all the channels at once").

So an 8 × 8 grid of LEDs is not a scanned matrix. **Nothing is multiplexed on
the panel**: every lamp is a latch output holding DC, there is no row driver, no
refresh, no flicker and no duty cycle to trade against brightness. The
multiplexing was done by the exchange, and eight packages undo it.

**The grid is the numbering.** Row = highway = block = the first dialled digit;
column = slot = the second. The port map (`protocol.md` §5) is therefore
the panel's silkscreen, already laid out:

```
        s=0    1      2      3      4      5      6      7
  h=0   idle  DT     busy   NOGO   OPER   night  (line) (line)   block 0: tones 01-03, bank 04-07
    1   .     trunk  trunk  trunk  .      trunk  trunk  trunk     block 1: first MF8 group when networked
    2   20     21     22     23     24     25     26     27       blocks 2-7: lines (or more trunks)
   ...
    7   70     71     72     73     74     75     76     77
```

**Now the half that is not free.** `HC` and `HA` are on the cable and every tap
sees them. `BUSY` is not. A block commutates its eight ports' `BUSY` with a
fourth '151 (`fabric.md` §3.1) onto **`PB0`, which eight blocks share and
which only the selected block drives** (`mainboard.md` §2.2): "only the
marker reads them, so eight blocks share two wires". `marker.md` §5.2 calls
it "the `BUSY` highway", and inside a block it is one; on the cable it is one
wire that carries one block at a time, and which block is **whichever one the
last sixteen-bit word named**.

That single fact separates the two fields completely:

| | hook | busy |
|---|---|---|
| where it comes from | `HA[0..7]`, cable A | `PB0`, cable B |
| how many ports at once | **all 64**, every frame | **eight** — one block, the one `DST[5:3]` names |
| what addresses it | `SLOTQ` and the wire | `SLOTQ`, and the marker's own last word |
| refreshed | every 15.6 µs | while its block is selected; once a scan, ≈ 9 ms |
| with no marker fitted | **works** | freezes |
| fitted at | bring-up step 2 (`fabric.md` §7) | step 3, with the console |
| packages | 8 | 12 |

---

## 2. The hook field: eight packages and no gates

| | parts |
|---|---|
| the demultiplexers | 8 × 74HC259, one a highway: `D` = `HA[h]`, `A[2:0]` = `SLOTQ`, `/LE` = `HCLK`, `/CLR` tied high |
| the lamps | 64 LEDs and 64 resistors |
| | **8 packages, no gates** |

**`/LE` is `HCLK` and nothing else.** `HCLK` is high for the first half of a
cell and `SLOTQ` changes a quarter of a cell in (`mainboard.md` §2.1), so
the address moves while the latch is closed, and the addressed output follows
its port's bit through the second half of the cell — the same window every port
in the exchange captures in (`fabric.md` §3.2). There is no glitch window
and no edge to place. The eleven conductors it needs are `HCLK`, `SLOTQ[2:0]`
and the eight `HA`.

**What a lamp shows is `A_TX`: the card's own M, raw.** Not a call, not a state
the exchange holds — there is no such thing — but what the thing behind the port
is saying about itself, 64 000 times a second:

| the card | its lamp is |
|---|---|
| a phone (`channel-cards.md` §2) | off-hook. **Dial pulses are visible**: 10 pps, 33 ms of break, a flicker you can count |
| an FXS card | loop current |
| an FXO card, the exchange build (`features.md` §5) | ringing present, held 5 s across the cadence gap, OR the loop closed: an incoming CO call lights it *steadily* |
| a tie trunk channel | **what the far end is sending on A** — not a hook here at all. §4 |
| a tone, a radio, an announcement before it answers, a sink card | `A_TX` tied low: **dark for ever, and working perfectly** |
| a conference bridge leg | `A_TX` = `A_RX`: the leg mirrors its own caller |
| an empty slot, an unfitted block | pulled to ground: dark |

**`/CLR` is tied high and not to `/RESET`.** A reset clears every latch in the
exchange; it does not put anyone's phone down.

---

## 3. The busy field: it needs the marker's word to know which row is live

| | parts |
|---|---|
| the word | 2 × 74HC164 — sixteen bits, shifted by `SCLK`, exactly as at a block. `DST[5:3]` is bits 13–11, so both registers are needed although only three bits are read |
| the row | 1 × 74HC138 on `DST[5:3]`, its eight active-low outputs straight onto the eight `/LE` pins. `/E1` = `HCLK`; `/E2` = `INH` |
| the demultiplexers | 8 × 74HC259: `D` = `PB0`, `A[2:0]` = `SLOTQ`, **`/CLR` = `/RESET`** |
| the shift inhibit | ½ 74HC123 or a '14 and an RC: `INH` high while `SCLK` is moving and for a cell after it |
| | **≈ 12 packages** |

**The row decode is the block's own rule, so the field cannot be wrong about
whose bit it has.** The block that drives `PB` is the block `DST[5:3]` names
(`rtl.md`, "steering the probe costs a visit"), and the field decodes the
same three bits out of the same broadcast. Whatever is on `PB0` in cell *s*
belongs to port (`DST[5:3]`, *s*) by construction. It is `counters.md` §1's
argument — "the shift register has no phase, only content" — used for the row
instead of the pattern.

**Why the inhibit, then.** Mid-word the '164 holds rippling garbage, and the row
it names walks about. The *data* stays honest, because the block's `/BLK`
decoder is rippling with it and the block driving `PB` is the one the field is
writing to; what is not honest is the **hand-over**, where one block's '244 is
turning off and the next is turning on and `PB` is briefly undriven. `PB` is
pulled low at the marker (`mainboard.md` §6), so an undriven instant reads
*not busy*, and a '259 is transparent while addressed: a lamp could be wrongly
cleared and hold that until its block's next visit, up to a scan later. `INH`
costs a package and removes the question. **A word is 31 µs at 512 kHz and the
field is blind for it**; the lamp it would have written is written on the next
frame, 15.6 µs later.

**`/CLR` is `/RESET`.** The one signal that clears every latch in the exchange
clears all 64 lamps in the same instant, for no parts and one conductor already
at the tap.

**What a lamp shows is not the `BSY` bit.** `marker.md` §5.2's fix put the
release guard on the same wire: `BUSY` + any detector still timing out
(`port.v`: `busy || fe || (fm && !m)`). So a busy lamp is **not free**, which is
what the marker tests and what the operator wants, and it stays lit for up to
about 0.6 s after both parties have hung up. That lag is the design's, not the
field's.

**The field follows whoever has the bus.** During a console tenure
(`console.md` §2) the rows are steered by the console's words, and under HOLD
the marker stops writing: the busy field freezes with one row live while the
hook field runs on. **That difference is a diagnosis** — see §4.

---

## 4. The two fields together

### 4.1 Four states, and only one of them is a call

| hook | busy | what it is |
|---|---|---|
| 0 | 0 | idle and on hook. **Also**: an empty slot, an unfitted block, a tone, a radio, a sink. The bus's polarity is *absent reads as empty* (`mainboard.md` §6) and the field inherits it |
| **1** | 0 | **off hook and unserved.** For up to one scan, normal — the marker has not been round yet. For seconds: **no register was free** (`marker.md` §6). For ever: the marker has stopped, or a phone is off its cradle |
| 0 | **1** | being rung; a trunk seized outbound and waiting for its claim, for up to 2.7 s of flood; the release guard, ≤ 0.6 s; a sink pointed at somebody (`console.md` §5); a make-busy (§4 there); or **a port held by nothing**, which is a fault and stays lit for ever |
| 1 | 1 | a call |

**Nothing else in the exchange knows any of this.** "Nobody is in charge of a
call" (`fabric.md` §3.5) means the state of the machine exists only as 64
latches and 64 hook wires, and the two fields are the only place it is gathered
up. The marker does not have it; the registers do not have it; no call ever ends
on the control bus at all (`counters.md` §4), so no listener can reconstruct
it from the words. **It has to be read where it lives.**

### 4.2 The fields diagnose the shunt column

`mainboard.md` §6 calls a block with a shunt in the `/BLK` row only "the
confusing one": it answers the marker but drives no highway. Two fields settle
it at a glance, because the two halves of a block's identity are on different
cables:

| hook row | busy row | |
|---|---|---|
| live | refreshing | the block is right |
| **dark** | refreshing | the `HC`/`HA` shunts are out: it answers and is not heard |
| live | **frozen** | the `/BLK` shunt is out: it is heard and never answers — and is never scanned, hunted or written |
| dark | refreshing all-clear | no block fitted at all |

"Refreshing" is readable because the marker is scanning: a row that the scanner
visits changes when the exchange changes, and a frozen one does not.

### 4.3 Classes do not appear, and should not

A lamp field shows **behaviour**, and a class is **identity**. The identity is on
`PB1`, one bit a frame, eight in a visit (`extensions.md` §2.2) — to put it
on the panel per port would want eight '164, one a column, and 192 more lamps,
to display something that changes only when somebody changes a card.

So: **the class is the silkscreen and the watch.** The port map is printed round
the grid (§1), which labels every fixed address — 00 idle, 01–03 the tones, 04
the operator bank, the first trunk group on block 1 when networked — and §5's card reads the
live class of any one port on demand. What the field gives instead is each
class's **signature**, which is more useful than its name:

| class | in the field |
|---|---|
| **line** (1) | both lamps together, and the hook lamp flickering while they dial |
| **operator** (2) | a line, at 04, usually the busiest lamp on the panel |
| **external trunk** (3) | hook lit by ringing before anyone has done anything; §2 |
| **tie trunk** (4) | busy alone for the length of a flood, then hook if it claimed. §4.4 |
| **tone, source** (5, 6) | **both dark always.** Working and idle look identical, and a pulled tone card looks the same again (`marker.md` §3: the next class-5 port serves, and with none the call still completes in silence) |
| **announcement** | dark, then hook 300 ms after it is rung, then dark |
| **conference bridge leg** | the leg's hook is its caller's hook, one lamp a leg |
| **unequipped** (0) | both dark |

### 4.4 A flood is visible, and nothing else makes it visible

A trunk channel's hook lamp is the far end's A bit, so the two fields read a
network call from opposite ends of the link:

```
 the caller dials 1        every free trunk in every direction is seized, all pointed at the caller:
                           the BUSY lamps of a whole row light at once, and stay lit for up to 2.7 s
 the flood                 those trunks' HOOK lamps are dark -- nothing has claimed
 a distant exchange claims  ONE of them lights its hook lamp.  The rest go out, both lamps, together
 an INBOUND seizure        a trunk's hook lamp lights and then FLICKERS: that is a distant
                           subscriber's dial pulses, arriving as forward A (network.md 3)
```

**The cost of the pulse flood is a row of lamps for two and a bit seconds on
every call that leaves**, which is exactly what `network.md` §5 measures and
`topology.md` §4 limits the network by. It is worth being able to see it.

---

## 5. The port watch: one port, in full

Two octal wheels pick a port `h s`; the card shows everything the two cables can
say about that one port. It is `console.md` §3.2's watch with the other three
things beside it, and it is the answer to *who rang 23?*

| | parts |
|---|---|
| the word | 2 × 74HC164 |
| the port match | 1 × 74HC688: `DST[5:0]` and `G` against the wheels and a 1 |
| **the shadow** | 1 × 74HC574 on bits 7–0, clocked by `WR` · match. 8 LEDs: `SRC` as two octal groups, `BSY`, `CLM` |
| the block match | ¾ 74HC86 and a gate: `DST[5:3]` against the wheels' `h`, for `PB` |
| the strobes | 1 × 74HC138 on `SLOTQ`, `HCLK` on `/E` — the register's trick (`mainboard.md` §2.2) |
| the moment, the wire | 2 × 74HC151: strobe *s*, and `HA[h]`. **This is a port's own listen structure** |
| hook and `BUSY` | 1 × 74HC74, two lamps |
| the card's word | 1 × 74HC164 off `PB1`, gated to whole octets. 8 LEDs, three of them the class |
| armed, seen, stale | ½ 74HC74 and gates, two lamps, one key |
| | **≈ 10 packages, ≈ 20 LEDs, two wheels, one key** |

**Bits 7–0 are the port's '273 verbatim** (`mainboard.md` §2.3.1), so the
'574 is a true shadow of the latch: what the port was last *told* to listen to.
For a called port that is the caller — a call trace. For a caller it is the
called port, and before that the dial tone port, and before that whatever the
last call left.

**Three rules, and the card shows two of them rather than leaving them to the
operator:**

- **It must be armed before the call.** A call already up when the wheels are
  turned to it is invisible: latches cannot be read back, and the write that made
  it has gone by. The SEEN lamp, cleared by the key, says whether what is
  displayed was caught or is left over from a previous setting.
- **A port clears its own latch and tells nobody.** A release is not a word
  (`counters.md` §4). So **STALE** = the shadow is not idle and the live
  `BUSY` off `PB` is clear: the port let go and the display is history. One gate,
  and it is the difference between a call trace and a lie.
- **Across a trunk it names the trunk port and nothing beyond it.** The distant
  caller is not knowable here, by anything, ever — the flood carries no calling
  number and the claim carries no address (`network.md` §3). What the card
  *can* add is the trunk's own word, which carries its direction
  (`extensions.md` §2.2): the trace ends with "in from the west", and the rest
  is a telephone call to the other exchange's operator. At a hub the shadow of a
  trunk port also catches every tie-through and resolver write, which is several
  a call.

**The class beside the shadow is what tells an empty slot from an idle line** —
the one thing §4.3 says the field cannot do. Set the wheels to a dark pair of
lamps: class 0 is an empty slot, class 1 with all ones is a plain line card, a
nail is a nail, and no word at all is a card held off at power-up or taken out of
service (`extensions.md` §2.2).

---

## 6. The last-word display: a one-shot logic analyser

| | parts |
|---|---|
| the word | 2 × 74HC164 |
| the display | 2 × 74HC574, 16 LEDs: `G` and the spare, `DST` as two octal groups, `SRC` as two more, `BSY` and `CLM` |
| the trigger | 1 × 74HC688 with `counters.md` §2's three-way straps — ground, Vcc or `P`ᵢ — over any eight of the sixteen bits |
| armed / frozen | ½ 74HC74, one lamp, one key, and one gate into the '574 clocks |
| | **≈ 5½ packages.** 5 on a panel that already carries §5's '164 pair |

Free-running it holds **the last word cable B carried**, which on a quiet
exchange is the last thing that happened, and under load is a blur that tells you
the marker is alive. Armed, it holds the *first* word matching the straps and
lights FROZEN. That is a one-shot logic analyser for six packages, and at
bring-up it is what turns `fabric.md` §7 step 6 — "a second block, then the
marker" — from inference into a reading.

**Two modes, one strap:**

| clocked by | catches | needs |
|---|---|---|
| `WR` | every **write**, by either master | nothing. `mainboard.md` §2.3.2's one rule already keeps `WR` clear of every `SCLK` edge, so the word is stable through the pulse |
| **the end of an `SCLK` burst** | every word, **probe steers included** — the scanner walking the blocks, live | a retriggerable one-shot of about one `SCLK` period. Works only with `SCLK` gated per word, not on the free-running strap of §2.3.2 |

The second mode is the one that shows what the marker is *doing* rather than what
it has decided, and it is the same `SCLK`-is-moving signal the busy field needs
for its inhibit (§3) — one one-shot serves both on a shared panel.

**A trigger output.** The match, brought to a pin, triggers a scope on "the word
that wrote port 37" or "the next claim". `mainboard.md` §9 asks for `WR`
scoped against `SCLK` at the far end of the longest run, cold and warm; this is
the thing that arms that measurement.

**What it cannot catch.** A release, because a release is not a word. An answer,
because that is `E` rising inside a port. And it cannot distinguish an outbound
completion from an inbound one, for the reason `counters.md` §3 measured: they
are the same sixteen bits.

---

## 7. The panel

64 LEDs at 0.2-inch pitch is 40.6 mm square, in 90 mm of usable height and 8HP
of width; 12HP leaves room for the port-map legend, which is the whole point of
printing it. **Two separate fields side by side would want 16HP or more, so the
recommendation is one grid of bicolour LEDs** — green hook, red busy, amber both
— which costs the same silicon (8 '259 a colour either way), half the panel, and
reads as one picture instead of two. The four states of §4.1 are then four
colours, and *dark* is idle.

Current is arithmetic, not a measurement: 2 mA a lamp is 16 mA out of a '259, a
third of its 50 mA package limit and well inside ±5.2 mA an output at 4.5 V, and
128 mA for a full grid of 64. If 2 mA is not readable at arm's length in a rack
the cure is a ULN2803 a row and no change anywhere else.

---

## 8. What this changes elsewhere

- **`features.md` §4**, "a busy-lamp field — '259s and LEDs off the M and
  `BUSY` highways": the '259s are right and there is no `BUSY` highway on the
  cable. The M field is 8 packages and independent of everything; the `BUSY`
  field is 12 and needs the control bus to know which row it is looking at. §1.
- **`marker.md` §5.2** calls `BUSY` a highway. Inside a block it is one;
  outside, it is `PB0` and one block at a time. Worth a word there.
- **`mainboard.md` §9**, "what re-drives the scanned port's `M`": **none of
  these four cards needs it.** The hook field and the watch both take M off `HA`,
  where every port's is, continuously. The open question is the marker's and
  `network.md` §3.2's alone.
- **`console.md` §3.2**, the watch: the same card with hook, `BUSY`, the class
  and a STALE lamp beside the shadow, at ≈ 10 packages instead of ≈ 4. Its two
  rules — armed before the call, stale on a self-release — become two lamps.
- **`console.md` §2.4**: HOLD stops the marker, and now it visibly stops it —
  a frozen busy field beside a live hook field. That is a second lamp for the
  same fault `/CON` already earns one for.
- **`fabric.md` §7**: the hook field joins at step 2, before the console,
  because it needs cable A and nothing else. Step 3's "read `BUSY` back on the
  probe bus" is the busy field's first job.

---

## 9. Not measured

- **None of it is in `verilog`**, on purpose: the RTL has a marker, a console and a
  counter card, and these four would be listeners on the same `ctl_write` and
  highway signals the benches already carry. The busy field's row decode against
  a *running* marker — how often a row is stale, and whether the inhibit window
  is wide enough — is the one thing a bench would actually settle.
- **The `PB` hand-over.** §3's argument that an undriven `PB` reads not-busy and
  could clear a lamp is reasoned from `mainboard.md` §6's pull, not
  measured, and the width of the inhibit follows from it.
- **The circuit.** `/LE` = `HCLK` against the '259's set-up and hold either side
  of the address change; the '138's two enables; the one-shot; the '688 against
  `WR`'s width; the wheels' contacts, which are not synchronised to anything and
  do not need to be, because nothing they change is clocked.
- **Bicolour LEDs.** Whether green, red and amber are told apart at arm's length
  in a rack, and whether amber at 2 mA a die is the same brightness as the other
  two. The fallback is two grids and 16HP.
- **The watch's word display** assumes the card's octet is aligned to `TX_OCT`
  (`extensions.md` §2.2's '165 loaded on `TX_OCT`), so eight frames of `PB1`
  from an octet edge are the word. If a block's selection changes mid-octet the
  shifted byte is garbage; the gate that suppresses that is named here and not
  drawn.
- **Two consoles, two watches, two of anything.** All four cards are listeners
  and cannot contend. The trigger output is the only pin any of them drives.
