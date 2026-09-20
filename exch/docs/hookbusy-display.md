# The exchange — the hook/busy display

`ex-observers.md` §2 and §3 are two lamp fields and §7 recommends merging them
into one grid of bicolour LEDs. **This is that panel, built the other way**: not
64 two-colour lamps but 128 single-colour ones, on a stack of seventeen cards
that is one PCB design in sixteen copies. The colour stops being the carrier and
becomes the confirmation, which costs two packages and buys back everything a
hue judgement costs.

> **Status: proposed; the decoding measured in RTL.** `exrtl/rtl/hc259.v`,
> `lamp_card.v`, `common_card.v` and `hb_panel.v` are the parts and the stack,
> and `exrtl/tb/tb_panel.v` drives them from the real clock card and from
> `ctl_write` — 57 checks, passing under both Icarus and Verilator. §7 is what
> it measures, and §7.2 is the one that needed measuring: the inhibit, against a
> control stack built without it. **The mechanics and the panel are a sketch.**
> Nothing has been drawn, nothing has been on a bench, and §8 is longer than §7.

---

## 1. Two fields, and they are not the same kind of thing

`ex-observers.md` §1 is the whole argument and it is worth restating, because
every awkwardness below descends from it:

| | hook | busy |
|---|---|---|
| where it comes from | `HA[0..7]`, cable A | `PB0`, cable B |
| how many ports at once | **all 64**, every frame | **eight** — one block, the one `DST[5:3]` names |
| refreshed | every 15.6 µs | when the scanner comes round, ≈ 9 ms |
| with no marker fitted | **works** | freezes |
| fitted at | bring-up step 2 | step 3, with the console |

`HC` and `HA` are sixteen conductors on cable A because the ports need them to
hear each other. `BUSY` got two, shared by eight blocks, because
`exch-mainboard.md` §2.2 could say *"only the marker reads them"* — which was
true when it was written, and stopped being true when a lamp field wanted to
read all 64 at once. **The cable was sized before this panel existed**, and §9
says what to do about it.

So one signal is a 64 kHz sample of a wire and the other is a decision the
marker wrote down. They are displayed in adjacent columns and they behave
differently, and that is honest rather than untidy.

---

## 2. The card: one PCB in sixteen copies

| | parts |
|---|---|
| the latch | 1 × 74HC259 — the inverse of a '151 commutator (`ex-observers.md` §1) |
| the lamps | 8 × 5 mm LED, one column at the front edge, **green or orange by stuffing** |
| | 8 resistors |
| **BLK** | a 2×8 shunt column, silkscreen 0–7, **two shunts in one position** |
| **MODE** | a 2×3 block: hook or busy, three poles |
| | 26-way stacking header, through |
| | **≈ 1 package a card, 16 cards** |

`BLK` routes `HA[h]` to the hook `D` and `LEB[h]` to the busy `/LE` off the same
position, so the block number is set once and `MODE` picks which of the two the
'259 sees:

| | `D` | `/LE` | `/CLR` |
|---|---|---|---|
| **HOOK** | `HA[h]` | `HCLK` | Vcc |
| **BUSY** | `PB0` | `LEB[h]` | `/RESET` |

**The card knows nothing.** That is `exch-mainboard.md` §2.1's bargain one level
down — *"the cable is common, the board is position-wired, and the card knows
nothing"* — and it is why any card works in any position, why the stack order
cannot be got subtly wrong, and why **one spare covers eight**.

**No card carries a gate.** The busy `/LE` arrives already gated because the
common card's '138 does it with its own enables (§3). `ex-observers.md` §3 spent
a '138 and half a '123 on one field of eight rows; here the same parts serve
sixteen cards.

**`/LE` = `HCLK` needs no edge placed.** `HCLK` is high for the first half of a
cell and `SLOTQ` changes a quarter of a cell in (`exch-mainboard.md` §2.1), so
the address moves while the latch is closed and the addressed output follows its
port's bit through the second half — the same window every port in the exchange
captures in. There is no glitch window and nothing to trim.

### 2.1 The colour is the label

