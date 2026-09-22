# The exchange — the hook/busy display

`observers.md` §2 and §3 are two lamp fields and §7 recommends merging them
into one grid of bicolour LEDs. **This is that panel, built the other way**: not
64 two-colour lamps but 128 single-colour ones, on a stack of seventeen cards
that is one PCB design in sixteen copies. The colour stops being the carrier and
becomes the confirmation, which costs two packages and buys back everything a
hue judgement costs.

> **Status: proposed; the decoding measured in RTL; PCB placement started.**
> `verilog/rtl/hc259.v`, `lamp_card.v`, `common_card.v` (the interface card) and
> `hb_panel.v` are the parts and the stack, and `verilog/tb/tb_panel.v` drives
> them from the real clock card and from `ctl_write` — 57 checks, passing under
> both Icarus and Verilator. §3 defines the interface card; §7 is what the bench
> measures. **KiCad boards** (outline + footprints + pad nets, not routed) live
> in [`pcb/hookbusy/`](../pcb/hookbusy/). Schematics there are stubs. Nothing has
> been on a bench, and §8 is still longer than §7.

---

## 1. Two fields, and they are not the same kind of thing

`observers.md` §1 is the whole argument and it is worth restating, because
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
`mainboard.md` §2.2 could say *"only the marker reads them"* — which was
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
| the latch | 1 × 74HC259 — the inverse of a '151 commutator (`observers.md` §1) |
| the lamps | 8 × 5 mm LED, one column at the front edge, **green or orange by stuffing** |
| | 8 resistors |
| **BLK** | a 2×8 shunt column, silkscreen 0–7, **two shunts in one position** |
| **MODE** | a 2×3 block: hook or busy, three poles |
| | four stacking headers, through — **HA**, **LEB**, **PWR**, **control** (§4.2) |
| | **≈ 1 package a card, 16 cards** |

`BLK` routes `HA[h]` to the hook `D` and `LEB[h]` to the busy `/LE` off the same
position, so the block number is set once and `MODE` picks which of the two the
'259 sees:

| | `D` | `/LE` | `/CLR` |
|---|---|---|---|
| **HOOK** | `HA[h]` | `HCLK` | Vcc |
| **BUSY** | `PB0` | `LEB[h]` | `/RESET` |

**The card knows nothing.** That is `mainboard.md` §2.1's bargain one level
down — *"the cable is common, the board is position-wired, and the card knows
nothing"* — and it is why any card works in any position, why the stack order
cannot be got subtly wrong, and why **one spare covers eight**.

**No card carries a gate.** The busy `/LE` arrives already gated because the
interface card's '138 does it with its own enables (§3). `observers.md` §3 spent
a '138 and half a '123 on one field of eight rows; here the same parts serve
sixteen cards.

**`/LE` = `HCLK` needs no edge placed.** `HCLK` is high for the first half of a
cell and `SLOTQ` changes a quarter of a cell in (`mainboard.md` §2.1), so
the address moves while the latch is closed and the addressed output follows its
port's bit through the second half — the same window every port in the exchange
captures in. There is no glitch window and nothing to trim.

### 2.1 The colour is the label

Green cards are hook rows, orange cards are busy rows, and **that is the only
difference in the bill of materials**. So a card in the wrong position is
visible before it is powered on.

It also settles the objection to `observers.md` §7's bicolour grid. There,
amber-versus-red was a *hue* discrimination with no other cue: it needed
three-lead common-cathode parts, two resistors trimmed per lamp to get a real
amber, and it failed outright for about one man in twelve. Here **position
carries hook-versus-busy and the colour only confirms it.** Nothing needs
trimming, no lamp has two dies, and someone who cannot separate green from
orange reads the panel perfectly from the column alternation.

---

## 3. The interface card

The seventeenth card is the stack's **interface card** — the only tap on the
two exchange cables, the only driver onto **control** and **LEB**, and the
left-hand end of all four hookbusy stack headers. (RTL still calls the module
`common_card`; the board is this.) Its front edge is bare 2HP and is the
panel's **slot legend**. It carries no lamps.

