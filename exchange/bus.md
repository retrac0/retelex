# The exchange bus

One bus runs between the clock card, the eight blocks and the common-control
cards: 32 signals on one 2 × 25 header, the same at every position. This
document is its signals, pinout, pulls, control word and masters, and what an
absent part or a glitch on it costs. What the signals do is `fabric.md`; the
block's side of the header is `block-stack.md` §6.

> **Built:** `newimpl/rtl/mainboard.v`, `ctl_write.v`, `ctl_queue.v`,
> `clock_card.v`; `tb_ctl`, `tb_debug`, `tb_fabric`, the network benches.
> **Proposed:** the header's fills; only the block's two 2 × 25s are drawn.
> **Measured in:** `exch.py mainboard` (§2.4), for a 64-way totem-pole ribbon.

---

## 1. Signals by function

| group | signals | n | driven by | read by | undriven |
|---|---|---|---|---|---|
| cell timing | `HCLK`, `SLOT[2:0]`, `SLOTQ[2:0]` | 7 | the clock card | every block; `HCLK`, `SLOTQ` every probe | 100 k down at each block |
| scan | `SCAN[5:0]` | 6 | the clock card | every block and probe | — |
| speech highways | `HC[7:0]` | 8 | block *h* drives `HC[h]`, through its HC ROUTE jumper | every block | 4.7 k to `FILL` at the clock card |
| references | `RBT`, `/RING_CAD` | 2 | a ringback card (§7); the clock card | every block, through the header's '244 | `RBT`: 4.7 k to `FILL` at the clock card |
| supervision planes | `/HA` (M), `/HB` (`BUSY`), `/HW` (card word) | 3 | open drain, one a block; `/HW` the selected block only | ports (`/HA`, for E), markers, registers, the unit, the debugger | 4.7 k up at the clock card |
| the word select | `/WS` | 1 | open drain, any reader, in the bit-time of the port it names | every block and reader | 4.7 k up at the clock card |
| control | `SDATA`, `SCLK`, `WR`, `/RESET`, `/UREQ` | 5 | the master holding the bus; `/RESET` power-on and a button, its driver unplaced (§7); `/UREQ` the network unit | every block; `/UREQ` the marker | 100 k down at each block; `/UREQ` pulled up |

Cell timing, `SCLK` and `WR` are the lines whose edges matter: each block's
strobe '138 turns cell timing into every capture clock (`fabric.md` §2.2),
and a block shifts on `SCLK` and writes on `WR`. Nothing on the bus is faster
than 512 kHz. `SCAN` names the port whose turn it is (`SCAN0` is `FILL`,
`SCAN5` is `TICK`). `RBT` is the ringback tone as a 64 kbps stream,
entering each block only through the header's '244; `/RING_CAD` is low
2.048 s, high 4.096 s. The four open drains are sampled at one instant,
mid-cell 4 (`fabric.md` §3.2). Control carries writes only.

**Not on the bus:** −48 V, ringing and ±12 V (a harness, §2.3); the socket
clocks, made on each block (`common/clocks.md` §1); the strobe lines, `/WR`
lanes, `SRC`/`BSY`/`CLM`, *h* and `MUTE_BLK`, which stay in a block
(`block-stack.md` §3); and the marker ↔ unit ribbon with `/NET` on it
(`network.md` §3.6) and the register ribbon (`register.md` §3), short ribbons
across the common-control cards' top edges.

---

## 2. The 2 × 25 header

### 2.1 Pinout

2.54 mm, 2 × 25, at every card position: 32 signals, 1 spare, 13 ground and
4 × +5 V. Odd pins are row 1, and a ribbon's conductor *n* is pin *n*.

| pins | odd | even | | pins | odd | even |
|---|---|---|---|---|---|---|
| 1–2 | +5 V | +5 V | | 27–28 | `SCAN0` | `SCAN1` |
| 3–4 | **`HCLK`** | GND | | 29–30 | `SCAN2` | `SCAN3` |
| 5–6 | **`SLOT0`** | GND | | 31–32 | `SCAN4` | `SCAN5` |
| 7–8 | **`SLOT1`** | GND | | 33–34 | `HC0` | `HC1` |
| 9–10 | **`SLOT2`** | GND | | 35–36 | `HC2` | `HC3` |
| 11–12 | **`SLOTQ0`** | GND | | 37–38 | `HC4` | `HC5` |
| 13–14 | **`SLOTQ1`** | GND | | 39–40 | `HC6` | `HC7` |
| 15–16 | **`SLOTQ2`** | GND | | 41–42 | GND | `RBT` |
| 17–18 | **`SCLK`** | GND | | 43–44 | `/RING_CAD` | `/HA` |
| 19–20 | **`WR`** | GND | | 45–46 | `/HB` | `/HW` |
| 21–22 | `SDATA` | `/UREQ` | | 47–48 | `/WS` | spare |
| 23–24 | `/RESET` | GND | | 49–50 | +5 V | +5 V |
| 25–26 | GND | GND | | | | |