Green cards are hook rows, orange cards are busy rows, and **that is the only
difference in the bill of materials**. So a card in the wrong position is
visible before it is powered on.

It also settles the objection to `ex-observers.md` §7's bicolour grid. There,
amber-versus-red was a *hue* discrimination with no other cue: it needed
three-lead common-cathode parts, two resistors trimmed per lamp to get a real
amber, and it failed outright for about one man in twelve. Here **position
carries hook-versus-busy and the colour only confirms it.** Nothing needs
trimming, no lamp has two dies, and someone who cannot separate green from
orange reads the panel perfectly from the column alternation.

---

## 3. The common card: the seventeenth

| | parts |
|---|---|
| the word | 2 × 74HC164 — sixteen bits off cable B, exactly as at a block |
| the row | 1 × 74HC138 on `DST[5:3]`, **`/E1` = `HCLK`, `/E2` = `INH`** |
| the inhibit | ½ 74HC123, retriggerable, about a cell |
| | **≈ 3½ packages**, and the tap on both cables |

**The '138's eight active-low outputs *are* the `LEB` lines.** Its own enables do
the gating, which is why no lamp card has a gate on it.

**Both '164 are needed although only three bits are read.** `DST[5:3]` is bits
13–11 of the word (`exch-mainboard.md` §2.3.1), so the second register exists to
push them to the end.

**The shift register has no phase, only content.** Its sixteen bits are right
whenever the marker has driven sixteen good bits in a row, so this card counts
nothing and needs no frame reference. And because the block that drives `PB0` is
the block `DST[5:3]` names, and this decodes the same three bits out of the same
broadcast, **whatever is on `PB0` in cell *s* belongs to port (`DST[5:3]`, *s*)
by construction.** The field cannot be wrong about whose bit it has. It is
`ex-counters.md` §1's argument used for the row instead of the pattern.

**`G` is not read**, because nothing here writes a latch and there is no guard to
honour. So an event word (`ex-counters.md` §9, `G` = 0) steers this field's row
exactly as it steers `/BLK` at every block. The row moves to the port the event
is about and the data stays honest, because the block driving `PB0` moved with
it.

### 3.1 Why the inhibit

Mid-word the '164 holds rippling garbage and the row it names walks about. The
**data** stays honest — the block's own `/BLK` decoder is rippling in lockstep,
so the block driving `PB` is always the one being written to. What is not honest
is the **hand-over**: one block's '244 turning off, the next turning on, and `PB`
briefly undriven. `PB` is pulled LOW at the marker (`exch-mainboard.md` §6), so
an undriven instant reads *not busy* — and a '259 is transparent while addressed,
so a lamp is wrongly **cleared** and holds that until its block's next visit, up
to a scan later.

Half a package removes the question. A word is 31 µs at 512 kHz and the field is
blind for it; the lamp it would have written is written on the next frame, 15.6
µs later. §7.2 measures both halves of that.

---

## 4. The stack, and where it goes

Seventeen cards standing at **0.4 inch**, plugged into one another on a 26-way
that passes straight through. The common card is at the left end, where three
things fall out at once: its front edge is a bare 2HP strip and becomes **the
slot legend**; its cable connectors are unconstrained because it has no
neighbour on one side; and the bus enters the stack at one end rather than the
middle.

```
   common   1   2   3   4   5   6              15  16
   legend  0H  0B  1H  1B  2H  2B    ...      7H  7B
           grn orn grn orn grn orn            grn orn
    s=0     ·   ·   ·   ·   ·   ·               ·   ·
    s=1     ·   ·   ·   ·   ·   ·               ·   ·
    s=2     ·   ·   ·   ·   ·   ·               ·   ·
    s=3     ·   ·   ·   ·   ●   ○               ·   ·      port 23, on a call
    ...
    s=7     ·   ·   ·   ·   ·   ·               ·   ·
   ╰─2HP─╯ ╰───────────── 32HP ─────────────────────╯
```

Card *n* is block ⌊(*n*−1)/2⌋, hook if *n* is odd. Columns numbered 1–16 from
the left, slots 0–7 top to bottom.

