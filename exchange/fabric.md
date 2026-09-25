# The exchange — the switching fabric, as built

The fabric is **8 × 8** — eight 512 kbps highways (space) by eight slots (time)
— and the 64 squares of that grid are the exchange's 64 ports. The crosspoints
are one-way and belong to the listener, so every port can listen to any square
and any number of ports can listen to the same one.

> **Status: proposed.** The logic is `exch.py fabric` (measured: every source to
> every listener, bit-exact, one frame). The timing is `exch.py timing`: a
> worst-case analysis — every delay of every part drawn on its own between a
> third of typical and the data-sheet maximum for 74HC at 4.5 V, 400 000 trials,
> the worst reported — **not a simulation of the gates, and not a bench**. No
> schematic has been drawn. Package counts here are a parts list by function and
> **replace the rounder estimate of `protocol.md` §3**, which left out most of
> the supervision.

---

## 1. Why this way

| a port that can hear any of 64 could be | a port costs | verdict |
|---|---|---|
| a 64-input selector a port, in gates | nine '151 for `C` and nine for `A` | no |
| **analog crosspoint arrays with their own control memory** — MT8816, 8 × 16: 32 for a plane, 64 for `C` and `A` | no latch, no selects, no clocks at all: the streams simply pass, and an idle column is pulled to `FILL` by a resistor. About 270 small packages and 64 forty-pin ones | the serious alternative. Set aside because the array's memory is write-only: **a port cannot drop its own crosspoint**, so every release goes back to the marker as a 64-write clear of a column, and "nobody is in charge of a call" is lost; and it is an LSI holding the exchange's state, which the rules here exclude |
| **highways: space × time**, the crosspoint a latch at the listener | ≈ 5 packages, all of them parts the trunk card already uses | **chosen.** One low rate, one driver a wire, and a port that releases itself by clearing its own latch |

### 1.1 How a highway carries eight ports, and how one bit is picked off it

A highway is one wire where eight ports take turns.  It is eight bit
positions to a 64 kHz frame, 512 kbps — every position a port, no line
code, and the clock on a wire of its own.  An MF8 trunk group's *line*
still has that eight-bit shape with F and S at bits 0 and 4 (`mf8-spec.md`
§2); the fabric highway of that block is ordinary `HC[h]` from the eight
`C_TX` on the **block header** — seats 0 and 4 unequipped, the unit
inserting F and S on the way to the pair (`mf8-unit.md` §1).

Every card puts out one bit a frame on its `C_TX` pin and holds it for the whole
frame (it changes at the frame edge, as on the MF8 backplane). The block's
**commutator** is a 74HC151 — an eight-input multiplexer — with the eight ports'
`C_TX` on its eight data inputs and the cell counter `SLOT[2:0]` on its three
select inputs. The counter steps 0 to 7 once a frame, so the output is port 0's
bit for the first 1.95 µs, port 1's for the next, and so on: a rotary switch
turning at 64 kHz. Buffered, that output is the block's highway `HC[h]`. A second
'151 on the same count does the same for the eight `A_TX`, giving `HA[h]`.

One counter, on the clock card, serves every block, so cell *k* is the same
instant everywhere. Eight blocks make eight wires, and across one frame those
eight wires carry all 64 ports, each exactly once — **the port's address is where
it appears: which wire, and when.**

```
            cell 0   cell 1   cell 2   cell 3   cell 4   cell 5   cell 6   cell 7      one frame, 15.6 µs →
  HC[0]      00       01       02       03       04       05       06       07
  HC[1]      10       11       12       13       14       15       16       17
  HC[2]      20       21       22       23       24      [25]      26       27
   ...
  HC[7]      70       71       72       73       74       75       76       77
```

**A listener picks one square of that grid: a wire, and a moment.** Port 47
listening to port 25 holds `[ highway 2 | slot 5 ]` in its latch:

- **the wire** — a second 74HC151 with the eight highways on its data inputs and
  the latch's highway bits on its select inputs. Its output follows `HC[2]`
  continuously: all eight of block 2's ports, one after another.
