# The exchange — the hook/busy display

`observers.md` §2 and §3 are two lamp fields and §7 recommends merging them
into one grid of bicolour LEDs. **This is that panel, built the other way**: not
64 two-colour lamps but 128 single-colour ones, on a stack of seventeen cards
that is one PCB design in sixteen copies. The colour stops being the carrier and
becomes the confirmation, which costs nothing and buys back everything a hue
judgement costs.

> **Status: redrawn for the folded plane (`newimpl/`); placed, not routed, not
> simulated.** The panel reads `/HA` and `/HB`, the two scanned open-collector
> conductors of `newimpl/README.md` §1, and nothing on cable B. The earlier
> design — `HA[0..7]` highways for hook, the block-steered `PB0` for busy, a
> word decode and an inhibit — was measured in `old/verilog/tb/tb_panel.v`
> (57 checks) and is **gone with the bus it read**; §7 says what of that
> carries over. **KiCad boards** (outline, footprints, pad nets, not routed)
> live in [`pcb/hookbusy/`](../pcb/hookbusy/). Schematics there are stubs.
> Nothing has been on a bench.

---

## 1. Two fields, and now they are the same kind of thing

The old panel's awkwardness all came from one asymmetry: hook was a 64 kHz
sample of eight highways, busy was a decision the marker had written down,
readable eight ports at a time off `PB0` while the scanner pointed at a block.
The folded plane removes it:

| | hook | busy |
|---|---|---|
| where it comes from | `/HA`, cable A | `/HB`, cable A |
| addressed by | `SCAN[5:0]`, the clock card's divider | the same `SCAN[5:0]`, the same bit-time |
| how many ports | **all 64**, one a bit-time | **all 64**, one a bit-time |
| refreshed | every **1 ms** | every **1 ms** |
| with no marker fitted | works | **works** — every busy lamp dark, which is true |

In bit-time *p* port *p* pulls `/HA` if its card is off hook (M) and `/HB` if it
is busy — the port's full term, `bsy || fe || (fm && !m) || mute_blk`
(`newimpl/rtl/port.v`). Both wires idle high on a 4.7 k pull-up at the clock
card and are sampled in cell 4. The two columns of a block are now **one
circuit with a different wire on its input**, and the only difference between
a hook card and a busy card is which of the two a jumper picks.

`observers.md` §1's argument — that the busy field could only ever be a window
onto the marker's scan — was true of `PB`, and `PB` no longer exists.

---

## 2. The card: one PCB in sixteen copies

| | parts |
|---|---|
| the latch | 1 × 74HC259 — the inverse of the scan: 64 serial bits back into 64 DC outputs, eight a card |
| the lamps | 8 × 5 mm LED, one column at the front edge, **green or orange by stuffing** |
| | 8 × 1k5 |
| **BLK** | `JP1`, a 2×8 shunt column, silkscreen 0–7, **one shunt** |
| **MODE** | `JP3`, 1×3: hook (`/HA`) or busy (`/HB`) |
| | three stacking headers, through — **LE**, **PWR**, **control** (§4.2) |
| | **1 package a card, 16 cards** |

| '259 pin | net | |
|---|---|---|
| `A0..A2` (1–3) | `SCAN0..SCAN2` | the slot, off the control bus |
| `D` (13) | `/HA` or `/HB` | by `MODE` |
| `/LE` (14) | `LE[h]` | by `BLK`: the interface card's decode of `SCAN[5:3]` = *h* |
| `/CLR` (15) | +5 V | nothing clears the field; the next pass rewrites it |
| `Q0..Q7` (4–7, 9–12) | 1k5 → LED cathode | LED anode to +5 V |

**The lamp sinks into the latch.** A port that pulls its plane makes `D` low,
so the latched output is low and the LED between it and +5 V lights. An idle
port, an unstuffed slot and an unfitted block all leave the wire at its
pull-up, latch high and stay **dark** — the panel fails dark with no inverter
and no part that knows about absence. A '259 sinks 16 mA with all eight lit,
well inside the package.

**The card knows nothing.** `mainboard.md` §2.1's bargain one level down: any
card works in any position, set by one shunt and one jumper, and **one spare
covers sixteen** — hook and busy are the same board, stuffed with a different
colour.

**No `/RESET`, no `/CLR` line.** At power-up the latches hold whatever they
come up in for at most one pass, 1 ms, and then every lamp has been written.

### 2.1 The colour is the label