| | |
|---|---|
| 17 cards × 0.4" | 172.72 mm = **exactly 34HP** |
| 8 rows at 0.4" | 71.12 mm centre to centre, ≈ 76 mm with the bodies — in §7's 90 mm |
| card | ≈ 80 mm tall × 60 mm deep |
| clearance | 10.16 − 1.6 board − 4 mm DIP = **4.5 mm**; a 5 mm LED leaves 5.16 mm |
| panel | **3U × 34HP** |

**0.4 inch is exactly 2HP**, which is why it is worth holding: seventeen cards
come out as a whole number of horizontal units with nothing to fudge. It is
*not* set by the connector. The pitch comes from the LED grid and the header has
to live with it, so **the spacers are the datum and the header floats** — a
2.54 mm pin strip has several millimetres of usable engagement and does not need
to define the spacing, only to conduct. Nobody should go hunting for a 10.16 mm
stackthrough part.

### 4.1 The gap between the pairs

A block's two columns want to read as one thing. The card carries **two LED
footprint columns 2 mm apart and one is stuffed**: green cards use the right,
orange the left. Same PCB, and the pairs close up:

| | |
|---|---|
| within a pair | 8.16 mm |
| between pairs | 12.16 mm |
| grid, first to last centre | 150.4 mm |

Cells stop being square, which is the point — the pair is the unit.

### 4.2 The 26-way

| | |
|---|---|
| `SLOTQ[2:0]` | 3 |
| `HCLK` | 1, **ground either side** — it is every hook card's `/LE` and its edges are load-bearing |
| `HA[0..7]` | 8 |
| `PB0` | 1 |
| `LEB[0..7]` | 8 |
| `/RESET` | 1 |
| +5V, GND | 2 |
| | **24 signals, 26 pins** |

`SDATA` and `SCLK` are not on it: they stop at the common card. Its own taps are
twelve signals off cable A (`HCLK`, `SLOTQ[2:0]`, `HA[0..7]`) and four off cable
B (`SDATA`, `SCLK`, `/RESET`, `PB0`).

**A through-stack, not a backplane.** Both are two PCB designs, so that is not
the difference. The difference is that a bad contact anywhere takes out
everything downstream, and that pulling a middle card means disassembling from
one end. Against that: one bolt-through, one outline, one spacer length, no
bracket — and a failure in the stack announces itself as *everything to the
right went dark*, which is about as self-diagnosing as a fault gets.

---

## 5. Reading it

### 5.1 Four states, one of them a call

`ex-observers.md` §4.1, as a horizontal pair 8 mm apart:

| | | |
|---|---|---|
| dark | dark | idle — or an empty slot, an unfitted block, a tone, a sink |
| **green** | dark | off hook and unserved. A scan: normal. Seconds: no register was free. For ever: the marker has stopped, or a handset is off its cradle |
| dark | **orange** | ringing; a trunk seized and awaiting its claim; the ≤ 0.6 s release guard; a make-busy — or **a port held by nothing**, which is a fault and stays lit for ever |
| **green** | **orange** | **a call** |

Nothing else in the exchange knows any of this. *"Nobody is in charge of a
call"* (`exch-fabric.md` §3.5) means the state of the machine exists only as 64
latches and 64 hook wires; no call ever ends on the control bus
(`ex-counters.md` §4), so no listener can reconstruct it from the words. **It has
to be read where it lives**, and this is the only place it is gathered up.

### 5.2 A flood, on the vertical axis

`ex-observers.md` §4.4 reads better rotated:

```
  the caller dials 1      every free trunk in every direction is seized,
                          all pointed at the caller
  the flood               a trunk block's ORANGE COLUMN LIGHTS DOWN ITS WHOLE
                          LENGTH and holds for up to 2.7 s.  The green column
                          beside it stays dark -- nothing has claimed
  a distant exchange      ONE lamp in the green column lights.  The orange bar
  claims                  clears, all at once
  an INBOUND seizure      a green lamp lights and then FLICKERS: a distant
                          subscriber's dial pulses, arriving as forward A
```

A vertical bar is a shape the eye tracks well, and **nothing else makes a flood
visible.** The cost of the pulse flood is a column of lamps for two and a bit
seconds on every call that leaves, which is what `exch-network.md` §5 measures
and `Topology.md` §4 limits the network by.

