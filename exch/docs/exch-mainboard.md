# The exchange — the mainboard: what runs between the blocks

`exch-fabric.md` §2 lists the bus in one table and leaves its physical form
open: "everything below is on the mainboard or a ribbon between blocks", with
"sixteen highways across eight blocks on a ribbon or a mainboard" among the
things not measured. This document closes that. It is the signal list in full,
the two cables that carry it, what decides a block's number, what a cut or an
absent part reads as, and the electrical argument — which turns out to be the
easy part.

> **Status: proposed; the timing measured by the same method as `exch-fabric.md`
> §4.** `exch.py mainboard` adds the clock's own flight down the cable to that
> section's 400 000 draws. The line's capacitance, edge rate and drive current
> are arithmetic from the ribbon's geometry. Crosstalk is an estimate and is
> named as one (§9). Nothing has been drawn and nothing has been on a bench.

---

## 1. The one thing that decides the shape

A ribbon is a bus of identical conductors, and every connector crimped along it
sees the same signals. Almost all of this bus wants exactly that — the clocks,
the sixteen highways, the marker's control lines are the same at every block.

**Three signals are not.** Block *h* drives highway `HC[h]` and `HA[h]` and
answers to `BLK[h]`, and that is the whole of a block's identity: it is why
`exch-fabric.md` §3.1 can say a block "needs no address and no comparator —
layout, not logic". A plain daisy-chained ribbon cannot give it, because every
tap is the same. Making a block work it out instead costs a '138 on three
strapped ID pins, eight individually-enabled tri-states for `HC` and eight for
`HA`: **about six packages a block, forty-eight in the exchange, 7 % of the
fabric, to buy back something the layout was giving away free.**

So the split is:

```
  one continuous ribbon, identical taps  ─── 55 signals, the same at every block
                        │
                  the MAINBOARD at each tap ── a passive board: the cable's header, the block's
                        │                      connector, and ONE 2x8 shunt field
                        │
                     the block  ─── HC_OUT, HA_OUT, /BLK: three pins, and the shunt column says which
```

**The block's number is three shunts in one column.** The mainboard brings the
eight `HC` conductors to the top row of a 2 × 8 header and busses the block's
`HC_OUT` pin along the bottom row; a shunt in column *h* makes it block *h*'s
highway. Two more headers do the same for `HA_OUT` and for `/BLK`, which runs the
other way. Silkscreen 0–7 across them and a block's number is three jumpers in a
labelled column, set once when the subrack is wired. No part, no logic, and the
mainboard is one board design wherever it sits.

This is the same bargain as `mf8-backplane.md` §3's "no slot-ID pins", one level
up: **the cable is common, the board is position-wired, and the card knows
nothing.**

---

## 2. The signals

Fifty-five, in three groups by who drives them. All 74HC at 5 V.
`exch-fabric.md` §2 is the same list; `HB`, `RX_OCT` and `/CON` are new here and
§8 says why.

### 2.1 From the clock card — 15

| signal | rate | what |
|---|---|---|
| `HCLK` | 512 kHz | the cell clock, high for the first half of a cell (1 953 ns). **The one signal on the bus whose edges are load-bearing**: through each block's '138 it becomes every port's capture strobe |
| `SLOT[2:0]` | 512 kHz | the cell number, changing at the start of the cell. Addresses every commutator, and is an MF8 trunk card's frame bit count |
| `SLOTQ[2:0]` | 512 kHz | the same count a quarter cell late, from the '175 on the 1.024 MHz tap. Addresses every strobe decoder and nothing else (`exch-fabric.md` §3.2) |
| `HB` | 1.024 MHz | the half-bit clock of `mf8-spec.md` §9.1. **The fastest thing on the bus**, and only a trunk card wants it (§8) |
| `TX_CLK` | 64 kHz | the frame clock. Every card's `RX_CLK` pin is this signal |
| `TX_OCT` | 8 kHz | the octet mark. Also the scanner's and the monitors' step |
| `RX_OCT` | 8 kHz | `TX_OCT` one frame late, from one flip-flop on the clock card (`exch-fabric.md` §3.4). A card's `RX_OCT` pin |
| `FILL` | 32 kHz | the `1010` idle pattern: what an unfitted port, an unfitted block and a cleared latch all hear |
| `RBT` | 64 kb/s | the ringback tone as bits, substituted ahead of a ringing port's commutator input |
| `/RING_CAD` | 2 s / 4 s | the ring cadence, low true |
| `TICK` | 1 kHz | the marker's and the registers' time base |

