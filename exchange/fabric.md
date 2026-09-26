# The switching fabric

The fabric is what connects 64 ports without a central switch: eight C
highways that carry every port's voice, two scanned open-drain planes that
carry every port's hook and busy, a word line that carries one card's
declaration on demand, and at each port a latch and a few gates that listen,
ring and release. This document is the fabric as a circuit; the bus it runs
on is `bus.md`, the block as boards is `block-stack.md`.

> **Built:** `newimpl/rtl/port.v`, `block.v`, `exch.v`, `mainboard.v`,
> `probe.v`, `word_rx.v`; `tb_fabric`, `tb_ha`, `tb_probe`, `tb_word`, `tb_ctl`.
> **Drawn:** `pcb/portcard`, `hdrbus`, `hdrlogic`, locked to the RTL (`block-stack.md` §8).
> **Measured in:** `exch.py fabric`; `exch.py timing` (§7): worst case, no gate delays.

---

## 1. Overview

The fabric is **8 × 8**: eight highways (space) by eight slots (time). The 64
squares of that grid are the 64 ports, and a port's number `h s` is its
square: highway *h*, slot *s*, three bits each (`numbering.md` §2).

| plane | conductors | rate | carries | driven by |
|---|---|---|---|---|
| C | `HC[0..7]` | 512 kbps, one port a cell | voice and data, 64 kbps a port | block *h* drives `HC[h]` |
| supervision | `/HA`, `/HB` | 64 kbps, one port a bit-time | M and `BUSY` of the port whose turn it is | open drain, every port in its turn |
| word | `/HW`, named on `/WS` | 64 kbps | the primary octet of one card's word | open drain, the card a reader selected |

**The crosspoint belongs to the listener.** A port listens to one square by
holding its number in a latch; any number of ports may listen to one square;
a conversation is two latches, each naming the other. The eight highways are
the switch: a connection exists only as six bits in a listener's latch, and
there is exactly one path between two ports, always free.

**Nobody is in charge of a call.** Once written, a port rings its own phone,
sends its own ringback, and clears its own latch when either party hangs up
(§5). A marker writes latches; it never has to take a connection down.

Highways and not analog crosspoint arrays (MT8816): an array's memory is
write-only, so a port could not drop its own crosspoint, and an LSI would hold
the exchange's state. Eight by eight puts one '151 on each axis and runs the
highways at MF8's line rate; the six-bit port number, the 1 ms pass and the
16-bit control word are one decision (`analysis/why-bits.md` §3).

---

## 2. The C plane

### 2.1 The commutator

Every card sends one bit a frame on `C_TX` and holds it for the whole frame.
Each port card puts its card's bit (or ringback, §5.2) on its block's lane
`C_TXk`. The block's **commutator** is a '151 with the eight lanes on its data
inputs and `SLOT[2:0]` on its selects: `SLOT` steps 0 to 7 once a 64 kHz frame,
so the output is port *h*0's bit for the first 1.953 µs cell, *h*1's for the
next, and so on. Buffered, that is `HC[h]`. One `SLOT` counter on the clock
card serves every block, so cell *k* is the same instant everywhere, and
across a frame the eight highways carry all 64 ports once each:

```
          cell 0   cell 1   cell 2   cell 3   cell 4   cell 5   cell 6   cell 7     one frame, 15.63 µs →
  HC[0]    00       01       02       03       04       05       06       07
  HC[1]    10       11       12       13       14       15       16       17
  HC[2]    20       21       22       23       24      [25]      26       27
   ...
  HC[7]    70       71       72       73       74       75       76       77
```

### 2.2 The listener

A port listening to 25 holds `[ 2 | 5 ]` in its '273 and picks one square:

- **the wire**: a '151 with the eight highways on its data inputs and the
  latch's highway bits on its selects, following `HC[2]` continuously;
- **the moment**: a '151 with the block's eight strobe lines on its data
  inputs and the latch's slot bits on its selects. Line 5 pulses in the middle
  of cell 5, when `HC[2]` carries port 25; the '151's inverted output W rises
  there and clocks half a '74 whose D is the wire.

