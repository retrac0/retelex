# The channel socket and the common cards

Every channel card plugs into one socket: a slot of an MF8 shelf, or, in an
exchange, the J4 edge header of its port card. This document is that socket
pin by pin, what each card does with each pin and says about itself, the
rails, the FXO card's jumper and the connectors. The cards' circuits are
`channel-cards.md` and `mf8-spec.md` §12.1 (E&M); the port card is
`block-stack.md` §2.2.

> **Built:** the socket as a port list in `newimpl/rtl/cvsd_line_card.v` and `baseband_card.v` (`tb_line`, `tb_tie`); the block's side as J4 on `pcb/portcard`.
> **Proposed:** every card here; the shelf's connector family.
> **Measured in:** nothing new; §5's FXO behaviour is `exch.py calls` 11.

---

## 1. One channel socket

### 1.1 The pins

Row *a* signals, row *c* power. **Direction is the card's view.** On the
port card's J4 (a shrouded, keyed 2 × 17 IDC, `block-stack.md` §5) a*n* is
pin 2*n* − 1, c*n* is pin 2*n*, and pins 33–34 are ground.

| pin | a | dir | in an MF8 shelf | in an exchange block | c, shelf | c, on J4 |
|---|---|---|---|---|---|---|
| 1 | `TX_CLK` | in | from the trunk card | `/SLOT2`, made on the block header | +5 V | +5 V |
| 2 | `LOOP_HB` | in | the '4040 tap | `/SLOT1`, made on the header (`clocks.md` §4) | GND | GND |
| 3 | `TX_OCT` | in | | `SCAN[2:0]` = 7, on the header | +5 V | +5 V |
| 4 | `FILL` | in | | `SCAN0` | GND | GND |
| 5 | `C_TX` | **out** | → the frame mux | → the port card's ringback '157, then lane `C_TXk` | +12 V | **NC** |
| 6 | `A_TX` | **out** | → the signalling mux | M: the port's drain on `/HA` in its turn | GND | GND |
| 7 | `RX_CLK` | in | recovered | **is `TX_CLK`** | −12 V | **NC** |
| 8 | `RX_OCT` | in | recovered | `TX_OCT` a frame late | GND | GND |
| 9 | `C_RX` | in | ← the receiver's '259 | ← the port's C capture | −48 V, fused | **NC** |
| 10 | `A_RX` | in | ← the '259, raw | ← the port's gate: E, chopped by the cadence while the port rings (`fabric.md` §5.2) | −48 RET | **NC** |
| 11 | `MUTE` | in | asserted when not locked | **tied to "locked"** | GND | GND |
| 12 | card word | **out**, o.d. | NC | lane `WORDk`, read on `/HW` by whoever selects the port (`fabric.md` §4) | RING, FXS slots only | **never** |
| 13 | `/ANS` | **out**, o.d. | NC | the port's own gates (`fabric.md` §5.2) | RING RET | **never** |
| 14 | spare (`RAI`) | **out**, o.d. | NC | a pull-up; unused | GND | GND |
| 15 | key | | | | key | key |
| 16 | GND | | | | GND | GND |

**No rail above +5 V passes through a port card**: in a block, ±12 V, −48 V
and ringing reach a subscriber card on its own harness (§3).

### 1.2 A card drives four pins, and only four

| pins | driven by | a card may |
|---|---|---|
| a1–a4, a7, a8, a11: common | the trunk card's '244 in a shelf; the port card's '244 and 33 Ω in a block | **listen only** |
| a5, a6: per slot, in | the card, totem-pole, into one input | drive, from the frame it powers up in |
| a9, a10: per slot, out | the receiver's '259, or the port | listen only |
| a12–a14: declarations | the card, **open drain**: a 2N7002, or a wire to a row-*c* ground | pull low or leave open; **never drive high** |

a12–a14 face a ~680 Ω pull-up at the port and must read as *nothing* when the
card is out, half in or held off by its power-up RC, so the same pin can be a
grounded constant on one card and a shifted word on the next. The rise into
~1 nF is under a microsecond against a 15.6 µs bit.

### 1.3 What each card does with each pin

● uses the pin; ○ only where the optional '165 word is fitted; — nothing.