### 2.2 Why this order

Pins 1–24 are the fast half: each line in bold has a ground beside it and
across from it. Pins 27–50 are the slow half, fenced by the grounds at 25–26.
`/RESET` sits between a slow level and a ground; a ground, `RBT` and
`/RING_CAD` shield the planes from the highways. +5 V fills both end columns
and the centre column is ground, so a connector turned round (pin *p* to
51 − *p*) or with its rows swapped cannot short the supply. The bus fits a
2 × 24, but 50-way is the stock IDC size.

### 2.3 Fills, contacts and power

**One footprint, three fills**, chosen at build time on the same holes, if
**each position's two bus edges are mirror images**, row 1 outermost at both
(two right-angle connectors mating edge to edge meet outer row to outer row):

| fill | right edge | left edge | between |
|---|---|---|---|
| direct mating | right-angle male | right-angle female | nothing |
| bridge | vertical male | vertical male | a 2–3 cm board with two sockets, pin *n* to pin *n* |
| ribbon | vertical male or shrouded header | — | one daisy-chained 50-way ribbon |

A bridge needs no key; a position turned round does, so each header sits a
few millimetres off the centre of its edge.

**The block header takes the ribbon fill only** (Joel, 2026-09-26): one
shrouded, keyed right-angle IDC at its front edge, and no mirrored pair
(`block-stack.md` §6). Contacts are gold on both halves,
about 0.76 µm; positions joined by bridges or mating sit on one flat plate.

**Power.** +5 V and ground ride the bus, fed at both ends of the chain.
**Ringing, −48 V and ±12 V never do**: ringing, about 80 Vrms on −48 V
(`mf8/mf8-psu.md` §3.2), peaks near 161 V, beyond a 2.54 mm header's creepage. They run on a separate shrouded twisted-pair
harness, in a star from a fused distribution point, to the blocks with
analogue line cards only, and the ringing return rides its own pair.

### 2.4 Electrical

`exch.py mainboard`, for eight blocks on 2 m of 64-way ribbon, ground on every
other conductor. The conclusions carry; the numbers are not redone (§7).

- **The clock travels with the data**, so skew cancels whenever the driving
  block is nearer the clock card than the listener. Worst loss 17.9 ns with the
  clock card at one end, 8.9 ns mid-chain: **put the clock card in the
  middle**. Set-up falls to 725 ns (743 with no cable); hold never worsens.
- **`HCLK` and `SLOTQ` travel together**, so `fabric.md` §2.2's hazard is
  untouched.
- **Slow the edges**: 193 pF and a 20.4 ns round trip; 100 Ω at each
  clock-card output gives a 59 ns edge, three round trips, 3 % of a cell.

---

## 3. What left the bus

| signal | now |
|---|---|
| `TX_CLK` | `/SLOT2`, made on each block |
| `TX_OCT` (`CLK_8K`) | `SCAN[2:0]` = 7, decoded on each block; a ripple up-count cannot glitch it |
| `RX_OCT` | `TX_OCT` a frame late, two '74 halves on each block; **not** `SCAN[2:0]` = 0, which the '4040 passes through from 1 to 2 and from 3 to 4 |
| `FILL`, `TICK` | `SCAN0` and `SCAN5`; `SCAN5`'s fall is the pass boundary and the 1 ms time base |
| `LINE_HB` (1.024 MHz) | read by nothing on the bus; the tap stays in the clock card for the '175 that makes `SLOTQ` |
| `HA[0..7]`, `PB[1:0]`, `ADVANCE`, `START` | `/HA`, `/HB`, `/HW` and a free-running `SCAN` (`fabric.md` §3, §4) |
| the eight `/BLK` lines a block, the shunt field | each block makes `/BLK` from its own NUMBER jumper (`fabric.md` §6.1) |
| `/CON` | no console is built; the spare is kept for its request line (§5) |

