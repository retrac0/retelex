# Clocks — one crystal, one chain, in both shelves

Every clock in an MF8 shelf and every clock in an exchange is a tap of one
4.096 MHz crystal divided by two. There are **nine taps, three domains and two
crystals in a system** — the near shelf's and the far one's — and everything
else that looks like a clock is one of those nine under another name.

This document lists them, says which pin each reaches a card on, and sets the
rule that follows from the list: **no channel card makes a clock.** It also
closes `baseband.md` §2.3's first open item — where a CVSD subscriber
line card in an exchange gets its 128 kHz — which is the question that made the
list worth writing.

> **Status: proposed. Nothing here is newly measured.** The chain is
> `mf8-spec.md` §9.1's and [clock_card.v](../verilog/rtl/clock_card.v)'s, read
> against each other; the rates are arithmetic off the 4.096 MHz both of them
> start from. §4's derivation is one inverter that has never been built, and its
> phase wants a scope at bring-up.

---

## 1. The chain

4.096 MHz into a ripple divider. `mf8-spec.md` §9.1 picks the crystal — "the
lowest that reaches the 2.048 MHz half-bit clock of the fastest family rate" —
and `clock_card.v` starts from the same value for the exchange, independently.
They are the same chain:

| ÷ | rate | in MF8 | in the exchange | on the channel socket | who wants it |
|---|---|---|---|---|---|
| 1 | 4.096 MHz | the crystal | the crystal | — | the divider, and nothing else |
| 2 | 2.048 MHz | the MF8 unit's line `HB` (Q1) | — | — | the unit's encoder; not on the fabric (`mf8-unit.md` §5.5) |
| 4 | 1.024 MHz | — | **`HB`**, and the tap the '175 clocks `SLOTQ` from | — | the block's strobe decoder |
| 8 | 512 kHz | — | **`HCLK`** the cell clock, and **`SLOT[2:0]`** | — | every commutator; every capture strobe |
| 16 | 256 kHz | — | `SLOT[0]` | — | **nobody** |
| 32 | **128 kHz** | **`TX_HB`** — the next '4040 tap | **`/SLOT[1]`** — §4 | **a2** | the CVSD subscriber line card's downstream encoder |
| 64 | 64 kHz | **`TX_CLK`** | **`TX_CLK`** = `/SLOT[2]` | **a1**, and **a7** as `RX_CLK` | every card, every port, everything |
| 128 | 32 kHz | **`FILL`** | **`FILL`** | **a4** | every unfitted `C_TX`; any card that must send silence |
| 512 | 8 kHz | **`TX_OCT`** | **`CLK_8K`** (= `TX_OCT` on a3) | **a3**, and **a8** as `RX_OCT` | data and PCM cards; the word's '165; the exchange's scanner and monitors |
| 4096 | 1 kHz | — | **`TICK`** | — | the marker and the registers |

**The exchange's cell is not MF8's line bit.** A block commutates eight ports
into one frame at 512 kHz. The MF8 unit converts that highway to a 16-bit
line at 1024 kbps (`mf8-unit.md` §5.2½). `SLOT[2:0]` addresses the commutator
only. A card still sees the same payload taps in both shelves (`TX_CLK`,
`TX_OCT` / `CLK_8K`, `FILL`); the line's `HB` 2.048 MHz stays on the unit.

Two rates on the list are not on the socket and not on any card:

| | | |
|---|---|---|
| `SCLK` | 64 kHz – 512 kHz | the control bus's shift clock, free-running `TX_CLK` on a strap (`mainboard.md` §2.3.2). It is the one clock in the exchange whose rate is a choice |
| `/RING_CAD` | 2 s / 4 s | the ring cadence, low true. A counter off the frame, not a tap |

`RBT` is 64 kb/s of bits, not a clock: the ringback tone as a CVSD stream
(`mainboard.md` §2.1).

---

## 2. Three domains, and only one of them is the crystal's

`mf8-backplane.md` §2 has the domains; this is the same statement with the
exchange folded in.