Green cards are hook rows, orange cards are busy rows, and **that is the only
difference in the bill of materials** besides where `MODE` sits. So a card in
the wrong position is visible before it is powered on.

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
exchange, the only driver onto **control** and **LE**, and the left-hand end of
all three stack headers. Its front edge is bare 2HP and is the panel's **slot
legend**. It carries no lamps.

### 3.1 Parts

| | |
|---|---|
| the block decode | `U3`, 1 × 74HC138: `A` = `SCAN[5:3]`, enabled in the lamps' sampling window (§3.4) |
| the control buffer | `U5`, 1 × 74HC244: five of eight bits onto the control bus |
| decoupling | `C3`, `C5`: 100 nF at each package |
| connectors | `J5` cable A tap; `J7` +5 V in; three stack headers toward the lamps |
| | **2 packages** |

**Nothing off cable B.** There is no word to decode: the old card's two '164,
its '123 inhibit and its cable-B tap existed only to find out which block `PB0`
was speaking for, and `/HB` says so by the bit-time it arrives in.

### 3.2 Cable-side tap

Eleven signals off cable A, one load on each conductor:

| net | from cable A | into |
|---|---|---|
| `SCAN0..SCAN2` | the clock card's scan, low bits | '244 → control |
| `SCAN3..SCAN5` | the scan, high bits = the block | '138 `A0..A2` |
| `/HA`, `/HB` | the two scanned planes | '244 → control |
| `HCLK` | high for the first half of a cell | '138 `/E1` |
| `SLOTQ1`, `SLOTQ2` | the cell number, a quarter cell late | '138 `/E2`, `E3` |

**Cable A has no pin table for the folded plane yet.** `mainboard.md` §3.1
still lists `HA0..HA7` and no `SCAN`, and `newimpl/README.md` §5 records only
that `SCAN[5:0]` moves onto cable A. `J5` is a 2×8 placeholder carrying the
eleven nets on pins 1–11 and ground on 12–16; it becomes a crimped IDC tap
when the cable is drawn.

### 3.3 Stack-side headers

Three headers, pin 1 at the top of the card:

| bus | pins | nets | driven by |
|---|---|---|---|
| **LE** | 1–8 | `LE0_N` … `LE7_N` | '138 `Y0`…`Y7`, active low |
| **PWR** | 1–4 | `+5V`, `GND`, `+5V`, `GND` | `J7`, local supply into the stack |
| **control** | 1–6 | `SCAN0`, `SCAN1`, `SCAN2`, `HA_N`, `HB_N`, spare | '244 outputs |

**PWR** is injected on this card — the exchange ribbons do not carry the
panel's 256 mA. Dual `+5V`/`GND` pairs share the return.

`/HA` and `/HB` **must** be buffered here. They are the exchange's only two
supervision conductors, each one pull-up against 64 open drains, and the rise
time of that pull-up sets how long after a frame edge the whole exchange can
sample. Sixteen '259 inputs hung on them would be sixteen loads of capacitance
on the slowest edge in the machine; the '244 makes it one.

| '244 | cable in | control out |
|---|---|---|
| pin 2 → 18 | `SCAN0` | pin 1 |
| 4 → 16 | `SCAN1` | pin 2 |
| 6 → 14 | `SCAN2` | pin 3 |
| 8 → 12 | `/HA` | pin 4 |
| 11 → 9 | `/HB` | pin 5 |
| 13, 15, 17 | tied to GND | unused |
| `/1OE`, `/2OE` | GND | always enabled |

### 3.4 The window

The '138's eight active-low outputs **are** the `LE` lines:

| '138 | net | |
|---|---|---|
| `A0..A2` | `SCAN3..SCAN5` | the block whose ports own this frame |
| `/E1` | `HCLK` | the **second** half of a cell |
| `/E2` | `SLOTQ1` | low in cells 4 and 5 … |
| `E3` | `SLOTQ2` | … and high in them |
| `Y0..Y7` | `LE0_N..LE7_N` | |

So `LE[h]` is low in the second half of cells 4 and 5 of every frame that
belongs to a port of block *h*, and the '259 addressed by `SCAN[2:0]` follows
its port's bit through that window and holds it when the window closes.

**Why this needs no inhibit.** The old card's '123 existed because the address
came off a shift register that rippled for a whole word. Here the address is
`SCAN`, which steps only at the frame edge — between cell 7 and cell 0, two
cells clear of the window on either side. `/HA` and `/HB` are driven for the
whole bit-time, so by cell 4 the handover is 7.8 µs old; the exchange's own
sample is the middle of cell 4 and the lamps close later, at the end of cell 5.
`SLOTQ` moves a quarter cell in, while `HCLK` still holds the '138 off, so the
enable itself cannot glitch (`mainboard.md` §2.1). There is nothing to trim.

