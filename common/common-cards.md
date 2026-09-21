# The common card set — four cards that plug into either shelf

**Decided: the POTS subscriber/CO converter, the CVSD subscriber line card, the
data card and the E&M subscriber card are one design each, and a card moves
between an MF8 shelf and an exchange block with nothing changed on the circuit.**
Same socket **pinout**, same rails, same clocks, and — when the connector is
settled — the same connector family. **Outline:** MF8 is the **100 × 100 mm
spacer-stack** (`mf8-psu.md`, `mf8-trunk.md`); the exchange block's card outline
may differ so long as the pinout matches.

This was already half true and never stated as a requirement. `mf8-backplane.md`
§8 and `baseband.md` §2.2 gave the same 2 × 16 pin for pin;
`protocol.md` §1 says "a port has the same structure as an MF8 channel"; and
`terminal.md` is the consequence — a stock MF8 shelf of channel cards *is*
eight lines of an exchange, and no card in it knows. What was missing is the short
list of things that stopped it being true in both directions. This document is
that list, resolved.

> **Status: proposed.** Nothing here is newly measured. §5's two behaviours are
> `exch.py calls` 11 and `channel-cards.md` §1 respectively, both already reported;
> everything else is an assignment or an argument. No board has been laid out and
> no connector has been chosen.

The cards, and where each is specified:

| card | | signalling |
|---|---|---|
| **POTS subscriber / CO converter** (FXS / FXO) | `channel-cards.md` §3 — the codec on the card, a hybrid, a loop-start line circuit | loop start, §5's strap |
| **CVSD subscriber line card** | `channel-cards.md` §2 — two pairs to a phone that holds its own codec | hook state from the line's own bit patterns |
| **Data card** | `channel-cards.md` §4 — 64 kb/s synchronous, a DS0, or async oversampled | `DTR` / `DSR` |
| **E&M subscriber card** | `mf8-spec.md` §12.1 — four-wire audio, the codec engine, E and M leads | E and M, which **are** `A_RX` and `A_TX` |

---

## 1. One socket

The channel socket is `mf8-backplane.md` §8's, and this is the single table, with
the exchange's readings of the three pins MF8 reserved folded in. It supersedes
nothing in either document; it joins them.

### 1.1 The pins

Row *a* signals, row *c* power and returns. **The direction is the card's view**:
`in` is the shelf driving the card, `out` is the card driving the shelf.

| pin | a — signals | dir | in an MF8 shelf | in an exchange block | c — power |
|---|---|---|---|---|---|
| 1 | `TX_CLK` | in | 64 kHz, from the trunk card | 64 kHz, from the clock card via the block | `+5 V` |
| 2 | `TX_HB` | in | the '4040 tap | `/SLOT[1]`, one inverter at the block (`clocks.md` §4) | `GND` |
| 3 | `TX_OCT` | in | | | `+5 V` |
| 4 | `FILL` | in | | | `GND` |
| 5 | `C_TX[n]` | **out** | → the trunk card's frame mux, input *n* | → the block's `C` commutator, input *n* | `+12 V` |
| 6 | `A_TX[n]` | **out** | → the signalling mux | → the block's `A` commutator | `GND` |
| 7 | `RX_CLK` | in | recovered | **is `TX_CLK`** | `−12 V` |
| 8 | `RX_OCT` | in | recovered | `TX_OCT` one frame late | `GND` |
| 9 | `C_RX[n]` | in | ← the receiver's '259 | ← the port's capture flip-flop | `−48 V` (fused) |
| 10 | `A_RX[n]` | in | ← the '259, raw | ← the port's supervision gate: E, chopped by the ring cadence while the port rings | `−48 RET` |
| 11 | `MUTE` | in | asserted when not locked | **tied to "locked"**: a block has no link | `GND` |
| 12 | `TYPE0` — **the word** (§2) | **out**, o.d. | not connected | read by the marker's scanner | `RING` (FXS slots only, strapped) |
| 13 | `TYPE1` — **`/ANS`** (§2) | **out**, o.d. | not connected | read by the port's own gates | `RING RET` |
| 14 | `RAI` — spare | **out**, o.d. | not connected | a pull-up at the port; unused | `GND` |
| 15 | key | | | | key |
| 16 | `GND` | | | | `GND` |

