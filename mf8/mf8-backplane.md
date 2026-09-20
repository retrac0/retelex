# MF8 backplane — modules, interfaces and clocking

The exchange is a trunk card, six channel slots and a passive backplane. This
document defines every interface along the chain

```
phone ══ two pairs ══▶ subscriber line ─▶ channel ─▶ ║ backplane ║ ─▶ trunk TX ══ trunk pair ══▶
                 I1                    I2         I3             I4                I5

  ══▶ trunk RX ─▶ ║ backplane ║ ─▶ channel ─▶ subscriber line ══ two pairs ══▶ phone
       I5'         I3'              I2'                    I1'
```

with its inputs and outputs, its clock domain and its timing. The frame, the
framer, the line and the cards themselves are `mf8-spec.md`; the subscriber
line is `subscriber-line.md`. What is new here is the backplane, the slot
interface, and where the three clocks in the system meet.

> **Status: proposed, analysis except where marked measured.** The timing
> margins are computed from data-sheet figures and the frame geometry, not
> scoped. The one thing measured is the cost of the plesiochronous slip (§7),
> because it decides the clocking design.

---

## 1. Modules

| module | one per | what it does | specified in |
|---|---|---|---|
| **Subscriber line** (SL) | phone | the two pairs: transformers, 48 V phantom feed, a 128 kBaud differential-Manchester driver, the §9.4 receiver at the 64 kbps plug, and the hook and ring detectors | `subscriber-line.md` §§1–3 |
| **Channel** (CH) | slot | the slot logic: relays bits between the subscriber line and the slot, retimes across clock domains, applies MUTE, and holds the exchange-side rule of `subscriber-line.md` §4 | this document §4, §5 |
| **Trunk card** (TC) | exchange | the transmitter of `mf8-spec.md` §10 and the receiver of §11 on one card, slot 0. It owns the crystal | `mf8-spec.md` §§9–11 |
| **Backplane** | exchange | passive: dedicated per-slot lines, shared clocks, power | this document §2, §3, §8 |

The subscriber line and the channel are drawn as two modules because their
interface (I2) is worth fixing: the same slot takes the other cards
`mf8-spec.md` §12 defines — the CVSD E&M card, where I2 is four-wire audio and
E&M leads to some other equipment, and the data card, where I2 is a synchronous
DTE interface. On a line card they share a board.

---

## 2. Clock domains — the design decision

There are three clocks in the system, and every signal on the backplane belongs
to exactly one of them.

| domain | source | rate | on the backplane as |
|---|---|---|---|
| **T** — transmit | the trunk card's 4.096 MHz crystal, through the `mf8-spec.md` §9.1 chain | 512 kHz line, 64 kHz frame, 8 kHz superframe | `TX_CLK`, `TX_HB`, `TX_OCT`, `FILL` |
| **R** — receive | recovered from the trunk pair by the §9.4 classifier: transition-timed, no clock | 64 kHz frame, 8 kHz superframe, nominal | `RX_CLK`, `RX_OCT`, `C_RX`, `A_RX`, `MUTE` |
| **P** — each phone | the phone's upstream, recovered at the line card by its own §9.4 receiver; one per line, loop-timed to T if the phone loop-times, free-running otherwise | 64 kHz bit strobe | never on the backplane |

**Rule.** A card's transmit half lives in T and its receive half in R, and the
two halves share nothing but power. The only places domains meet are inside a
line card, at two defined points:

| crossing | from → to | where | what happens at 100 ppm |
|---|---|---|---|
| **downstream** | `C_RX[n]` (R) → the phone's downstream (T) | the line card samples `C_RX[n]` on `TX_CLK` through a two-stage synchronizer | one CVSD bit dropped or doubled every **156 ms** |
| **upstream** | the phone's `Q` (P) → `C_TX[n]` (T) | the line card samples its receiver's data latch on `TX_CLK` through a two-stage synchronizer | none if the phone loop-times from its downstream (P = T, phase wander only); the same 156 ms slip if the phone free-runs |