The window is cells 4 **and** 5 rather than cell 4 alone because the '138 has
three enables and `SLOTQ0` would need a fourth. Latching twice in one bit-time
from the same wire is harmless.

### 3.5 Signal flow

```
 cable A ── SCAN[2:0], /HA, /HB ──► '244 ──► control bus ──► lamp cards
        └─ SCAN[5:3] ──────────────► '138 A
        └─ HCLK, SLOTQ1, SLOTQ2 ───► '138 enables
                                     '138 Y ──► LE bus ──────► lamp cards

 local +5V/GND ─────────────────────────────► PWR bus ─────► lamp cards
```

### 3.6 What this card is not

- **Not a lamp card.** No '259, no LEDs, no BLK/MODE.
- **Not on cable B.** It never sees a word, drives nothing on the control bus,
  and cannot be a second master because it is not on the cable at all.
- **Not a probe.** It does not read `/HW`.
- **Not optional.** Every lamp card needs `LE` and the buffered control bus;
  there is no longer a hook-only configuration that can do without it, and no
  reason to want one.

---

## 4. The stack, and where it goes

Seventeen cards standing at **0.4 inch**, plugged into one another on **three
internal buses** that pass straight through — `LE`, `PWR` and **control**. The
**interface card** (§3) is at the left end: legend, cable tap, and the driven
ends of control and `LE`.

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
| 8 rows at 0.4" | 71.12 mm centre to centre, ≈ 76 mm with the bodies |
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
orange and `MODE` selects which plane the latch reads. Adjacent cards in the
stack still read as a pair at 0.4″ centres.

### 4.2 Three buses through the stack

| bus | pins | |
|---|---|---|
| **LE** | 8 | `LE[0..7]` — the interface card's window, one line a block |
| **PWR** | 4 | `+5V`, `GND`, `+5V`, `GND` — dual returns for 256 mA lit |
| **control** | 6 | `SCAN[2:0]`, `/HA`, `/HB`, one spare — buffered on the interface card |
| | **18** | |

`LE` is the only bus a card is jumpered onto; control is the same five signals
on every card; `PWR` is current, not signal. Nothing clock-shaped leaves the
interface card except the window, and the window is already gated.

**A through-stack, not a backplane.** Both are two PCB designs, so that is not
the difference. The difference is that a bad contact on one bus takes out that
bus downstream — an open on `LE` pin *h* freezes both columns of block *h* to
the right of it; an open on control pin 4 or 5 freezes every hook or every
busy column to the right — and that pulling a middle card means disassembling
from one end. Against that: one bolt-through, one outline, one spacer length,
three floating headers, no bracket — and a fault that names which bus went
open.

---

## 5. Reading it

### 5.1 Four states, one of them a call

`observers.md` §4.1, as a horizontal pair 8 mm apart:

| | | |
|---|---|---|
| dark | dark | idle — or an empty slot, an unfitted block, a tone, a sink |
| **green** | dark | off hook and unserved. A pass or two: normal. Seconds: no register was free. For ever: the marker has stopped, or a handset is off its cradle |
| dark | **orange** | ringing; a trunk seized and awaiting its claim; the ≤ 0.6 s release guard; a make-busy or a muted block — or **a port held by nothing**, which is a fault and stays lit for ever |
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

### 5.3 Jumpers, by what they look like

| what is wrong | what the panel shows |
|---|---|
| a block header's jumper is out | both columns of that block dark — its ports never take a turn on either plane. The same signature as no block at all |
| a port card's slot jumper disagrees with its socket | its lamps light **in the row the jumper says**, not the row it sits in — and if that row's own card is fitted the two share a bit-time and OR |
| a lamp card's `BLK` shunt in the wrong position | its column repeats another block's — the same pattern in two places |
| a lamp card's `MODE` the wrong way | a green column showing busy, or an orange showing hook: the colour and the behaviour disagree |

The second row is the one worth building the panel for: `newimpl/README.md` §5
records that the slot jumper *must* match the socket, and nothing else in the
exchange shows that it does not.

### 5.4 One lag, and it is not the panel's

A lamp is at most one pass behind its port: **1 ms**. That is the whole of the
panel's own delay, for hook and busy alike.

