# Clocks — one crystal, one chain, shelf or block

Every clock in an MF8 shelf and in an exchange is a tap of one 4.096 MHz
crystal divided by two. This document lists the taps, where each is made and
which socket pin carries it, and the rule that follows: **no channel card
makes a clock.**

> **Built:** `newimpl/rtl/clock_card.v`, `frame_decode.v`; bench `tb_clock`. The block's decode is drawn on `pcb/hdrbus`, `pcb/hdrlogic`.
> **Proposed:** the clock card as parts; nothing is on a bench.
> **Measured in:** `tb_clock`; every rate is arithmetic off 4.096 MHz.

---

## 1. The chain

The exchange's clock card is a 4.096 MHz oscillator, a '4040, a '163 for
`SLOT`, a '175 for `SLOTQ`, the ring-cadence counter and drivers: about ten
packages. An MF8 shelf's chain is its trunk card's (`mf8-spec.md` §9.1), with
the same divisions.

| ÷ | rate | in the exchange | made | socket |
|---|---|---|---|---|
| 4 | 1.024 MHz | clocks the '175 | clock card only, not on the bus | — |
| 8 | 512 kHz | `HCLK`, `SLOT[2:0]`; `SLOTQ[2:0]` a quarter cell late | clock card, bus | — |
| 32 | 128 kHz | `SLOT1`; **`LOOP_HB` = `/SLOT1`** | `LOOP_HB` on each block | a2 |
| 64 | 64 kHz | `SLOT2`; **`TX_CLK` = `/SLOT2`**: a bit-time | `TX_CLK` on each block | a1, a7 |
| 128 | 32 kHz | **`SCAN0` = `FILL`** | bus | a4 |
| 512 | 8 kHz | **`TX_OCT`** = (`SCAN[2:0]` = 7); `RX_OCT` a frame later | on each block | a3, a8 |
| 4096 | 1 kHz | **`SCAN5` = `TICK`**: the pass and the 1 ms time base | bus | — |

`SCAN1`–`SCAN4` are the stages between. `/RING_CAD`, 2.048 s low and 4.096 s
high, is a counter off the 1 kHz, on the bus. ÷2 and ÷16 (`SLOT0`) have no
customer.

**On the bus: `HCLK`, `SLOT`, `SLOTQ`, `SCAN`**, 512 kHz and slower
(`bus.md` §1). Each block makes its sockets' clocks in about one package
(`newimpl/rtl/frame_decode.v`; `block-stack.md` §2.1): `TX_CLK` and `LOOP_HB`
through '14 sections; `TX_OCT` in a '11, a decode a ripple up-count cannot
glitch; `FILL` as a wire; and `RX_OCT` in two '74 halves, `TX_OCT` taken at the
start of cell 5 and then moved onto the frame edge. **`RX_OCT` is never a
decode of `SCAN[2:0]` = 0**, which the '4040 passes through between 3 and 4,
nor one step at the frame edge, which races the ripple (`block-stack.md`
§8.1).

**The scan is the chain**: 64 ports of 64 master ticks is 4096, so `SCAN` is
the six stages between `TX_CLK` and `TICK` (`fabric.md` §3.1). **The frame
edge is `SLOT2`'s fall**, `TX_CLK`'s rise.

---

## 2. Three domains

| domain | from | what lives in it | in the exchange |
|---|---|---|---|
| **T**, transmit | the local crystal | everything a card sends | the only domain below a trunk card |
| **R**, receive | an MF8 line: the far crystal | `C_RX`, `A_RX`, `RX_CLK`, `RX_OCT` | **`RX_CLK` is `TX_CLK`**, `RX_OCT` is `TX_OCT` a frame late; R exists only on a trunk card |
| **S**, the subscriber's | the phone, loop-timed to the downstream by a circuit not yet drawn (`subscriber-line.md` §1, §7) | the upstream pair | T's rate at an unknown phase: re-timed into T on the line card (`channel-cards.md` §2.3) |

A card correct in MF8, where T and R differ, is correct in an exchange by
construction. **Every exchange and shelf has its own crystal**, ±20 ppm, and
none is slaved to another, so what crosses between them slips (`network.md`
§8, §9).