A data card has no crossing: its DTE takes `TX_CLK` for transmit data and
`RX_CLK` for receive data, as V.35 and X.21 interfaces do, and gets a slip-free
pipe at the price of accepting two clocks. A CVSD E&M card has none: the encoder
is in T, the decoder in R.

**Why plesiochronous and not loop-timed.** The alternative is to make one end
of the trunk the slave and run its whole exchange from the recovered clock. The
§9.4 receiver has no clock to give — it times intervals — so that end would need
a PLL locked to the transition strobes (`line-codes.md` §2.2 C), and every phone
on it would lose its downstream clock whenever the trunk did. Plesiochronous
timing costs one slip per channel per 156 ms at 100 ppm, per 780 ms at 20 ppm,
and §7 measures that slip at **−30 dB below speech for about a millisecond**,
34 dB against the clean decode: below anything the codec itself does. And the exchange keeps
its phones clocked, idle-patterned and ringable with the trunk down. `RX_CLK`
is on the bus anyway, so a slave trunk card with a PLL could take T from R
later without a change to any channel card.

**Metastability.** Both crossings sample a signal that changes asynchronously.
A 74HC74 pair clocked at 64 kHz has a mean time between failures of years for
any resolution window in the family, and a failure costs one wrong CVSD bit —
the same −25 dB event as a slip. The two stages are specified anyway; they are
half a package.

---

## 3. Backplane signals

All logic is 74HC at 5 V. Per-slot lines are point-to-point between slot *n*
and the trunk card; the clocks and `MUTE` are multi-drop with six loads.

| signal | driver | loads | domain | rate | meaning |
|---|---|---|---|---|---|
| `TX_CLK` | TC | all slots | T | 64 kHz | the frame clock. Rising edge = the start of bit 0 (F). Every T-domain output on every card changes on this edge and only on it. Also the subscriber line's bit clock |
| `TX_HB` | TC | line cards | T | 128 kHz | half-bit clock for the subscriber line's differential-Manchester encoder — the next tap of the same '4040 chain |
| `TX_OCT` | TC | PCM and data cards | T | 8 kHz | one frame wide, at superframe state 7: the octet boundary (`mf8-spec.md` §6) |
| `FILL` | TC | every `C_TX` through 4.7 kΩ | T | 32 kHz | `TX_CLK` ÷ 2 — one bit per frame alternating, the `1010` empty-slot fill of §12.3 |
| `C_TX[n]` | slot *n* | TC frame mux input *n*'s bit | T | 64 kb/s | slot *n*'s channel bit for this frame |
| `A_TX[n]` | slot *n* | TC signalling mux | T | level | slot *n*'s signalling bit: OFF-HOOK on a line card, the M lead on an E&M card. Sampled once per superframe |
| `RX_CLK` | TC | all slots | R | 64 kHz nominal | the recovered frame clock: rising edge = the receiver's bit-count wrap, after all six `C_RX` have been written |
| `RX_OCT` | TC | PCM and data cards | R | 8 kHz nominal | recovered superframe state 7 |
| `C_RX[n]` | TC, a 74HC259 | slot *n* | R | 64 kb/s | slot *n*'s received bit; written during bit *n*'s time, stable by `RX_CLK` |
| `A_RX[n]` | TC, the §11 '259 | slot *n* | R | level | slot *n*'s received signalling bit, raw. The §14 RC and Schmitt are on the card |
| `MUTE` | TC | all slots | R | level | asserted when not locked or no carrier (`mf8-spec.md` §13). Audio outputs muted, data `RXD` forced 1, line cards send `1010` |
| `LOCK`, `CD` | TC | front panel, test | R | level | as §13; no card needs them |
| `RAI` | — | — | — | — | one pin reserved for `mf8-spec.md` §3.5's seventh S bit; not connected |
| `+5 V`, `GND` | PSU | all | | | logic |
| `±12 V` | PSU | E&M cards, comparators | | | analog |
| `−48 V`, `−48 RET` | PSU | line cards, FXS cards, fused per slot | | | the phantom feed of `subscriber-line.md` §1; the battery feed of `channel-cards.md` §3.4 |
| `RING`, `RING RET` | a shelf ring generator on the PSU slot | FXS slots only, by a strap on the backplane per slot | | 20 Hz, ~90 Vrms | the ringing bus of `channel-cards.md` §3.4; never reaches a line, data or E&M card |