A common-control card takes the 1 ms edge off `SCAN5` and the frame edge off
`SLOT2`'s fall.

---

## 4. The control word

A master's whole output is **one 16-bit word on `SDATA`, shifted by `SCLK`
and broadcast to every block**; the block whose number matches answers `WR`.

| bit | field | |
|---|---|---|
| 15 | `G` | guard, ANDed into `WR` at every block: a word without it cannot write |
| 14 | — | spare (§7) |
| 13–11 | `DST[5:3]` | the block |
| 10–8 | `DST[2:0]` | the port in it |
| 7–2 | `SRC[5:0]` | the port to listen to, as dialled |
| 1 | `BSY` | busy |
| 0 | `CLM` | a claimed trunk's backward A |

The word is `h s` twice and two flags, and **bits 7–0 are the port's '273
verbatim**. Sixteen is 2 × 6 + 4: the six-bit port and the 16-bit word are one
decision (`analysis/why-bits.md` §3).

**At the block** two '164 shift every word, with no output latch since nothing
reads them until `WR`; a '688 makes `/BLK` = FIT · (`DST[5:3]` = *h*) · `G`; a
'138 enabled by `/BLK` · `WR` picks one `/WRk` lane by `DST[2:0]`, and that
port's '273 takes bits 7–0 on its leading edge. **A shift register has content,
not phase**: whatever happened to the last word, the next realigns. A word with
`G` = 0, the **event word**, shifts and pulses `WR` but writes nothing: a mark
a listener can count (`debugger.md`, `proposed/counters.md`).

**Rate and the one rule.** `SCLK` is 128 kHz, high for the middle half of each
of its 7.8 µs periods. A written word is sixteen periods and a seventeenth for
`WR`, 133 µs, and **`WR` is pulsed mid-way through the seventeenth with `SCLK`
idle**, never near a shifting edge. `tb_ctl` measures every `SCLK` period at
32 master ticks and seventeen periods a word (`newimpl/rtl/ctl_write.v`).

---

## 5. Two masters

The marker and, where fitted, the network unit each drive `SDATA`, `SCLK` and
`WR` through a '244 of their own, enabled only while they hold the bus
(`newimpl/rtl/ctl_queue.v`). **There is no grant**, and a transaction is one
written word. `ctl_queue` is a model part: on a board a master's sequencer
holds until its word is away, and there is no queue.

- **The marker** starts a word only while `/UREQ` is high, and lets go between
  words.
- **The unit** pulls `/UREQ` low while it has words to write, and drives only
  after 640 master ticks, 156 µs: longer than the marker's longest transaction,
  545 ticks and two more to hand its '244 back. The unit ranks above the
  marker.
- **With neither enabled**, the blocks' pull-downs read `SDATA`, `SCLK` and
  `WR` low: zeros shift, `G` is 0, nothing is written.

Every network bench counts a clash (`b_clash`); none has lit. The spare, pin
48, is kept for a console's request line ranked above the unit
(`proposed/console.md`).

---

## 6. Absent parts and glitches

### 6.1 What an absent or wrong part reads as

**Absent reads idle because nothing pulls, not because something pulls low.**

| absent or wrong | on the bus | what the exchange does |
|---|---|---|
| a block position empty, or FIT out | its highway undriven, so `FILL`; no drain on any plane; no select answered | eight ports read M 0, `BUSY` 0, word *none*: unequipped, never written, silence to a listener. With FIT out the block still listens |
| HC ROUTE out | no driver on its highway | its ports are written and scanned normally and heard as `FILL`: the confusing one |
| HC ROUTE and NUMBER disagree | scanned and written as *h*, heard on another highway | callers to its ports hear another block. Nothing checks it |
| two blocks set alike | two '244s on one highway; both answer one `/BLK`; both drive the planes and `/HW` in the same turns | a broken `1010`, every write landing in both, ORed M, `BUSY` and words (`fabric.md` §6.3 step 2) |
| a seat with no port card | lane on `FILL`, no drain in its turn, word lane pulled up | unequipped |
| a subscriber card off its port card | `C_TX` to `FILL`, `A_TX` down, a12 and a13 up (`common/common-cards.md` §1.4) | on-hook, no word |
| a block header off the bus | 100 k pull-downs: `/RESET`, `SDATA`, `SCLK`, `WR`, `HCLK`, `SLOT` low | the block holds itself in reset, every latch at 00, no write, strobes frozen: the clean failure |
| no master driving | `SDATA`, `SCLK`, `WR` low | nothing written |
| no ringback card | `RBT` at `FILL` | silence while the far phone rings |
| no network unit | `/UREQ` at its pull-up | the marker never yields |
| the clock card pulled | no clocks, `SCAN` or pull-ups | the exchange stops; every latch holds until `/RESET` |