### 1.2 A card drives four pins, and only four

| class | pins | driven by | a card may |
|---|---|---|---|
| **common, one net across the shelf** | a1–a4, a7, a8, a11 | the trunk card's 74HC244 in MF8 (`mf8-backplane.md` §8); cable A and the block in an exchange (`mainboard.md` §2.1) | **listen only.** One driver a net; a card that drove one would fight that buffer and corrupt every other slot |
| **per slot, into the shelf** | a5, a6 | the card, 74HC totem-pole into one mux input | drive, always, from the frame it powers up in |
| **per slot, out of the shelf** | a9, a10 | the frame receiver's '259, or the port | listen only |
| **per slot, declarations** | a12, a13, a14 | the card, **open drain**: ¼ 74HC03, or a wire to a row-*c* ground | pull low, or leave open. **Never drive high** |

**Why the two kinds of output differ.** a5 and a6 reach one mux input and
nothing else, so a totem-pole output is right, and a pulled card is covered by
the backplane's idle resistors. a12–a14 face a pull-up at the port
(`fabric.md` §3.5) and must read as *nothing* when the card is out,
mid-insertion, or held off by its power-up RC (§2) — which an output that drives
high cannot do. It is also what lets the same pin be a tied-to-ground constant
on a plain line card and a shifted byte on the card beside it.

**The per-slot count is six.** `C_TX`, `A_TX`, `C_RX`, `A_RX`, the word, `/ANS`
— **6 a slot, 48 a block.** Pin `a14` is spare (a secondary word on it is
retired with `groups.md`). The clocks and the rails are the only common
lines, and the property that matters is unchanged.

### 1.3 What each card does with each pin

The four cards of this document, the tone card of `tone-card.md`, the exchange's
baseband trunk card (`baseband.md` §3.5), and the dual-tone POTS trunk
(`pots-trunk.md` §6), which share the same socket and the same argument.
● = the card uses the pin; ○ = only where the optional '165 is fitted; — = no
connection on the card.

| pin | | CVSD line | FXS | FXO | data | E&M | tone | baseband | pots-t |
|---|---|---|---|---|---|---|---|---|---|
| a1 | `TX_CLK` | ● | ● | ● | ● | ● | ● | ● | ● |
| a2 | `TX_HB` | ● | — | — | — | — | — | — | — |
| a3 | `TX_OCT` | ○ | ○ | ● | ● | ○ | ○ | ● | ● |
| a4 | `FILL` | ● | — | — | — | — | — | — | — |
| a5 | `C_TX[n]` | ● | ● | ● | ● | ● | ● | ● | ● |
| a6 | `A_TX[n]` | ● | ● | ● | ● | ● | low | ● | ● |
| a7 | `RX_CLK` | — | ● | ● | ● | ● | — | — | ● |
| a8 | `RX_OCT` | — | — | — | ● | — | — | — | — |
| a9 | `C_RX[n]` | ● | ● | ● | ● | ● | **—** | ● | ● |
| a10 | `A_RX[n]` | ● | ● | ● | ● | ● | — | ● | ● |
| a11 | `MUTE` | ● | — | — | ● | — | — | — | — |
| a12 | the word | GND | GND | '165 | '165 | GND or '165 | '165, or none at 01–03 | '165 | '165 |
| a13 | `/ANS` | open | open | low | low | open or low | low | low | low |
| a14 | spare | ○ | ○ | ○ | ○ | ○ | ○ | — | — |
| c5, c7 | `±12 V` | — | ● | ● | — | ● | ● | — | ● |
| c9, c10 | `−48 V` | ● | ● | — | — | — | — | — | — |
| c12 | `RING` | — | ● | — | — | — | — | — | — |
| | rear pins (§7.3) | 4 | 2 | 2 | — | 6 | — | 6 | 2 |