| domain | where its rate comes from | what lives in it | in the exchange |
|---|---|---|---|
| **T** — transmit | §1's chain, the local crystal | everything a card sends: `C_TX`, `A_TX`, the word, the downstream to a phone | **the only domain below a trunk card** |
| **R** — receive | recovered from the MF8 line, so the *far* shelf's crystal | `C_RX`, `A_RX`, `RX_CLK`, `RX_OCT` | **`RX_CLK` is `TX_CLK`** and `RX_OCT` is `CLK_8K` (`TX_OCT`) one frame late (`fabric.md` §3.4). R exists in an exchange only on a trunk card, which crosses into T with two '174s |
| **S** — the subscriber's own | the phone's clock, loop-timed or free-running (`subscriber-line.md` §7) | the 128 kBaud upstream pair | the same. It never reaches a backplane: the line card's receiver recovers it and re-times into T with two '74 stages (`channel-cards.md` §2.3) |

So a channel card may see three rates and generates none of them. **In an
exchange it sees two**, because T and R are one clock there, and a card that is
correct in MF8 is therefore correct in an exchange by construction — the
crossings it carries simply become crossings between a clock and itself.

The two crystals in a system are ±20 ppm each, up to 40 between neighbours: one
slip every 390 ms at 40 ppm and 780 at 20, measured at 34.6 dB below the clean
decode (`mf8-backplane.md` §7). That is the whole cost of there being two, and it
is the only place in the design where a rate is not a tap of §1.

---

## 3. The rule: no card makes a clock

**Every clock a card uses comes off the socket.** No oscillator, no divider, no
PLL on any channel card, in either shelf.

The MF8 **exchange unit** is the one exception on the exchange side: it owns
the 4.096 MHz that makes line `HB` 2.048 MHz, because that rate is not on
the fabric cable (`mf8-unit.md` §5.5). It is a trunk function, not a
channel card.

The reason is phase, not rate. A 128 kHz divider on a line card would start on a
random phase at power-up, and the downstream encoder's mid-bit transition would
land anywhere in the cell; a 32 kHz `FILL` made on a card would disagree with the
backplane's, and pulling that card would click. Every tap in §1 comes off one
counter, so **any two of them differ by one gate delay and never by a phase**.

Two things on a card are timing but not clocks, and are allowed:

- **the line-card receiver's one-shots** — the '221 and '123 of `mf8-spec.md`
  §9.4, on the rate plug: 11.7 µs classifier, 3.1 µs dead time, 31.3 µs carrier
  timeout. They measure the *subscriber's* clock, which is domain S and not ours
  to generate.
- **a tone card's audio oscillator** (`features.md` §2), which is a tone and
  not a clock.

A third is a divider, not a generator: the **analog tone card's cadence counter**
(`tone-plan.md` §5.2) is a `'4040` off socket `TX_CLK` (a1). Q13 is 256 ms; a
nibble and sixteen jumpers make the 4.096 s on/off mask. That is a tap of the
shelf chain, not a crystal or free-running oscillator on the card.

---

## 4. Where 128 kHz comes from in an exchange

**Resolved: `/SLOT[1]`, one inverter a block, nothing added to cable A.**

`baseband.md` §2.3 raised this once and left it: "`TX_HB`, 128 kHz, is
not on cable A and the CVSD subscriber line card cannot encode without it." It is
the only place in the exchange documents where a CVSD subscriber line card in an
exchange block is considered at all.

`SLOT[2:0]` is already on cable A at every block, counting the eight cells of a
frame at 512 kHz:

```
 cell            0    1    2    3    4    5    6    7
 SLOT[0]         0    1    0    1    0    1    0    1      256 kHz
 SLOT[1]         0    0    1    1    0    0    1    1      128 kHz
 /SLOT[1]        1    1    0    0    1    1    0    0      rises at the frame edge and at mid-frame
 SLOT[2]         0    0    0    0    1    1    1    1
 /SLOT[2]  =  TX_CLK                                       rises at the frame edge
```

So **`TX_HB` = `/SLOT[1]`**: 128 kHz, rising coincident with `TX_CLK`'s rising
edge and again at mid-frame, which is exactly what a differential-Manchester
encoder wants — a transition at the bit boundary and the option of one in the
middle (`mf8-spec.md` §9.2). It is ⅙ of a '04 on each block, and cable A does not
change.

