# Tones — four tones in two timbres, and the cards that make them

A call-progress tone is a `C` bit stream like any other, so it comes either from
an oscillator through a CVSD encoder or from a ROM played on repeat. This covers
which tones, the ROM card, the analog card, the MF8 tone bus that lets one card
hold a whole shelf on a tone, and how ringback reaches a caller. Which ports hold
tones is `numbering.md` §2; what an exchange fits is `features.md` §1.

> **Built:** nothing. `newimpl` has no tone card, and `exch.v` ties `RBT` to `FILL` (no ringback card).
> **Proposed:** the ROM card, the analog card, the tone bus.
> **Measured in:** `sim/tones.py`. The committed `sim/tones.log` holds only its IMAGE section; §2's plans, §5's
> warble table and the cadence seam come from runs that are not logged.

## 1. The tones

| tone | reached by | image | cadence |
|---|---|---|---|
| **dial** | port 01, by address | **A**: 425 ∿ 25, the Australian warble | continuous |
| **busy** | port 02, by address | **B**: 600 ∿ 120, the old Bell buzz | 0.512 / 0.512 s |
| **cannot-complete** | port 03, by address | **B** | 0.256 / 0.256 s |
| **ringback** | the `RBT` conductor, in the ringing port's cell (§8) | **A** | open (§9) |

`x ∿ y` is a carrier *x* amplitude-modulated at *y*: three equally spaced lines.
The letters are images to generate, not ROM bits. **A warble is one oscillator**:
400 + 425 + 450 Hz at equal amplitude is `cos(2π·425t)·[1 + 2cos(2π·25t)]`, one
carrier and one modulator.

**Why two images.** Busy and cannot-complete are what a subscriber most needs to
tell apart. Here they differ in speed *and* pitch, and neither can be taken for
the low warble that means the call is progressing. Which failures get which is
`numbering.md` §4.

The burned image (`tones.log`, IMAGE): plane A carries 398 + 422 + 445 Hz at
36.4 dB SNR, plane B 484 + 602 + 719 Hz at 34.2 dB. Each is DC balanced to
within a bit, so nothing in a decoder drifts.

## 2. Why this plan

Eight plans were scored by `tones.py plans` (not in the committed log). In
images and analog oscillators: ETSI/CEPT 1 and 1; old Australian and Japanese NTT
2 and 1; **this plan** 2 and 2, as Bell before 1976; modern Australian 3 and 3;
North American and old GPO 3 and 4. Quality separates nothing (26–38 dB through
the codec), nor does cadence (every plan lands under 1 % on a binary divide of
`TX_CLK`), and the old GPO dial tone, 33 + 50 Hz, is below the 300 Hz band edge.
The warble is why Australia wins on parts; this plan adds a carrier for the stop
tones.

## 3. What any implementation must hold

These tolerances make the two cards interchangeable once the analog pots are set:

| | | ROM gives | analog gives |
|---|---|---|---|
| plane A carrier | **425 Hz ± 1.5 %** | 421.875 (−0.74 %) | f0 pot, ± 1–2 % |
| plane A modulation | **25 Hz ± 10 %** | 23.4375 (−6.25 %) | f_w pot, ± 5 % |
| plane B carrier | **600 Hz ± 1.5 %** | 601.5625 (+0.26 %) | f0 pot, ± 1–2 % |
| plane B modulation | **120 Hz ± 10 %** | 117.1875 (−2.34 %) | f_w pot, ± 5 % |
| modulation shape | **sinusoidal; a switch is prohibited (§5)** | exact | OTA multiplier |
| line spacing | **equal, to 1 %** | exact by construction | as the pots drift |
| level | `mf8.NOMINAL_RMS` | exact | one trim |
| cadence | **± 10 %**, and §4.1's ratios | exact taps | one 256 ms step |

**Equal spacing binds.** 25 Hz is not a multiple of the 8 kB part's 7.8125 Hz
grid, so the carrier and the modulation snap to the grid and the sidebands fall
where they fall. Rounding each sideband alone gives 398 + 422 + **453**: unequal,
and no longer one tone.

## 4. The ROM card

```
  TX_CLK ─▶ ['4040] ─ Q0..Q11 ─┐
              └─▶ ['393] ─ Q12 ─┴─▶ 13-bit address ─▶ [ 27C64 ] ─ D0, D1 ─▶ ['74] ─▶ planes A, B
                     └─ Q14, Q15, Q17 ─▶ ['02: NOR(Q17, Q15)]
                                      ─▶ ['157: each tone against FILL] ─▶ ['244] ─▶ C_TX, rear pins
```

| part | does |
|---|---|
| 27C64, 8 kB | **2 planes used, 6 spare**. One address a frame: 8192 bits, a 128 ms loop |
| '4040, '393 | Q0–Q12 the address; Q13–Q17 the cadence |
| '74 | retimes both planes on `TX_CLK`, against the ROM's access glitch |
| '02 | the ringback gate, as drawn (§4.1) |
| '157 | three 2:1 muxes: ringback, busy, cannot-complete against `FILL` |
| '244 | buffered outputs, 33 Ω |
| | **7 packages, +5 V only, no trims** |