- **the moment** — a third 74HC151 with the block's eight strobe lines on its data
  inputs and the latch's slot bits on its select inputs. Line 5 pulses in the
  middle of cell 5, when the wire is carrying port 25's bit; the '151 passes that
  pulse, and it clocks a flip-flop whose D input is the wire.

The flip-flop now holds port 25's bit and keeps it until cell 5 of the next
frame: it has rebuilt port 25's 64 kbps stream from the one cell in eight that
belongs to it. That output is port 47's `C_RX`. A fourth '151 and the other half
of the '74 do the same on `HA` for `A_RX`.

```
  frame f                                                                          frame f+1
  cell      |  0   |  1   |  2   |  3   |  4   |  5   |  6   |  7   |  0   |
  HC[2]     |  20  |  21  |  22  |  23  |  24  |  25  |  26  |  27  |  20' |
  strobe 5  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾    low for the second half of cell 5
  47's flip-flop ..........................................↑ takes 25's bit for frame f     (10.8 µs into the frame)
  47's card .....................................................................↑ samples C_RX at the frame edge
```

Port 25 meanwhile holds `[ 4 | 7 ]` and takes port 47's bit off `HC[4]` in cell 7.
The two directions are two separate squares and know nothing of each other.
**The whole fabric is one part number used three ways — to put bits on a wire in
turn, to choose a wire, and to choose a moment — with a latch to say which and a
flip-flop to keep the answer.**

What follows from the shape:

- **No central switch.** The sixteen wires *are* the switch; a connection exists
  only as six bits in the listener's latch.
- **Any number of ports can take the same square.** A tone is a port that fifty
  others happen to be sampling.
- **The delay is the same for every pair.** The source's bit for frame *f* is on
  the wire during frame *f*; the listener's card samples at the edge that begins
  *f* + 1 (§3.4). Slot numbers do not enter into it, so octets stay aligned.
- **An empty slot is `FILL`**: its commutator input is pulled to the `FILL` line
  through a resistor, exactly as an empty MF8 slot is, so whoever listens there
  hears CVSD silence.
- **The marker reads ports the same way.** `BUSY` and each card's word are commutated
  by two more '151s onto `PB[1:0]`, and its probe is a
  listener's two selects and a flip-flop, **addressed by `SCAN[2:0]` — the
  scanner's own low three bits, on the cable (`mainboard.md` §2.3.3) — not by
  `SLOT`**. So for a whole visit
  `PB` holds that card's pin steady, and a **16-bit** word at 128 kHz fits one
  octet (`extensions.md` §2.2). Highway commutators stay on `SLOT`. The probe
  select is three conductors driven straight from the scanner while the marker
  owns the bus, so a visit does not need a fresh serial word a port — which it
  could not have, since a word is 125 µs and so is a visit; `/BLK` still comes
  from the once-a-block steer. A console `PROBE` uses the serial word's
  `DST[2:0]` instead (`block.v`:108). **`PB` is therefore readable by any card
  on the ribbon, not only the marker** — `inprogress.md` is the first.
- **An MF8 trunk group uses six of eight seats**: the **block adapter** drives
  appearances 1–3 and 5–7; 0 and 4 are unequipped on the fabric (`protocol.md`
  §5). F and S exist on the line. The unit's line mux may still address payload
  with `SLOT` (`mf8-unit.md` §1, `mf8_trunk_card.v`). The commutator remains only
  a commutator — likeness to the old frame mux, not identity with the pair.