The detail behind each column is in that card's own document: `channel-cards.md`
§2.4 for the CVSD line card, §3.7 for both POTS populations, §4 for the data
card, `mf8-spec.md` §12.1 for E&M, `tone-card.md` §4 for the tone card,
`baseband.md` §3.5 for the baseband trunk card, and `pots-trunk.md` §6 for the
dual-tone POTS trunk. The last four rows are the rails, which §3 gives
again with the current each one draws.

Five things the matrix shows that no card's own document can:

- **a2 `TX_HB` has exactly one customer**, and a4 `FILL` has exactly one, and it
  is the same card. `TX_HB` clocks the CVSD line card's differential-Manchester
  encoder and nothing else in the set encodes a line; `FILL` is the pattern that
  card sends downstream to an on-hook phone, and every other card's idle is its
  own codec's `1010`. **Both are on the socket for one card**, which is why
  `clocks.md` §4's derivation had to exist at all.
- **a7 `RX_CLK` is the split in the set.** The cards that hold a codec or a
  bit pipe run their receive side in R on it — FXS, FXO, data, E&M, and the
  dual-tone POTS trunk; the CVSD line card and the baseband card do not use
  it, because each resynchronizes `C_RX` into T with `TX_CLK` and carries the
  crossing on its own flip-flops (`channel-cards.md` §2.3, `baseband.md` §1).
  Those two are therefore the only cards in the set that cannot tell the
  shelves apart at all. The others do see the difference on those two pins —
  recovered in MF8, `TX_CLK` in an exchange — and are indifferent to it, which
  is `clocks.md` §5's point and not a weaker version of it.
- **No card uses more than eleven of the fourteen signal pins**, and the baseband
  card uses eight. Nothing on this socket is oversubscribed.
- **The tone card is the only one that drives and never listens.** a9 is the
  pin no other card can leave open: a talking circuit, a data pipe and a trunk
  all have to hear something. It also explains a10 and a11 in that column —
  nothing rings it, nothing answers it, and an outage it cannot hear is an
  outage it need not handle. In a channel slot it is one port of class
  *source*; at ports 01–03 the marker reaches it by address and it needs
  no word at all (`extensions.md` §2.2).
- **a12 and a13 are where portability was broken** and §2 is the repair; the
  matrix is that section's answer in one column each.

### 1.4 What the socket does not carry

- **A clock out of a channel card.** a7 is an *input*, common to all eight slots
  and driven by the shelf. A channel card cannot put a clock it has recovered
  onto the backplane. On an MF8 shelf that is the trunk card's job from slot 0
  and no channel card wants it; in an exchange it is exactly what
  `baseband.md` §3.2's one-clock strap needs — slaving the clock card to
  a trunk's far-end clock — and **it has no pin**. Either that card takes a wire
  to the clock card that is not on this connector, or the bit-exact synchronous
  case is not available from a channel slot. **Open.**
- **`/HUNT_INH`.** Specified in `marker.md` §4 and `network.md` §3.2,
  in no signal list, driven by nothing in `verilog`. a14 is spare again (the
  secondary word is retired), so it could take this pin if `/HUNT_INH` is ever
  built from a channel slot (§9).
- **The line.** Rows *a* and *c* are fully committed; the subscriber pair, the
  E&M leads, the baseband card's four conductors and the dual-tone POTS trunk's
  tip/ring leave by §7.3's rear connector.
- **`LOCK` and `CD`.** Trunk-card slot to the panel; no channel card needs them
  (`mf8-backplane.md` §8, §7.2 here).
- **Any slot ID**, in either shelf.

One more that is a card gap and not a socket gap, and belongs here because the
matrix is where it becomes visible: **`MUTE` is read by two columns of seven.** The
CVSD line card switches an off-hook phone to `FILL` on it (`channel-cards.md` §2.3)
and the data card forces `RXD` to 1 (§4.1); the FXS, FXO and E&M cards leave a11
open — the tone card has no decoder to mute — so through an outage those three
decoders are fed the cleared '259's all-zeros,
which a CVSD decoder integrates toward the rail rather than the `1010` that is
silence. It is a gate and a mux input to fix, on cards that already carry both.
**Nobody has decided it should be fixed, and nothing has been listened to.**

