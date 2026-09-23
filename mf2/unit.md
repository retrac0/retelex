# The MF2 unit — six boards, and the signals on each

An MF2 unit is two channel cards, a digital board, an analog board and the two
PSU boards, on the 100 × 100 mm spacer stack of `mf8-backplane.md` §8. Two units
back to back over two pairs are **two leased circuits** (`mf2/leased.md`). This
document defines every signal each board presents, and the three connectors they
meet on.

> **Status: proposed.** Nothing here has been on a bench and no board has been
> laid out. What is measured and cited: the framer and the slot rule on N = 2
> (`sim/mf2.log`), the section length and the code comparison on the buried pair
> (`sim/mf2_span.log`). What is carried unchanged from MF8 and was never measured
> there either: the whole physical layer (`mf8-spec.md` §15). Package counts are
> counts of an undrawn schematic.

Parent: [`spec.md`](spec.md). The line code is differential Manchester and the
PHY is `mf8-spec.md` §9 at the **Q3 rate plug** (§5.2).

> `mf2/repeater.md` and `mf2/leased.md` are referenced below and **are not
> written yet**; the repeater's measured span limits are in
> `sim/mf2_repeater.log` meanwhile.

---

## 1. The six boards

```
  CH1 ══ C ══ CH2 ══ C ══ MF2-D ══ P ══ MF2-A ══ Quiet PSU ══ pass ══ Noisy PSU ── 15–18 V in
                             │              │         │                   │
                      crystal, framer,   encoder,  +5, ±12,            intake,
                      muxes, counters,   75176,    −48 out             −48 stage,
                      C and the panel    classifier,                   RING inverter
                                         magnetics
```

| board | what it is | ≈ packages |
|---|---|---|
| **channel card** ×2 | the common card set, unchanged (`common-cards.md`) | 4–11 each |
| **MF2-D** | clocks, frame and superframe counters, muxes, framer, stack header **C** | **≈ 12–15** |
| **MF2-A** | biphase encoder, 75176, magnetics, protection, comparator, Q3 classifier | **≈ 6–8** + 2 transformers |
| **Quiet PSU** | `+5 V`, `±12 V`, the `−48 V` finish, the star point | `mf8-psu.md` §4.2 |
| **Noisy PSU** | 15–18 V intake, the `−48 V` stage, the ring inverter | `mf8-psu.md` §4.1 |

Ten boards on an MF8 shelf, six here. The split point is `mf8-trunk.md`'s and is
not reopened: plant energy and interval timing on A, every stack driver and the
framer on D.

**Three connectors**, and no others carry signal:

| | | |
|---|---|---|
| **stack header C** | channel cards ⇄ MF2-D | the channel socket of `common-cards.md` §1.1, two appearances (§2) |
| **pass header P** | MF2-D ⇄ MF2-A | 2 × 7, keyed (§4) |
| **rear connector** | MF2-A ⇄ the line | four conductors, a pair each way (§5.4) |

The PSU pass is `mf8-psu.md` §4.3 and carries no channel signal.

---

## 2. The channel socket — unchanged, and that is the point

**A channel card cannot tell an MF2 unit from an MF8 shelf.** The socket is
`common-cards.md` §1.1 pin for pin, and every clock on it is the same rate and
the same phase, because MF2 keeps the 64 kHz frame rate and the 8-frame
superframe that MF8 has. Only the *line* differs, and no channel card sees the
line.

| pin | signal | dir | in an MF2 unit | same as MF8? |
|---|---|---|---|---|
| a1 | `TX_CLK` | in | 64 kHz, `/FB[1]` from MF2-D | **yes** |
| a2 | `LOOP_HB` | in | 128 kHz, `/FB[0]` from MF2-D (§3.2) | **yes** |
| a3 | `TX_OCT` | in | 8 kHz, superframe state 7 | **yes** |
| a4 | `FILL` | in | 32 kHz, `/SFC[0]` | **yes** |
| a5 | `C_TX[n]` | **out** | → MF2-D's frame mux, input 1 or 3 | yes; the mux is 4:1, not 8:1 |
| a6 | `A_TX[n]` | **out** | → MF2-D's signalling mux, input 1 or 5 | **yes** |
| a7 | `RX_CLK` | in | recovered 64 kHz | **yes** — recovered, as in a shelf |
| a8 | `RX_OCT` | in | recovered state 7 | **yes** |
| a9 | `C_RX[n]` | in | ← the receive demux | **yes** |
| a10 | `A_RX[n]` | in | ← the receive `'259`, raw; the RC and Schmitt are on the card | **yes** |
| a11 | `MUTE` | in | asserted when the framer is not locked | **yes** |
| a12 | card word | out, o.d. | **pulled to `+5 V` through 680 Ω** and brought to a test header | MF8 leaves it open (§2.1) |
| a13 | `/ANS` | out, o.d. | the same | the same |
| a14 | `RAI` — spare | out, o.d. | the same | the same |
| a15 | key | | | yes |
| a16 | `GND` | | | yes |
| c1–c16 | rails | | `mf8-backplane.md` §8's row *c*, unchanged | **yes** |