Two things are deliberately absent. **No slot-ID pins:** slot *n*'s `C_TX`,
`A_TX`, `C_RX` and `A_RX` are wired to input and output *n* of the trunk card's
muxes and latches, so a card need not know where it is — this is the "layout,
not logic" of `mf8-spec.md` §10, carried onto the backplane. **No serial channel
bus:** the receiver's '259 gives every slot its own line for the cost of one
package on the trunk card and nothing on any channel card.

---

## 4. The interfaces, module by module

Each table is one module's view: what it takes in, what it puts out, and the
domain and timing of each.

### I1 — the subscriber line (SL ↔ phone)

`subscriber-line.md` §1, unchanged: two pairs, 64 kbps differential Manchester
at 128 kBaud each way, the exchange transmitting continuously, 48 V on the
phantom. Signalling is the held patterns of §2 of that document.

### I2 — subscriber line ↔ channel (inside a line card)

| signal | direction | domain | timing | meaning |
|---|---|---|---|---|
| `UP_Q` | SL → CH | P | valid at `UP_STB` | the phone's data bit, from the §9.4 receiver's data latch |
| `UP_STB` | SL → CH | P | transition-timed, ~64 kHz | the receiver's bit strobe |
| `ON_HOOK` | SL → CH | level | 4 ms RC, comparator 0.85 / 0.70 | the `1100` detector of `subscriber-line.md` §3 |
| `DN_D` | CH → SL | T | changes on `TX_CLK` | the bit to send to the phone |
| `TX_CLK`, `TX_HB` | CH → SL | T | | the encoder's bit and half-bit clocks, straight from the bus |
| `UP_CD` | SL → CH | level | 2 cells | carrier on the upstream (§9.6); folded into `ON_HOOK` by the detector's violation term, kept for the panel |

For the **E&M card**, I2 is four-wire audio at the level `mf8-spec.md` §12.1's
step size is tuned for, M in and E out. For the **data card**, I2 is `TXD` in on
`TX_CLK`, `RXD` out on `RX_CLK`, both clocks out, and `RXD` forced 1 by `MUTE`.

### I2' — channel → subscriber line, the exchange-side rule

The channel module implements `subscriber-line.md` §4 with the bus signals:

```
DN_D     =  ON_HOOK ?  ( A_RX[n] ? all-zeros : 1010 )  :  C_RX[n] synchronized to T
C_TX[n]  =  UP_Q synchronized to T           (the 1100 pattern passes through as bits)
A_TX[n]  =  NOT ON_HOOK
MUTE     →  DN_D = 1010 regardless, A_RX[n] reads 0 (the '259 is cleared)
```

`A_RX[n]` goes through the §14 RC (τ = 2 ms) and Schmitt before it is used;
`ON_HOOK` already has its own 4 ms filter. The phone's `1100` on-hook pattern
travels the trunk as ordinary channel bits and is decoded again at the far
exchange's line card, so hook state reaches the far end twice — as the A bit,
which is what the far line card ringing logic uses, and in band, which nothing
uses.

### I3 — slot ↔ trunk card, transmit

| at the trunk card | in / out | domain | timing |
|---|---|---|---|
| `C_TX[1..6]` | in, to '151 inputs 1, 2, 3, 5, 6, 7 | T | sampled during bit `CBIT[n]` of each frame (§5) |
| `A_TX[1..6]` | in, to the signalling '151 inputs 1, 2, 3, 5, 6, 7 | T | sampled at bit 4 of the frame at superframe state `CBIT[n]` |
| `TX_CLK`, `TX_HB`, `TX_OCT`, `FILL` | out | T | from the '393 chain, buffered |

