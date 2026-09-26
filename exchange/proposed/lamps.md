# Lamps: the hook/busy panel, the port watch and the last-word display

Three cards that only listen. The hook/busy panel shows every port's hook and
`BUSY`; the port watch shows everything about one port; the last-word display
holds a control word. None drives anything but LEDs, and none needs a marker.

> **Proposed.** The panel's two boards are placed, not routed, in
> `pcb/hookbusy/` (schematics are stubs); no `newimpl` bench models any of the
> three. The port watch and the last-word display are sketches by function.
> Drawing of the panel: [`hookbusy.svg`](hookbusy.svg).

---

## 1. What there is to see

- **Every port's hook and `BUSY`**, on `/HA` and `/HB` in the port's own
  bit-time, all 64 every pass, 1 ms (`fabric.md` §3). A listener with `SCAN`
  gathers them; nothing is steered and no marker need be fitted.
- **Every write** on `SDATA`, `SCLK`, `WR` (`bus.md` §4), from either master.
- **A card's word**, on `/HW` after a select on `/WS` (`fabric.md` §4).

**Nobody is in charge of a call**: the state of the machine is 64 latches and
64 hook wires, and a normal hang-up writes nothing (`proposed/counters.md` §4),
so no listener can rebuild it from the words. **It has to be read where it
lives**, and the panel is the one place it is gathered up.

---

## 2. The hook/busy panel: one lamp card in sixteen copies

128 single-colour lamps — a hook column and a busy column a block — on a stack
of seventeen cards: sixteen lamp cards of one design and an interface card.

| | parts |
|---|---|
| the latch | 1 × 74HC259: the inverse of the scan, 64 serial bits back into DC outputs, eight a card |
| the lamps | 8 × 5 mm LED in one column at the front edge, **green or orange by stuffing**; 8 × 1k5 |
| **BLK** | `JP1`, a 2×8 shunt column, silkscreen 0–7, **one shunt** |
| **MODE** | `JP3`, 1×3: hook (`/HA`) or busy (`/HB`) |
| | three stacking headers, through: **LE**, **PWR**, **SIG** (§4) |

| '259 pin | net | |
|---|---|---|
| `A0..A2` (1–3) | `SCAN0..SCAN2` | the slot, off the stack's SIG header |
| `D` (13) | `/HA` or `/HB` | by `MODE` |
| `/LE` (14) | `LE[h]` | by `BLK`: the interface card's decode of `SCAN[5:3]` = *h* |
| `/CLR` (15) | +5 V | nothing clears the field; the next pass rewrites it |
| `Q0..Q7` (4–7, 9–12) | 1k5 → LED cathode | LED anode to +5 V |

**The lamp sinks into the latch.** A port that pulls its plane makes `D` low,
the latched output low, and the LED lights. An idle port, an empty socket and
an unfitted block leave the wire at its pull-up and stay **dark**: the panel
fails dark with no inverter and no part that knows about absence. A '259 sinks
16 mA with all eight lit. No `/RESET`: at power-up every lamp is written within
one pass.

**The card knows nothing**: any card works in any position, set by one shunt
and one jumper, and one spare covers sixteen. **The colour is the label**:
green cards are hook columns and orange busy, the only difference in the bill
of materials besides `MODE`, so a card in the wrong place shows before power
is on. Position carries hook-versus-busy and colour only confirms it: no
bicolour parts, nothing to trim, and a reader who cannot tell green from
orange reads the panel from the column alternation.

---

## 3. The interface card

The seventeenth card: the only tap on the exchange, the only driver onto the
stack's SIG and LE headers, and the left-hand end of all three. Its bare 2HP
front edge is the panel's slot legend. **2 packages**: `U3`, a 74HC138 (the
block decode), and `U5`, a 74HC244 (the buffer); 100 nF at each; `J5` the bus
tap, `J7` +5 V in.

