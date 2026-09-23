# The tone card — one slot, and a whole shelf on fast busy

**One tone generator, on a plain 2 × 16 channel card, can hold every channel of
an MF8 shelf on a tone, so that every phone hears fast busy the moment it is
lifted** — the difference between a dead telephone and a telephone that says no.

It is not one of the four cards of `common-cards.md`, and it is worth having. It
is the **cheapest card in an MF8 shelf or an exchange block**, and the only one
that drives and never listens: `C_RX` and `A_RX` go nowhere on it, nothing rings
it, nothing answers it, and an outage it cannot hear is an outage it need not
handle (`common-cards.md` §1.3).

Feeding more than its own channel takes a change to the MF8 backplane, and that
change is **a bus wire, a resistor and a field of jumpers** — §4. The card does
not know it is happening, which is the point: it is one card, one slot, either
an MF8 shelf or an exchange block.

> **Status: proposed. Nothing here is measured.** The generator is
> `features.md` §2's, already described there. §4's jumper field is new and
> is **not in `mf8-backplane.md`** — no board, no bench, and nothing has been
> listened to.

---

## 1. The card

A channel card like any other. It drives `C_TX[n]` with the tone and holds
`A_TX[n]` low; it takes `TX_CLK` and nothing faster.

- **In an exchange block** it is exactly `features.md` §2's tone card: class
  *source*, never busy, any number of listeners, reached through the fabric. The
  block needs no modification, because a commutator already lets the marker
  switch every port that wants it onto one card.
- **In an MF8 shelf** it feeds its own channel as it stands, and §4's jumper field
  lets it feed any subset of the other five, or all of them.

`A_TX` low is what every source does (`features.md` §6): nothing rings,
nothing is ever answered, and no call is held up. A listener leaves by going
on-hook.

**One design, two populations**, and the second is one buffer:

| | fitted | what it is |
|---|---|---|
| **plain** | most of them | the generator, its own channel, and nothing else |
| **bus driver** | one a shelf, at most | **⅛ of a 74HC244 and a 33 Ω series resistor**, from the same node that feeds `C_TX`, out to one pin of the rear connector. That pin is punched to a bus conductor in the wiring field — §4 in an MF8 shelf, §5 in an exchange |

The buffer is **additive**: `C_TX` still goes to the commutator exactly as it
always did, so the card keeps its own channel and stays dialable whichever
population it is.

## 2. The card's pins

Against the socket of `common-cards.md` §1. It is the shortest column in that
table: **six of the fourteen signal pins.**

| pin | | | what this card does with it |
|---|---|---|---|
| a1 | `TX_CLK` | in | the encoder's clock. The generator's T half runs on it |
| a2 | `LOOP_HB` | — | nothing here encodes a line |
| a3 | `TX_OCT` | ○ | loads the word's '165 where it is fitted — §5 |
| a4 | `FILL` | — | the encoder's own `1010` at silence is the idle, and the cadence mutes its **input** rather than its output, so there is never a pattern to substitute |
| a5 | `C_TX[n]` | **out** | the tone, into the commutator. The bus-driver population takes a second copy off the same node, **not** off this pin — one output, one load, as every other card has |
| a6 | `A_TX[n]` | **out** | **held low** |
| a7 | `RX_CLK` | — | there is no decoder on this card |
| a8 | `RX_OCT` | — | |
| a9 | `C_RX[n]` | — | **the pin no other card can leave open.** A talking circuit, a data pipe and a trunk all have to hear something; a source does not |
| a10 | `A_RX[n]` | — | it is never rung and never seized |
| a11 | `MUTE` | — | there is no decoder to mute. §4 is where `MUTE` matters, and it matters at the backplane, not here |
| a12 | card word | ● / — | §5 |
| a13 | `/ANS` | **out** | tied low: it answers at once, and must never give its listener ringback |
| a14 | spare | ○ | open |
| c1, c3 | `+5 V` | in | the logic and the encoder's digital half |
| c5, c7 | `±12 V` | in | the carrier, the warbler and the engine of `mf8-spec.md` §12.1. **The ROM-player version needs neither rail**, because it needs no codec |
| c9–c13 | `−48 V`, `RING` | — | nothing on this card goes near the line |
| | rear connector | ○ | **plain: nothing leaves it** — the only card in the set with no line side. **Bus driver: one pin and a ground**, the buffered tone, into the wiring field of `common-cards.md` §7.3 |