---

## 3. The rule: no card makes a clock

**Every clock a channel card uses comes off the socket**: no oscillator,
divider or PLL on a channel card, in a shelf or a block. The reason is phase:
a divider on a card starts on a random phase at power-up, while every tap in
§1 comes off one counter and differs from another only by gate delays.
Allowed because they are not clocks: a line-card receiver's one-shots, which
measure domain S (`mf8-spec.md` §9.4); a tone card's audio oscillator; and a
timer that divides a socket clock to time a cadence or a window, whose output
clocks no bit — the analog tone card's cadence counter, a '4040 off socket
`TX_CLK` (`common/tones.md`), the pulse generator's timebase
(`../exchange/proposed/pulse-gen.md`) and a conference leg's detector window
(`../exchange/proposed/conference.md`).

A trunk card is not a channel card: an MF8 shelf's owns its shelf's crystal,
and the exchange's local trunk takes `HCLK` on the adapter commons' spare
(`trunks.md` §3). Common-control cards take the frame edge off `SLOT2` and the
1 ms edge off `SCAN5`.

---

## 4. `LOOP_HB` in an exchange

```
 cell            0    1    2    3    4    5    6    7
 SLOT[1]         0    0    1    1    0    0    1    1      128 kHz
 /SLOT[1]        1    1    0    0    1    1    0    0      rises at the frame edge and at mid-frame
 /SLOT[2]        1    1    1    1    0    0    0    0      TX_CLK: rises at the frame edge
```

**`LOOP_HB` = `/SLOT1`**: 128 kHz, rising with `TX_CLK` and again at
mid-frame, and falling twice a bit, each fall a quarter bit from a `TX_CLK`
edge: a boundary and a mid-cell edge, as a differential-Manchester encoder needs
(`mf8-spec.md` §9.2; the line card's '112 takes the fall, `channel-cards.md`
§2.4).
In MF8 it is the trunk card's next '4040 tap; a card cannot tell which made
it. **The contract on a2**, shelf or block: 128 kHz square; `LOOP_HB` ÷ 2 is
`TX_CLK`, both rising at the frame edge; a tap of the counter that makes
`TX_CLK`, never a divider of its own; skew of a gate or two (in a block: made
on header A, out through the port card's '244 and 33 Ω, `block-stack.md` §5).
Its name says its medium: the MF8 line's half-bit clock is **`LINE_HB`**,
1.024 MHz, on a shelf's trunk card and not on the exchange bus.

---

## 5. What a channel card may rely on

| pin | signal | rate | guaranteed | shelf vs block |
|---|---|---|---|---|
| a1 | `TX_CLK` | 64 kHz | its rise starts a bit; every T output changes on it and only on it | same |
| a2 | `LOOP_HB` | 128 kHz | §4 | same waveform |
| a3 | `TX_OCT` | 8 kHz | high one frame in eight, frame 7; loads a card's word (`card-word.md` §3) | same |
| a4 | `FILL` | 32 kHz | `TX_CLK` ÷ 2, free-running, one phase for every slot | same |
| a7 | `RX_CLK` | 64 kHz | the reference for what the card is given | **recovered in MF8; `TX_CLK` in a block** |
| a8 | `RX_OCT` | 8 kHz | recovered frame 7 | **`TX_OCT` a frame late in a block** |

Every card crosses R into T on its own flip-flops, so it never notices. Data
is bit-exact inside one exchange and slips between exchanges (`network.md` §8).

---

## 6. Open

- **The MF8 adapter's 1.024 MHz** is not on the adapter commons and cannot be
  divided out of `HCLK`: `trunks.md` §5, which lists the options.
- **`LOOP_HB` against `TX_CLK` at the line card's encoder**: `channel-cards.md`
  §6. A fix may land on the card or on §4's contract.
- **`SCLK` is not a tap** in the RTL (`bus.md` §7).
- **`LOOP_HB`'s skew across a block**, and the metastability window where a
  trunk card's R edge meets T: arithmetic only; a failure is one CVSD bit.