**Why eight by eight.** Sixty-four is the product; the split decides the parts.
More slots on a wire means a faster wire (16 slots is 1.024 Mbps); more wires
means a wider select at every port (16 wires is two '151s and a gate). Eight and
eight puts a single '151 on each axis and runs the wires at MF8's own line rate
(512 kbps).

---

## 2. The bus

One clock domain. Everything below is on the mainboard or a ribbon between
blocks; all 74HC at 5 V. **`mainboard.md` is this table in full** — the
forty-three signals, the two cables that carry them, the pinouts, and what the
cable costs §4's margins (18 ns of 743). **The latch write is serial**
(`mainboard.md` §2.3): one sixteen-bit word on one wire, broadcast, in place
of the twenty conductors this table used to list.

| signal | from | what |
|---|---|---|
| `HCLK` | clock card | 512 kHz, high for the first half of a cell. A cell is 1 953 ns |
| `SLOT[2:0]` | clock card, a 74HC163 | the cell number; changes at the start of the cell. Addresses every commutator |
| `SLOTQ[2:0]` | clock card, a 74HC175 on the 1.024 MHz tap | **the same count a quarter of a cell late.** Addresses every strobe decoder, and nothing else (§3.2) |
| `TX_CLK`, `TX_OCT`, `RX_OCT` | clock card | 64 kHz frame, 8 kHz octet, as `mf8-backplane.md` §3. **A card's `RX_CLK` pin is `TX_CLK`, and its `RX_OCT` is `TX_OCT` one frame late** (§3.4), from one flip-flop here |
| `LINE_HB` | clock card | 1.024 MHz, the half-bit clock of `mf8-spec.md` §9.1. Only a trunk card wants it, and it is the fastest thing on the bus: **4.096 MHz never leaves the clock card** (`mainboard.md` §8) |
| `FILL`, `/RING_CAD`, `TICK` | clock card | 32 kHz idle pattern; 2 s / 4 s, low true; 1 kHz |
| `RBT` | **the ringback tone card**, through a buffer on the card | the ringback bit stream. One of the fabric-wide references and carried with them, but an analog tone oscillator through a CVSD encoder does not belong on the clock card, so this one conductor is driven from a tone card's rear connector and **pulled to `FILL` at the clock card when none is fitted** (`mainboard.md` §2.1, `tone-card.md` §5) |
| `HC[0..7]`, `HA[0..7]` | block *h* drives wire *h* | the highways. **One driver a wire**; every block listens to all sixteen through its own receivers. `HA` is also the marker's M highway |
| `PB[1:0]` | the block the marker's probe has selected, tri-state | `BUSY`, and the card's word: its class and options, or a dest form (`extensions.md` §2.2), **sixteen bits at 128 kHz** over the visit. Commutated by `SCAN[2:0]`; eight blocks share two wires |
| `SCAN[2:0]` | marker | **the port `PB` is showing**, stepping at 8 kHz — one port a visit. On cable B (`mainboard.md` §2.3.3), so a listener can tell whose `BUSY` and whose word it has. Under `/CON` the probe follows the word's `DST[2:0]` instead |
| `ADVANCE`, `START` | marker | **the scanner stepped**, and **a pass begins**. No block reads them; they are on the cable so a listener can de-duplicate a repeated visit without a comparison and find the pass boundary without counting wraps — and so the three can be held against each other to catch a failed conductor (`mainboard.md` §2.3.4) |
| `SDATA`, `SCLK` | marker, or the console | the latch write as one sixteen-bit word — `DST[5:0]`, `SRC[5:0]`, `BSY`, `CLM`, a guard bit — shifted to every block at once. Two '164 take it in and a '138 turns `DST[5:3]` into the eight lines the shunt picks `/BLK` off, so a block still needs no address and no comparator: "layout, not logic" (`mainboard.md` §2.3) |
| `WR`, `/RESET` | the same | the write, gated with `/BLK` and the guard bit; and the clear. **`/RESET` is the signal on the bus a glitch can hurt most**, and is filtered at every block; `SCLK` is the one it can hurt next, and costs one call (`mainboard.md` §7) |
| `/CON` | console | the console has the bus: marker goes high-Z |

---

## 3. The circuit

### 3.1 A block: what eight ports share

| function | part | notes |
|---|---|---|
| Commutators: `C`, `A` | 2 × 74HC151 | addressed by `SLOT`; input *k* is port *k*. Same job as an MF8 shelf's frame mux (`mf8-spec.md` §10), without F and S — likeness, not a tap of the pair |
| Commutators: `BUSY`, the word | 2 × 74HC151 | addressed by **`SCAN[2:0]`** off cable B (live from the marker's scanner while it owns the bus; from the serial word's `DST[2:0]` on a console `PROBE`). Steady on `PB` for the visit |
| Ringback substitution ahead of the `C` commutator | 2 × 74HC157 | port *k* sends `RBT` instead of its card's `C_TX` while it is being rung (§3.5) |
| Strobe decoder | 74HC138 | addressed by `SLOTQ`; `HCLK` on an active-low enable, so line *k* is low for **the second half of cell *k*** and its falling edge is the middle of the cell |
| Write decoder | 74HC138 | `/BLK`·`WR`·`G` enables; `DST[2:0]` picks the latch to clock |
| The control word | 2 × 74HC164 | sixteen bits, shifted by `SCLK`. No output latch: nothing reads them until `WR`. Bits 7–0 are the port's own '273, verbatim |
| Block select | 74HC138 | `DST[5:3]` into eight lines, out to the shunt field and back as `/BLK` |
| The guard bit | ¼ package | `G`·`WR`: a word that does not carry bit 15 cannot write |
| Backward A on a claimed trunk: `A` out = E + `CLAIM` | 2 × 74HC32 | used on trunk blocks; harmless elsewhere, where `CLAIM` is never written |
| Receivers: clocks, counts, the serial pair; the sixteen highways | 4 × 74HC244 | a highway drives eight receivers, not sixty-four selects. The serial bus gave nine of these back: fourteen control inputs became five |
| Drivers: `HC[h]`, `HA[h]`, and `PB` when selected | 74HC244 | |
| | **≈ 15¼** | ≈ 2¼ more than the parallel control bus: three packages added, about one '244 freed |

### 3.2 A port: the crosspoint

| function | part | notes |
|---|---|---|
| Listen latch: slot, highway, `BUSY`, `CLAIM` | 74HC273 | clocked by the write decoder; **cleared by the port's own release** |
| Highway select, `C` | 74HC151 | the eight `HC` |
| Highway select, `A` | 74HC151 | the eight `HA` |
| Slot select | 74HC151 | the eight strobe lines. **Its inverted output W is the capture clock**: low-going line, rising W, in the middle of the chosen cell |
| Capture, `C` and `A` | 74HC74 | both halves clocked by W. Their outputs are the card's `C_RX` and, through §3.5's gate, its `A_RX` |
| | **5** | |

**The one hazard, and why `SLOTQ` exists.** Decode the strobes from `SLOT` itself
and, at the turn of a cell, the new address races the disable: if the address
wins, the *next* port's line pulses low at the very start of its cell, with
nothing on the highway settled — and for slot 0 that is the frame edge, where
every card is sampling. Typical parts lose that race by 18 ns and show nothing;
across the data-sheet spread it happens in **9.6 % of draws, up to 45 ns wide**
(`exch.py timing` 3). A hazard that only appears across the spread is the kind
not to build on. With the address a quarter of a cell late it only ever moves
while the decoder is disabled, 415 ns after the disable and 368 ns before the
next enable. One 74HC175 on the clock card, for the whole exchange.

### 3.3 A cleared latch listens to 00

A port that releases clears its '273 to zeros: highway 0, slot 0.  For this reason
port 00 is never fitted. It reads `FILL` and A = 0. 

If the operator were at 00, a port listening to the operator would ring
whenever the operator lifted, and an off-hook phone waiting for a register would
hear the operator's calls. That is why the operator is at 04
(`protocol.md` §5). The slot select is wired in order and the marker sends
port numbers as they are. No parts, and nothing for a latch written by hand to
get wrong.

### 3.4 No re-timing flip-flop

`protocol.md` §3 had a second flip-flop to move every `C_RX` change to the
frame edge. It is not needed. **Every capture is in the middle of some cell, so
nothing a card is given changes within half a cell of the frame edge — and the
frame edge is where every card samples**, once `RX_CLK` is `TX_CLK`: the line
card's synchroniser, the FXS card's decoder and the data card's flip-flop all
take `C_RX` there (`channel-cards.md`). A bit sent in frame *f* is captured during *f*
and sampled at the edge that begins *f* + 1, whatever the two slots: the one
frame `exch.py fabric` measured, whose model already takes the card's sample at
that edge. `RX_OCT` is `TX_OCT` a frame late, from one flip-flop on the clock
card.

### 3.5 A port: supervision

`marker.md` §5, in gates. M is the card's `A_TX`; E is the captured A.

```
 fM, fE    M and E, each through a diode-and-two-resistor RC into a 74HC14: up in 16 ms, down in 256
 release   the fall of fM, or of fE, differentiated and squared up  →  the '273's clear
 ON      = RINGS · /M · /fM        an on-hook port that rings — and not one that hung up a moment ago.  RINGS is
                                   the card's /ANS pin left open (extensions.md §2.3)
 RB      = ON · E                  being rung: send RBT instead of C_TX              (the '157 of §3.1)
 A_RX    = E · /( ON · /RING_CAD ) ring in cadence while ON; otherwise E as it stands, which is what a
                                   trunk, an outside line and a data card want
 BUSY out= BUSY + fE + fM·/M       busy while either detector is still timing out     (marker.md §5.2)
```

| function | part |
|---|---|
| Two detectors: filter, its inverse, the edge | 74HC14, two RC, two CR, two diodes |
| Pull-ups for the card's `/ANS` and word pins (`extensions.md` §2.1): **~680 Ω** each | two resistors |
| `ON`, `RB`, `A_RX`, the in-flight term, `BUSY` out, the clear | ½ 74HC02, ¾ 74HC08, ¼ 74HC00, ⅓ 74HC4075, ⅓ 74HC4073 |
| | **≈ 3¼** |

**Whether a port rings is one bit, and it comes from the card: `/ANS`.** `ON` is
true of a phone's port. It must be false of a trunk (or a caller hears ringback
the instant they seize one, and forward A is chopped by the ring cadence), of an
outside line, of a conference bridge leg (which would wait up to 4 s for the
cadence before it could answer, `conference.md` §6), and of any card that
answers at once. Each such card ties the pin low, and a phone's card leaves it
open (`extensions.md` §2.3). The class does not enter into it: the port's
gates never see the class at all.