| pin | | CVSD line | FXS | FXO | data | E&M | tone | baseband | pots-t |
|---|---|---|---|---|---|---|---|---|---|
| a1 | `TX_CLK` | ● | ● | ● | ● | ● | ● | ● | ● |
| a2 | `LOOP_HB` | ● | — | — | — | — | — | — | — |
| a3 | `TX_OCT` | ○ | ○ | ● | ● | ○ | ○ | ● | ● |
| a4 | `FILL` | ● | — | — | — | — | — | — | — |
| a5 | `C_TX` | ● | ● | ● | ● | ● | ● | ● | ● |
| a6 | `A_TX` | ● | ● | ● | ● | ● | low | ● | ● |
| a7 | `RX_CLK` | — | ● | ● | ● | ● | — | — | ● |
| a8 | `RX_OCT` | — | — | — | ● | — | — | — | — |
| a9 | `C_RX` | ● | ● | ● | ● | ● | — | ● | ● |
| a10 | `A_RX` | ● | ● | ● | ● | ● | — | ● | ● |
| a11 | `MUTE` | ● | — | — | ● | — | — | — | — |
| a12 | card word | GND | GND | '165 | '165 | GND or '165 | '165, or none at 01–03 | '165 | '165 |
| a13 | `/ANS` | open | open | low | low | open or low | low | low | low |
| a14 | spare | — | — | — | — | — | — | — | — |
| c5, c7 | ±12 V † | — | ● | ● | — | ● | ● | — | ● |
| c9, c10 | −48 V † | ● | ● | — | — | — | — | — | — |
| c12 | `RING` † | — | ● | — | — | — | — | — | — |
| | rear pins (§6.3) | 4 | 2 | 2 | — | 6 | — | 6 | 2 |

† On a shelf these rails are socket pins; on J4 they are not connected, and
the card takes them from the harness (§3). Each column's detail is its card's
document (`channel-cards.md` §2–§4, `mf8-spec.md` §12.1, `common/tones.md`,
`trunks.md` §2, `proposed/pots-trunk.md`).

**a2 and a4 serve the CVSD line card alone**: `LOOP_HB` clocks its encoder
and `FILL` is what it sends an on-hook phone; a word shifts on a1 and loads on
a3 (§2). **a7 splits the set**: the CVSD line and baseband cards re-time
`C_RX` into T themselves and cannot tell a shelf from a block. **The tone card
drives and never listens**; at 01–03 it needs no word (`common/tones.md`). No card uses more than
eleven signal pins.

### 1.4 What the socket does not carry

A clock out of a card (a7 is a common input, and clock slaving is set aside,
`network.md` §9); the line (§6.3); `LOCK` and `CD` (§6.2); and **any slot ID**:
a card never knows where it is, and in a block the port card knows its slot by
its own jumper (`block-stack.md` §4). **Six signals a slot, point to point**:
only clocks and rails are common. **An empty slot idles by resistor**: `C_TX`
4.7 k to `FILL`, `A_TX` pulled down, a12–a14 up, so a pulled card leaves
silence, on-hook and no word (in a block, on the port card at J4).

---

## 2. What a card says about itself

Two pins: **a12, the card word** (encoding `card-word.md` §2) and **a13,
`/ANS`**, open if the port rings (`fabric.md` §5.2). **Every card carries its
own word source, and the footprint is on every board**: one 74HC165 into a
2N7002, held off at power-up by an RC on the FET gate, shifted on `TX_CLK`
and loaded in frame 7 on `TX_OCT` · `TX_CLK`: the primary octet at 64 kbps
(`card-word.md` §3). A card with nothing to say leaves it out and grounds a12:
all ones, a plain line. A shelf connects neither pin, so a card built for
either home works in both.

| card | a12, card word | a13, `/ANS` | why |
|---|---|---|---|
| CVSD subscriber line | **grounded** | **open** | a phone |
| POTS converter, FXS | **grounded** | **open** | a phone |
| POTS converter, FXO | '165, *outside line* | **low** | never rung in cadence, no ringback to its caller |
| data card | '165: a tied nail to the far card of its circuit (`card-word.md` §6.2), or *line* with `D` (`card-word.md` §4) | **low** | `DSR` follows `DTR`; no marker pairs it with a voice port |
| E&M, facing a station | **grounded**, or a '165 if it answers to a number | **open** | E rings it |
| E&M, facing a PBX | '165, *outside line* | **low** | a foreign switch takes no part in the flood |
| baseband trunk | '165, *trunk*, glare and direction, gated by its link | **low** | `trunks.md` §2 |
| dual-tone POTS trunk | '165, *trunk* | **low** | a voice-band tie on a dry pair |

A card that needs a class and an answers-to number at once needs the
secondary byte, which no reader takes yet (`card-word.md` §7).

---

## 3. Rails, and what each card draws

| | +5 V | ±12 V | −48 V | `RING` |
|---|---|---|---|---|
| CVSD subscriber line | yes | no | **yes**: the phantom, ≤ 40 mA | no |
| POTS converter, FXS | yes | **yes** | **yes**: feed bridge, 25–45 mA | **yes** |
| POTS converter, FXO | yes | **yes** | no | no |
| data card | yes | no | no | no |
| E&M subscriber | yes | **yes** | no | no |
| baseband trunk | yes | no | no | no |
| dual-tone POTS trunk | yes | **yes** | no | no |