A busy lamp can then be up to **0.6 s** behind the *call* because `marker.md`
§5.2 put the release guard on the same wire — what a lamp shows is the port's
full busy term, *not free* rather than `BUSY`, which is what the marker tests
and what an operator wants. That lag is the design's, not the field's.

---

## 6. What it costs

| | |
|---|---|
| silicon | 16 × '259 + 2 = **18 packages** |
| lamps | 128 LEDs, 128 resistors |
| current | 2 mA a lamp: 16 mA into a '259, a third of the package limit; **256 mA** for the full panel |
| panel | 3U × 34HP |
| PCB designs | **two** — the lamp card in 16 copies, the interface card in 1 |
| stack buses | three headers: `LE`, `PWR`, control — **18 pins** |
| cables | eleven signals off cable A, **none off cable B** |

The old panel was 20½ packages, four stack buses and a cable-B tap, and its
busy half was up to 9 ms stale and blind with no marker. The fold made it
cheaper and better at once, which is the fold's own argument
(`newimpl/README.md` §1) seen from the side.

---

## 7. Measured

**Nothing, in this form.** `newimpl/` has no panel model and no bench reads
`/HA` and `/HB` into a stack of latches.

`old/verilog/tb/tb_panel.v`'s 57 checks were against the old bus. What carries
over as an argument, not a measurement:

- **The inhibit result** (3 of 8 columns corrupted without it) was about a
  shift-register address rippling while `PB` changed hands. Neither exists
  here, and §3.4 is why the new window needs no inhibit — but that is
  reasoning, not a bench.
- **`/RESET` clearing the busy field** has no counterpart: the busy latches are
  rewritten every millisecond from the ports themselves, and there is no reset
  input on any lamp card.
- **The hook field working with no marker** now holds for both fields.

The bench to write is small: `clock_card`, a `mainboard` with a few ports
pulling, and eight '259 models behind one '138 — checking every lamp against
the port that owns its bit-time, including a slot jumper set wrong.

---

## 8. Not measured

- **Routing and fab.** `pcb/hookbusy/` has both boards placed with nets on pads;
  copper is not routed. `make check` in `pcb/` runs DRC: what remains is
  unrouted nets and silkscreen size, not collisions.
- **Schematics.** The KiCad sheets are stubs; the board nets are the authority
  until the sheets catch up.
- **Cable A's pins** (§3.2). `J5` is a placeholder until the folded plane's
  cable is drawn.
- **The stacking part.** §4 says the spacers are the datum and the headers
  float, which needs three headers whose engagement range actually covers
  10.16 mm ± the stack-up.
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
- **The `/HA` rise time with the panel's one load on it.** `newimpl/README.md`
  lists the 4.7 kΩ pull-up as unanalysed; the '244 adds one HC input to it.
- **Against a running exchange.** No bench sits the panel inside `tb_net` and
  checks the lamps against a flood, which is the run that would show §5.2 as a
  column rather than as an argument.

---

## 9. What this changes elsewhere

- **`observers.md` §7**, the bicolour recommendation. This supersedes it, and
  the reason is §2.1: position can carry hook-versus-busy, so colour does not
  have to.
- **`observers.md` §1 and §3** describe busy as a window onto the marker's scan
  off `PB0`. With `/HB` that is no longer true of any listener, and §3's '138
  and one-shot are gone rather than moved.
- **This document's earlier §9** asked for `HB[0..7]` on a future cable A so the
  busy field could stop depending on the scan. The folded plane did better with
  one conductor.

---

## 10. What this is not

- **Not a scanned matrix.** The clock card already multiplexed all 64 ports onto
  two wires, and sixteen '259 undo it. Every lamp is a latch output holding DC:
  no row driver, no refresh, no flicker, no duty cycle traded against
  brightness. Multiplexing the lamps would need the 64 bits of storage
  *anyway* — the '259s are the memory, not the drivers — plus a refresh
  counter and 8× peak current, to save 120 resistors.
- **Not a shift-register field.** `/HA` is now one serial stream of all 64 ports
  in order, and eight '164 clocked by `TX_CLK` would take it — but the bits
  would crawl round the field, one lit bead orbiting for one caller, and the
  column, which is half the port number, would be thrown away. The '259 keeps
  every lamp in its place.
- **Not a heartbeat.** The scan is 1 kHz and fused. A frozen scan shows as a
  frozen panel only because nothing changes — if a stopped clock card ever
  needs showing, that is a lamp on the clock card, not this field.
