# The tone plan — four tones from one ROM and one counter

A call-progress tone in this design is a `C` bit stream like any other
(`features.md` §2), so it can come from an analog oscillator through a CVSD
encoder or from a ROM played on repeat. This document settles **which tones**,
and specifies both cards.

- **Four tones, two images.** Dial and ringback are the same bit stream, gated
  differently. Busy and cannot-complete are the same stream, gated differently.
- **A warble is one oscillator, not three.** 400+425+450 at equal amplitude *is*
  `cos(2π·425t)·[1 + 2cos(2π·25t)]`, so plane A costs one carrier and one
  modulator.
- **Every cadence is a tap off the address counter.** No table, no decode, no
  comparator. The double ring is one NOR gate.
- **The analog card may not make the warble with a switch.** Measured: 52
  spurious lines and 23 dB lost. It needs a true four-quadrant multiplier.

> **Status: proposed.** `sim/tones.py` is the run and `sim/tones.log` the record.
> Nothing here is perceptual — nobody has listened to `sim/out/tone_*.wav`. No
> circuit is drawn and no image burned. The historical plans in §2 are from
> memory, and §6 says which to distrust.

---

## 1. The tones

| category | reached by | image | cadence | gate |
|---|---|---|---|---|
| **dial** | class 5, port 10 | **A** — 425 ∿ 25, the Australian warble | continuous | none |
| **ringback** | the `RBT` bus | **A** | double pulse, 4.096 s | `NOR(Q17, Q15)` |
| **busy** | class 6, port 14 | **B** — 600 ∿ 120, the old Bell buzz | 0.512 / 0.512 s | `Q15` |
| **cannot-complete** | class 6 by address, port 11 | **B** | 0.256 / 0.256 s | `Q14` |

`x ∿ y` is a carrier of *x* amplitude-modulated at *y*: three equally spaced
lines. **The letters are distinct images, not ROM bits** — what has to be
generated, and what an analog card needs an oscillator for.

| | burned lines | SNR best / worst | crest |
|---|---|---|---|
| plane A, 425 ∿ 25 | 398 + 422 + 445 | 34.1 / 26.5 dB | 7.7 dB |
| plane B, 600 ∿ 120 | 484 + 602 + 719 | 33.4 / 29.9 dB | 7.8 dB |

**Why two images.** Busy and cannot-complete are what a subscriber most needs to
tell apart, and in a one-frequency plan they differ only in speed. Here they
differ in speed *and* pitch, and neither can be mistaken for the low warble that
means the call is progressing.

**Why a fourth tone.** `marker.md` §3's class 6 is "cannot-complete: busy /
error tone" — one destination for both. Splitting them needs a second source
port, and the marker already computes the free test that would steer it. Under
the proposed class codes both tone ports are class *source* **reached by
address** (`extensions.md` §2.2), so a third is another address constant, not
another class. **Port 11** is free wherever block 1 is not a trunk group, and is
never dialable because 1 is a first key. Where block 1 *is* a trunk group, drop
to three tones and let busy share port 14 as it does today.

---

## 2. Why this plan and not another

Eight plans measured (`tones.log`, `plans`):

| plan | images | analog oscillators |
|---|---|---|
| ETSI / CEPT | 1 | 1 |
| Australian, old · Japanese NTT | 2 | **1** |
| **this plan** | **2** | 2 |
| Bell, pre-1976 | 2 | 2 |
| Australian, modern | 3 | 3 |
| North American | 3 | 4 |
| British, old GPO | 3 | 4 |

- **Quality separates nothing.** Every plan lands 26–38 dB through the codec.
- **Cadence divisibility separates nothing either.** The tick need only *divide*
  each interval, not equal their GCD, so every plan lands under 1 % on some
  binary divide off `TX_CLK`.
- **The old GPO dial tone cannot be carried at all.** 33 + 50 Hz is below the
  300 Hz band limit of every card in the set.

The warble is why Australia wins on parts, and this plan takes it and adds one
carrier for the stop tones.

---

## 3. What any implementation must hold

Tolerances, so the ROM card and the analog card are interchangeable:

| | | ROM gives | analog gives |
|---|---|---|---|
| plane A carrier | **425 Hz ± 1.5 %** | 421.875 (−0.74 %) | RC, ± 1–2 % |
| plane A modulation | **25 Hz ± 10 %** | 23.4375 (−6.25 %) | RC, ± 5 % |
| plane B carrier | **600 Hz ± 1.5 %** | 601.5625 (+0.26 %) | RC, ± 1–2 % |
| plane B modulation | **120 Hz ± 10 %** | 117.1875 (−2.34 %) | RC, ± 5 % |
| modulation shape | **sinusoidal. A switch is prohibited — §5** | exact | OTA multiplier |
| line spacing | **equal, to 1 %** | exact by construction | as oscillators drift |
| level | `NOMINAL_RMS` | exact | one trim |
| cadence | **± 10 %**, and the ratios of §4.2 | exact | the same counter |