> **Measured in RTL:** the word decode, the inhibit, the `LEB` enables and the
> cable→control split (`common_card.v`, `tb_panel.v`). The '244 is a port split
> in the model — transparent assigns — so the bench does not prove drive
> current; it proves that lamp cards see only the buffered nets. Mechanics,
> the IDC taps and the '123's RC are not drawn.

### 3.1 Parts

| | |
|---|---|
| the word | 2 × 74HC164 — sixteen bits off cable B, exactly as at a block |
| the row | 1 × 74HC138 on `DST[5:3]`, **`/E1` = `HCLK`**, **`/E2` = `INH`** |
| the inhibit | ½ 74HC123, retriggerable, about a cell and a half |
| the control buffer | 1 × 74HC244 — six of eight bits onto the control bus |
| decoupling | 100 nF a package, at the '244 and the '138 |
| connectors | cable A tap, cable B tap; four **hookbusy stack** headers (through toward the lamps) |
| | **≈ 4½ packages** |

**No shunt column and no MODE.** This card is one position and one job.

### 3.2 Cable-side tap

Twelve signals off cable A, four off cable B — one load on each ribbon
conductor it uses. Pin numbers are `mainboard.md` §3's IDC positions:

| cable A | pin | into |
|---|---|---|
| `HCLK` | 3 | '244 and '138 `/E1` |
| `SLOTQ0` | 13 | '244 |
| `SLOTQ1` | 15 | '244 |
| `SLOTQ2` | 17 | '244 |
| `HA0`…`HA7` | 49…63 odd | **HA** header, straight through |

| cable B | pin | into |
|---|---|---|
| `SDATA` | 3 | first '164 `DS` |
| `SCLK` | 5 | both '164 `CP`; '123 retrigger |
| `/RESET` | 7 | '244 |
| `PB0` | 11 | '244 |

`SDATA` and `SCLK` **stop here**. They are not on any stack bus. `WR` is not
taken: nothing on this card writes a latch.

### 3.3 Stack-side headers

Four **hookbusy stack** headers, pin 1 at the front (lamp) edge. The interface card is
the left end: its receptacles face the first lamp card; the cable taps and the
legend face out.

| bus | pins | nets | driven by |
|---|---|---|---|
| **HA** | 1–8 | `HA0` … `HA7` | cable A, unbuffered |
| **LEB** | 1–8 | `LEB0` … `LEB7` | '138 `Y0`…`Y7`, active low |
| **PWR** | 1–4 | `+5V`, `GND`, `+5V`, `GND` | local supply into the stack |
| **control** | 1–6 | `SLOTQ0`, `SLOTQ1`, `SLOTQ2`, `HCLK`, `PB0`, `/RESET` | '244 outputs |

**PWR** is injected on this card — the exchange ribbons do not carry the
panel's 256 mA. Dual `+5V`/`GND` pairs share the return.

### 3.4 The '244 — control leaves the cable here

| '244 | cable in | control out |
|---|---|---|
| 1A1 / 1Y1 | `SLOTQ0` | control pin 1 |
| 1A2 / 1Y2 | `SLOTQ1` | pin 2 |
| 1A3 / 1Y3 | `SLOTQ2` | pin 3 |
| 1A4 / 1Y4 | `HCLK` | pin 4 |
| 2A1 / 2Y1 | `PB0` | pin 5 |
| 2A2 / 2Y2 | `/RESET` | pin 6 |
| 2A3, 2A4 | tie to GND | unused |
| `/1G`, `/2G` | GND | always enabled |

Sixteen '259 address and enable pins must not hang on the ribbons. The '164s
and the '138 keep the **cable-side** `HCLK` and `SCLK` — one ribbon load — and
the '244 is a separate drive into the stack. Lamp cards see only the control
header.