### 2.1 The one deliberate difference

An MF8 shelf leaves a12–a14 **unconnected**, so a card that shifts a word drives
into an open circuit and a card that ties a pin low pulls a floating net. An MF2
unit pulls all three to `+5 V` through **680 Ω** — the port pull-up value of
`fabric.md` §3.5 — and brings them to a three-pin test header on MF2-D.

Nothing about a card changes: it still only ever pulls low or leaves open
(`common-cards.md` §1.2). What changes is that the levels are defined, so a
card's word can be read on a scope at a unit without an exchange behind it. That
is a bring-up convenience, not a contract change, and `common-cards.md` §1.1's
MF8-shelf column stands.

### 2.2 Two appearances, on a ribbon

The card side of an MF2 unit is a **star**, as a block's is: six per-slot signals
a card (`C_TX`, `A_TX`, `C_RX`, `A_RX`, card word, `/ANS`), the clocks and rails
common, nothing addressed and nothing contending. Stack header **C** collects
that star on MF2-D.

**mk1 breaks it out as a two-slot ribbon**, in the `block ribbon` idiom of
`fabric.md` §5.1, rather than solving the stack-native geometry that
`mf8-backplane.md` §8 and `mf8-trunk.md` §5 both defer for six layers. MF2 has
two layers and no need to settle a six-layer mechanical standard on its own.

**Seat keying is not cosmetic.** `spec.md` §5 forbids two data cards, and
`sim/mf2.log` measures why: two data cards hold a wrong alignment in **520**
(byte, hook-state) combinations, and the framer false-locks 4 of 16 start-ups on
the adversarial pair with none of them releasing. Key the two seats so that two
data cards cannot both be fitted, and **do not reuse MF8's "seats 1–3" wording** —
the rule is carrier-specific (`spec.md` §5).

---

## 3. MF2-D — the digital board

### 3.1 What it owns

Crystal and the whole clock chain; the frame and superframe counters; the frame
and signalling muxes; the F generator; the framer; the receive demuxes; the
stack driver; the panel; and the hotline cadence gate.

### 3.2 The clock chain, and both new clocks are old taps

One 4.096 MHz crystal, the chain of `clocks.md` §1, unchanged:

| ÷ | rate | name | who wants it |
|---|---|---|---|
| 8 | **512 kHz** | **`LINE_HB`** — the MF2 line's half-bit clock | the biphase encoder on MF2-A |
| 16 | **256 kHz** | **`H`** — the line bit clock, and the half-cell phase | the encoder; the frame counter |
| — | — | `FB[1:0]` — bit position in the frame, counting `H` | the frame mux address |
| 32 | 128 kHz | **`LOOP_HB`** = `/FB[0]` | socket a2 |
| 64 | 64 kHz | **`TX_CLK`** = `/FB[1]` | socket a1; the superframe counter |
| — | — | `SFC[2:0]` — superframe state, counting `TX_CLK` | the signalling mux, F, the guard |
| 128 | 32 kHz | **`FILL`** = `/SFC[0]` | socket a4 |
| 512 | 8 kHz | **`TX_OCT`** = decode `SFC` = 7 | socket a3 |

**Neither line clock is new.** 256 kHz is the tap `clocks.md` §7 records as "the
one tap in §1 with no customer… If something later needs 256 kHz it is already
there, on no pin" — MF2 is that customer. 512 kHz is the exchange's `HCLK` tap.
Both stay off the socket.

**`LOOP_HB` = `/FB[0]`, and the derivation is `clocks.md` §4's exactly.** The
frame is four bit positions:

```
 bit position    0    1    2    3
 FB[0]           0    1    0    1      128 kHz
 /FB[0]          1    0    1    0      rises at the frame edge and at mid-frame
 FB[1]           0    0    1    1
 /FB[1] = TX_CLK 1    1    0    0      rises at the frame edge
```

`/FB[0]` rises at the start of bit 0 and again at the start of bit 2, and
`/FB[0] ÷ 2` **is** `TX_CLK`, in phase. That is a2's whole contract
(`clocks.md` §5), met by a tap of the same counter and not by a divider on any
card — so the CVSD subscriber line card's differential-Manchester encoder gets
what it gets in an exchange block, from `/SLOT[1]`, and in an MF8 shelf, from
the '4040. **Three hosts, one waveform.**

### 3.3 Transmit

```
  C_TX[1] ──┐
  C_TX[2] ──┤ frame mux, 4:1 on FB[1:0] ──► TX_BIT ──► P ──► MF2-A
      F  ───┤      bit 0 = F   bit 1 = C1
      S  ───┘      bit 2 = S   bit 3 = C2
```

| function | part | signal |
|---|---|---|
| F generator | ⅓ 74HC10 | `F = NAND(SFC2, SFC1, SFC0)` — 0 only at state 7, the word `11111110` |
| Frame mux | ½ 74HC153 | 4:1 on `FB[1:0]`; the framing bits are mux **inputs**, not an override |
| Signalling mux | 74HC151 | 8:1 on `SFC[2:0]` — the S lane (§3.4) |
| Counters | 74HC393 | `FB[1:0]` on `H`, `SFC[2:0]` on `TX_CLK` |

**One race, carried from `mf8-spec.md` §10.** `F` is a superframe-counter output
read at bit-count 0, which is when that counter has just ticked. Clock `SFC` off
the opposite edge, or from the 3→0 transition of `FB`.

### 3.4 The S lane

| state | S carries | `'151` input |
|---|---|---|
| 0 | **guard, 0** | tied low |
| 1 | `A_TX[1]` | a6 of seat 1 |
| 2 | **`RAI`** — reserved | §3.7 |
| 3 | reserved | tied low |
| 4 | **guard, 1** | tied high |
| 5 | `A_TX[2]` | a6 of seat 2 |
| 6 | **`/RAI`** — reserved | §3.7 |
| 7 | reserved | tied low |

Guard geometry is `spec.md` §3.2: two states of the same parity, values different
from each other and from F at those states. `sim/mf2.log` measures what it buys —
with the guard out of the receiver's check, a lane carrying the F word false-locks
**12 of 16** start-ups; with it, **0 of 16**. A single guard state instead of a
pair lets the F-word lane through 4 of 16. The pair is load-bearing.

**States 2 and 6 are reserved, not assigned.** The complement pair is the shape
`mf8-spec.md` §3.5 measured as the better of two and decided on for MF8's remote
alarm, and MF2 has spare states so it can carry one **without spending a guard
seat and without a 16-frame phase** — the thing MF8 could not have. It is not
frozen here: `mf2/sim.md` wants a `rai` run first, and until that exists §3.7 is
a footprint and a lamp.

### 3.5 Receive

```
  MF2-A ──► RX_BIT, RX_STB, /CD ──► framer ──┬──► C_RX[1..2], A_RX[1..2]
                                             ├──► RX_CLK, RX_OCT
                                             └──► MUTE, LOCK, CD
```

| function | part |
|---|---|
| Superframe counter | ½ 74HC393, clocked by the recovered frame wrap |
| Expected F | ⅓ 74HC10 |
| Guard decode | ¼ 74HC02 — enable `NOR(SFC1, SFC0)`, expected `SFC2` |
| Compare and good-frame gate | 74HC86 / 74HC08 |
| Acquisition, 32 frames | ½ 74HC393 |
| Loss of frame, +2/−1, floor 0, trip 12, **every frame** | 74HC193 |
| Loss of frame, +2/−1, **guard states only** | 74HC193 — clocked by the guard enable; either carry drops lock |
| Lock state | ½ 74HC74 |
| Signalling demux | 74HC259 on `SFC[2:0]`, 2 of 8 used |
| Channel demux | 2 × ½ '74 written at bit times 1 and 3 |

**Both counters are mandatory, and `sim/mf2.log` measures it.** With the F word
in one seat and speech in the other, the framer acquires a wrong alignment 24 of
24 forced attempts; **with the frame counter alone it never releases**, and with
the guard counter it releases in 22–262 frames, mean **1.40 ms**, none stuck.