Three properties hold in both shelves and are what make a card portable at all:

- **No slot-ID pins.** A card never knows where it is (`mf8-backplane.md` §3,
  `baseband.md` §2.1).
- **Point to point, never a bus.** Seven signals a slot, nothing shared, nothing
  addressed, nothing contending; only the clocks and the rails are common.
- **An unfitted slot idles by resistor**: `C_TX[n]` pulled to `FILL` through
  4.7 kΩ and `A_TX[n]` to ground, so a pulled card leaves silence and on-hook
  behind it (`mf8-backplane.md` §6, `fabric.md` §4 — the exchange does the
  same at the commutator input).

**Mechanical.** MF8 channel cards are **100 × 100 mm** stack layers. The exchange
may use the same outline or a taller card behind the same pinout — portability is
electrical. (Eurocard 100 × 160 was the earlier common assumption; superseded for
MF8.)

---

## 2. What a card says about itself

This is the one thing that was genuinely broken, and it was broken one way only.

`extensions.md` §2.1 argues that **an exchange-built card works unchanged in an
MF8 shelf**, because a card only ever pulls a12 and a13 to ground and MF8 leaves
both unconnected. True. The reverse did not hold: an **MF8-built card in an
exchange block** has a12 open, the port's pull-up reads "no word", and the marker
reads class 000 — unequipped. The card is fitted, the phone is live, and nothing
can ever be hunted to it or dialled to it.

**Resolved: every card in the set carries its own word source, and the footprint
is on every board.** One 74HC165 into ¼ of a '03, held off at power-up by an RC
(`extensions.md` §2.2) — ≈ 1¼ packages, shifted by `TX_CLK` and loaded by
`TX_OCT`, both of which are on the socket in both shelves. Two of the four cards
leave it unpopulated and strap a12 to a row-*c* ground instead. In an MF8 shelf
the pin is unconnected either way: a grounded pin goes nowhere, and a populated
'165 shifts its byte into an open circuit, harmlessly, for ever.

**The word's encoding is settled.** `protocol.md` §5 has a plain line card tie
its pin to ground and read "all ones, a line with no options", while
`fabric.md` §3.5's table gives *line* as class 001. Both are right about
different codes, and `groups.md` §2.1's table is the proof:

```
 frame of the octet    0    1  2  3    4  5  6  7
 class and options     0    c  c  c    p  p  p  p     an explicit word: class 001 is a line
 a nail                1    h  h  h    s  s  s  0
 answers to            1    h  h  h    s  s  s  1
 a plain line          1    1  1  1    1  1  1  1     the constant. The pin tied to ground
 nothing               0    0  0  0    0  0  0  0     an empty slot, or a card out of service
```

All ones is a **constant**, not a class field, and it is what a grounded pin
produces. Class 001 is for a card that shifts a word because it has something
else to say. [line_card.v](../verilog/rtl/line_card.v)'s default `WORD` is
`8'hFF`; the marker maps all ones to `C_LINE` beside class 001.

**So, card by card:**

| card | a12 — the word | a13 — `/ANS` | why |
|---|---|---|---|
| CVSD subscriber line | **grounded**: all ones, a plain line | **open**: the port rings | a phone. No part on either pin |
| POTS converter, FXS | **grounded** | **open** | a phone |
| POTS converter, FXO | **'165**, class 100 *outside line* | **tied low** | an outside line must never be rung in cadence, and must not give its caller ringback (`fabric.md` §3.5) |
| Data card | **'165**, class 110 *data line* | **tied low** | so the marker refuses to connect a phone to it (`features.md` §8) |
| E&M, facing a station | **grounded**, or a '165 if it answers to a number | **open** | E rings it |
| E&M, facing a PBX | **'165**, class 100 | **tied low** | a tie to a foreign switch is an outside line, not a network trunk: it carries no direction word and takes no part in the flood |
| Baseband trunk (`baseband.md`) | **'165**, class trunk + direction | **tied low** | a copper tie; `/ANS` low so it never rings |
| Dual-tone POTS trunk (`pots-trunk.md`) | **'165**, class trunk + direction | **tied low** | a voice-band tie on a dry pair; not an FXO |

