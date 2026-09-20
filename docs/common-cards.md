# The common card set — four cards that plug into either shelf

**Decided: the POTS subscriber/CO converter, the CVSD subscriber line card, the
data card and the E&M subscriber card are one design each, and a card moves
between an MF8 shelf and an exchange block with nothing changed on it.** Same
socket, same pinout, same rails, same clocks, same mechanical format, and — when
the connector is settled — the same connector.

This was already half true and never stated as a requirement. `mf8-backplane.md`
§8 and `exch-basebandcard.md` §2.2 give the same 2 × 16 pin for pin;
`exch-protocol.md` §1 says "a port has the same structure as an MF8 channel"; and
`exch-terminal.md` is the consequence — a stock MF8 shelf of channel cards *is*
six lines of an exchange, and no card in it knows. What was missing is the short
list of things that stopped it being true in both directions. This document is
that list, resolved.

> **Status: proposed.** Nothing here is newly measured. §5's two behaviours are
> `exch.py calls` 11 and `mf8-cards.md` §1 respectively, both already reported;
> everything else is an assignment or an argument. No board has been laid out and
> no connector has been chosen.

The cards, and where each is specified:

| card | | signalling |
|---|---|---|
| **POTS subscriber / CO converter** (FXS / FXO) | `mf8-cards.md` §3 — the codec on the card, a hybrid, a loop-start line circuit | loop start, §5's strap |
| **CVSD subscriber line card** | `mf8-cards.md` §2 — two pairs to a phone that holds its own codec | hook state from the line's own bit patterns |
| **Data card** | `mf8-cards.md` §4 — 64 kb/s synchronous, a DS0, or async oversampled | `DTR` / `DSR` |
| **E&M subscriber card** | `mf8-spec.md` §12.1 — four-wire audio, the codec engine, E and M leads | E and M, which **are** `A_RX` and `A_TX` |

---

## 1. One socket

The channel socket is `mf8-backplane.md` §8's, and this is the single table, with
the exchange's readings of the three pins MF8 reserved folded in. It supersedes
nothing in either document; it joins them.

| pin | a — signals | in an MF8 shelf | in an exchange block | c — power |
|---|---|---|---|---|
| 1 | `TX_CLK` | 64 kHz, from the trunk card | 64 kHz, from the clock card via the block | `+5 V` |
| 2 | `TX_HB` | the '4040 tap | `/SLOT[1]`, one inverter at the block (`clocks.md` §4) | `GND` |
| 3 | `TX_OCT` | | | `+5 V` |
| 4 | `FILL` | | | `GND` |
| 5 | `C_TX[n]` | → the trunk card's frame mux, input *n* | → the block's `C` commutator, input *n* | `+12 V` |
| 6 | `A_TX[n]` | → the signalling mux | → the block's `A` commutator | `GND` |
| 7 | `RX_CLK` | recovered | **is `TX_CLK`** | `−12 V` |
| 8 | `RX_OCT` | recovered | `TX_OCT` one frame late | `GND` |
| 9 | `C_RX[n]` | ← the receiver's '259 | ← the port's capture flip-flop | `−48 V` (fused) |
| 10 | `A_RX[n]` | ← the '259, raw | ← the port's supervision gate: E, chopped by the ring cadence while the port rings | `−48 RET` |
| 11 | `MUTE` | asserted when not locked | **tied to "locked"**: a block has no link | `GND` |
| 12 | `TYPE0` — **the word** (§2) | not connected | read by the marker's scanner | `RING` (FXS slots only, strapped) |
| 13 | `TYPE1` — **`/ANS`** (§2) | not connected | read by the port's own gates | `RING RET` |
| 14 | `RAI` — the secondary word (`ex-groups.md` §3.3) | not connected | a pull-up at the port; optional | `GND` |
| 15 | key | | | key |
| 16 | `GND` | | | `GND` |

Three properties hold in both shelves and are what make a card portable at all:

- **No slot-ID pins.** A card never knows where it is (`mf8-backplane.md` §3,
  `exch-basebandcard.md` §2.1).
- **Point to point, never a bus.** Six signals a slot, nothing shared, nothing
  addressed, nothing contending; only the clocks and the rails are common.
- **An unfitted slot idles by resistor**: `C_TX[n]` pulled to `FILL` through
  4.7 kΩ and `A_TX[n]` to ground, so a pulled card leaves silence and on-hook
  behind it (`mf8-backplane.md` §6, `exch-fabric.md` §4 — the exchange does the
  same at the commutator input).

**Mechanical.** Eurocard 100 × 160 in both shelves. The exchange's card side has
never had a size written down; it has one now, and it is MF8's.

---

## 2. What a card says about itself

This is the one thing that was genuinely broken, and it was broken one way only.

`ex-extensions.md` §2.1 argues that **an exchange-built card works unchanged in an
MF8 shelf**, because a card only ever pulls a12 and a13 to ground and MF8 leaves
both unconnected. True. The reverse did not hold: an **MF8-built card in an
exchange block** has a12 open, the port's pull-up reads "no word", and the marker
reads class 000 — unequipped. The card is fitted, the phone is live, and nothing
can ever be hunted to it or dialled to it.