The flip-flop holds 25's bit until cell 5 of the next frame, rebuilding 25's
64 kbps stream as the listener's `C_RX`. The two directions of a call are two
squares and know nothing of each other.

```
  cell      |  0   |  1   |  2   |  3   |  4   |  5   |  6   |  7   |  0   |
  HC[2]     |  20  |  21  |  22  |  23  |  24  |  25  |  26  |  27  |  20' |
  strobe 5  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾   low for the second half of cell 5
  capture   .........................................↑ 25's bit for frame f, 10.74 µs in
  card      .............................................................↑ samples C_RX at the frame edge
```

**The strobe lines.** A '138 on each block, addressed by `SLOTQ[2:0]` and
enabled while `HCLK` is low, so line *k* is low for the second half of cell
*k* and its falling edge is the middle of the cell. **The decoder is addressed
by `SLOTQ`, never `SLOT`.** Decoded from `SLOT`, the new address races the
disable at every cell boundary; across the data-sheet spread the next line
pulses at the start of its cell in 9.6 % of draws, up to 45 ns wide, with
nothing settled on the highway, and for slot 0 that is the frame edge where
every card samples (`exch.py timing` 3). `SLOTQ` is the same count a quarter
cell late, from one '175 on the clock card, so the address moves only while
the decoder is disabled: 415 ns after the disable, 368 ns before the enable.

### 2.3 One frame, for every pair

Every capture is mid-cell, so nothing a card is given changes within half a
cell of the frame edge, where every card samples `C_RX` (`RX_CLK` is
`TX_CLK`, `common/clocks.md` §5). A bit sent in frame *f* is taken by the
listener's card at the edge that begins *f* + 1, whatever the two slots:
**one frame for every pair**, with no re-timing flip-flop. So octets survive
a connection inside one exchange — a card framing on `RX_OCT`, `TX_OCT` a
frame late, gets every byte — and data passes bit-exact; across a trunk they
do not (`network.md` §8). Fan-out costs nothing: a tone is a port fifty
others sample. `tb_fabric` checks all 4 096 ordered pairs bit-exact at one
frame, and fan-out.

### 2.4 Idle is `FILL`

An empty lane idles on `FILL` (the 32 kHz `1010`, CVSD silence) through 4.7 k
on the block header, and a highway no block drives is pulled to `FILL` at the
clock card (`bus.md` §1). **A cleared latch listens to 00**, which is never
fitted, so a released port hears `FILL` with E = 0; nothing that talks may sit
at 00 (`numbering.md` §2). The slot select is wired in order, and a latch
holds port numbers as dialled.

### 2.5 A write lands at any instant

A marker needs no synchronisation to the frame: of 4 000 writes at random
cells, every listener got the new source from that frame or the next, with at
most one bit held over (`exch.py fabric`). **The worst a re-point does is
repeat one bit**, the slip a plesiochronous trunk makes anyway.

---

## 3. The supervision planes: `/HA`, `/HB` and `SCAN`

### 3.1 The scan

`/HA` and `/HB` are open-drain conductors, idle high, each pulled up at the
clock card (`bus.md` §1). **In bit-time *p* — the frame in which `SCAN[5:0]` =
*p* — port *p* pulls `/HA` if its M is up and `/HB` if its `BUSY` is up**, for
the whole frame. A pass is 64 bit-times, 1 ms, and every port's hook and busy
refresh at 1 kHz.

`SCAN[5:0]` is the port number and nothing else: six stages of the clock
card's divider, between `TX_CLK` and `TICK` (`common/clocks.md` §1), with no
enable, load or clear, so **nothing in the exchange can stop the scan**. A
port nobody could deal with comes round again 1 ms later. A pass boundary is
`SCAN5`'s fall.

A port's own '688 compares `SCAN` with `{h, POS}` (§6.1) and enables its two
drains for the bit-time. A block ORs its eight ports' drains onto a
block-local `/HA_L` and `/HB_L` and pulls each bus plane through one drain of
its own, gated by FIT (`block-stack.md` §2.3). Enables overlap by nanoseconds
at the frame edge, which on a wired-OR is harmless.