**Equal spacing is the binding one.** 25 Hz is not a multiple of the 8 kB part's
7.8125 Hz grid, so the **carrier and the modulation** snap to the grid and the
sidebands fall where they fall. Rounding each sideband on its own gives
398 + 422 + **453** — unequal, and no longer one tone.

---

## 4. The ROM card

### 4.1 The whole of it

```
                    ┌──── Q0..Q11 ─────────────────┐
  frame_stb ──▶ ['4040] ──▶ ['393] ── Q12 ─────────┤ 13-bit address
                              │                    ▼
                              │              [ 27C64, 8 kB ]
                              │                 D0 ─┬─▶ ['74] ─▶ plane A
                              │                 D1 ─┴─▶ ['74] ─▶ plane B
                              │
                     Q14, Q15, Q17 ──▶ ['02: NOR(Q17,Q15)]
                              │                    │
                              ▼                    ▼
                        ['157: three 2:1 muxes, tone against FILL]
                              │
                        ['244] ──▶ C_TX · RBT · /RING_CAD · two punched
```

| | |
|---|---|
| 27C64, 8 kB | **2 planes used**, 6 spare. One address a frame, 8192 = 128 ms |
| '4040 | address bits Q0–Q11 |
| '393 | Q12 completes the address; Q13–Q17 are the cadence |
| '74 | retime both planes on `TX_CLK`, against the ROM's access glitch |
| '02 | ½: the ring gate and its complement, `/RING_CAD` |
| '157 | three 2:1 muxes — ringback, busy, cannot-complete against `FILL` |
| '244 | six buffered outputs, 33 Ω |
| | **7 packages, +5 V only, no trims** |

No word shifter: tone cards reached by address need none (`extensions.md`
§2.2). `/ANS` is tied low, and `A_TX` low — a source never answers and is never
rung.

### 4.2 The cadences are counter taps

A counter bit's period is `2ⁿ⁺¹ / 64 kHz`:

| gate | taps | on / off | period | against nominal |
|---|---|---|---|---|
| dial | — | always | — | continuous |
| **cannot-complete** | `Q14` | 0.256 / 0.256 s | 0.512 s | 0.25 / 0.25 (+2.4 %) |
| **busy** | `Q15` | 0.512 / 0.512 s | 1.024 s | 0.5 / 0.5 (+2.4 %) |
| **ringback** | `NOR(Q17, Q15)` | §4.3 | 4.096 s | the double pulse |

**Cannot-complete is busy one stage faster**, which is what the Bell 60/120 IPM
pair is. Both land within 2.4 % of nominal with no adjustment of any kind.

### 4.3 The double pulse, in one gate

`/Q17` is a 2.048 s window; inside it `Q15` completes exactly two cycles. So
`/Q17 · /Q15` — one NOR — is on, off, on, then silence for the rest of `Q17`:

| | |
|---|---|
| burst | 0.512 s |
| gap | 0.512 s |
| burst | 0.512 s |
| silence | 2.560 s |
| **period** | **4.096 s** |

**The general rule is `/Qn · /Q(n−2)`**: the window is `2ⁿ` counts and the
chopper's period `2ⁿ⁻¹`, so it fits exactly twice. Burst and gap come out equal —
Australia's 2:1 would cost more gates, and against 0.4/0.2/0.4/2.0 this reads as
two distinct rings rather than a tight burr. That is the price of one gate, and
it is the design's only deliberate departure from the plan it is modelled on.

**`/RING_CAD` is the same gate, complemented.** It is low-true — `fabric.md`
§3.5's `A_RX = E · /(ON · /RING_CAD)` rings the phone while it is low — so:

```
  ring gate   = NOR(Q17, Q15)                 tone on
  /RING_CAD   = NOR(ring gate, ring gate)     the complement, a second '02 section
```

Two of the '02's four sections, no extra package. **The caller's ring and the
called phone's ring are then locked by construction, not by luck** — which is
what `tone-card.md` §5 wanted and could not otherwise guarantee, and it is the
reason this card and not the clock card owns the signal (`mainboard.md`
§2.1 for the same argument about `RBT`).