**The class is in the card's word** (`extensions.md` §2.2), which only the
marker reads:

The three bits are a **family** of two and a **member** of one, so that the first
four bit-times of the word name the family and nothing else need be read
(`extensions.md` §2.2):

| family | member 0 | member 1 |
|---|---|---|
| `00` — **none** | 000 unequipped: an empty slot, or a card held off | 100 **reserved**: the spare code, and any word carrying it is out of service |
| `10` — **attached** | 001 source: a radio, a clock, a test tone (`features.md` §6). Dial tone at 01, busy at 02 and cannot-complete at 03 are sources too, and need no word, since the marker reaches them by address | 101 outside line |
| `01` — **trunk** | 010 tie trunk. Its direction, N, S, E or W, and its glare bit **are the word's option bits** — frame 5 glare, frames 6–7 direction. The no-forward jumper is one plug a direction on the network unit, not in the word (`network.md` §3.3) | 110 tone trunk: a trunk that offers dial tone on seize instead of taking a flood (`leaf-uplink.md` §3). It faces no direction and carries no glare |
| `11` — **subscriber** | 011 line; options `P b D`, where `D` is a data line (`extensions.md` §2.4) | 111 **restricted**: a lobby or public phone; options `z b 0`. Warm is a call nail to 04. Conference leg as a class is retired: a bridge leg is an ordinary line |