**One turn, both facts.** M and `BUSY` of the same port arrive in the same
bit-time, so a reader never holds half a sample across a frame edge and can
never pair one port's hook with its neighbour's busy. That is what the second
conductor buys, and why the pass is 64 bit-times and not 128.

### 3.2 The capture instant

**Every reader samples every plane at one instant: the fall of strobe line
4, mid-cell 4, 8.79 µs into the 15.63 µs bit-time, with 6.84 µs of hold.**
`/HA`, `/HB`, `/WS` and `/HW` share that one settling budget. The line is
`SLOTQ`-addressed, so free of §2.2's hazard; a reader off the blocks makes it
from `HCLK` and `SLOTQ` with a '138 of its own.

**A pulled plane is a one**, and nothing ever pulls a plane to its active
state, so everything absent reads idle with no part: an empty seat, an
unfitted block, a pulled card and a cut cable all read M 0, `BUSY` 0
(`bus.md` §6).

### 3.3 E

A port listening to *q* captures `/HA` in bit-time *q* (its second '688,
`SCAN` against its latch) and holds it as **E**, the other party's M, within
one pass of it. The capture re-inverts the plane, so a latch cleared to 00
reads E = 0.

### 3.4 The probe

Everything else that reads the planes — markers, registers, monitors, the
debugger — uses the same **probe** (`newimpl/rtl/probe.v`): a '688, half a
'74 and a quarter '08. Tied to `SCAN` it follows the scan; tied to a held
number it watches one port. It publishes a turn only if it sampled it, so a
probe re-pointed mid-turn publishes nothing, never a mixture. **Its outputs are
levels, held until that port comes round again**: an event on a wire is a
race, and a level valid when read is not.

Seizure latency is at most a pass and a bit-time. `tb_ha` checks the
bit-time map on both planes, the capture instant and E within one pass;
`tb_probe` the following and held probe and the per-port clear.

---

## 4. Reading a card's word: `/WS` and `/HW`

A card declares what it is in an option word on its a12 pin (`card-word.md`
§1). The word is read on demand, not scanned: the scan only names the card,
and nothing continuous depends on `/HW`.

**The select.** A reader names a port by pulling `/WS` for that port's whole
bit-time. Every block samples `/WS` at the capture instant (§3.2). The block
whose number is `SCAN[5:3]` latches `SCAN[2:0]` and becomes selected; every
other block deselects. The selected block's word '151 then puts that seat's
word lane onto `/HW` through the block's drain, one bit a frame, until the
next select, whoever makes it.