## 3. The generator

**Which tones, and both cards that make them, are `tone-plan.md`.** It settles
four tones in two timbres, specifies them as tolerances an analog card and a ROM
card both meet when the analog pots are set, and measures the one thing that
constrains the analog build: a warble may not be made with a switch. What
follows is the generator in outline.

`features.md` §2's analog card: **one slot, one tone.** A 555-style or discrete
carrier into one encoder half of `mf8-spec.md` §12.1; a pot sets the carrier, a
second pot the warble rate, and a jumper chooses pure tone or Aussie-style AM
(425 ∿ 25) through ½ LM13700. Cadence is a 16-bit on/off mask read from jumpers,
stepped at 256 ms off `TX_CLK`, muting the encoder's **input** so the off
periods are the codec's own `1010`. Fast busy is the cannot-complete tone with
its own mask — `tone-plan.md` §5.

Or `features.md` §3's ROM player instead, and the shelf speaks a sentence:
8 s of CVSD fills a 64 kB part, and **no codec is needed at all** — which also
takes the `±12 V` off the card and leaves it pure 74HC.

**A tone is the same idea at 128 ms.** An 8 kB part holds an 8192-bit loop that
repeats seamlessly, and **two planes of it are all four tones**: dial and
ringback share one image, busy and cannot-complete the other, and every cadence
is a tap off the same counter that addresses the ROM. One card then serves every
tone port in the exchange, at seven packages and no trims — `tone-plan.md` §4.
`sim/tones.py` measures the loop, sizes the part and renders the result.

## 4. Feeding the other slots: the tone bus

**The one thing that must be broken is that `C_RX[n]` already has a driver.** It
comes off the trunk card's receiver '259 (`common-cards.md` §1). A second driver
on it is contention, so a listening slot's `C_RX` has to be *switched*, not
paralleled — and that, plus one conductor, is the whole of the modification.

```
  the source card, bus-driver population (§1)
      encoder ──┬───────────────────▶ C_TX[k] ── its own channel, as always
                └─[ ⅛ '244 ]─[33Ω]──▶ rear pin ── punched in the wiring field
                                                            │
         ┌───────────────── the tone bus ───────────────────┘
         │     4k7 to FILL, so an unfed bus is 1010
   slot n  a9 ◀── o──┬── the trunk card's '259, output n    (normal)
   (a listener)      └── the bus                            (barred)
                     a 3-pin header: one or the other, never both
```

| on the backplane | | |
|---|---|---|
| the bus | one trace the length of the shelf, to a punch-down in the wiring field | **1 wire** |
| its idle | 4.7 kΩ to `FILL`, so a bus with no source fitted is `1010` — CVSD silence, exactly what `mf8-backplane.md` §6 already does at an empty slot | **1 resistor** |
| listener select | a 3-pin header a slot: socket a9 to the '259 output *n*, or to the bus | **6** |
| `MUTE` select | one 3-pin header, shelf-wide — §4.2 | **1** |

| on the card | |
|---|---|
| the buffer | ⅛ 74HC244, 33 Ω series, one rear pin and a ground — §1 |

**≈ 7 headers, one resistor, one trace, and ⅛ of a package on one card.** No
tri-state on the backplane, no enables, no new bus signal, and nothing for the
clock card or the trunk card to do.

**A listener jumpered to an unfed bus is safe by construction**: the 4.7 kΩ holds
it at `FILL`, which is what an empty slot already sounds like.

### 4.1 Why the driver is on the card, not the backplane

The obvious alternative is a source tap a slot — a jumper linking each slot's
`C_TX` to the bus — and it is worse for three reasons.