Class *operator* is retired with the adjacent `o` run: an operator's position is a
line that answers to 04 (`groups.md` §2), and its code is the spare above.

**All ones is not class 111.** It is a separate constant: a plain line card ties
its word pin to ground and reads sixteen ones, which means *line, no options*,
with no part (`extensions.md` §2.2, `common-cards.md` §2). Class 011 is the
same class when a card shifts an explicit word because it has options to say.
The constant falls inside the subscriber family, so a reader of the first four
bit-times gets the right answer for it without a carve-out; what keeps a *legal*
class word off the constant is restricted's must-be-zero frame 7.
An empty slot sends no word and reads 000. An earlier form carried the class on
three pins and took "rings" from one of its bits, which tied the codes to the
ringing. With the class in the word and `/ANS` on a pin, the codes are free, and
a plain line card says both with no part: its word pin tied to ground, its `/ANS`
pin open.

This renumbers `marker.md` §1's classes, adds *source*, *tone trunk* and
*restricted*, retires *operator* and *data line* as classes, and has the marker
reach the two tones by address rather than by hunt. It is in the RTL
(`make word`); the `calls` model keeps the older numbers by its own note.

---

## 4. Timing

`exch.py timing`; nanoseconds from the start of a cell; worst of 400 000 draws.

| | |
|---|---|
| A highway bit valid at a listener's flip-flop — card or `RBT` mux, commutator, driver, mainboard, receiver, select | by **252** (typical 165) |
| Strobe address settled before the enable / moves after the disable | 368 / 415 |
| Capture clock rises | 994 – 1 099 |
| **Set-up / hold at the capture flip-flop** | **752 / 927** |
| A source in slot 7: `C_RX` settled before the card samples | 820 |
| A source in slot 0: `C_RX` moves after the card samples | 979 |