### 4.1 The cadences are counter taps

Counter bit Qn has period 2ⁿ⁺¹ / 64 kHz. No table, no decode, no comparator:

| gate | tap | on / off | against nominal |
|---|---|---|---|
| dial | — | continuous | |
| **cannot-complete** | `Q14` | 0.256 / 0.256 s | 0.25 / 0.25 (+2.4 %) |
| **busy** | `Q15` | 0.512 / 0.512 s | 0.5 / 0.5 (+2.4 %) |
| ringback, as drawn | `NOR(Q17, Q15)` | 0.512 on, 0.512 off, 0.512 on, 2.560 off: a 4.096 s double pulse | §9 |

Cannot-complete is busy one stage faster, as the Bell 60/120 IPM pair is.

## 5. The analog card — one slot, one tone

One oscillator into one encoder half of `mf8-spec.md` §12.1, one tone out of one
slot. Pots set the carrier and the warble rate; jumpers choose pure tone or the
warble, and the cadence. The measurement that shapes it is negative (`tones.py
warble`, not logged):

| making the warble | SNR best / worst | in-band lines |
|---|---|---|
| three lines, equal | 34.1 / 27.3 dB | **3** |
| carrier × (1 + 2cos), identical | 34.1 / 27.3 dB | **3** |
| sine AM, depth 0.5 | 35.0 / 28.4 dB | **3** |
| **square gate at the warble rate** | **10.8 / 10.6 dB** | **52** |
| square gate, RC-rounded 4 ms | 18.2 / 17.9 dB | 9 |

Muting the encoder's **input** is right for a cadence at ~2 Hz and splatters at
25 Hz. **The warble is a four-quadrant multiplier (½ LM13700), never a switch at
the modulation rate**; the pure-tone jumper bypasses the multiplier.

### 5.1 The whole of it

| | |
|---|---|
| Carrier | NE555 astable or a one- or two-transistor RC oscillator; **pot sets it** (~425 or ~600 Hz) |
| Warbler | a second RC oscillator; **pot sets it** (~25 or ~120 Hz); used only with the warble jumper |
| AM | ½ LM13700, four-quadrant; depth fixed for equal sidebands |
| Pure / warble | 3-pin header: carrier, or multiplier out, into the encoder |
| Cadence | a '4040 and a '393 off `TX_CLK`, as on the ROM card: Q13 steps a four-bit count every **256 ms** into a 16:1 mux ('150, or a dual '151) of sixteen jumpers. A 1 opens the encoder input; a 0 leaves the codec on its own `1010` |
| Encoder half, level | §12.1's, ≈ 4 packages with the LM13700 and comparator; one level trim |
| | **≈ 10 packages, ±12 V and +5 V, three pots, one jumper field** |

The cadence is a tap of the socket clock, not a crystal on the card
(`clocks.md` §3).

### 5.2 Cadence from sixteen jumpers

Sixteen 256 ms steps make a 4.096 s cycle. The pattern is the mask, first step
at the MSB:

| tone | mask | on / off |
|---|---|---|
| dial | `1111 1111 1111 1111` | continuous |
| busy | `1100 1100 1100 1100` | 0.512 / 0.512 s, the ROM's `Q15` |
| cannot-complete | `1010 1010 1010 1010` | 0.256 / 0.256 s, the ROM's `Q14` |
| ringback, as drawn | `1101 1000 0000 0000` | 0.512 / 0.256 / 0.512 / 2.816 s, 2:1 burst to gap (§9) |

**Against the ROM card**: one ROM card makes all four tones at 7 packages, +5 V,
no trims and exact frequencies for ever; the analog card makes one, at ≈ 10
packages, ±12 V, three trims and RC drift, and needs no memory part. Either meets
§3 once the pots are set.

## 6. A tone card in a socket

The only card in the set that drives and never listens: it drives `C_TX` with
the tone off `TX_CLK`, holds `A_TX` low and ties a13 `/ANS`
low, so it is never busy, never rung and never gives its listener ringback; any
number may listen. It reads no a9 `C_RX`, a10 `A_RX` or a11 `MUTE`. At ports
01–03 the marker reaches it by address and never reads its word, so a12 needs no
part; anywhere else it carries a '165 with class 001, source (`card-word.md` §2).
The ROM card needs +5 V only; the analog card ±12 V as well, on socket row *c*
in an MF8 shelf and by harness in a block (`common-cards.md` §3).

**Two populations.** *Plain*: the tone on its own channel and nothing else. *Bus
driver*: ⅛ of a 74HC244 and 33 Ω from the node that feeds `C_TX`, out to one
rear-connector pin and a ground (§7, §8). The buffer is additive: `C_TX` is
unchanged, so the card keeps its own channel.

## 7. The MF8 tone bus

One tone card can hold every channel of an MF8 shelf on a tone, so every phone
hears fast busy the moment it is lifted: the difference between a dead telephone
and one that says no. **What must be broken is that `C_RX` already has a
driver**, the trunk card's '259, so a listening slot's `C_RX` is switched, not
paralleled:

```
 source card, bus driver:  encoder ─┬──────────────────▶ C_TX, its own channel
                                    └─[⅛ '244]─[33 Ω]─▶ rear pin ─ punched ─┐
 the tone bus, 4.7 kΩ to FILL ◀─────────────────────────────────────────────┘
 a listening slot:  a9 ◀─o─┬─ the trunk card's '259, output n    (normal)
                           └─ the bus                            (barred)
                     a 3-pin header: one or the other, never both
```

| on the backplane | |
|---|---|
| the bus | one trace the length of the shelf, to a punch-down in the wiring field |
| its idle | 4.7 kΩ to `FILL`, so an unfed bus is `1010`, as an empty slot is |
| listener select | a 3-pin header a slot: a9 to the '259 or to the bus |
| `MUTE` select | one 3-pin header, shelf-wide |

No tri-state, no enables, no new signal. **The driver is on the card**: the
socket has no pin for a tap, and feeding the bus then takes two deliberate acts,
a card built for it and a punch in the per-card wiring field.

**`MUTE` must be jumpered.** With the trunk down the CVSD line card switches an
off-hook phone to `1010` (`channel-cards.md` §2.3), which defeats the tone bus
on exactly the outage it is for. So the shelf-wide header takes `MUTE` from the
trunk card or ties it "locked", as every exchange block does:

| card | `MUTE` as usual | `MUTE` tied locked |
|---|---|---|
| CVSD line | hears `1010`: the tone is muted at the card | hears the tone |
| FXS, FXO, E&M | hears the tone (none reads a11) | the same |
| data | `RXD` forced to 1 | `RXD` follows the bus. Do not bar a data slot |

A barred shelf is one whose `MUTE` is tied locked: one jumper. Uses: a shelf
whose exchange or link is out, a terminal being commissioned, a shelf barred out
of hours; and any card feeding the others: a milliwatt, an announcement ROM.

## 8. Ringback on `RBT`

**Ringback is the one tone that is not switched to the caller**: the caller's
latch already points at the called port, so the tone arrives in that port's
cell. `RBT` is a bus conductor (`bus.md` §1), pulled to `FILL` through 4.7 kΩ at
the clock card. Each block receives it and each port's '157 puts it on the lane
while the port rings (`fabric.md` §5.2, `block-stack.md` §2.2). With no ringback
card `RBT` is `FILL`, and a caller hears silence while the far phone rings.

**The ringback card is a tone card with the bus-driver population**, its buffered
output onto `RBT`, keeping its own port with `/ANS` low. The dial-tone card at 01
is the natural home: dial on `C_TX`, ringback out of the rear. The ROM card holds
both images already; an analog card would populate the §12.1 card's decoder half
as a second encoder with its own carrier, warbler and cadence gate, which is
undrawn.

**`/RING_CAD` is the clock card's**, 2.048 s low (ringing) and 4.096 s high, a
6.144 s single ring (`clock_card.v`, `bus.md` §1). No tone card drives it.

## 9. Open

- **Ringback has no path in a block.** The block-stack form has no wiring field:
  `RBT` enters only through the block header's '244 (`block-stack.md` §2.1) and
  goes up the stack as a common, and nothing on a port card's edge header J4
  reaches it. `block.v` puts `FILL` on an unfitted port, so there is no seat for
  a card without a port either. The same holds for a ROM card's outputs to 02
  and 03. Options include a lead from the card to the bus's `RBT` pin or an
  `RBT` input on the header; neither is drawn. Until then a block gets no
  ringback, and one tone card a tone port.
- **Ringback's cadence.** The called phone rings 2.048 s on and 4.096 s off. The
  ROM card's gate as drawn is a 4.096 s double pulse at 1:1, the analog mask a
  4.096 s double pulse at 2:1. Neither matches the ring or is locked to it, and
  they differ from each other against §3. Locking needs `/RING_CAD` at the tone
  card, and the channel socket does not carry it.
- **Nothing perceptual.** Nobody has listened to `sim/out/tone_*.wav`: the
  −6.25 % warble, the −0.74 % carrier, the binary cadences.
- **The historical plans are from memory.** The pre-1976 Bell values, and whether
  they were AM or additive, are least sure, and plane B is built on them.
- **No circuit for either card**: oscillator start-up and the OTA's feedthrough
  are not worked; `spice/tone-analog/` explores the front end only.
- **A depth-1.0 warble** reverses phase twice a cycle; what the syllabic filter
  makes of that at a cadence seam is not worked. The seam itself is −44.7 dB
  worst over 32 cut points (`tones.py cadence`, not logged).
- **The tone bus is not in `mf8-backplane.md`** (§6, §8 there). Two bus drivers
  punched to one conductor are not detected; an RC on the '244's `/OE` would make
  power-up benign, and is not drawn. `MUTE` tied locked suppresses every card's
  squelch: not a jumper to leave fitted in service.
- **`sim/tones.log`** holds only the IMAGE section, and `tones.py` writes the
  image to `verilog/rtl/tone_rom.hex`, a retired path.