**Resolved: every card in the set carries its own word source, and the footprint
is on every board.** One 74HC165 into ¼ of a '03, held off at power-up by an RC
(`ex-extensions.md` §2.2) — ≈ 1¼ packages, shifted by `TX_CLK` and loaded by
`TX_OCT`, both of which are on the socket in both shelves. Two of the four cards
leave it unpopulated and strap a12 to a row-*c* ground instead. In an MF8 shelf
the pin is unconnected either way: a grounded pin goes nowhere, and a populated
'165 shifts its byte into an open circuit, harmlessly, for ever.

**The word's encoding, which `exrtl/README.md` lists as open.** `exch-protocol.md`
§5 has a plain line card tie its pin to ground and read "all ones, a line with no
options", while `exch-fabric.md` §3.5's table gives *line* as class 001. Both are
right about different codes, and `ex-groups.md` §2.1's table is the proof:

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
else to say. The open item closes with no change to either document, and
[line_card.v](../exrtl/rtl/line_card.v)'s `WORD` parameter can take `8'hFF` for a
plain line.

**So, card by card:**

| card | a12 — the word | a13 — `/ANS` | why |
|---|---|---|---|
| CVSD subscriber line | **grounded**: all ones, a plain line | **open**: the port rings | a phone. No part on either pin |
| POTS converter, FXS | **grounded** | **open** | a phone |
| POTS converter, FXO | **'165**, class 100 *outside line* | **tied low** | an outside line must never be rung in cadence, and must not give its caller ringback (`exch-fabric.md` §3.5) |
| Data card | **'165**, class 110 *data line* | **tied low** | so the marker refuses to connect a phone to it (`exch-features.md` §8) |
| E&M, facing a station | **grounded**, or a '165 if it answers to a number | **open** | E rings it |
| E&M, facing a PBX | **'165**, class 100 | **tied low** | a tie to a foreign switch is an outside line, not a network trunk: it carries no direction word and takes no part in the flood |

A card that wants a number as well as a class says it on a14, the secondary word
(`ex-groups.md` §3.3) — a second '165 into a second gate of the same '03. a14 is
unconnected in an MF8 shelf too, so that is portable by the same argument.

**Cost of the decision.** The data card goes from 4 packages to 5¼ and is no
longer the cheapest card in the shelf (`mf8-cards.md` §4.4); the FXO population
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

That is what `exch-basebandcard.md` §2.3's open item was about, and §4 of
`clocks.md` closes it: `TX_HB` is `/SLOT[1]`, one inverter a block, no new
conductor on cable A. **Without it the CVSD subscriber line card cannot be fitted
in an exchange at all**, which is a strange thing for the project's centrepiece
card and was one bullet away from being noticed.

---

## 5. The one genuine split: what the FXO's `A_TX` means

`mf8-cards.md` §3.5 has the FXO card send `A_TX` = *ringing present*, raw.
`exch-features.md` §5 measured that this is wrong in an exchange: the call is set
up on every ring burst and torn down 220 ms into every gap, the operator's phone
rings for 2 s in 6, and the call never survives (`exch.py calls` 11). It wants
*ringing, held by a retriggerable 5 s, OR loop closed*.

**Resolved: one board, one strap — and the strap says what is at the far end, not
which shelf the card is in.**

| strap | `A_TX` is | the far end is | why the other position fails |
|---|---|---|---|
| **OFFICE** | ringing present, raw, in the CO's own cadence | a station card — an FXS, a CVSD line card or an E&M card — extending the line (`mf8-cards.md` §1) | with SEIZE, the far phone answers, the FXO closes its loop, `A_TX` rises, and the far card reads that as *ring the phone*. Ring trip would drop it inside 200 ms, so every answered call would start with a 200 ms blast of ringing into the earpiece |
| **SEIZE** | ringing present held 5 s, OR the loop closed | an exchange port, which reads `A_TX` as M and releases the call on its fall (`exch-fabric.md` §3.5) | with OFFICE, `exch.py calls` 11's row: torn down 220 ms into every cadence gap |

Both cases occur in both shelves. An FXO in an exchange block always faces an
exchange port, so SEIZE. An FXO in an MF8 shelf faces **either**: an extended
line to a distant phone is OFFICE, and an outside line at a subscriber terminal —
which `exch-terminal.md` §1 explicitly allows — faces an exchange port across the
link and is SEIZE. So the jumper is not an MF8-versus-exchange jumper, and the
card stays fully interchangeable; it answers a question the installer has to
answer anyway, in the same words in both shelves.

Cost: ½ a '123 and a gate, in the FXO population only.

Outgoing needs nothing in either position: 9 hunts the card, the caller's
off-hook closes the loop through E, and the CO's dial tone comes back on `C`
(`exch-features.md` §5).

---

## 6. A fifth card: the tone card, and a whole shelf on fast busy

Not one of the four, and worth having. **One tone generator can hold every
channel of an MF8 shelf on a tone, so that every phone at the far end hears fast
busy the moment it is lifted** — the difference between a dead telephone and a
telephone that says no.

**Where it goes: the gateway slot.** A channel slot reaches its own `C_TX` and no
other, so a channel card cannot do this without a backplane modification. The
gateway slot already can: it is the trunk-card slot mirrored, carrying all six
`C_TX[n]` and `A_TX[n]` as *its* outputs, on a 2 × 32, with a drive rule already
written — **drive only a slot that holds no card, every output released at
power-up** (`mf8-backplane.md` §8, `mf8-pico.md` §3). No new bus signal is needed
and the shelf is not touched.

**One encoder serves all six.** Each channel's bit is sampled in its own cell from
the same T-domain stream, so six `C_TX` pins take one output and there is nothing
per-channel to build. `A_TX` is held low on all six — which is what every source
does (`exch-features.md` §6) — so nothing rings, nothing is ever answered, and no
call is held up. A listener leaves by going on-hook.

**What the far end hears.** A station card off-hook passes `C_RX` to its phone
(`mf8-cards.md` §2.3's rule), so the tone arrives the instant the handset lifts;
on-hook the phone hears `FILL`, which is silence, and with `A_RX` at 0 it never
rings. Nothing else at that shelf needs to know.

**The generator** is `exch-features.md` §2's: a tuned oscillator pair into one
encoder half of `mf8-spec.md` §12.1, with the cadence muting the encoder's
**input**, not its output, so the off periods are the codec's own `1010` and
nothing clicks. Fast busy is the cannot-complete tone at its own cadence. Or
`exch-features.md` §3's ROM player instead, and the shelf speaks a sentence: 8 s
of CVSD fills a 64 kB part, and no codec is needed at all.

**Uses.** A shelf whose exchange or whose link is out of service; a terminal being
commissioned; a shelf deliberately barred outside hours.

**One generator, two carriers.** On a 2 × 16 channel card it is one port, in
either shelf, and in an exchange that is exactly `exch-features.md` §2's tone
card — class *source*, never busy, any number of listeners. On a 2 × 32 gateway
card it is six channels of one MF8 shelf. Same schematic, two boards, because the
connectors differ.

**The one hazard** is the drive rule: an enabled gateway output and a fitted card
on the same slot fight. Six enables, one a slot, and an RC on the '244's `/OE` so
that the card comes up released — the hardware form of `mf8-pico.md` §3's
"powers up with every output released".

---

## 7. The connector, which is not settled

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

Whichever it is, the channel socket keeps this document's §1 pinout unchanged.

---

## 8. What this changes in other documents

| document | |
|---|---|
| `mf8-backplane.md` §8, `exch-basebandcard.md` §2.2 | joined into §1 here. Neither is wrong; there were two copies |
| `exrtl/README.md`, "the word's encoding" | **closed** (§2). All ones is the constant *plain line*, from a grounded pin; class 001 is an explicit word. `line_card.v`'s `WORD` may be `8'hFF` |
| `exch-basebandcard.md` §2.3, first bullet | **closed** (`clocks.md` §4). `TX_HB` = `/SLOT[1]`, one inverter a block |
| `mf8-cards.md` §3.5 | the FXO gains §5's strap. `exch-features.md` §5's "the exchange build of the FXO card" becomes the SEIZE position of that strap, not a second board |
| `mf8-cards.md` §4.4 | the data card is 5¼ packages, not 4, and no longer the cheapest card in the shelf |
| `mf8-cards.md` §2.4, §3.7 | each parts list gains the word footprint: ≈ 1¼ where it is populated, a wire where it is not |
| `ex-extensions.md` §2.1 | its "a card built for the exchange works unchanged in an MF8 shelf" now holds in both directions, and §2 here says what it costs |

---

## 9. Not measured, and open

- **Every card.** Nothing in the set has been on a bench; `mf8-cards.md` §6 and
  `mf8-spec.md` §15 hold unchanged.
- **The connector** (§7), and with it the keying `mf8-backplane.md` §6
  recommends for data cards in slots 1–3.
- **`/SLOT[1]`'s phase against a real encoder** (`clocks.md` §7).
- **The FXO strap's 5 s constant** (§5): `exch-features.md` §5 measured that 5 s
  works against a 2 s / 4 s cadence and did not sweep it. A CO with a longer
  silent interval would want more.
- **The tone card** (§6): no circuit, and the hardware release-at-power-up has
  only ever existed as firmware. What a shelf full of fast busy sounds like
  through `mf8-cards.md` §2.3's rule at the instant of lifting has not been
  rendered.
- **`/HUNT_INH`**, still specified in three documents, present in no signal list
  and driven by nothing (`exch-basebandcard.md` §2.3). a14 is now the secondary
  word, so if `/HUNT_INH` is ever built it needs a different pin.
- **A dialled port whose class is trunk or outside line**, which
  `exch-marker.md` does not cover and the `calls` model does not have.