The signalling mux and the frame mux use the same input numbering because the
guard sits at states 0 and 4 (`mf8-spec.md` §3.2): the S superframe mirrors the
frame, so slot *n*'s A bit is at superframe state `CBIT[n]` as its C bit is at
frame bit `CBIT[n]`.

### I4, I5 — the trunk pair

`mf8-spec.md` §9.3 at the transmitter and §9.3–9.4 at the receiver, unchanged.

### I3' — trunk card ↔ slot, receive

| at the trunk card | in / out | domain | timing |
|---|---|---|---|
| `C_RX[1..6]` | out, a 74HC259 addressed by the receiver's bit counter, D = the recovered data, write = the recovered bit strobe | R | output *n* written during bit `CBIT[n]`; all six written before `RX_CLK` |
| `A_RX[1..6]` | out, the §11 '259 addressed by the superframe counter, written at bit 4 | R | output *n* written at superframe state `CBIT[n]`; cleared while not locked |
| `RX_CLK`, `RX_OCT` | out | R | from the receiver's counters |
| `MUTE`, `LOCK`, `CD` | out | R | §13 |

The C-bit '259 is the one package the backplane adds to `mf8-spec.md` §11's
list: ≈ 11 on the trunk card.

### I2', I1' — receive side of the line card

The mirror of I2: `C_RX[n]` and `A_RX[n]` in from the bus, `DN_D` out to the
subscriber-line encoder, on the rule above.

---

## 5. Timing

At 512 kbps a line bit is 1.953 µs, a frame 15.625 µs. Data-sheet figures at
5 V: 74HC74 clock-to-Q ≈ 25 ns, '151 select-to-output ≈ 40 ns, '259 address or
data to output ≈ 40 ns, '393 ripple ≈ 20 ns a stage, backplane ≈ 2 ns.

**Transmit.** A card changes `C_TX[n]` on the rising edge of `TX_CLK`, which is
the start of bit 0. The trunk card's mux selects input *n* during bit `CBIT[n]`
and the encoder needs the bit by mid-cell for the differential-Manchester
decision. So:

| | first use of a new `C_TX` | last use of the old one |
|---|---|---|
| slot 1, bit 1 | mid-cell of bit 1 = **2.93 µs** after the edge | — |
| slot 6, bit 7 | mid-cell of bit 7 = 14.65 µs | the old value is needed until 14.65 µs; it changes at 15.625 µs |
| **margin** | **setup ≥ 2.8 µs** after card `t_co`, mux and bus | **hold ≥ 0.9 µs** |

Both margins are at the family's fastest rate, 1 024 kbps, still half a
microsecond. `A_TX` is a level from an opto-isolator or a 4 ms detector and has
no timing requirement.

**Receive.** The C-bit '259 is written by the recovered strobe of bit `CBIT[n]`;
the receiver's frame counter wraps on the strobe of the following bit 0, and
that wrap is `RX_CLK`. The last write, slot 6 at bit 7, precedes `RX_CLK` by one
cell less the classifier's timing tolerance (±13 % of a cell, `mf8-spec.md`
§9.4): **≥ 1.6 µs setup** at the card. The first rewrite, slot 1 at bit 1 of the
next frame, follows `RX_CLK` by a cell: **≥ 1.6 µs hold**. Cards sample `C_RX`
on the rising edge of `RX_CLK` and nowhere else.

**Ripple.** The frame mux address comes from a ripple counter and changes at the
bit boundary, ~60 ns after the H edge through three stages; the encoder samples
the mux output at mid-cell, 977 ns later. `mf8-spec.md` §10's race — F read at
bit-count 0 as the superframe counter ticks — is handled as that section says,
by clocking the superframe counter off the opposite edge; nothing on the
backplane adds a race, because nothing on it is sampled at the edge that changes
it.

---

## 6. The bus under faults