**Eleven signals off the bus**, one load on each: `SCAN0..SCAN5`, `/HA`, `/HB`,
`HCLK`, `SLOTQ1`, `SLOTQ2` (pins: `bus.md` §2). `SCAN0..2`, `/HA` and `/HB`
go through the '244 onto SIG; `SCAN3..5` and the three timing signals go to the
'138. **Nothing off the control lines**: `/HB` says which port is busy by the
bit-time it arrives in, so there is no word to decode.

**`/HA` and `/HB` must be buffered here.** Each is one pull-up against a drain
a block (`bus.md` §1), and its rise time sets how soon after a frame edge the
whole exchange can sample; sixteen '259 inputs on it would be sixteen loads on
the slowest edge in the machine, and the '244 makes it one.

**The window.** The '138's outputs **are** the `LE` lines:

| '138 | net | |
|---|---|---|
| `A0..A2` | `SCAN3..SCAN5` | the block whose port owns this frame |
| `/E1` | `HCLK` | the second half of a cell |
| `/E2`, `E3` | `SLOTQ1`, `SLOTQ2` | cells 4 and 5 |

So `LE[h]` is low in the second half of cells 4 and 5 of every frame that
belongs to a port of block *h*, and the '259 addressed by `SCAN[2:0]` follows
that port's bit through the window and holds it. **No inhibit is needed**:
`SCAN` steps only at the frame edge, two cells clear of the window either
side; `/HA` and `/HB` are driven for the whole bit-time; the exchange samples
mid cell 4 (`fabric.md` §3) and the lamps close at the end of cell 5; `SLOTQ`
moves while `HCLK` holds the '138 off, so the enable cannot glitch. Two
latchings in one bit-time from one wire are harmless.

---

## 4. The stack

```
   legend   0H  0B  1H  1B  2H  2B    ...      7H  7B
            grn orn grn orn grn orn            grn orn
    s=0      ·   ·   ·   ·   ·   ·               ·   ·
    s=3      ·   ·   ·   ·   ●   ○               ·   ·      port 23, on a call
    s=7      ·   ·   ·   ·   ·   ·               ·   ·
   ╰─2HP─╯ ╰───────────── 32HP ──────────────────────╯
```

Card *n* (1–16 from the left) is block ⌊(*n*−1)/2⌋, hook if *n* is odd; slots
0–7 top to bottom. The rows are the port map transposed (`numbering.md` §2).

| | |
|---|---|
| 17 cards at 0.4″ | 172.72 mm = **exactly 34HP** |
| 8 rows at 0.4″ | 71.12 mm centre to centre |
| a card | **50 mm deep × 100 mm tall** |
| clearance | 10.16 − 1.6 board − 4 mm DIP = 4.5 mm; a 5 mm LED leaves 5.16 mm |
| panel | **3U × 34HP** |

**The spacers are the datum and the headers float**: the pitch comes from the
LED grid, and a 2.54 mm strip has millimetres of engagement to spare. Three
buses pass straight through: **LE** (8, the window, one line a block, the only
bus a card is jumpered onto), **PWR** (`+5V`, `GND`, `+5V`, `GND`, for 256 mA
lit, injected on the interface card), **SIG** (`SCAN[2:0]`, `/HA`, `/HB`, one
spare; the boards call it `control`, which is not the exchange's control
lines): **18 pins**. An open on a bus freezes that bus downstream — `LE` pin
*h* both columns of block *h*, SIG pin 4 or 5 every hook or busy column to its
right — and pulling a middle card means unstacking from one end. Against that:
one outline, one spacer length, no backplane, and a fault that names its bus.

**Not a scanned matrix.** Every lamp is a latch output holding DC: no row
driver, no refresh, no duty cycle. Multiplexing the lamps would need the 64 bits
of storage anyway, plus a refresh counter and 8× peak current, to save 120
resistors.

| cost | |
|---|---|
| silicon | 16 × '259 + 2 = **18 packages** |
| lamps | 128 LEDs and resistors, 2 mA each, **256 mA** full |
| PCB designs | **two** |