A card that needs both a class (e.g. *restricted*) and an *answers to* number
cannot say both in one word; that combination is not offered (`groups.md`:
secondary word retired). Use a plain cover member, or the `o` run.

**Cost of the decision.** The data card goes from 4 packages to 5¼ and is no
longer the cheapest card in the shelf (`channel-cards.md` §4.4); the FXO population
gains the same 1¼. The two line cards gain a wire.

---

## 3. Rails, and what each card draws

| | `+5 V` | `±12 V` | `−48 V` | `RING` (c12) |
|---|---|---|---|---|
| CVSD subscriber line | yes | no | **yes** — the 48 V phantom into the downstream centre tap, ≤ 40 mA to the phone | no |
| POTS converter, FXS | yes | **yes** | **yes** — the feed bridge, 25–45 mA | **yes** |
| POTS converter, FXO | yes | **yes** | no | no |
| Data card | yes | no | no | no |
| E&M subscriber | yes | **yes** | no | no |
| Baseband trunk | yes | no | no | no |
| Dual-tone POTS trunk | yes | **yes** — codec, oscillators, notches | no | no |

Both shelves present all of these at every channel socket. `RING` is strapped on
the backplane only to a slot that holds an FXS card, in both shelves, and each
shelf needs its own 20 Hz generator if any such slot is fitted
(`mf8-backplane.md` §8, and the same strap at c12 of a block). A block with no
analog card need not have a generator; **the pins stay either way**, because a
card must be able to arrive.

---

## 4. Clocks

`clocks.md`. In one line: every clock a card uses comes off a1, a2, a3, a4, a7
and a8, every one of them is a tap of the shelf's one 4.096 MHz crystal, **and no
card generates one**. The only difference a card can see between the shelves is
that an exchange's `RX_CLK` *is* its `TX_CLK`, which none of the four cards
notices, because each crosses the two domains with its own flip-flops whatever
their rates.

That is what `baseband.md` §2.3's open item was about, and §4 of
`clocks.md` closes it: `TX_HB` is `/SLOT[1]`, one inverter a block, no new
conductor on cable A. **Without it the CVSD subscriber line card cannot be fitted
in an exchange at all**, which is a strange thing for the project's centrepiece
card and was one bullet away from being noticed.

---

## 5. The one genuine split: what the FXO's `A_TX` means

`channel-cards.md` §3.5 has the FXO card send `A_TX` = *ringing present*, raw.
`features.md` §5 measured that this is wrong in an exchange: the call is set
up on every ring burst and torn down 220 ms into every gap, the operator's phone
rings for 2 s in 6, and the call never survives (`exch.py calls` 11). It wants
*ringing, held by a retriggerable 5 s, OR loop closed*.

**Resolved: one board, one strap — and the strap says what is at the far end, not
which shelf the card is in.**

| strap | `A_TX` is | the far end is | why the other position fails |
|---|---|---|---|
| **OFFICE** | ringing present, raw, in the CO's own cadence | a station card — an FXS, a CVSD line card or an E&M card — extending the line (`channel-cards.md` §1) | with SEIZE, the far phone answers, the FXO closes its loop, `A_TX` rises, and the far card reads that as *ring the phone*. Ring trip would drop it inside 200 ms, so every answered call would start with a 200 ms blast of ringing into the earpiece |
| **SEIZE** | ringing present held 5 s, OR the loop closed | an exchange port, which reads `A_TX` as M and releases the call on its fall (`fabric.md` §3.5) | with OFFICE, `exch.py calls` 11's row: torn down 220 ms into every cadence gap |