| condition | on the bus | what the far end sees |
|---|---|---|
| empty slot | `C_TX[n]` pulled to `FILL` through 4.7 kΩ, `A_TX[n]` to ground through 4.7 kΩ; a fitted card's 74HC output overrides 1 mA without noticing | `1010` — CVSD silence — and on-hook (`mf8-spec.md` §12.3) |
| card pulled with power on | the same as empty, from the moment its pins leave | the channel goes idle, cleanly |
| trunk not locked, or no carrier | `MUTE` asserted; the A '259 cleared, so every `A_RX` reads 0 | every phone hears `1010`, nothing rings; the phones keep their downstream clock, since T is local; hook states still go out on `A_TX`, harmlessly |
| trunk card absent | no clocks at all | phones lose their downstream: no carrier, ringers armed off, nothing to dial into |
| card type mismatch, slot for slot | nothing on the bus can tell | `mf8-spec.md` §13: loud, locked, not squelched. Label every slot |
| two data cards three slots apart | nothing on the bus can tell | the §5 slot rule, broken |

The last two are mechanical. Data cards fit only slots 1–3 if their connectors
are keyed for it, and then the slot rule cannot be broken; a two-pin `TYPE`
code on the connector would let a future trunk card carry card types to the far
end. Neither is specified here; the keying is recommended.

---

## 7. Measured: the plesiochronous slip

`subscriber-line.md` §7 left the free-running upstream as "one CVSD bit every
~150 ms at 100 ppm, which the codec should not hear." §2 above puts the same
event on the downstream of every line, so it is measured here rather than
assumed. One 64 kbps CVSD bit is dropped or duplicated every *N* bits, the
stream is decoded, and the result is scored against the clean decode. Three
talkers at nominal level, 30 s each.

Two scorers, because the obvious one misleads. `audio.block_snr_db` aligns each
100 ms block once; a slip inside a block leaves half of it one sample out, and
that phase error — not the codec — is what it then measures, capping a block at
about 9 dB whatever the slip rate. Scored **sample-aligned** instead, with the
reference the clean decode with the same sample removed, only the decoder's
transient remains:

| slip rate | ppm equivalent | segSNR vs clean, sample-aligned | the transient |
|---|---|---|---|
| one bit in 50 000 (every 781 ms) | 20 | **34.8 dB** | peak −29 dB below speech rms, settled to 1 % in 1.3 ms |
| one bit in 15 625 (every 244 ms) | 64 | **34.3 dB** | peak −30 dB, 1.2 ms |
| one bit in 10 000 (every 156 ms) | 100 | **34.0 dB** | peak −30 dB, 1.2 ms |
| one bit in 5 000 (every 78 ms) | 200 | **33.0 dB** | peak −30 dB, 1.2 ms |
| one bit in 3 333 (every 52 ms) | 300 | 31.9 dB | peak −30 dB, 1.2 ms |
| one bit in 1 000 (every 16 ms) | 1 000 | 26.2 dB | peak −30 dB, 1.2 ms — settled well before the next |

The codec's own clean decode scores 25.4 dB against the source, so at 20 and
100 ppm the slip sits 9 dB below the codec's own error, at 200 ppm — two
±100 ppm crystals at opposite extremes, the real worst case — still 7 dB below
it, and even 1 000 ppm does not reach it. Dropping and duplicating measure the
same. **A ±100 ppm crystal at each end is enough**; the slip is inaudible, and
the case for a PLL and loop timing is the data card's alone.

These are under the MIL-STD-188-113 law `mf8.BASE` now carries — τ_syl 5 ms,
τ_int 1 ms, 34.2 dB. The transient is the integrator recovering from one wrong
step, so its length follows τ_int: under the earlier law, τ_int 3 ms, the same
measurement gave a −25 dB peak settling in 5 ms, and 33.2 dB at 100 ppm, 31.3
at 200 and 20.7 at 1 000.

---

## 8. Mechanical and electrical