### 3.6 What MF2-D drives toward the cards

One 74HC244 with 33 Ω series, as `mf8-backplane.md` §8 has it: `TX_CLK`,
`LOOP_HB`, `TX_OCT`, `FILL`, `RX_CLK`, `RX_OCT`, `MUTE`. Per-slot lines are
point to point and need no buffer.

### 3.7 The panel

| lamp | from | means |
|---|---|---|
| `LOCK` | lock state | the framer is locked |
| `CD` | `/CD` from MF2-A, ORed with the digital no-transition timer | carrier present |
| `RAI` | S state 2 held for 32 ms | **the far end is not locked** — reserved until §3.4's run |

`LOCK` / `CD` / `RAI` are **not socket pins** (`terms.md`): they are MF2-D
outputs to the panel, exactly as they are on a trunk card.

### 3.8 The hotline cadence gate

At a two-unit span **nothing cadences A**, and that is a real gap rather than a
detail. `mf8-psu.md` §3.2 and `mf8-backplane.md` §8 both say "cadence is the far
A bit", and on every other link the far end is an exchange port whose `E` is
chopped by `/RING_CAD` (`fabric.md` §3.5). Here there is no exchange, so a lifted
handset would ring the far phone **continuously**.

Per channel, behind a jumper on MF2-D:

```
A_TX_line[n]  =  A_TX_card[n] · ( A_RX[n] + RING_CAD )
```

`RING_CAD` is 2 s on / 4 s off from a '4040 off `TX_CLK` with a nibble of
jumpers — the `tone-plan.md` §5.2 idiom, which `clocks.md` §3 blesses as a
divider and not a clock. The `A_RX` term releases the chopping the moment the far
end answers, so an established call does not chatter the far ring relay.
≈ 1½ packages a channel, and **no channel card changes** — which is what "the
same subscriber cards as the exchange and MF8" requires.

---

## 4. Pass header P — MF2-D ⇄ MF2-A

2 × 7, odd signal and even ground, short, keyed so **A and D cannot mate
reversed and MF2-D cannot mate a Trunk-A**. Directions are signal flow.

| pin | | pin | |
|---|---|---|---|
| 1 | `TX_BIT` — 256 kb/s, D → A | 2 | `GND` |
| 3 | `LINE_HB` — 512 kHz, D → A | 4 | `GND` |
| 5 | `H` — 256 kHz, D → A | 6 | `GND` |
| 7 | `RX_BIT` — ~256 kb/s, A → D | 8 | `GND` |
| 9 | `RX_STB` — ~256 kHz, A → D | 10 | `GND` |
| 11 | `/CD` — level, A → D | 12 | `GND` |
| 13 | `+5 V` | 14 | key |

**Nothing analog crosses**, as on MF8.

**`H` is passed, not derived on A**, which closes `mf8-trunk.md` §5's open item
for MF2. A ÷2 on MF2-A would power up on a random phase, and the encoder's
cell boundaries would then disagree with the frame counter that produced
`TX_BIT`. One pin removes a phase hazard; `clocks.md` §3's rule — no board makes
a clock but the one that owns the crystal — is the same argument at board scale.

That is the only difference from `mf8-trunk.md` §2.3's table, which is otherwise
this one at twice the rate.

---

## 5. MF2-A — the analog board

### 5.1 Transmit

| item | specification | from |
|---|---|---|
| Encoder | **74HC112** JK, `J = K = EN`, `EN = NAND(/H, TX_BIT)`, clocked by `LINE_HB` | `mf8-spec.md` §9.2 as corrected by `circuit-review.md` §1 |
| Driver | 75176 differential transceiver, driver half | §9.3 |
| Series matching | two ~50 Ω into the 100–135 Ω pair, ~25 mA from a 5 V swing | §9.3 |
| Slew limiting | ~150 ns edges, R and shunt C on the rate plug. At 512 kBaud that is 7.7 % of a 1 953 ns half-cell — comfortable, where MF8 spends 15.4 % | §9.3 |
| Transformer | 1:1, ≥ 33 mH, **centre-tapped on the line side**, specified as magnetising **and leakage** inductance and never as a coupling coefficient (§8) | §9.3 |
| Protection | gas tube to ground both conductors, series PTC, TVS above the feed voltage | §9.3 |