Nothing in the fabric has less than three quarters of a microsecond in hand.

---

## 5. How much, and on what

| | packages |
|---|---|
| a port: crosspoint 5, supervision 3¼ | ≈ 8¼ |
| a block, fully fitted: eight ports and §3.1 | **≈ 82** |
| an exchange: eight blocks | ≈ 655 |
| clock card: crystal, '4040, '163, '175, `FILL`, `RING_CAD`, the 1 kHz tick, drivers | ≈ 10 |

### 5.1 Physical form of a block

Fabric cable A and the mainboard **block shunt** are `mainboard.md`. What hangs
off one tap is this:

```
  fabric cable A ──▶ mainboard (block shunt: HC / HA / `/BLK`) ──▶ block shared board (§3.1)
                                                          │
                                                          └─ **block header**  (§5.2)
                                                               │
                                                    **block ribbon** (breakout)
                                                               │
                                                    slot 0 … slot 7  ← channel sockets
                                                               │
                                                    card + port circuit (§3.2, §3.5)
                                                    only when that slot is fitted
```

**The shared board is always there for a fitted block** — commutators, strobe and
write decoders, highway drivers and receivers, the serial word path: ≈ 15¼
packages of §3.1. It drives `HC[h]` / `HA[h]`, listens to every highway, and
answers `/BLK`. It does not hold eight idle port circuits.

**The card side is a star.** Electrically it is still §2 / `baseband.md` §2.1:
six signals a slot point to point, clocks and rails common, no slot-ID, nothing
contending. The **block header** is that star collected on the shared board.
The usual stuffing **breaks it out**: a **block ribbon** in the same connector
family as the channel socket (`common-cards.md` §1) ends at the header; the
**slots** along the ribbon *are* the channel sockets. Commons run the length;
per-slot lines peel to one slot. It is a loom that preserves the star, not a
multi-drop bus for `C_TX`.

**A port circuit is populated only with its card.** The ≈ 8¼ packages of §3.2 and
§3.5 — latch, selects, capture, supervision — sit with the card at that slot, not
as empty seats on the shared board. An unfitted slot leaves the commutator input
pulled to `FILL`, A and `BUSY` at 0, and no word: unequipped (`mvp.md` §2). The
MVP fits two port circuits on one block and leaves the other six out; that is the
normal growth rule, not a special case.