**An MF8 shelf** presents every rail at every slot, `RING` on c12 jumpered
only to FXS slots, with a 20 Hz generator only if one is fitted. **An
exchange block** presents +5 V and ground on J4 only; the rest reach the
subscriber card on the fused harness, to blocks with analogue cards only
(`bus.md` §2.3).

---

## 4. Clocks

Every clock a card uses comes off a1–a4, a7 and a8, and no card makes one
(`clocks.md` §3, §5). A block's `RX_CLK` is its `TX_CLK`; no card here notices.

---

## 5. The FXO jumper: what `A_TX` means

An FXO sending `A_TX` = *ringing present*, raw, is set up on every ring burst
and torn down 220 ms into every gap by an exchange port, which releases on M's
fall (`exch.py calls` 11). **One jumper, saying what is at the far end:**

| jumper | `A_TX` is | the far end is | the other position would |
|---|---|---|---|
| **OFFICE** | ringing present, raw | a station card extending the line | with SEIZE, ring the far phone for up to 200 ms after it answers |
| **SEIZE** | ringing held by a retriggerable 5 s, OR the loop closed | an exchange port | with OFFICE, drop the call in every cadence gap |

In a block an FXO faces an exchange port: SEIZE. In a shelf, an extended line
is OFFICE and an outside line at a subscriber terminal is SEIZE. Cost: ½ '123
and a gate. Outgoing needs neither: the caller's off-hook closes the loop
through E (`features.md` §4).

---

## 6. The connectors

### 6.1 The family

A block's card reaches its port card's J4 by a ribbon of 0.3 m or less
(`block-stack.md` §5). The MF8 shelf has not chosen: DIN 41612 type B (rows
*a*, *c*; 16 columns a channel slot, 32 a trunk slot) or a 0.1-inch header.
Either way §1.1's pinout holds, and §6.2–§6.3 are positions, not shells.

### 6.2 The shelf's trunk and gateway slot, 2 × 32

The exchange's MF8 unit is a block adapter instead (`trunks.md` §4). Row *a*
holds 32 with the key, so `LOCK` and `CD`, slow lamp levels, go to row *c*;
`RAI` rides the S bit and needs no pin.

| row a | | row c | |
|---|---|---|---|
| 1–4 | `TX_CLK`, `LOOP_HB`, `TX_OCT`, `FILL` | 1, 3 | +5 V |
| 5–7 | `RX_CLK`, `RX_OCT`, `MUTE` | 5, 7 | +12 V, −12 V |
| 8 | key | 8 | key |
| 9–14 | `C_TX[1..6]` | 10, 12 | `LOCK`, `CD` |
| 15–20 | `A_TX[1..6]` | 9, 11, 13 | GND |
| 21–26 | `C_RX[1..6]` | 14–32 | +5 V and GND alternating |
| 27–32 | `A_RX[1..6]` | | |

**The gateway slot is this table with directions reversed**, so the two must
be keyed apart, or a card in the wrong one fights every channel card.

### 6.3 The line side

The line leaves by **a second connector at the rear edge, at the far end from
the signal connector**, into a wiring field, keeping −48 V, ringing and surges
away from the logic by construction. It is per card, so the backplane carries
no line conductor.

| card | pins | |
|---|---|---|
| POTS converter, FXS or FXO | 2 | tip, ring |
| CVSD subscriber line | 4 | downstream and upstream pairs, both carrying the phantom |
| E&M subscriber | 6 | audio pair each way, E, M |
| data card | — | its DTE cable is on the front edge |
| baseband trunk | 6 | C, A and the link clock each way (`trunks.md` §2) |
| dual-tone POTS trunk | 2 | tip, ring, a dry pair |
| shelf trunk card | 4 | a pair each way |

---

## 7. Open

- **One card, two ways in.** In a shelf a card takes signals from a backplane
  connector and rails from row *c*; in a block, signals from a ribbon to J4
  and rails from a harness. Whether each card carries both entries, or a shelf
  adapter bridges them, is undecided, and it blocks any card meant to move
  between the two unchanged.
- **The shelf's connector family** (§6.1) and the keying of its trunk slot
  against its gateway slot (§6.2).
- **`MUTE` on the FXS, FXO and E&M cards**, which leave a11 open:
  `channel-cards.md` §6.
- **The FXO jumper's 5 s** was not swept; a CO with a longer silence wants
  more.
- **§1.3 is an assignment**, read off each card's description; the E&M card
  has no pin list of its own.