Both cases occur in both shelves. An FXO in an exchange block always faces an
exchange port, so SEIZE. An FXO in an MF8 shelf faces **either**: an extended
line to a distant phone is OFFICE, and an outside line at a subscriber terminal —
which `terminal.md` §1 explicitly allows — faces an exchange port across the
link and is SEIZE. So the jumper is not an MF8-versus-exchange jumper, and the
card stays fully interchangeable; it answers a question the installer has to
answer anyway, in the same words in both shelves.

Cost: ½ a '123 and a gate, in the FXO population only.

Outgoing needs nothing in either position: 9 hunts the card, the caller's
off-hook closes the loop through E, and the CO's dial tone comes back on `C`
(`features.md` §5).

---

## 6. A fifth card: the tone card

**Moved to `tone-card.md`.** One generator holding every channel of a shelf on
fast busy — the difference between a dead telephone and a telephone that says no
— outgrew a section here, and what it grew into is not what stood here: it is a
**plain 2 × 16 channel card**, in either shelf, plus a passive strap field on the
MF8 backplane that lets one slot's `C_TX` reach the others' `C_RX`.

What stood here put it in the gateway slot. That was wrong, and worth recording:
the gateway drives `C_TX[n]` and `A_TX[n]` — what a channel card sends *toward
the trunk* — and only into a slot that holds no card (`mf8-pico.md` §3). A phone
hears `C_RX[n]`, which comes off the trunk card's '259. **So a gateway tone card
reaches the exchange, not the phones on its own shelf**, and only for slots with
no card and therefore no phone in them. The drive rule, the six enables and the
`/OE` RC were all machinery for standing in for absent channel cards, which is
the Pico adapter's job and not this one.

What the card takes from this document is unchanged: the channel socket of §1,
the `/ANS` and word rules of §2, and — for the strap field — the `FILL` pull-up
idiom of `mf8-backplane.md` §6. It keeps its column in §1.3's matrix, because it
plugs into the same socket as the other four.

---

## 7. The connectors

### 7.1 The family, which is not settled

`mf8-backplane.md` §8 offers "DIN 41612 half-length or 0.1-inch header" and
chooses neither. **Whatever is chosen must be chosen once**, for both shelves and
for all three slot widths, or this document is void.

The recommendation, for what it is worth: **DIN 41612 type B throughout — rows
*a* and *c*, 16 columns for a channel slot and 32 for the trunk and gateway
slots.** It is one family and one part number per length; the existing pin tables
already name rows *a* and *c* and already reserve a15/c15 as a key, which is the
coding pin; and the 2 × 32 the trunk and gateway slots want is the full-length
part of the same type. The 0.1-inch header is cheaper and is the right answer for
a first breadboard.

Whichever it is, the channel socket keeps §1's pinout unchanged. The two
assignments below are pin *positions*, and survive the choice of shell.

### 7.2 The trunk and gateway slot, 2 × 32

**The exchange unit is not this slot.** It mates collect T and commons C
(`mf8-unit.md` §5). This 2 × 32 is the *shelf's* trunk and gateway header,
now eight C/A pairs.

**An assignment, and eight C/A pairs do not fit the old 2 × 32 count.**
Payload alone is 32 pins. The shelf trunk stays a stack header, eight
wide (`mf8-unit.md` §5, §9). The table below is the six-channel
arithmetic this section first wrote; it does not size the eight-channel
header.

Row *a* of a 2 × 32 holds 32, and one of those wants to be the key. So "row *a*
signals, row *c* power" does not survive here, and the two indicator levels are
the ones to move: they are slow DC to a lamp, they clock nothing, and
`mf8-backplane.md` §3 already says no card needs them.

| row a | | row c | |
|---|---|---|---|
| 1–4 | `TX_CLK`, `TX_HB`, `TX_OCT`, `FILL` | 1, 3 | `+5 V` |
| 5–7 | `RX_CLK`, `RX_OCT`, `MUTE` | 5, 7 | `+12 V`, `−12 V` |
| 8 | key | 8 | key |
| 9–14 | `C_TX[1..6]` | 10, 12 | **`LOCK`, `CD`** |
| 15–20 | `A_TX[1..6]` | 9, 11, 13 | `GND` |
| 21–26 | `C_RX[1..6]` | 14, 16, 18 … 32 | `+5 V` and `GND` alternating, one ground in two across the per-channel half |
| 27–32 | `A_RX[1..6]` | | |