### 5.3 The shunt column, by colour

`ex-observers.md` §4.2, now touching:

| green column | orange column | |
|---|---|---|
| live | refreshing | the block is right |
| **dark** | refreshing | the `HC`/`HA` shunts are out: it answers and is not heard |
| live | **frozen** | the `/BLK` shunt is out: it is heard and never answers — and is never scanned, hunted or written |
| dark | all clear | no block fitted at all |

"Refreshing" is readable because the marker is scanning: a column the scanner
visits changes when the exchange changes, and a frozen one does not.

### 5.4 Two lags, and only one of them is the panel's

A busy lamp is up to **9 ms** behind because the row waits for the scanner. It is
then up to **0.6 s** behind again because `exch-marker.md` §5.2 put the release
guard on the same wire — what a lamp shows is `busy || fe || (fm && !m)`, *not
free* rather than `BUSY`, which is what the marker tests and what an operator
wants. The second lag is the design's, not the field's.

---

## 6. What it costs

| | |
|---|---|
| silicon | 16 × '259 + 3½ = **19½ packages** |
| lamps | 128 LEDs, 128 resistors |
| current | 2 mA a lamp: 16 mA out of a '259, a third of the package limit; **256 mA** for the full panel |
| panel | 3U × 34HP |
| PCB designs | **two** — the card in 16 copies, the common card in 1 |
| cables | twelve signals off A, four off B: one tap on the harness |

Two packages more than `ex-observers.md` §7's bicolour grid, for one board
design in sixteen copies, a dead lamp that is a pull-and-replace, and no hue
anywhere in the reading of it.

---

## 7. Measured

`exrtl/tb/tb_panel.v` drives `clock_card` and `ctl_write` and reads three
stacks: the normal configuration, a control with the inhibit left out, and one
jumpered as sixteen hook cards. 57 checks, identical under Icarus and Verilator.

### 7.1 The asymmetry is the design's, and it is measured

| | |
|---|---|
| **the hook field with no word ever sent** on cable B — all eight columns correct, every busy column dark | bring-up step 2, before a marker exists |
| a new hook pattern on the panel **within two frames** | 15.6 µs |
| **one word naming block 3: eight lamps move, 56 do not** | the eight-port window |
| the scanner walks 0–7 and the whole field fills | |
| the fabric changes and only the block named is re-read — **seven of eight columns stale** | 9 ms, not 15.6 µs |

### 7.2 The inhibit, against a control

The bench models the hand-over rather than asserting it: whatever the '164 names
is what drives `PB0`, and when the decode moves, `PB` is undriven for an instant
and reads low. That is not a case injected by hand — **it happens at every one of
the sixteen shifts of every word.**

| | |
|---|---|
| with `INH` | **not one lamp wrongly cleared** |
| without it, same stimulus | **3 of 8 columns corrupted** |

Both simulators give the same figure. Half a package, and the fault it prevents
is real and is not small.

### 7.3 `/RESET`, and one lamp that comes straight back

`/RESET` clears all 64 busy lamps in the same instant and does not put anyone's
phone down — the hook field's `/CLR` is tied high and every green column is
still lit. Then **the one block the stack's own '164 still names is read again
within a frame**, because nothing cleared the word; the other seven wait for the
scanner. That is correct and it was not obvious until the bench showed it.

### 7.4 One PCB, jumpered the other way

Sixteen hook cards, two columns a block, both agreeing — and not one of them
needs anything off cable B. That is the configuration a fabric-only bring-up
wants, and it is a jumper, not a different card.

---

## 8. Not measured

- **All of the mechanics.** Nothing is drawn. The card outline, the spacer
  length, the stacking header's engagement, the bezel and the two LED footprint
  columns of §4.1 are arithmetic and a sketch.
- **The stacking part.** §4 says the spacers are the datum and the header
  floats, which needs a header whose engagement range actually covers 10.16 mm
  ± the stack-up. Not chosen, not checked.
- **The bezel.** One window with a diffuser and the grid and port map
  silkscreened on it, referenced off the panel rather than off the stack, so
  that 128 lamps stay off the tolerance budget. Drawn nowhere.