The clock card keeps a **pull-down** on it. The two bus lines fail differently:
undriven `RBT` pulled to `FILL` is silence, but undriven `/RING_CAD` pulled
*high* would mean **no phone ever rings**. Pulled low it rings continuously and
calls still complete, which is the degradation `mvp.md` already documents for
a shelf with no tone card fitted.

### 4.4 One card, four ports

A channel card reaches its own `C_TX` and no other, so three outputs leave by the
**rear connector** (`common-cards.md` §7.3) and are punched in the wiring field:

| output | to | |
|---|---|---|
| `C_TX` on the socket | port 10 | dial tone — the card's own port |
| rear pin 1 | port 11's `C_TX` net | cannot-complete — **slot 1 vacant** |
| rear pin 2 | port 14's `C_TX` net | busy — **slot 4 vacant** |
| rear pin 3 | `RBT` | ringback |
| rear pin 4 | `/RING_CAD` | the ring cadence |

**The hazard is a card seated in a punched slot**, which fights the wire.
Mitigated by it taking two deliberate acts — the punch, and leaving the slot
empty — and by the backplane's 4.7 kΩ pull to `FILL`, which makes a vacant slot
benign. **Blank those two slots.** It needs block 1's slots 1 and 4 free, so it
suits a standalone exchange or one using only trunk group 0.

---

## 5. The analog card

`features.md` §2's card plus a modulator. **The measurement that shapes it
is negative:**

| making the warble | SNR | in-band lines |
|---|---|---|
| three lines, equal | 34.1 / 27.3 | **3** |
| carrier × (1 + 2cos) — identical | 34.1 / 27.3 | **3** |
| sine AM, depth 0.5 | 35.0 / 28.4 | **3** |
| **square gate at the warble rate** | **10.8 / 10.6** | **52** |
| square gate, RC-rounded 4 ms | 18.2 / 17.9 | 9 |

§2's own trick — muting the encoder's **input** — is right for a cadence at 2 Hz
and **splatters at 25 Hz**. The modulator must be a true four-quadrant
multiplier; the LM13700 of `mf8-spec.md` §12.1 is already on the card, so it
costs half a package, but it may not be a switch.

| | |
|---|---|
| ½ TL072 | 425 Hz Wien bridge, amplitude stabilised |
| ½ TL072 | 25 Hz modulator |
| ½ LM13700 | the multiplier |
| §12.1 encoder half | ≈ 4 packages incl. LM13700, TL072, LM311 |
| the same counter and taps | §4.2 |
| | **≈ 11 packages, ±12 V, 3–4 trims** |

**One encoder makes one tone**, so every simultaneous tone is a full chain —
three or four cards where the ROM is one, and plane B needs a second carrier and
modulator besides.

| | ROM | analog |
|---|---|---|
| cards for four tones | **1** | 3–4 |
| packages | **7** | ≈ 11 each |
| rails | **+5 V only** | ±12 V and +5 |
| trims | **none** | 3–4 a card |
| frequency stability | **exact, forever** | RC drift |
| integration level | **the EPROM is LSI** | SSI/MSI and linear |

The analog card costs roughly five times the packages, two extra rails, four
trims and three more cards, to avoid one memory part. **If the integration rule
is binding that is the price and it is payable** — either card meets §3 and both
plug into the same socket. The rule is not written down anywhere in this
repository; the README says only "discrete logic".

---

## 6. Not measured, and open

- **Nothing perceptual.** `sim/tones.py render` writes `sim/out/tone_*.wav` as
  the card would produce them. **Nobody has listened.** Whether a −6.25 % warble
  rate, a −0.74 % carrier or §4.3's 1:1 burst-to-gap is noticeable is not an SNR
  question and this document cannot answer it.
- **The ring period is 4.096 s** against the 3.0 s it is modelled on, all of the
  stretch in the silence, and the bursts are 0.512 s against 0.400. Both follow
  from taking counter taps and neither has been heard.
- **The historical plans are from memory**, not a standard in hand. The pre-1976
  Bell values and whether they were AM or additive are least sure, and **plane B
  is built on them**.
- **No circuit, either card.** The Wien bridge's start-up against a tone that
  must be present the instant a caller lifts is not worked, nor the OTA's
  feedthrough.
- **The overmodulated envelope** of a depth-1.0 warble reverses phase twice a
  cycle; what the syllabic filter makes of that at a cadence seam is not worked.
  The seam itself measures −44.7 dB worst over 32 cut points.
- **§4.4's punched outputs** are an assignment. No wiring field exists, and
  nothing prevents a card being seated in a punched slot.