- **The line is not on this connector.** A trunk is one twisted pair each way —
  four conductors — and leaves by §7.3's route, as a channel card's line does.
- **`RAI` is not here either.** x is the remote alarm and it travels in the S bit
  between trunk cards (`mf8-spec.md` §3.5); it reaches the panel as `LOCK` and
  `CD` do, and needs no conductor of its own.
- **The gateway slot is this table with the directions reversed**: a9–a20,
  `C_TX[n]` and `A_TX[n]`, are the card's *outputs* there, and everything else is
  an input. Same shell, same positions, so a trunk card and a gateway card cannot
  be told apart by the connector — **key them differently**, or one seated in the
  other's slot fights every channel card in the shelf.

### 7.3 The line side

**An assignment, and it fills a gap: no document says how a subscriber pair
physically leaves a card.** Rows *a* and *c* of the 2 × 16 are fully committed —
16 signals and 16 power pins, `RAI` and the key included — so the line cannot go
there without breaking the one pinout this whole document rests on.

**A second connector at the rear edge, at the opposite end from the 2 × 16**,
into a shelf wiring field:

| card | pins | |
|---|---|---|
| POTS converter, FXS or FXO | 2 | tip, ring |
| CVSD subscriber line card | 4 | downstream pair, upstream pair — both carrying the 48 V phantom |
| E&M subscriber card | 6 | audio pair each way, E, M |
| Data card | — | none: its DTE cable is RS-422 or RS-232 and belongs on the front edge, where a person plugs it in |
| Baseband trunk card (`baseband.md`) | 6 | `C`, A and the link clock each way — 4 if §3.3's clock conductor is not fitted. In the RS-422 population these are three pairs each way, 12 conductors, and the card is the only one in the set whose "line" is another shelf's backplane |
| Dual-tone POTS trunk (`pots-trunk.md`) | 2 | tip, ring — dry pair, no feed; same leave as FXS/FXO, different circuit |
| Trunk card (§7.2) | 4 | a pair each way |

Two reasons for the rear and for the far end of it:

- **Creepage and clearance.** This is where `−48 V`, ~80 Vrms ringing and
  outside-plant surges meet the shelf, and `channel-cards.md` §3.6 asks for the line
  side and the logic side to be kept apart. Putting the two connectors at
  opposite ends of the rear edge is the cheapest way to have that be true by
  construction rather than by layout discipline.
- **Where plant belongs.** Forty-eight subscriber pairs hanging off the front of
  a subrack is not an installation. The front edge is for the data card's DTE
  cable, for `LOCK` and `CD` if they end up as lamps on the trunk card, and for
  nothing else.

**It is per card, not per slot**, which means the backplane carries no line
conductors at all and the wiring field can be re-punched without touching it.

---

## 8. What this changes in other documents