- **LED current and readability.** 2 mA a lamp is arithmetic. Whether 5 mm
  lamps at 0.4 inch read at arm's length in a rack, and whether green and orange
  separate under whatever light is in the room, wants eyes and not a calculation.
- **The port map is a new drawing.** `ex-observers.md` §1's claim that *"the port
  map is the panel's silkscreen, already laid out"* does not survive the
  rotation: `exch-protocol.md` §5's map is *h*-rows × *s*-columns and this is its
  transpose.
- **Against a running exchange.** The bench replays words into the stack; it does
  not sit inside `tb_net` or `tb_stress` and check the lamps against 48 callers.
  That is the run that would show §5.2's flood as a column rather than as an
  argument.
- **The marker's real scan.** §7 steers the row by hand. It has never been driven
  by `marker.v`'s own probe-steer words with the scanner walking, which is what
  sets the 9 ms and what makes "refreshing" readable in §5.3.
- **`/CON`.** During a console tenure the window follows the operator's `DST`
  wheels rather than the scanner, so the panel dwells on whatever block they are
  looking at. Reasonable, and not thought through.
- **Two consoles, two masters, and a stopped marker** — the states
  `ex-console.md` §2 puts the bus in, none of them exercised here.

---

## 9. What this changes elsewhere

- **`ex-observers.md` §7**, the bicolour recommendation. This supersedes it, and
  the reason is §2.1: position can carry hook-versus-busy, so colour does not
  have to, and every problem with amber goes away with it.
- **`ex-observers.md` §3** keeps its parts list but loses its '138 and its
  one-shot to the common card, where sixteen cards share them instead of eight
  rows.
- **`exch-mainboard.md` §2.2's justification** — *"only the marker reads them, so
  eight blocks share two wires"* — now has a counter-example. Everything awkward
  about the busy half descends from it: the '138, the `INH`, the 9 ms window and
  the freeze. **Eight conductors would delete all four**, making the busy field
  identical to the hook field, eight packages instead of twelve, refreshed every
  frame and working with no marker. Cable A is a 64-way carrying 31 signals with
  one spare pin, so this is not a change to make today — but `HB[0..7]` belongs
  on §8's list of what a future cable should carry, beside `HB`, `RX_OCT` and
  `/CON`, which are the precedent for cable A growing at all.
- **`exch-mainboard.md` §9** still has `M` unlisted as a conductor. If cable A is
  ever respun, that and a `BUSY` highway are the two open items, and pin 1 is
  the spare.

---

## 10. What this is not

- **Not a scanned matrix.** The fabric already multiplexed all 64 ports onto
  eight wires, and eight '259 undo it. Every lamp is a latch output holding DC:
  no row driver, no refresh, no flicker, no duty cycle traded against
  brightness. Multiplexing would need the 64 bits of storage *anyway* — the
  '259s are the memory, not the drivers — plus a read-back mux, a refresh
  counter and 8× peak current, to save 120 resistors. It starts to pay only
  somewhere past 128 positions.
- **Not a shift-register field.** The hook half could be: `HA[h]` is a serial
  stream in the right order and eight '164 clocked by `HCLK` would take it, same
  package count, with the bits crawling round each row at a jumpered rate — one
  lit bead orbiting for one caller. It is prettier and it throws away the column,
  which is half the port number. **The busy half cannot be one at all**: there is
  no cycle in which 64 busy bits exist to be read, because `PB0` is one wire
  carrying one block at a time. Holding the other 56 across seven scans is an
  addressable latch field, which is the '259s again.
- **Not a heartbeat.** The row the field is writing walks with the scanner, and
  flaring it would make the panel breathe in time with the marker — a frozen
  wave meaning a stopped marker, which §1 says the busy field otherwise
  announces only by going quietly stale. But a 9 ms scan is 111 Hz and fused;
  it would need dividing by sixteen to be seen, and a panel that shimmers is a
  panel whose §5.3 diagnosis is a judgement call. If it is ever wanted, it wants
  a STEADY/LIVE toggle and it is not in this design.