---

## 5. Reading the panel

**Four states, one of them a call** (a hook and busy pair, 8 mm apart):

| hook | busy | |
|---|---|---|
| dark | dark | idle, or an empty socket, an unfitted block, a tone, a source, an idle sink |
| **green** | dark | off hook, not yet taken: under the mini marker a pass or two; under the class marker up to a round of its walk, ≈ 250 ms (`marker.md` §4.2). Seconds: the one register is held. For ever: no marker, a handset off its cradle, or a port no marker takes — an off-hook data line, a ring source, a card whose word reads none |
| dark | **orange** | ringing; a trunk seized by a flood, awaiting its claim; the release time after a hang-up (`fabric.md` §5); a make-busy; a block muted by its adapter; a sink in use; a tied nail's port with its phone on hook — or **a port held by nothing**, a fault that stays lit |
| **green** | **orange** | **a call** |

A busy lamp is the port's full busy term (`newimpl/rtl/port.v`), *not free*
rather than `BSY`: what the marker tests and what an operator wants.

**A flood.** A trunk's hook lamp is the far end's A, so the panel reads a
network call from both ends of a link:

```
 the caller dials 1     one trunk each way that has a free one is seized, all
                        listening to the caller: at most four busy lamps, wherever
                        those cards sit; their hook lamps dark -- nothing has claimed
 a far exchange claims  that trunk's hook lamp lights; the others go dark at the claim
 an inbound seizure     a trunk's hook lamp lights, its busy lamp a few passes later
                        as the unit holds it; the hook flickers with the far pulses
```

Nothing else makes a flood visible (`network.md` §4 for its timing).

**Jumpers, by what they look like:**

| what is wrong | what the panel shows |
|---|---|
| a block header's jumper out | both columns of that block dark, as if no block |
| a port card's slot jumper set to the wrong socket | its lamps in the row the jumper says; if that row's card is fitted, the two share a bit-time and OR |
| a lamp card's `BLK` shunt misplaced | its column repeats another block's |
| a lamp card's `MODE` the wrong way | a green column showing busy, or an orange showing hook |

The second row is the one worth building the panel for: the slot jumper must
match the socket (`block-stack.md` §4), and nothing else shows that it does not.
**A lamp lags its port by at most one pass, 1 ms.**

---

## 6. The port watch: one port, in full

Two octal wheels pick a port; the card shows everything the bus says about it.
It answers *who rang 23?*

| | parts |
|---|---|
| the word | 2 × 74HC164 on `SDATA`, `SCLK` |
| the port match | 1 × 74HC688: `DST[5:0]` and `G` against the wheels and a 1 |
| **the shadow** | 1 × 74HC574 on bits 7–0, clocked by `WR` · match; 8 LEDs: `SRC` as two octal groups, `BSY`, `CLM` |
| hook and `BUSY` | a probe: a '688 on `SCAN` against the wheels, ¼ '08, ½ '74, reading `/HA` and `/HB` at the port's turn (`newimpl/rtl/probe.v`); two lamps |
| the card's word | a word reader (`newimpl/rtl/word_rx.v`, ≈ 6): a select on `/WS` at the port's turn, eight frames of `/HW` into a '259; 8 LEDs: type, family and member, options — on a trunk its glare and direction |
| armed, seen, stale | ½ 74HC74 and gates, two lamps, one key |
| | **≈ 12 packages, ≈ 20 LEDs, two wheels, one key** |

**Bits 7–0 are the port's '273 verbatim** (`bus.md` §4), so the '574 is a true
shadow of the latch: what the port was last *told* to listen to. For a called
port that is the caller, a call trace. The word is read once when the key is
pressed, since it changes only when a card does; a read every pass would hold
off the other readers (`fabric.md` §4).