**Check the encoder's hold margin against the specific parts.** §9.2's JK samples
`H` from before the edge and depends on the divider's clock-to-Q exceeding the
JK's hold time — "a hold violation works on a warm bench and fails at
temperature".

### 5.2 Receive — the Q3 rate plug

The receiver is `mf8-spec.md` §9.4's clockless interval classifier. **There is no
clock anywhere on the receive timing path**, which is the property that makes the
repeater a comparator and a driver (`repeater.md`).

| function | part | signal out |
|---|---|---|
| Termination | 100–135 Ω on the line side of the comparator | |
| Input filter | two RC sections at the symbol rate | |
| Comparator | hysteresis ≤ 10 % of received amplitude | |
| Transition detector | 74HC86 — comparator XOR a short RC-delayed copy | one pulse a transition |
| Dead-time timer | ½ 74HC221, non-retriggerable | |
| Classifier timer | ½ 74HC123, retriggerable | |
| LONG sample, MID state | 74HC74 | **`RX_BIT`**, **`RX_STB`** |
| Carrier detect | timer on the transition pulse | **`/CD`** |

**The plug is `mf8-spec.md` §9.7's existing 256 kbps row**, which is why MF2
needs no line-code document of its own:

| | line | baud | filter | classifier 0.75 cell | dead 0.2 cell | carrier |
|---|---|---|---|---|---|---|
| MF8, Q2 | 512 k | 1.024 M | 1.0 MHz | 1 465 ns | 391 ns | 3.9 µs |
| **MF2, Q3** | **256 k** | **512 k** | **512 kHz** | **2 930 ns** | **781 ns** | **7.8 µs** |

**MF2 is the comfortable member of the family to build.** §9.4 warns that at
1.024 MBaud the absolute timing window is ±98 ns, "where layout stray
capacitance stops being negligible". At 512 kBaud it is **±195 ns**.

Three of §9.4's rules apply unchanged and are easy to get wrong: the receiver's
rate must match the **far** end's transmitter, so the plug is set per direction;
"sample, then retrigger" is three same-edge reads and must use both edges of the
dead-time pulse (`circuit-review.md` §3); and the state self-heals, so there is
no lock to lose on the classifier itself.

### 5.3 Preamp and equaliser

`mf8-spec.md` §9.3's footprint, unpopulated on short sections. **At the 1 km
sections `repeater.md` specifies it is not needed**: 1 km is 10.0 dB in
differential Manchester's band, and a 5 V 75176 launching ~2.7 V differential
leaves ~0.86 V at a 50 mV comparator — 5.8 % hysteresis, inside §9.3's
"specify ≤ 10 %".

### 5.4 The rear, and the simplex feed

**Four conductors**, a pair each way, as `common-cards.md` §7.3 gives the trunk
card. The rear leaves MF2-A only; the stack carries no line conductor.

The **simplex feed** — the DC that powers line-fed repeaters (`repeater.md`) — is
injected on the transformers' line-side **centre taps** on this board, so it adds
no rear pin. `mf8-spec.md` §9.3 already requires the tap: "brought out to an
unpopulated footprint for a simplex feed. DC injected there is common-mode and
the ampere-turns cancel. **Specify it now** — retrofitting means a new
transformer." This is the design that cashes it in.

Two consequences:

- the feed is **common mode**, so the 56 V TVS, which is tip–ring, never sees it;
- §9.3's "the TVS must clamp above the eventual 48 V feed voltage" becomes a real
  number, and so does the gas tube's DC sparkover — `repeater.md` §8 sets it.

---

## 6. The PSU — `mf8-psu.md`, with a smaller load

The rails are `mf8-psu.md` §2's and the two boards are its §4. **MF2 adds no
rail**: the line driver is a 75176 on `+5 V`, so there is no bridge supply and
nothing above the family's existing `−48 V` and `RING`.

| unit content | fit |
|---|---|
| two CVSD subscriber line cards | `+5 V`, `−48 V` phantom. No `±12 V`, no `RING` |
| FXS | full: `+5`, `±12`, `−48`, `RING` |
| FXO only | `+5`, `±12`; no `−48`, no `RING` |
| data + voice | `+5`, and `−48` if the voice card is CVSD |
| MF2-D / MF2-A bring-up, no channels | `+5 V` only |
| **feeding a line-fed repeater** | `−48 V` with a constant-current source into MF2-A's centre taps |

The last row is MF2's only addition to `mf8-psu.md` §6, and it is a population of
an existing rail rather than a new one.