### 2.2 The highways — 16

| signal | driver | loads | what |
|---|---|---|---|
| `HC[0..7]` | block *h* drives wire *h*, through its shunt | every block, plus the marker's probe | eight ports a wire, one a cell. The whole switch |
| `HA[0..7]` | the same | every block; the marker's, the registers' and the monitors' probes | the signalling highways. `HA` is also the M highway the probes read |

Each highway carries one driver and about ten receivers. **A highway with no
driver — an unfitted block, or a missing shunt — is pulled to `FILL` through
4.7 kΩ at the clock card**, exactly as an empty MF8 slot is pulled
(`mf8-backplane.md` §6), so it reads as CVSD silence rather than as noise.
`HA` is pulled to ground: on-hook.

### 2.3 The control bus — 24, multi-master

Driven by the marker, or by the operator's console when it takes the bus.

| signal | direction | what |
|---|---|---|
| `BLK[0..7]` | marker → mainboards | one select a block, picked off by the shunt. Enables the block's write decoder and its `PB` drivers |
| `PORT[2:0]` | marker → blocks | which of the block's eight latches |
| `SRC[5:0]` | marker → blocks | what to write into it: the source port, **as dialled** (`exch-protocol.md` §5) |
| `BSY`, `CLM` | marker → blocks | the latch's other two bits: busy, and a claimed trunk's backward A |
| `WR` | marker → blocks | the write. Gated with `BLK[h]` in the block's write decoder |
| `PB[1:0]` | the selected block → marker, tri-state | `BUSY`, and the card's word one bit a frame. **Pulled LOW at the marker** (§6) |
| `/CON` | console → marker | the console has the bus; the marker's drivers go high-impedance. One '244 enable |
| `/RESET` | marker or power-on → blocks | clears every latch: every port listening to 00. **The only signal on the bus a glitch can hurt** (§7) |

### 2.4 Not on the bus

**`−48 V` and `RING` never leave a subrack.** Ninety volts of ringing beside
sixteen highways on 0.05-inch pitch is not worth the one cable it saves; each
subrack takes its rails from its own PSU slot as `mf8-backplane.md` §8 has it,
and the mainboard carries `+5 V` and ground only.

**A trunk card is not on the bus either.** It taps its *own block's* `HC[h]` and
`HA[h]`, which are already its transmitter's multiplexed frame
(`exch-fabric.md` §1.1), and takes `HCLK`, `HB`, `SLOT` and `TX_OCT` from the
block. So the cable has ten taps — eight blocks, the clock card and common
control — however many trunks are fitted.

**Registers, resolvers and the marker share one tap.** A register's probe reads
its caller's hook off `HA` and regenerates its own strobes from `HCLK` and
`SLOTQ` with a '138 of its own; it does not need a block's strobe lines. The
digits it hands the marker stay on their own short ribbon between the two
(`exch-marker.md` §4). Monitors sit on trunk blocks and need no tap at all.

---

## 3. The two cables

| | conductors | signals | carries |
|---|---|---|---|
| **A — the fabric cable** | 64-way IDC | 31 + 1 spare | everything in §2.1 and §2.2 |
| **B — the control cable** | 50-way IDC | 24 + 1 spare | everything in §2.3 |

**A ground on every other conductor**, so every signal has a ground either side
and the cable's impedance is about 105 Ω. Both cables run the same route, in one
harness, with an IDC connector crimped at each of the ten taps: **one unbroken
conductor end to end, and no buffer anywhere between the clock card and a
block.** A repeater in the middle would add its own delay to the skew of §5, and
the skew is the only thing the cable costs.

Two cables rather than one hundred-way because of what `exch-fabric.md` §7 does
at bring-up: the clock card and a block come up on cable A alone, and the console
and then the marker arrive on cable B. It also puts the multi-master bus, which
is the one with a person on the end of it, on its own cable.

### 3.1 Cable A, 64-way — odd pins signal, even pins ground