**What a line-card installation is.** Card + its port circuit on one ribbon
slot. Shared logic and the highway stay on the shared board behind the block
header. Two blocks of eight fitted ports fill an 84 HP subrack beside their
cards; in SO-16 the shared board alone is a single Eurocard. Forty-eight lines
are then about 500 packages of line cards, 640 of fabric and a hundred of
common control.

### 5.2 The block header — and the block adapter

A second stuffing of the same star: one board mates the **block header**
directly — eight ordinary slot appearances electrically — and the block ribbon
is not populated. That board is a **block adapter**. The header is the fabric
contract; the adapter is any non-breakout mate of it.
**Live six-channel MF8** is a block adapter on this header (`mf8-unit.md` §1):
appearances 1–3 and 5–7 live, 0 and 4 unequipped, rear the MF8 pair. The
eight-channel payload split measured in that file is **not taken**.

**Principle.** Each appearance is the same six per-slot signals a channel card
uses on a ribbon slot (`common-cards.md` §1), same four pins a card may drive,
same word and `/ANS`. The block's commutator, latches, captures and supervision
are unchanged: they sit behind the header as they sit behind a slot. The adapter
does not tap `HC`/`HA`. What is block-scoped — one force that busies all eight
ports together — is not smuggled onto a slot pin; it is a pin of its own on the
header commons.

```
  fabric cable A ──▶ mainboard ──▶ block shared board (§3.1)
                               │
                               └─ **block header**
                                    ├─ breakout: **block ribbon** → slots = channel sockets
                                    └─ non-breakout: **block adapter**
                                         eight port circuits still behind the header
```

**Dual footprint, one stuffing.** A block kept as lines populates the ribbon
slots off the header. A block kept as an adapter group mates a **block adapter**
to the header and does not populate those slots. Mixing a line card with an
adapter on the same block is not a configuration: there is nowhere to plug the
card, and the group's busy-out is block-wide. Eight ribbon plugs on one board
are refused — the slots are spaced for separate cards, and a11 still would not
carry a busy force.

| | shell | what |
|---|---|---|
| **appearances** | DIN 41612 type B, 64-way | eight slots of `C_TX`, `A_TX`, `C_RX`, `A_RX`, word, `/ANS`, plus `+5 V` and `GND`. Column *s* in each group of eight is slot *s*. Direction is the *card's* view: `out` is the adapter driving the block. Column assignment is this contract's; the measured-and-not-taken adapter's per-pin behaviour is `mf8-unit.md` §5.3 |
| **commons** | 2 × 5, odd signal even ground, keyed | `TX_CLK`, `TX_OCT`, `FILL` in; **`MUTE_BLK` out**; `HCLK` in on the spare, for an adapter that muxes at the cell rate (`local-trunk.md` §3). Commons the appearances shell does not carry |

**`MUTE_BLK`.** Asserted by the adapter when the group must not be hunted —
link down, unlocked, no carrier, or whatever failure domain that adapter owns.
The block ORs it into its `BUSY` commutator (all eight inputs, or the `'151`'s
output — one gate), jumpered in when the header is stuffed for an adapter.
Pulled so an unfitted commons shell does not busy a ribbon stuffing. It is not
a11 (common listen-only, tied locked in an exchange) and not a14 on slot 0
(per-slot spare that still wants eight ribbon seats). One dedicated pin is the
path `network.md` §1 named.

**What a block adapter owes the block.** Drive the four card-side pins a slot
(`C_TX`, `A_TX`, word, `/ANS`) within `common-cards.md` §1.2. On group failure:
hold `A_TX` at 0, present `FILL` on `C_TX` or float the words as unequipped, and
assert `MUTE_BLK`. Take `TX_CLK` / `TX_OCT` / `FILL` from the header commons.
Own whatever line or plant sits on its rear; the fabric never sees that rear.

**What the block still has.** Eight port circuits behind the header, the
commutators including word and `BUSY`, a monitor pool that reads this block's M,
the `MUTE_BLK` OR when jumpered. Nothing on H for the adapter. A ribbon
stuffing leaves the OR off.