| document | |
|---|---|
| `mf8-backplane.md` §8, `baseband.md` §2.2 | joined into §1 here. Neither is wrong; there were two copies |
| `verilog/README.md`, "the word's encoding" | **closed** (§2). All ones is the constant *plain line*, from a grounded pin; class 001 is an explicit word. `line_card.v`'s default `WORD` is `8'hFF`; the marker treats both as `C_LINE` |
| `baseband.md` §2.3, first bullet | **closed** (`clocks.md` §4). `TX_HB` = `/SLOT[1]`, one inverter a block |
| `channel-cards.md` §3.5 | the FXO gains §5's strap. `features.md` §5's "the exchange build of the FXO card" becomes the SEIZE position of that strap, not a second board |
| `channel-cards.md` §4.4 | the data card is 5¼ packages, not 4, and no longer the cheapest card in the shelf |
| `channel-cards.md` §2.5, §3.8 | each parts list gains the word footprint: ≈ 1¼ where it is populated, a wire where it is not |
| `channel-cards.md` §2, §3 | each card gains a pin section — **§2.4** for the CVSD line card, **§3.7** for both POTS populations — and Parts and Bring-up move down one |
| `baseband.md` §2.2, §3.5 | §2.2 becomes a pointer here, its table having been the second copy; **§3.5** is new and gives the baseband card's own pins, with Parts moved to §3.6 |
| `extensions.md` §2.1 | its "a card built for the exchange works unchanged in an MF8 shelf" now holds in both directions, and §2 here says what it costs |
| `mf8-backplane.md` §8, the trunk and gateway slots | given pins (§7.2), which they never had. **Its "row *a* signals, row *c* power" does not hold there** — the signal set is 33 and row *a* is 32 — so `LOCK` and `CD` move to row *c*. The two slots also need different keying, which §8 does not mention |
| `channel-cards.md` §2, §3; `subscriber-line.md` §1 | the subscriber pair leaves by a second rear connector (§7.3), which no document had. The backplane carries no line conductors |
| §6, the tone card | **moved to `tone-card.md`**, and **corrected**: the gateway-slot population it described cannot reach the phones on its own shelf, and is replaced by the plain channel card plus `tone-card.md` §4's strap field |
| `mf8-backplane.md` §6, §8 | **owed a change they do not carry**: `tone-card.md` §4's tone bus, its 4.7 kΩ to `FILL`, the per-slot `C_RX` select and the shelf-wide `MUTE` select are a backplane modification specified in neither |

---

## 9. Not measured, and open

- **Every card.** Nothing in the set has been on a bench; `channel-cards.md` §6 and
  `mf8-spec.md` §15 hold unchanged.
- **The connector family** (§7.1), and with it the keying `mf8-backplane.md` §6
  recommends for data cards (not C0 and C7 together).
- **§7.2 and §7.3 are assignments**, worked from the signal lists and from where
  high voltage has to be kept: no board, no connector in hand, nothing measured.
  What they are good for is that the arithmetic has been done once — 33 signals
  against 32 pins, and a line that has nowhere to go on a committed socket.
- **Keying the trunk slot against the gateway slot** (§7.2). They are the same
  shell with `C_TX` and `A_TX` reversed in direction, so a card in the wrong one
  drives into eight channel cards. Nothing in `mf8-backplane.md` or `mf8-pico.md`
  prevents it today.
- **`/SLOT[1]`'s phase against a real encoder** (`clocks.md` §7).
- **The FXO strap's 5 s constant** (§5): `features.md` §5 measured that 5 s
  works against a 2 s / 4 s cadence and did not sweep it. A CO with a longer
  silent interval would want more.
- **The tone card**: its own open items moved with it to `tone-card.md` §7.
- **§1.3's matrix is an assignment too.** Every ● and — is read off the card's
  own description, not off a board. Two columns are the least sure: the E&M
  card has never had a pin list of its own (`mf8-spec.md` §12.1 describes an
  engine and two leads), and the tone card's channel-slot population is worked
  no further than `tone-card.md` §4.
- **A recovered clock has no pin out of a channel slot** (§1.4). It costs
  `baseband.md` §3.2's bit-exact case, which is the one case that
  carries synchronous 64 kb/s data between exchanges. Either a wire off the
  card's rear connector to the clock card, or that case stays an MF8
  trunk-card one. **Undecided, and it is a decision and not a measurement.**
- **`MUTE` on the FXS, FXO and E&M cards** (§1.4): two cards of six read a11,
  and what the other three's decoders do through an outage has not been
  listened to.
- **`/HUNT_INH`**, still specified in three documents, present in no signal list
  and driven by nothing (`baseband.md` §2.3). a14 is spare again (the
  secondary word retired), so it is available if `/HUNT_INH` is ever built from
  a channel slot.
- **A dialled port whose class is trunk or outside line**, which
  `marker.md` does not cover and the `calls` model does not have.