`HA` needs no buffer here: each highway already has a '244 on the fabric
(`fabric.md` §3.1). `LEB` is born on this card as the '138's outputs.

### 3.5 The word and the row

**Both '164 are needed although only three bits are read.** `DST[5:3]` is bits
13–11 of the word (`mainboard.md` §2.3.1), so the second register exists to
push them to the end. Bit 15 (`G`) is not read: nothing here writes a latch, so
an event word (`counters.md` §9, `G` = 0) steers the row exactly as it steers
`/BLK` at every block.

**The shift register has no phase, only content.** Its sixteen bits are right
whenever the marker has driven sixteen good bits in a row — no bit counter, no
frame reference, gated or free-running `SCLK`.

**The '138's eight active-low outputs *are* the `LEB` lines.**

| | |
|---|---|
| `A2..A0` | `DST[5:3]` from the '164s |
| `/E1` | cable `HCLK` — enabled in the **second** half of the cell |
| `/E2` | `INH` — high while `SCLK` is moving and for ~1½ cells after |
| `E3` | Vcc |
| `Y0..Y7` | `LEB[0..7]` |

So `LEB[h]` is low only when the word names block *h*, the word is still, and
it is the open half of the cell. Whatever is on `PB0` in cell *s* then belongs
to port (`DST[5:3]`, *s*) **by construction** — the same three bits steer the
block that drives `PB0`. The field cannot be wrong about whose bit it has
(`counters.md` §1's argument, used for the row).

### 3.6 The inhibit

Mid-word the '164 holds rippling garbage and the row it names walks about. The
**data** stays honest — the block's own `/BLK` decoder is rippling in lockstep,
so the block driving `PB` is always the one being written to. What is not honest
is the **hand-over**: one block's '244 turning off, the next turning on, and `PB`
briefly undriven. `PB` is pulled LOW at the marker (`mainboard.md` §6), so
an undriven instant reads *not busy* — and a '259 is transparent while addressed,
so a lamp is wrongly **cleared** and holds that until its block's next visit, up
to a scan later.

Half a package removes the question. A word is 125 µs at 128 kHz and the field is
blind for it; the lamp it would have written is written on the next frame, 15.6
µs later. §7.2 measures both halves of that.

**`INH` timing.** Any edge on cable `SCLK` retriggers the '123. The output pulse
is about **1½ cells** (RTL `INH_TICKS = 12` at 4.096 MHz ≈ 2.93 µs against a
1.95 µs cell). The RC (or the second half of the '123 jumpered as a fixed
width) is set on the bench; the number is arithmetic until then.

### 3.7 Signal flow

```
 cable A ── HCLK, SLOTQ ─────────────► '244 ──► control bus ──► lamp cards
        └─ HCLK ────────────────────► '138 /E1
        └─ HA[0..7] ─────────────────────────► HA bus ──────► lamp cards

 cable B ── SDATA, SCLK ──► '164 ×2 ── DST[5:3] ──► '138 A
        └─ SCLK ──────────► '123 ──── INH ──────► '138 /E2
        └─ PB0, /RESET ──────────────► '244 ──► control bus
                                              '138 Y ──► LEB bus ──► lamp cards

 local +5V/GND ──────────────────────────────────► PWR bus ──► lamp cards
```

### 3.8 What this card is not

- **Not a lamp card.** No '259, no LEDs, no BLK/MODE.
- **Not a second master.** It never drives `SDATA` / `SCLK` / `WR`.
- **Not a probe.** It does not read `PB1` or a port's word — only `PB0` for the
  busy lamps, through the buffer.
- **Not optional for a busy field.** Hook-only bring-up can omit it and jumper
  every lamp card to HOOK with `HA` and control sourced some other way; a mixed
  or busy field needs this card for `LEB` and the buffered control.

---

## 4. The stack, and where it goes

Seventeen cards standing at **0.4 inch**, plugged into one another on **four
internal buses** that pass straight through — `HA`, `LEB`, `PWR`, and
**control**. The **interface card** (§3) is at the left end: legend, cable taps,
and the driven ends of control and `LEB`.

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
| card | **50 mm deep × 100 mm tall** (`pcb/hookbusy/`) |
| clearance | 10.16 − 1.6 board − 4 mm DIP = **4.5 mm**; a 5 mm LED leaves 5.16 mm |
| panel | **3U × 34HP** |

**0.4 inch is exactly 2HP**, which is why it is worth holding: seventeen cards
come out as a whole number of horizontal units with nothing to fudge. It is
*not* set by the connectors. The pitch comes from the LED grid and the headers
have to live with it, so **the spacers are the datum and the headers float** —
a 2.54 mm pin strip has several millimetres of usable engagement and does not
need to define the spacing, only to conduct. Nobody should go hunting for a
10.16 mm stackthrough part.

### 4.1 One LED column

Each lamp card has **one** front-edge hole set — eight 5 mm LEDs at 0.4″,
centred on the 100 mm edge. Same PCB for HOOK and BUSY; stuffing is green or
orange and MODE selects which latch inputs are live. Adjacent cards in the
stack still read as a pair at 0.4″ centres.

### 4.2 Four buses through the stack

One mixed header is the wrong cut. The stack carries four different kinds of
thing, so it gets **four stacking headers**, each through every lamp card and
rooted on the interface card (§3.3 for the pin maps):

| bus | pins | |
|---|---|---|
| **HA** | 8 | `HA[0..7]` — cable A's highways, every frame |
| **LEB** | 8 | `LEB[0..7]` — the interface card's already-gated busy `/LE` |
| **PWR** | 4 | `+5V`, `GND`, `+5V`, `GND` — dual returns for 256 mA lit |
| **control** | 6 | `SLOTQ[2:0]`, `HCLK`, `PB0`, `/RESET` — buffered on the interface card |
| | **26** | |

**Why four.** `HA` is the fabric sample and a hook card needs nothing else from
the stack to light. `LEB` is the busy half's only private bus. `PWR` is current,
not signal. **Control** is clock- and word-shaped and must not load the ribbons
— see §3.4.

`SDATA` and `SCLK` are on none of them: they stop at the interface card.

**A through-stack, not a backplane.** Both are two PCB designs, so that is not
the difference. The difference is that a bad contact on one bus takes out that
bus downstream — an open on `HA` darkens every hook column to the right; an
open on `LEB` freezes every busy column to the right and leaves the greens
alive — and that pulling a middle card means disassembling from one end.
Against that: one bolt-through, one outline, one spacer length, four floating
headers, no bracket — and a fault that names which bus went open.

---

## 5. Reading it

### 5.1 Four states, one of them a call

`observers.md` §4.1, as a horizontal pair 8 mm apart:

| | | |
|---|---|---|
| dark | dark | idle — or an empty slot, an unfitted block, a tone, a sink |
| **green** | dark | off hook and unserved. A scan: normal. Seconds: no register was free. For ever: the marker has stopped, or a handset is off its cradle |
| dark | **orange** | ringing; a trunk seized and awaiting its claim; the ≤ 0.6 s release guard; a make-busy — or **a port held by nothing**, which is a fault and stays lit for ever |
| **green** | **orange** | **a call** |

Nothing else in the exchange knows any of this. *"Nobody is in charge of a
call"* (`fabric.md` §3.5) means the state of the machine exists only as 64
latches and 64 hook wires; no call ever ends on the control bus
(`counters.md` §4), so no listener can reconstruct it from the words. **It has
to be read where it lives**, and this is the only place it is gathered up.

### 5.2 A flood, on the vertical axis

`observers.md` §4.4 reads better rotated:

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
seconds on every call that leaves, which is what `network.md` §5 measures
and `topology.md` §4 limits the network by.

### 5.3 The shunt column, by colour

`observers.md` §4.2, now touching:

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
then up to **0.6 s** behind again because `marker.md` §5.2 put the release
guard on the same wire — what a lamp shows is `busy || fe || (fm && !m)`, *not
free* rather than `BUSY`, which is what the marker tests and what an operator
wants. The second lag is the design's, not the field's.

---

## 6. What it costs

| | |
|---|---|
| silicon | 16 × '259 + 4½ = **20½ packages** |
| lamps | 128 LEDs, 128 resistors |
| current | 2 mA a lamp: 16 mA out of a '259, a third of the package limit; **256 mA** for the full panel |
| panel | 3U × 34HP |
| PCB designs | **two** — the lamp card in 16 copies, the interface card in 1 |
| stack buses | four headers: `HA`, `LEB`, `PWR`, control — **26 pins** |
| cables | twelve signals off A, four off B: one tap on the harness |

Two packages more than `observers.md` §7's bicolour grid was, before the
control buffer; with the '244 it is three more — for one board design in
sixteen copies, a dead lamp that is a pull-and-replace, and no hue anywhere
in the reading of it.

---

## 7. Measured

`verilog/tb/tb_panel.v` drives `clock_card` and `ctl_write` and reads three
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
still lit. Then **the one block the interface card's own '164 still names is
read again within a frame**, because nothing cleared the word; the other seven
wait for the scanner. That is correct and it was not obvious until the bench
showed it.

### 7.4 One PCB, jumpered the other way

Sixteen hook cards, two columns a block, both agreeing — and not one of them
needs anything off cable B. That is the configuration a fabric-only bring-up
wants, and it is a jumper, not a different card.

---

## 8. Not measured

- **Routing and fab.** `pcb/hookbusy/` has both boards placed with nets on pads;
  copper is not routed, DRC not run, no Gerbers.
- **Schematics.** The KiCad sheets are stubs; the board refs are the authority
  until the sheets catch up.
- **The stacking part.** §4 says the spacers are the datum and the headers
  float, which needs four headers whose engagement range actually covers
  10.16 mm ± the stack-up. §3.3 assigns the pin maps; the parts are not.
- **The bezel.** One window with a diffuser and the grid and port map
  silkscreened on it, referenced off the panel rather than off the stack, so
  that 128 lamps stay off the tolerance budget. Drawn nowhere.
- **LED current and readability.** 1k5 / 2 mA is arithmetic. Whether 5 mm
  lamps at 0.4 inch read at arm's length in a rack, and whether green and orange
  separate under whatever light is in the room, wants eyes and not a calculation.
- **The port map is a new drawing.** `observers.md` §1's claim that *"the port
  map is the panel's silkscreen, already laid out"* does not survive the
  rotation: `protocol.md` §5's map is *h*-rows × *s*-columns and this is its
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
  `console.md` §2 puts the bus in, none of them exercised here.

---

## 9. What this changes elsewhere

- **`observers.md` §7**, the bicolour recommendation. This supersedes it, and
  the reason is §2.1: position can carry hook-versus-busy, so colour does not
  have to, and every problem with amber goes away with it.
- **`observers.md` §3** keeps its parts list but loses its '138 and its
  one-shot to the interface card, where sixteen cards share them instead of eight
  rows.
- **`mainboard.md` §2.2's justification** — *"only the marker reads them, so
  eight blocks share two wires"* — now has a counter-example. Everything awkward
  about the busy half descends from it: the '138, the `INH`, the 9 ms window and
  the freeze. **Eight conductors would delete all four**, making the busy field
  identical to the hook field, eight packages instead of twelve, refreshed every
  frame and working with no marker. Cable A is a 64-way carrying 31 signals with
  one spare pin, so this is not a change to make today — but `HB[0..7]` belongs
  on §8's list of what a future cable should carry, beside `LINE_HB`, `RX_OCT` and
  `/CON`, which are the precedent for cable A growing at all.
- **`mainboard.md` §9** still has `M` unlisted as a conductor. If cable A is
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