- **It must be armed before the call.** Latches cannot be read back; the SEEN
  lamp, cleared by the key, says whether the display was caught or is left over.
- **A port clears its own latch and tells nobody**, so **STALE** = the shadow is
  not idle and the live `BUSY` is clear: the display is history. One gate, and
  the difference between a call trace and a lie.
- **Across a trunk it names the trunk port and nothing beyond**: the flood
  carries no calling number and the claim no address. The trunk's word adds its
  direction: the trace ends "in from the west". It also catches the unit's
  holds, claims and drops of that port, and at a hub every tie-through and
  resolver write.

**The word tells an empty slot from an idle line**, which the panel cannot:
none, a plain line, a class, or a nail (`card-word.md` §2).

---

## 7. The last-word display

| | parts |
|---|---|
| the word | 2 × 74HC164 |
| the display | 2 × 74HC574, 16 LEDs: `G` and the spare, `DST` and `SRC` as octal groups, `BSY`, `CLM` |
| the trigger | 1 × 74HC688 with three-way jumpers — ground, Vcc or `P`ᵢ — over any eight of the sixteen bits (`proposed/counters.md` §2) |
| armed / frozen | ½ 74HC74, one lamp, one key, a gate into the '574 clocks |
| | **≈ 5½ packages**; 5 beside a watch that already has the '164 pair |

Clocked by `WR`, it catches **every word**, by either master, event words
included: every word ends in `WR`, and the rule that keeps `WR` clear of every
`SCLK` edge keeps the word stable through the pulse. Free-running it holds the
last word, which on a quiet exchange is the last thing that happened; armed, it
holds the **first** word matching the jumpers and lights FROZEN — a one-shot
logic analyser. **The match on a pin** triggers a scope on "the word that wrote
port 37" or "the next claim".

It cannot catch a release (not a word), an answer (`E` rising inside a port),
or tell an outbound completion from an inbound one: they are the same sixteen
bits (`proposed/counters.md` §3).

---

## 8. What each kind of port looks like

A lamp field shows behaviour; a class is identity, and the watch reads it. Each
class's **signature** on the panel:

| port | hook / busy |
|---|---|
| line | both together in a call; the hook flickers while it dials |
| the operator at 04 | a line, usually the busiest pair on the panel |
| outside line | hook lit by the CO's ringing before anything is written; busy once the walk takes it |
| trunk | busy alone through a flood, then hook if it claimed; inbound, hook first and flickering |
| source | **both dark always**: never written, `M` never up. A pulled source looks the same |
| announcement | busy when called, hook 300 ms later, both dark at the end |
| conference leg | busy while connected; its hook is its caller's (`A_TX` = `A_RX`) |
| data line, off hook | hook alone, for ever: the class marker never takes it |
| a tied nail | busy always; hook with its phone |
| unequipped, empty | both dark |

---

## 9. Open

- **No bench.** The one to write is small: the clock card, the bus
  (`newimpl/rtl/mainboard.v`) with a few ports pulling, eight '259 behind one
  '138, every lamp checked against the
  port that owns its bit-time, a slot jumper set wrong among them; then the
  panel inside a network bench, to see a flood.
- **The bus tap.** `J5` on `pcb/hookbusy/` is still a 2×8 placeholder carrying
  the eleven nets on pins 1–11; it becomes a tap on the bus header (`bus.md` §2).
- **The panel's physical parts**: routing and fab (DRC's remaining complaints
  are unrouted nets and silkscreen); the KiCad sheets, stubs until they catch up
  with the board nets; a stacking part whose engagement covers 10.16 mm ± the
  stack-up; the bezel, a diffuser with the grid and port map silkscreened,
  referenced off the panel; whether 2 mA 5 mm lamps read at arm's length, and
  green from orange, under the room's light.
- **`/HA` and `/HB` with the panel's one load on each**: the 4.7 kΩ pull-ups
  are unanalysed (`bus.md` §7).
- **The port watch and the last-word display**: not drawn.