In MF8 the same waveform is the next tap of the trunk card's '4040
(`mf8-backplane.md` §3), which is the same division of the same crystal frequency
with the same phase relationship to `TX_CLK`. **The card cannot tell which shelf
made it**, which is the whole point.

**The contract on pin a2, in both shelves:**

| | |
|---|---|
| rate | 128 kHz, square |
| phase | `TX_HB` ÷ 2 **is** `TX_CLK`, in phase: both rise at the frame edge |
| source | a tap of the same counter that makes `TX_CLK`. Never a separate divider, and never on the card |
| skew | one gate. In the exchange the inverter is at the block, 25 cm from the socket (`mf8-backplane.md` §8) |

The one thing not settled is the polarity and the fine phase against a real
encoder: `baseband.md` §2.3 calls for a scope at bring-up and this does
not change that.

---

## 5. What a channel card may rely on

The six clock pins of the channel socket, and what is guaranteed about each in
**both** shelves:

| pin | signal | rate | guaranteed | differs between shelves? |
|---|---|---|---|---|
| a1 | `TX_CLK` | 64 kHz | rising edge = the start of bit 0; every T-domain output on every card changes on it and only on it | no |
| a2 | `TX_HB` | 128 kHz | §4's contract | source only; same waveform |
| a3 | `TX_OCT` / `CLK_8K` | 8 kHz | one frame wide, at superframe state 7. Exchange name **`CLK_8K`**: the scanner/visit mark, not an 8-bit word width | no |
| a4 | `FILL` | 32 kHz | `TX_CLK` ÷ 2, free-running, **common to the whole shelf** — an unfitted slot and a card must idle on the same phase | no |
| a7 | `RX_CLK` | 64 kHz | the frame reference for everything the card is given | **yes**: recovered in MF8, **is `TX_CLK`** in an exchange |
| a8 | `RX_OCT` | 8 kHz | recovered state 7 | **yes**: `CLK_8K` one frame late in an exchange |

**The last two rows are the only clock difference between the shelves, and none
of the common cards cares**, because each already crosses R to T with its own
flip-flops whatever the two rates are. A data card presents `TXC` and `RXC` to its
DTE as two clocks (`channel-cards.md` §4.2); in an exchange they are one clock, which
is not a degradation but the synchronous case, and is why bit-exact 64 kb/s data
passes inside an exchange and over copper ties (`network.md` §8).

---

## 6. One incoherence worth naming

There are two half-bit clocks in the design and they are the same idea at two
scales — a differential-Manchester encoder's clock at twice its medium's bit
rate:

| | medium | bit rate | half-bit clock | name |
|---|---|---|---|---|
| the MF8 line | one pair between shelves | 1024 kb/s | 2.048 MHz | the unit's `HB` |
| the subscriber loop | two pairs to a phone | 64 kb/s | 128 kHz | `TX_HB` |

`TX_HB`'s name says the domain, which is not the distinction — **both are T** —
and `HB`'s says nothing at all. `LINE_HB` and `LOOP_HB` would say it. This is a
rename across `mf8-spec.md`, `mf8-backplane.md`, `channel-cards.md`,
`mainboard.md` and `baseband.md` and is **not applied**; the names
above stay normative until someone decides the edit is worth it.

---

## 7. Not measured, and what to scope

- **`/SLOT[1]` against a real encoder** (§4): the derivation is arithmetic off
  the cell count. `baseband.md` §2.3 asked for a scope and still does.
- **`TX_HB`'s skew across a block's card side.** `mainboard.md` §5.2 gives
  under 0.1 ns/m conductor to conductor within one ribbon, and the backplane is
  25 cm; nothing has been measured at a socket.
- **The metastability window** where a card's T and an MF8 R edge coincide.
  `mf8-backplane.md` §9 has it as analysis only, and a failure is one bad CVSD
  bit.
- **Whether 256 kHz is wanted by anything.** `SLOT[0]` is the one tap in §1 with
  no customer. If something later needs 256 kHz it is already there, on no pin.