**Who uses it.** **Live MF8** (`mf8-unit.md` §1) and the **local eight-channel
highway trunk** (`local-trunk.md`) are the two block adapters: same header,
different rear (MF8 pair vs highway-shaped copper). A conference block that
wants the same header would mate with a different rear. Single-channel trunks
sit on a ribbon slot (`network.md` §1.1). Scatter across arbitrary ports is out
of scope for this header: one failure domain, one monitor, one `MUTE_BLK`.

---

## 6. The economy form: `A` in the second half of the cell

Put `C` on the highway for the first half of a cell and `A` for the second, make
the strobe high for the **middle** half, and capture `C` on its rising edge and
`A` on its falling edge — the '151 gives both senses, one to each half of the
'74. That drops the `A` highway select from every port and the `A` commutator
from every block and adds two '157 a block: **seven packages a block and eight
wires less.** Worst-case margins are 256 to 423 ns where §4 has 750 and more
(`exch.py timing` 5). It wants a glitch-free "middle half" from a Johnson counter
on the clock card. Not the baseline: the saving is 9 %, and it spends the
fabric's best property, which is that nothing in it is near a limit.

**And it deletes `SLOTQ`.** The strobe window is the middle half of the cell, not
the second half, so the address may move in the quarter either side of the cell
edge — which is where the undelayed count moves and where §3.2's delayed one does
not. Addressed by `SLOTQ` the decoder is *worse* than useless here: the address
settles **121 ns after its own enable**, which is §3.2's hazard walked straight
back in. Addressed by plain `SLOT` it settles 367 ns before the enable and moves
431 ns after the disable — §4's margin, kept, for nothing. So the economy form
takes the '175 off the clock card and three more conductors off the cable, and
the count is **eleven wires, not eight**. `mainboard.md` §9 says why that
number matters more than the packages: at eight highways and no `SLOTQ` the
fabric cable is twenty conductors, which is 1-in-1 grounding in the same 64-way,
which is that section's own named cure for the one estimate in this design that
could still be wrong.

---

## 7. Bringing it up

1. **Clock card alone**: `HCLK`, `SLOT`, `SLOTQ` a quarter cell behind it, `TX_CLK`,
   `FILL`. Scope `SLOTQ` against `HCLK`.
2. **One block, shared board only, no ribbon slots fitted.** Every `C_TX` pulled to
   `FILL`: `HC[h]` is `1010`. Strobe line *k* low for the second half of cell *k*
   and at no other time — trigger on any edge outside it, with the block warm and
   cold (§5.1).
3. **The console** (`features.md` §4): write a latch by hand, read `BUSY` back on
   the probe bus. Point port 3 at port 5; a data card's pattern in slot 5 comes
   out of slot 3 one frame late.
4. **A cleared latch**: hold `/RESET`, and every `C_RX` is `FILL` with every `A_RX`
   low — port 00.
5. **Supervision on one port**: two phones and the console are a working manual
   board. Ring, ringback, answer, both release orders; time the release and the
   busy-after-release on the probe bus.
6. **A second block**, then the marker.

---

## 8. Not measured

- **The circuit.** A parts list by function and a timing analysis; nothing drawn,
  nothing built. The supervision's gate count in particular is a sketch.
- **The detectors as RCs**: threshold spread of the '14 on top of the RC's, and
  the differentiator's pulse against the '273's minimum clear width.
- **A glitch on the slot select when its latch is written.** The marker writes at
  any instant; the select's output may pulse and capture one wrong bit, which is
  the single bit `exch.py fabric` 6 allows for a re-point. Not analysed further.
- **Sixteen highways across eight blocks on a ribbon or a mainboard**: worked
  through in `mainboard.md`. Loading and the series resistors are settled
  there — 193 pF and 100 Ω, which buys an edge three times the cable's round
  trip. **Crosstalk is still an estimate**, and is the one number there that
  would change the design if it were wrong.
- **The minimum delays.** Data sheets give typical and maximum; a third of typical
  is an assumption, and the hold figures rest on it.