- **The socket has no pin for it.** Rows *a* and *c* of the 2 × 16 are fully
  committed (`common-cards.md` §7.3: "16 signals and 16 power pins, `RAI` and the
  key included"), so a tap would have to steal `C_TX` from the commutator and
  cost the source its own channel. Off the card's **rear connector** it costs
  nothing, and that connector is already the design's route for everything that
  is not backplane (`common-cards.md` §7.3).
- **It halves the contention risk.** A tap a slot means **two taps fitted at once
  is two 74HC outputs fighting**, which nothing in the shelf can detect. With the
  driver on the card, feeding the bus takes a card built for it *and* a punch in
  the wiring field: two deliberate acts, either of which is a place to notice.
- **A backplane trace is the wrong owner of a drive decision.** The wiring field
  is per card and can be re-punched without touching the backplane, which is
  exactly the argument `common-cards.md` §7.3 already makes for the subscriber
  pair: "the backplane carries no line conductors at all."

The card still does not know where it is. It drives a rear pin whether or not
anything is punched to it, and the shelf decides whether that goes anywhere —
`mf8-backplane.md` §3's "no slot-ID pins" kept intact.

### 4.2 `MUTE` is not optional

`mf8-backplane.md` §6's fault table: with the trunk not locked, "**every phone
hears `1010`**". That is the CVSD subscriber line card ORing `MUTE` into its
`ON_HOOK` select (`channel-cards.md` §2.3) so that an off-hook phone gets silence
through an outage rather than the receiver's last latched bits.

**It is the right behaviour, and it defeats this card on exactly the outage it
was built for.** So the shelf-wide 3-pin header: `MUTE` from the trunk card as
usual, or **tied to "locked"** — which is precisely what an exchange block does
at every socket, for the same reason, because a block has no link
(`common-cards.md` §1).

| card | `MUTE` as usual | `MUTE` tied to "locked" |
|---|---|---|
| CVSD subscriber line | hears `1010`: the tone is muted at the card | hears the tone |
| FXS, FXO, E&M | hears the tone either way — none of them reads a11 (`common-cards.md` §1.4) | the same |
| data | `RXD` forced to 1 | `RXD` follows the bus, which is not data. Do not jumper a data slot to the bus |

So the two jumpers go together: a shelf barred with the tone bus is a shelf whose
`MUTE` is tied to "locked", and that is one jumper, not one a slot.

## 5. In an exchange: the ringback card is this card

**`RBT` is the exchange's tone bus, and it already exists.** The ringback bit
stream rides one mainboard conductor, is pulled to `FILL` through 4.7 kΩ at the
clock card when nothing drives it, and is substituted into a ringing port's
highway cell by 2 × 74HC157 a block (`fabric.md` §3.1, §3.5). That is §4's
arrangement with the backplane half already built.

So **the ringback card is a tone card with the bus-driver population fitted**,
its rear pin punched to `RBT` (`features.md` §2: "the same kind of card,
which drives a backplane line as well as its port"). No shunt, no new conductor,
no jumper field. The clock card simply does not populate that one '244 gate and
keeps the 4.7 kΩ.

**Ringback is the one tone that is not switched to the caller.** Dial tone is a
port — the marker points the caller's latch at it. Ringback cannot be, because
the caller's latch is already pointing at the *called* port; the tone has to
arrive in that port's cell, at every block at once (`marker.md` §5:
"ringback is the one tone that is not a line, because it is made where the call
state is"). Hence the bus.

### 5.1 Which port it sits at, and whether it is dialable

**There is no reserved port for it.** Block 0's switched-tone seats are spoken
for (`protocol.md` §5): 01 dial, 02 busy, 03 cannot-complete. Ringback is
the bus, so the card takes a port somewhere else, or no port at all:

| | where | dialable? | cost |
|---|---|---|---|
| **no port** | any slot, with only its commutator input and no port circuit — "a source never listens, so it needs no port circuit" (`mvp.md`) | no | **≈ 5 packages saved.** The bus does not care, and neither does the caller |
| **with the dial-tone card** | same board at 01: dial on `C_TX`, ringback on the rear pin to `RBT` (`§5.2`) | no | nothing extra |
| **a trunk block's spare slot** | slot 0 or 4 of a block 1–7 MF8 group — 10, 14, 20, 24, … | **yes** when that block's first digit is a local highway | nothing. Those ports exist whether or not anything is in them |
| **a line slot** | anywhere in the dialable map | yes | one subscriber number |

**Sharing the dial-tone card is the natural home.** Dialling a spare-slot home
gives ringback on demand — a bench test for the `RBT` conductor, the '157
substitution and a listener's decoder in one number.

Whichever it is, `/ANS` is tied low so the port is never rung. Its own `C_TX`
passes through unsubstituted, so what a caller hears when they dial it is the
same stream the '157s put in a ringing port's cell.

### 5.2 Two engines, and no port at all

**Not in any document, and offered as an option**: `mf8-spec.md` §12.1's card
carries two engines off one LM13700, and a tone card populates one of them as an
encoder and leaves the decoder half unfitted (`features.md` §2, "one encoder
half"). Populate that half as a **second encoder** and one card at port 01 makes
both progressing tones — dial tone continuous on `C_TX`, ringback cadenced through the bus
driver onto `RBT`.

Then the switched stop tones at 02 and 03 are a second card (or punches from a
multi-output ROM card), ringback needs no port of its own, and the only addition
is a cadence gate on the second encoder's input. **It has not been drawn and the
two engines have never been run as a pair**; the tone frequencies also differ
between the two tones, so it is two carrier+warbler chains on one board, not one.

## 6. What it says about itself

**In an MF8 shelf, nothing**: a12 and a13 are unconnected there, and a shelf full
of fast busy needs no one's permission.

**In an exchange**, it depends where it sits:

- **At ports 01–03** the marker reaches the tone cards by address and never
  reads their class (`extensions.md` §2.2), so the word needs no part at all.
- **Anywhere else**, a '165 with class 001 *source* (`fabric.md` §3.5), so
  that the card is never busy and any number of listeners can be switched to it.

Either way a13 is tied low, for the reason every card that must not be rung in
cadence ties it low (`extensions.md` §2.3): a tone card that rang would give
its listener ringback for 0–4 s before saying anything.

## 7. Uses

A shelf whose exchange or whose link is out of service; a terminal being
commissioned; a shelf deliberately barred outside hours.

And, once the bus exists, it is not only a tone bus: **any card can feed any
subset of the others.** A milliwatt at the codec's 0 dBm0 reference for level
checks (`extensions.md` §2), an announcement ROM, or one card's transmit heard
at another slot for a bench test. None of it needs a different card or a
different jumper.

## 8. Not measured, and open

- **No circuit**, in either the oscillator or the ROM-player version.
- **§4 is not in `mf8-backplane.md`.** The jumper field, the bus and its 4.7 kΩ
  belong in §6 and §8 there and are not in either. Until they are, this document
  is proposing a board change that the backplane's own specification does not
  carry.
- **Two bus drivers.** Nothing detects two cards built with the buffer and both
  punched to the same conductor — `mf8-backplane.md` §6's last two rows are the
  same kind of fault, and §4.1 only makes it take two deliberate acts instead of
  one. An RC on the '244's `/OE` so the buffer comes up released would at least
  make power-up benign; it is not load-bearing while there is one driver, and it
  is not drawn.
- **Who drives `RBT` was contradicted across three documents, and is now
  settled — applied, not owed.** `mainboard.md` §2.1 had it among the
  fifteen signals *from the clock card*; `marker.md` §5 said flatly it was
  not the clock card's; `fabric.md` §4 hedged with "clock card, ringback
  card". **It is the clock unit's conceptually and the tone card's
  electrically**: carried with the fabric-wide references, because that is what it
  is, and generated by this card, because an analog tone oscillator through a
  CVSD encoder has no business on a board that is otherwise a crystal and a
  divider chain. `mainboard.md` §2.1 now says so and counts fourteen driven lines,
  `fabric.md` §4 gives `RBT` its own row, and `features.md` §2 names
  the part. What is **not** measured is the obvious consequence: `RBT` is now one
  driver and about ten receivers on two metres of ribbon, driven from a card's
  rear connector rather than from the clock card's own '244, and that path has
  not been through `exch.py mainboard`.
- **§5.2's two-engine card** is an inference from `mf8-spec.md` §12.1's parts,
  not something any document proposes.
- **What it sounds like.** A shelf full of fast busy through
  `channel-cards.md` §2.3's rule, at the instant of lifting, has not been
  rendered.
- **Which port the ringback card sits at** (§5.1) is unassigned in every
  exchange document, including `mvp.md`'s fit-out list, which names the card
  and gives it no slot. The three options there are worked from
  `protocol.md` §5's map, not quoted from it.
- **The `MUTE` jumper's blast radius** (§4.2). Tying `MUTE` to "locked" shelf-wide
  suppresses the squelch for *every* card in the shelf, not just the ones
  listening to the bus. On a barred shelf there is nothing else to hear, so it
  costs nothing there; it is not a jumper to leave fitted in service.
- **The card's pin column** (§2) is an assignment read off this document, with no
  board behind it, like every other column in `common-cards.md` §1.3.