**The read.** The reader takes `/HW` at the capture instant in the eight
frames after its select, into a '259 addressed by `SCAN[2:0]` and wired
rotated so each bit lands in place whatever frame the read starts on (the bit
order is `card-word.md` §3's). **A read is nine frames, 140 µs, and touches
no other conductor**, so a write passing during it changes nothing on `/HW`.
It waits up to a pass for its port's turn. The reader is
`newimpl/rtl/word_rx.v`: a '174, a '688, two '161s, the '259 and a drain.

**Nobody owns `/WS`.** A select names only the port whose turn it is, so two
readers selecting in one bit-time both take the same word. **The one rule:
never select during another read's eight frames**; every reader sees every
select and counts eight frames before it may select again. No rank, no
request line, and every read is public.

**`/HW` fails safe.** A card pulls its word pin low for a one and `/HW` idles
high, so an empty seat, an unfitted block, a card held off by its power-up RC
and a trunk whose link is down all read **all zeros**, *none*
(`card-word.md` §2). A reader that took the wire's level as the bit would read
that absence as all ones, a plain line.

**A read delivers the primary octet only**: a card reloads every eight frames
and the socket marks nothing longer (`card-word.md` §7). `tb_word` checks
every octet phase, every absence reading zeros, two readers in one bit-time,
a select deferred past another read, and a write during a read.

---

## 5. The port circuit

### 5.1 Parts and the write

A port is one port card of thirteen DIP (`block-stack.md` §2.2): the '273,
two '151 selects, two '688s, a '74, the detectors on a '14, four gate
packages, the ringback '157, the socket drivers and two drains. The '273
takes bits 7–0 of the control word verbatim — `SRC[5:0]`, `BSY`, `CLM` — once,
on the leading edge of its `/WRk` lane (`bus.md` §4). A seat without a port
card leaves its lane on `FILL`, pulls no plane and reads no word:
*unequipped*.

### 5.2 The gates

M is the card's `A_TX` (a6). E is §3.3's capture.

```
 fM, fE    M and E, each through a diode-and-two-resistor RC into a '14:
           up in 16 ms (T_ARM), down in 256 (T_REL)
 release   the fall of fM or of fE, squared by a CR -> the '273's clear.
           A release beats a write
 RINGS   = the card's /ANS pin (a13) left open
 ON      = RINGS · /M · /fM              on-hook, rings, and did not just hang up
 RB      = ON · E                        being rung: the lane carries RBT, not C_TX
 A_RX    = (E + CLM) · /(ON · /RING_CAD) /RING_CAD is the wire, high between bursts
 BUSY    = BSY + fE + fM·/M + MUTE_BLK   onto /HB in the port's turn
```

`BUSY` is up while the port is written busy, while the party it listens to
is off-hook, for 256 ms after its own card hangs up, and while its adapter
holds `MUTE_BLK` (§6.2). An on-hook port whose E rises rings its card in the
`/RING_CAD` cadence, 2.048 s in 6.144 s (`common/clocks.md` §1), and its lane
carries `RBT` so the caller hears ringback; the card answers, M rises, `ON`
falls and both stop. `RBT` is `FILL` when no ringback card is fitted
(`features.md` §1).

Two terms are there because the model found their absence (`sim/exch.log`):

- **`BUSY` includes a detector still timing out** (`fM·/M`, and `fE`). The two
  detectors release at different moments; without the term a port seized in
  that window was cleared by the second detector's fall, killing 5 new calls
  in 300 (`exch.py calls` 16), and with it none. The price: a number reads
  busy for up to about 0.6 s after its call ends.
- **`ON` includes the filtered hook** (`/fM`). A caller who hangs up first
  while the other party is still off-hook meets on-hook with E high for 256 ms:
  without the term his phone was rung for 267 ms and the other party heard
  ringback; with it, neither (`exch.py calls` 17). Ring trip stays immediate,
  because the raw hook is still in the term.

**Whether a port rings is one bit, and the card owns it: `/ANS`.** A phone's
card leaves a13 open. A trunk, an outside line, a bridge leg and any card that
answers at once tie it low: otherwise a caller hears ringback the instant a
trunk is seized, and forward A is chopped by the cadence. The port's gates
never see the card's class.

**`CLM` is the A the port hands its card, never what it puts on the plane.**
On a claimed trunk the port sends backward A = 1 on `A_RX` (`network.md` §1).
On `/HA` it would jam the register the claim summons, which reads the far
caller's dial pulses in this port's own bit-time. **A claimed port keeps `CLM`
on every later write until it releases**: a write without it drops backward A
for one write, and every patch behind it clears 256 ms later.

### 5.3 Release

A port clears its own latch when either detector falls: its own card hung up
256 ms ago, or the party it listens to did. At the end of a call both ports
release so, each by itself; one still off-hook is an idle caller again.
**Release is on a fall, never a level**: a phone being rung, a caller
listening to a tone and a register's caller between digits all sit at 0
legitimately. 256 ms is the register's `CLR` (`register.md` §1) against a
longest dial break of 103 ms, and nothing in the exchange ever winks, so the
rule has no exceptions.

**A detector that never rose has no fall.** A port whose M or E was up for
less than `T_ARM` has nothing to release it. A marker that connects a call
watches the caller until the called port's E detector has risen, and writes
the called port free if the caller goes first (`marker.md` §5); the network
unit does the same for a trunk it holds (`network.md` §3.3).

---

## 6. The block

### 6.1 What eight ports share

The block header is `newimpl/rtl/block.v` without its ports, plus the
socket clocks: twenty DIP on two boards (`block-stack.md` §2.1). It holds the
bus receivers, the `/RESET` filter, the strobe '138 (§2.2), the commutator
(§2.1), the control word's '164s with `/BLK` = FIT · (`DST[5:3]` = *h*) · G and
the write '138 (`bus.md` §4), the select (§4), the socket clocks
(`common/clocks.md` §1) and the plane OR (§3.1). A full block is about 124 DIP
with its eight port cards.

**A port knows its own number without a word from anyone.** The header's
NUMBER jumper gives *h* and FIT, and *h* goes up the stack; each port card's
POS jumper gives its slot. A second header jumper, HC ROUTE, says which
highway `HC_OUT` drives. **FIT off silences the block**: no highway, no
`/BLK`, no select answered, no turn on the planes, while its ports still
listen. The jumpers must agree and nothing checks them (`block-stack.md` §4).

### 6.2 The block adapter

A **block adapter** is a trunk card that serves the seats of one block
through their card-side pins in place of subscriber cards (`trunks.md` §3,
§4; its face is `block-stack.md` §6). The ports behind it are unchanged.

- **An adapter drives only card-side pins** and never taps `HC` or `/HA`,
  which carry its seats only after it has driven them.
- **`MUTE_BLK`**, one pin on the adapter commons pulled down on the header, is
  ORed into every port's `BUSY` (§5.2): a link down busies the whole group and
  no hunt takes a seat of it.
- **On group failure** an adapter holds `A_TX` at 0, sends `FILL`, leaves the
  word pins open (*none*) and asserts `MUTE_BLK` (`tb_ltu`).

### 6.3 Bringing a block up

1. **The clock card alone**: `SLOTQ` a quarter cell behind `SLOT`; `SCAN`
   steps at every frame edge.
2. **A header, no port cards**: `HC[h]` is `1010`; strobe *k* low for the
   second half of cell *k* only, warm and cold.
3. **A latch by hand** from a jig on the control bus: 3 pointed at 5 repeats
   5's pattern a frame late; 20 and 21 pointed at each other are a hotline.
4. **A cleared latch**: `/RESET` low 2 ms, every `C_RX` `FILL`: port 00.
5. **One port's supervision**: two phones and the jig are a manual board.
6. **A second block**, then a marker.

---

## 7. Timing

The C plane, from `exch.py timing`: every delay of every part drawn on its
own between a third of typical and the data-sheet maximum, 74HC at 4.5 V,
400 000 draws, the worst reported. Nanoseconds from the start of a cell.

| | ns |
|---|---|
| a highway bit valid at a listener's flip-flop: card or ringback mux, commutator, driver, bus, receiver, select | by **252** (typical 165) |
| strobe address settled before the enable / moves after the disable | 368 / 415 |
| capture clock rises | 994 – 1 099 |
| **set-up / hold at the capture flip-flop** | **752 / 927** |
| the same across 2 m of bus, clock card at one end (`bus.md` §2.4) | 725 / 933 |
| a source in slot 7: `C_RX` settled before the card samples | 820 |
| a source in slot 0: `C_RX` moves after the card samples | 979 |

Nothing in the C plane has less than three quarters of a microsecond in hand.

The open-drain lines switch at the frame edge and are sampled 8.79 µs later;
that budget is where the fabric is nearest a limit (`bus.md` §7).

---

## 8. Open

- **The plane pull-ups are unanalysed** (`bus.md` §7).
- **One conductor, one failure domain.** A stuck drain on `/HA` or `/HB` takes
  every port's signalling. FIT lifts a block's drains, but not a failed block
  drain or a short on the bus plane; the debugger's `HA_STUCK` and `HB_STUCK`
  show it, and nothing isolates it (`debugger.md` §2).
- **The detectors as RCs**: the '14's threshold spread, and the CR's pulse
  against the '273's minimum clear width. The netlist check runs `port.v`'s
  count in their place (`block-stack.md` §8), so nothing has checked them.
- **A glitch on the slot select when its latch is written** may capture one
  wrong bit; not analysed beyond `exch.py fabric`'s one bit a re-point.
- **`exch.py timing` has not been re-run for the drawn chain** (the port
  card's '157, the lane jumpers, the stack, 33 Ω on the strobes), and its
  minimum delays, a third of typical, are an assumption the hold figures rest
  on.
- **Nothing watches `/WS`** for a select inside another read's eight frames
  (`debugger.md` §7).