| | |
|---|---|
| Cards | Eurocard 100 × 160 mm |
| Slots | 9: slot 0 the trunk card, slots 1–6 channels, slot 7 the gateway slot, slot 8 the power supply |
| Connector | 2 rows × 16, DIN 41612 half-length or 0.1-inch header; assignment below |
| Bus length | ≤ 25 cm. At 512 kHz-class edges from 74HC drivers this is electrically short; no termination |
| Clock drivers | one 74HC244 on the trunk card for `TX_CLK`, `TX_HB`, `TX_OCT`, `RX_CLK`, `RX_OCT`, `MUTE`, 33 Ω series at the driver against ringing |
| Ground | one row pin in four; the −48 V return separate, joined at the supply |
| Fusing | −48 V through a 100 mA PTC per slot |

**Channel-slot pins.** Row *a* signals, row *c* power and returns.

| pin | a | c |
|---|---|---|
| 1 | `TX_CLK` | `+5 V` |
| 2 | `TX_HB` | `GND` |
| 3 | `TX_OCT` | `+5 V` |
| 4 | `FILL` | `GND` |
| 5 | `C_TX[n]` | `+12 V` |
| 6 | `A_TX[n]` | `GND` |
| 7 | `RX_CLK` | `−12 V` |
| 8 | `RX_OCT` | `GND` |
| 9 | `C_RX[n]` | `−48 V` (fused) |
| 10 | `A_RX[n]` | `−48 RET` |
| 11 | `MUTE` | `GND` |
| 12 | `TYPE0` (reserved) | `RING` (FXS slots only, strapped) |
| 13 | `TYPE1` (reserved) | `RING RET` |
| 14 | `RAI` (reserved) | `GND` |
| 15 | key | key |
| 16 | `GND` | `GND` |

The exchange uses two of the three reserved pins (`exchange/ex-extensions.md`
§2.1): a12 carries the port's word, its class and options one bit a frame, and
a13 is `/ANS`, whether the port rings. a14 stays spare. A card only ever pulls
the two to ground, and this shelf leaves them unconnected, so a card built for
the exchange works here unchanged. The remote alarm that `mf8-spec.md` §3.5
puts on x is between trunk cards, and reaches the panel from the trunk-card slot
as `LOCK` and `CD` do.

`RING` sits on the power row between ground pins, and the backplane strap that
brings it to a slot is fitted only for a slot that holds an FXS card; every
other slot's pin c12 is left open. `LOCK` and `CD` go to the panel from the
trunk-card slot and no channel card needs them, so they are not on the channel
pins. The trunk-card slot carries the six `C_TX`, six `A_TX`, six `C_RX` and
six `A_RX` lines in place of the per-slot four, plus `LOCK` and `CD`, on a
2 × 32; the PSU slot carries the rails and the ring generator's output.

**The gateway slot** is the trunk-card slot mirrored: the same 2 × 32 with all
24 per-slot lines, the four clocks, `MUTE`, `LOCK` and `CD`, but `C_TX[n]` and
`A_TX[n]` are its *outputs* and everything else its inputs. It lets one card
stand in for any subset of the six channel cards, or listen to all of them; its
drive rule — only into a slot that holds no card, every output released at
power-up — and the card that uses it are `mf8-pico.md` §3. It needs no bus
signal the other slots do not already have.

---

## 9. Not measured, and what to scope at bring-up

- **Every margin in §5** — computed from typical figures. Scope `C_TX[6]`
  against the encoder's mid-cell sample and `C_RX[6]` against `RX_CLK` at the
  1 024 kbps rate, where the margins are smallest.
- **The synchronizer crossings.** Analysis only; a failure is one bad CVSD bit.
- **Loop-timed phones.** §2 assumes either case; `subscriber-line.md` §7 has
  designed neither. The measured slip cost makes the free-running phone
  acceptable for voice.
- **The `MUTE` transient.** What a phone hears at the instant its downstream
  switches from `C_RX` to `1010` and back has not been rendered; `mf8-spec.md`
  §7's "chopped" rows are the same event one step further along.
- **Hot plugging.** The fill and pull-down make a removed card harmless; a card
  inserted with power on has not been considered beyond that.
- **Crosstalk and radiation** on the backplane at 74HC edge rates: electrically
  short, so expected negligible; not measured.