---

## 7. Every signal in the unit, in one table

| signal | rate | where it lives | direction |
|---|---|---|---|
| `TX_CLK` | 64 kHz | MF2-D → C, a1 | frame clock; rising edge is the start of bit 0 |
| `LOOP_HB` | 128 kHz | MF2-D → C, a2 | `/FB[0]`; `÷2` is `TX_CLK`, in phase |
| `TX_OCT` | 8 kHz | MF2-D → C, a3 | superframe state 7 |
| `FILL` | 32 kHz | MF2-D → C, a4 | `TX_CLK ÷ 2`, common to both seats |
| `C_TX[n]` | 64 kb/s | card → MF2-D, a5 | into frame-mux input 1 or 3 |
| `A_TX[n]` | level | card → MF2-D, a6 | into signalling-mux input 1 or 5 |
| `RX_CLK` | 64 kHz | MF2-D → C, a7 | recovered frame clock |
| `RX_OCT` | 8 kHz | MF2-D → C, a8 | recovered state 7 |
| `C_RX[n]` | 64 kb/s | MF2-D → C, a9 | from the channel demux |
| `A_RX[n]` | level | MF2-D → C, a10 | from the `'259`, raw |
| `MUTE` | level | MF2-D → C, a11 | framer not locked |
| card word, `/ANS`, `RAI` | — | card → MF2-D, a12–a14 | open drain, 680 Ω pull-up (§2.1) |
| `H` | 256 kHz | MF2-D → MF2-A, P5 | line bit clock, and the half-cell phase |
| `LINE_HB` | 512 kHz | MF2-D → MF2-A, P3 | the line's half-bit clock |
| `TX_BIT` | 256 kb/s | MF2-D → MF2-A, P1 | F, C1, S, C2 in turn, before the encoder |
| `RX_BIT` | ~256 kb/s | MF2-A → MF2-D, P7 | recovered bit from the classifier |
| `RX_STB` | ~256 kHz | MF2-A → MF2-D, P9 | accepted-transition strobe that writes it |
| `/CD` | level | MF2-A → MF2-D, P11 | low = no carrier; forces LOF |
| `FB[1:0]` | 256 kHz | MF2-D only | bit position; the frame-mux address |
| `SFC[2:0]` | 64 kHz | MF2-D only | superframe state; the S-mux and `'259` address |
| `F`, `S` | 64 kHz | MF2-D only | mux inputs, never an override |
| `RING_CAD` | 2 s / 4 s | MF2-D only | the hotline gate (§3.8) |
| `LOCK`, `CD`, `RAI` | level | MF2-D → panel | lamps, not socket pins |
| line pair ×2 | 512 kBaud | MF2-A rear | four conductors |
| simplex feed | DC | MF2-A centre taps | common mode; no rear pin |

---

## 8. Not measured, and open

- **Every board.** Nothing laid out, nothing on a bench, no connector chosen.
  The connector family (DIN 41612-B vs 0.1 inch) is open for the whole project
  (`common-cards.md` §7.1), not MF2's to close.
- **The whole physical layer**, inherited from `mf8-spec.md` §15 and never
  measured there: driver, transformer, filter, comparator, classifier
  tolerances, squelch levels, signalling RC. `spice/dm/` is where that starts,
  and **nothing in the DM PHY has ever been simulated at circuit level**.
- **The transformer.** It must be specified as magnetising inductance *and*
  leakage, never as a coupling coefficient: `ami_xfmr.sub`'s `3.3 mH, k = 0.99`
  is 33 µH of leakage and a 1.06 MHz pole, but the same `k` at the family's
  ≥ 33 mH is 330 µH and a **106 kHz** pole, which closes a 512 kBaud eye
  outright. Target leakage ≤ 50 µH.
- **The encoder's hold margin** (§5.1) and **"sample, then retrigger"**
  (§5.2) — both are `circuit-review.md` corrections that have never been on a
  part.
- **The S map's states 2 and 6.** Reserved, not assigned; `mf2/sim.md`'s `rai`
  run freezes or kills the complement pair (§3.4).
- **The hotline cadence gate** (§3.8), drawn and measured end to end.
- **Package counts.** Counts of an undrawn schematic.
- **Seat keying** (§2.2): the rule is measured, the mechanism is not chosen.
- **`spec.md` §10's block adapter** — the exchange face — is out of scope here
  and unchanged by this document.