### 6.2 What one spurious edge costs

| signal | a spurious edge | costs |
|---|---|---|
| `HC` | nothing: sampled 750 ns after it changes | nothing |
| `/HA`, `/HB` | one port's M or `BUSY` wrong for one sample; detectors (16 ms) and a register's `HIT` (8 samples) ride through | nothing, bar §7 |
| `/WS`, `/HW` | a select nobody made, or one wrong bit: one word misread | at most one call |
| `SCAN` | a turn mislabelled if it falls at the frame edge; one wrong `FILL` or `TX_OCT` bit | one sample |
| `RBT`, `/RING_CAD` | a bit of tone, a millisecond of cadence | nothing audible |
| `SLOT`, `SLOTQ` | a mux or decoder misaddressed for 20 ns while the decoder is disabled | nothing |
| `SLOT2`, `HCLK` | a card samples twice; one extra strobe captures one wrong bit | one bit |
| `SDATA` | nothing: read only at `WR` | nothing |
| `WR` | between words, the last word written again; inside a word, a part-shifted word written if its `G` stage holds a 1 | nothing; one call |
| `SCLK` | one extra shift: the next write lands on the wrong port with the wrong source | one call |
| `/UREQ` | the marker pauses between words | nothing |
| `/RESET` | every latch cleared, every call dropped | the exchange |

One wrong CVSD bit is a transient 30 dB below speech, what a plesiochronous
slip does anyway (`mf8/mf8-backplane.md` §7). `SCLK` costs one call and no more:
the next word realigns and a wrongly pointed port releases itself (`tb_debug`).
`/RESET` is filtered at every block, 10 k into 100 nF and a '14, about 1 ms,
so **whatever drives `/RESET` must hold it low at least 2 ms**.

---

## 7. Open

- **The open-drain pull-ups are unanalysed**: 4.7 k at the clock card on
  `/HA`, `/HB`, `/HW` and `/WS` with one drain a block (and the readers on
  `/WS`), 1 k block-local on eight port drains, against 8.79 µs to the capture
  instant. `exch.py mainboard` has no open drain, `newimpl/README.md` §6's
  300 pF / τ 1.4 µs assumed 64 drains on the bus, and there is no SPICE rig.
  It is where the fabric is nearest a limit.
- **§2.4 is for a 64-way totem-pole ribbon**, not this header, the bridge or
  tiles. Crosstalk is an estimate (of order 5 %); ground bounce, radiation,
  tap stubs, contact current and hot-plugging are not analysed.
- **Who holds `/RESET` high.** Every block pulls it down through 100 k, so it
  needs a driver that is always enabled, not a master's switched '244, and a
  console's open-drain reset (`proposed/console.md` §9) would need a pull-up
  that beats eight 100 k. No document places the power-on RC and button; the
  clock card, not drawn, is the obvious place.
- **`SCLK` is not a tap.** `ctl_write` counts ÷32 off the 4.096 MHz master,
  which no bus line carries. On a board each master (the marker and the unit)
  takes it from `SLOT1`, 128 kHz on the bus, or counts its own; undecided.
- **One wrong plane sample** (§6.2): what a marker does with a caller seen for
  one pass, or a busy port read free once, is not analysed.
- **Open-drain control lines.** `SDATA`, `SCLK` and `WR` could go open-drain,
  low-true so that the edge that counts is the driven fall, and two masters
  could then never fight on them. It changes `block.v` in every build and the
  debugger's receivers (`debugger.md` §7). Asked, not decided, not built.
- **Bit 14, spare or parity** (two '280 a block against a one-call fault), and
  **the unit's 640-tick wait**, derived by hand, not measured: bench
  questions.
- **How a ringback card drives `RBT`** in a block: there is no wiring field
  to bring a card's output to pin 42 (`common/tones.md` §9). Proposed, and
  drawn on the block header: an RBT SOURCE jumper puts one lane's `C_TX` onto
  pin 42 through 100 Ω, shunted on the one block that holds the ringback card
  (`block-stack.md` §4). Not in `mainboard.v`.