| pin | | pin | | pin | | pin | |
|---|---|---|---|---|---|---|---|
| 1 | spare | 17 | `SLOTQ2` | 33 | `HC0` | 49 | `HA0` |
| 3 | **`HCLK`** | 19 | **`TX_CLK`** | 35 | `HC1` | 51 | `HA1` |
| 5 | `TICK` | 21 | `TX_OCT` | 37 | `HC2` | 53 | `HA2` |
| 7 | `SLOT0` | 23 | `RX_OCT` | 39 | `HC3` | 55 | `HA3` |
| 9 | `SLOT1` | 25 | `FILL` | 41 | `HC4` | 57 | `HA4` |
| 11 | `SLOT2` | 27 | `RBT` | 43 | `HC5` | 59 | `HA5` |
| 13 | `SLOTQ0` | 29 | `/RING_CAD` | 45 | `HC6` | 61 | `HA6` |
| 15 | `SLOTQ1` | 31 | **`HB`** | 47 | `HC7` | 63 | `HA7` |

The order is not arbitrary. **The three signals in bold are the only ones whose
edges matter**, and they are put eight conductors apart from each other and
sixteen from the highways, with the 1 kHz `TICK` and a spare as `HCLK`'s nearest
neighbours. The sixteen highways are bunched at the far end where the only thing
they can disturb is each other, which costs nothing (§7). `HCLK` is at pin 3 and
not pin 1 so that it has a ground on both sides.

### 3.2 Cable B, 50-way — odd pins signal, even pins ground

| pin | | pin | | pin | |
|---|---|---|---|---|---|
| 1 | spare | 19 | `SRC4` | 37 | `BLK2` |
| 3 | **`WR`** | 21 | `SRC5` | 39 | `BLK3` |
| 5 | `PORT0` | 23 | `BSY` | 41 | `BLK4` |
| 7 | `PORT1` | 25 | `CLM` | 43 | `BLK5` |
| 9 | `PORT2` | 27 | `PB0` | 45 | `BLK6` |
| 11 | `SRC0` | 29 | `PB1` | 47 | `BLK7` |
| 13 | `SRC1` | 31 | `/CON` | 49 | `/RESET` |
| 15 | `SRC2` | 33 | `BLK0` | | |
| 17 | `SRC3` | 35 | `BLK1` | | |

### 3.3 The block connector

Fifty signals: the 47 of §2 that are common, and `HC_OUT`, `HA_OUT` and `/BLK`
from the shunt field. On a **96-way DIN 41612, row b entirely ground**, rows a
and c the fifty signals and `+5 V` — so every signal has a ground pin beside it
in the connector as it had in the cable. A block in the "block mainboard" form
of `exch-fabric.md` §5, with its eighty packages flat and eight card sockets
standing on it, *is* the mainboard: the cable's two headers and the shunt field
go on that board and there is no block connector at all.

---

## 4. The shunt field

```
  mainboard, one per block position

        HC0 HC1 HC2 HC3 HC4 HC5 HC6 HC7        from cable A, pins 33-47
         o   o   o   o   o   o   o   o
         |
         #   o   o   o   o   o   o   o         a shunt in column 3 -> this is block 3
         o- -o- -o- -o- -o- -o- -o- -o         all bussed to the block's HC_OUT pin
              ... the same for HA_OUT, and for /BLK the other way ...
              0   1   2   3   4   5   6   7    silkscreen
```

Three shunts in one column. Set wrong, or left out, §6 says what happens.

---

## 5. Electrical — `exch.py mainboard`

Eight blocks a quarter of a metre apart: two metres of cable, 5.1 ns/m,
49 pF/m, ten taps.

### 5.1 The clock travels with the data, so the skew mostly cancels

A block's capture strobe comes from the `HCLK` that reached *it*, and the bit it
captures came from a block the same cable reached. Data arrives at listener *b*
at `dly(a) + flight(a,b)`; *b*'s strobe at `dly(b)`. The loss is the difference,
and it is **exactly zero whenever the driving block is nearer the clock card than
the listening one** — the flight cancels the skew term for term.

| clock card | worst loss | the pair |
|---|---|---|
| at one end of the cable | **17.9 ns** | block 7 driving, block 0 listening |
| **in the middle** | **8.9 ns** | block 7 driving, block 3 listening |

Put the clock card in the middle of the chain and the worst case halves, for the
cost of deciding which subrack it goes in. **Hold is never worse than with no
cable at all**: the same term that shortens set-up lengthens hold.

### 5.2 What that costs §4 of `exch-fabric.md`

The worst pair on the worse placement, through the same 400 000 draws across the
74HC spread:

| | with the cable | no cable |
|---|---|---|
| set-up at the capture flip-flop | **725 ns** | 743 |
| hold | **933 ns** | 915 |

Two metres of ribbon costs 18 ns of a three-quarter-microsecond budget. The
*data's* own flight was already inside `exch-fabric.md` §4's 12 ns `wire` term;
the clock's was not, and this is it.

**The §3.2 hazard is untouched.** `HCLK` and `SLOTQ` leave the clock card
together and arrive together, so their skew is conductor to conductor within one
ribbon — under 0.1 ns/m — and not the 5.1 ns/m of the cable itself. The address
still settles 367 ns before the enable.

### 5.3 The line, and why the cure for an edge is to slow it down

Two metres and eight taps is 193 pF and a 10.2 ns flight, 20.4 ns there and
back. A '244 into that load already gives a 17 ns edge, which is right at the
boundary where a line stops being lumped and starts ringing.

| series R at the driver | edge | of a cell |
|---|---|---|
| 33 Ω, as `mf8-backplane.md` §8 uses on 25 cm | 31 ns | 1.6 % |
| **100 Ω** | **59 ns** | **3.0 %** |
| 220 Ω | 110 ns | 5.7 % |

**100 Ω on every clock-card output.** It makes the edge three times the cable's
round trip, which is the definition of a line with nothing to settle, and it
spends 59 ns out of 725. At four metres, where the round trip is 41 ns, the same
resistor still gives 89 ns. A clock line draws C·V·f = 0.49 mA at 512 kHz and
0.99 mA at 1.024 MHz; a '244 sources 25 mA.

**This is the whole electrical story, and it is the point.** The fabric was
designed with three orders of magnitude in hand (`exch-fabric.md` §6 refused to
spend 9 % of it to save seven packages a block), and a backplane problem that
would be delicate at 50 MHz is, at 512 kHz with a 750 ns budget, solved by one
resistor pack and a ground between every pair.

---

## 6. What an absent or wrong part reads as

| | on the bus | what the exchange does |
|---|---|---|
| **a block not fitted** | its `HC` pulled to `FILL`, its `HA` to ground, `PB` pulled low | eight ports that read unequipped, never hunted, heard as silence by anyone pointed at them. The other seven blocks are untouched |
| **its three shunts left out** | the same | the same. **A block with no number is simply not heard**, and every port in it still listens perfectly well to everything else — which is a usable state to bring a block up in |
| **two blocks on the same column** | two '244s on one highway, two `PB` drivers on one select | contention: a broken `1010` on that highway, garbage in both blocks' words. Caught at `exch-fabric.md` §7 step 2, which scopes exactly this pattern. Both blocks hot but not damaged |
| **cable B unplugged at a block** | `/RESET` pulled low, `WR` and `BLK` pulled low at the block | that block clears every latch and takes no writes: every one of its ports listening to 00, silent, no call held. The clean failure |
| **cable A unplugged at a block** | `HCLK` and `SLOT` pulled low at the block | the strobes freeze, every capture flip-flop holds its last bit, the commutator puts port *h*0 on the highway continuously. Dead and obviously dead; nothing else is hurt |
| **the clock card pulled** | no clocks at all | the exchange stops. Nothing rings, nothing releases, every latch keeps what it had until `/RESET`. As `mf8-backplane.md` §6's "trunk card absent" |
| **a shunt in the `/BLK` row only** | the block answers the marker but drives no highway | its ports read and write correctly and are heard as `FILL`. The confusing one, and the reason the three shunts are one column on one silkscreen |

The polarity of every pull is chosen so that **absent reads as empty, not as
busy**: `PB` is pulled *low*, so a block the marker cannot select reads as eight
unequipped slots — class 000, never hunted, `BUSY` clear — rather than as eight
phantom busy lines, which is what a pull-up would give.

---

## 7. What a glitch costs, which is the real question

A backplane is judged by what its worst noise event does. Take every signal in
turn and ask what one spurious edge on it does to a call in progress:

| signal | a spurious edge does | costs |
|---|---|---|
| `HC`, `HA` | nothing. They are sampled 750 ns after they change; a glitch is 20 ns long | nothing |
| `PB` | nothing. The marker reads a word over a whole 125 µs visit, and re-reads it 8 ms later | nothing |
| `FILL`, `RBT`, `TICK`, `/RING_CAD` | one wrong bit of tone, or a millisecond of cadence | nothing audible |
| `SLOT`, `SLOTQ` | a commutator or a decoder addressed wrong for 20 ns, while the strobe decoder is disabled | nothing |
| `SRC`, `PORT`, `BSY`, `CLM` | the marker holds them a whole cell either side of `WR` | nothing |
| `WR` | **writes the latch a second time, with the same data** | nothing |
| `HCLK` | one extra strobe: **one port captures one wrong bit** | one bit |
| `TX_CLK` | one card samples twice, or sends one extra bit to its phone | one bit |
| `/RESET` | **every latch in the exchange cleared: every call in progress dropped** | the exchange |

One wrong CVSD bit is the event `mf8-backplane.md` §7 measured: a transient
30 dB below speech, settled in 1.2 ms, nine decibels below the codec's own
error, and the same thing a plesiochronous slip does every 156 ms on every line
of every MF8 shelf in the system. **So of fifty-five signals, fifty-four cannot
lose a call, and the worst any of them can do is what the system already does to
itself twice a second.**

That leaves `/RESET`, and it is not a fast signal — it comes from a pushbutton
and a power-on RC. **Filter it at every block**: a 10 kΩ and a 100 nF into one
gate of a '14, which each block already has for its supervision detectors
(`exch-fabric.md` §3.5). A millisecond of time constant makes every glitch on the
bus invisible to it and costs a sixth of a package for the whole exchange.

That is the answer to whether a ribbon is a sensible way to build this. It is
sensible **because the fabric switches bits at 512 kHz with 750 ns of margin and
holds its state in a latch at every port**: there is no central memory for a
disturbance to corrupt, no clock recovery to lose, and no signal but the reset
whose worst case is worse than one CVSD bit.

---

## 8. Three signals this adds to `exch-fabric.md` §2

- **`HB`, 1.024 MHz.** `exch-network.md` §1 says a trunk card in an exchange
  "takes 4.096 MHz and frame sync from the clock card instead of owning the
  crystal". It needs less than that. `mf8-spec.md` §9.1's chain wants only the
  half-bit clock `HB` — 1.024 MHz at the 512 kbps rate — and the line bit clock
  `H`, which *is* `HCLK`; and §9.4's receiver has no clock on its timing path at
  all. **So 4.096 MHz never has to leave the clock card**, and the fastest edge
  on the mainboard is 1.024 MHz rather than four. Worth having: it is the one
  signal that would have wanted care.
- **`RX_OCT`.** `exch-fabric.md` §3.4 says a card's `RX_OCT` is `TX_OCT` one
  frame late, from one flip-flop on the clock card — so it is a signal, and §2's
  table did not list it.
- **`/CON`.** §3.1 calls the control bus multi-master and leaves how the console
  takes it unsaid. One line, one '244 enable at the marker.

---

## 9. Not measured

- **Crosstalk.** With a ground between every pair the nearest aggressor is two
  conductors away, and published figures for interleaved ribbon put near-end
  coupling at one or two per cent; sixteen highways switching together at the
  cell boundary, dominated by the two nearest, is of the order of 5 % — a
  quarter of a volt against 74HC's volt of noise margin. **This is an estimate
  and not a measurement**, and it is the one number here that would change the
  design if it were wrong: the cure would be 1-in-1 grounding on a wider cable,
  or the economy form of `exch-fabric.md` §6, which halves the highways to eight
  wires and is worth re-reading now that a cable, and not only packages, is what
  they cost.
- **The stub from each tap to the block's receivers** — assumed under 100 mm,
  0.6 ns, and ignored.
- **The shunt field as a stub** in the highway driver's path: 60 mm of board and
  a jumper in series with a 512 kHz signal. Nothing at this rate, unscoped.
- **Ground bounce** at the clock card, where one '244 drives fifteen lines into
  193 pF each. The per-line current is half a milliamp; the simultaneous switch
  of eight `SLOT`/`SLOTQ` lines is not analysed.
- **Radiation.** Two metres of unshielded ribbon carrying 1.024 MHz with 59 ns
  edges, in a cabinet, next to a −48 V line feed and a 90 V ringing bus.
- **Hot-plugging a block.** The pulls make a removed block harmless (§6); a block
  inserted live, with its shunts already fitted, drives a highway other ports are
  listening to at an arbitrary instant. Not considered beyond that.
- **Everything mechanical.** No cable drawing, no board, no connector part
  numbers, nothing on a bench.
