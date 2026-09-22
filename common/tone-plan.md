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
- **ROM cadences are taps off the address counter.** No table, no decode, no
  comparator. The double ring is one NOR gate. The analog card uses a 16-bit
  jumper mask off `TX_CLK` instead (§5.2).
- **Warble quality is optional on the analog card.** A hard square gate at the
  warble rate costs 52 spurious lines and 23 dB (`sim/tones.py warble`); the
  card prefers a soft path, and a jumper chooses pure tone vs that modulated
  path — not a hard requirement to meet the ROM's SNR.

> **Status: proposed.** `sim/tones.py` is the run and `sim/tones.log` the record.
> Nothing here is perceptual — nobody has listened to `sim/out/tone_*.wav`. No
> circuit is drawn and no image burned. The historical plans in §2 are from
> memory, and §6 says which to distrust.

---

## 1. The tones

| category | reached by | image | cadence | gate |
|---|---|---|---|---|
| **dial** | class 5, port 01 | **A** — 425 ∿ 25, the Australian warble | continuous | none |
| **ringback** | the `RBT` bus | **A** | double pulse, 4.096 s | `NOR(Q17, Q15)` |
| **busy** | class 6, port 02 | **B** — 600 ∿ 120, the old Bell buzz | 0.512 / 0.512 s | `Q15` |
| **cannot-complete** | class 6 by address, port 03 | **B** | 0.256 / 0.256 s | `Q14` |

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
another class. **Ports 01–03** hold all three switched tones
(`protocol.md` §5), undialable because 0 is the operator key, and clear of
every MF8 trunk group.

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

Targets for the tones. The **ROM card meets them exactly.** The analog card
approximates by pot and jumper; warble quality is optional (§5).

| | | ROM gives | analog gives |
|---|---|---|---|
| plane A carrier | **425 Hz ± 1.5 %** | 421.875 (−0.74 %) | **f0 pot** |
| plane A modulation | **25 Hz ± 10 %** | 23.4375 (−6.25 %) | **f_w pot**, when warble jumper fitted |
| plane B carrier | **600 Hz ± 1.5 %** | 601.5625 (+0.26 %) | **f0 pot** |
| plane B modulation | **120 Hz ± 10 %** | 117.1875 (−2.34 %) | **f_w pot**, when warble jumper fitted |
| modulation shape | **sinusoidal** | exact | soft path preferred; square gate allowed as a parts trade (§5) |
| line spacing | **equal, to 1 %** | exact by construction | as pots drift |
| level | `NOMINAL_RMS` | exact | one trim |
| cadence | **± 10 %**, and the ratios of §4.2 / §5.2 | exact taps | 16-step jumper mask, §5.2 |

**Equal spacing is the binding one on the ROM.** 25 Hz is not a multiple of the
8 kB part's 7.8125 Hz grid, so the **carrier and the modulation** snap to the
grid and the sidebands fall where they fall. Rounding each sideband on its own
gives 398 + 422 + **453** — unequal, and no longer one tone.

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
| `C_TX` on the socket | port 01 | dial tone — the card's own port |
| rear pin 1 | port 03's `C_TX` net | cannot-complete — **slot 3 vacant** |
| rear pin 2 | port 02's `C_TX` net | busy — **slot 2 vacant** |
| rear pin 3 | `RBT` | ringback |
| rear pin 4 | `/RING_CAD` | the ring cadence |

**The hazard is a card seated in a punched slot**, which fights the wire.
Mitigated by it taking two deliberate acts — the punch, and leaving the slot
empty — and by the backplane's 4.7 kΩ pull to `FILL`, which makes a vacant slot
benign. **Blank slots 2 and 3 of block 0**, or seat one multi-output card at 01
and punch the rest. Block 0 is never an MF8 trunk group (`protocol.md` §5).

---

## 5. The analog card — one slot, one tone

Where the ROM card burns four tones into one part, the analog card is the cheap
opposite: **one oscillator into one encoder half, one tone out of one slot.**
Frequency and warble rate are pots; pure vs modulated and the cadence pattern
are jumpers. It is the card you set on the bench and leave alone.

**The measurement that shapes the warble jumper is negative:**

| making the warble | SNR | in-band lines |
|---|---|---|
| three lines, equal | 34.1 / 27.3 | **3** |
| carrier × (1 + 2cos) — identical | 34.1 / 27.3 | **3** |
| sine AM, depth 0.5 | 35.0 / 28.4 | **3** |
| **square gate at the warble rate** | **10.8 / 10.6** | **52** |
| square gate, RC-rounded 4 ms | 18.2 / 17.9 | 9 |

Cadence muting the encoder's **input** is right at ~2 Hz and **splatters at
25 Hz**. So the modulated jumper position prefers a soft path — RC-rounded gate
or a simple envelope — over a hard square at the LFO rate. A hard switch is
still allowed as a parts trade; the table above is why it is informed. The pure
position bypasses the modulator and feeds the carrier straight in. Wien bridges
and a four-quadrant OTA are **not** required on this card.

### 5.1 The whole of it

```
  [carrier osc]──▶ pot: f0 ──┬── pure ─────────────────────────┐
                             │                                 ▼
                             └── mod ──▶ [soft warble path] ─▶ [encoder input]
                                              ▲                     │
  [LFO osc]──────▶ pot: f_w ──────────────────┘                     │ muted when
                                                                    │ cadence bit = 0
  TX_CLK ──▶ ['4040] ── Q13 = 256 ms ──▶ nibble ──▶ ['150] ◀── 16 jumpers
                                              │                     ▼
                                         cadence bit           §12.1 encoder ──▶ C_TX
                                                                    │
                                                               ['244] rear → RBT / /RING_CAD
```

| | |
|---|---|
| Carrier | NE555 astable or a one-/two-transistor RC osc. **Pot sets the main frequency** (plane A ~425 Hz, plane B ~600 Hz) |
| Warbler | Second RC osc. **Pot sets the warble rate** (~25 Hz or ~120 Hz). Used only when the mod jumper is fitted |
| Pure / mod | 3-pin header: carrier → encoder, or soft-modulated carrier → encoder |
| Cadence | `'4040` off socket **`TX_CLK` (a1)**; **Q13 = 256 ms** clocks a 4-bit step into a 16:1 mux whose inputs are sixteen jumpers (or a DIP). Bit = 1 opens the encoder **input**; bit = 0 leaves the codec on its own `1010` |
| §12.1 encoder half | ≈ 4 packages incl. comparator (and LM13700 only if that half already carries one for the engine) |
| Level trim | one pot into the encoder, as every analog source |
| | **≈ 8–10 packages, ±12 V + +5, three pots, one jumper field** |

No `TICK`, no rear punch for clocks: the cadence divider is a tap of the socket
clock, not a crystal on the card (`clocks.md` §3).

### 5.2 Cadence from sixteen jumpers

Step period is fixed at **256 ms** (`2¹⁴ / 64 kHz`); sixteen steps make a
**4.096 s** cycle — the same window the ROM ringback uses. The pattern is the
mask, not a decode:

| tone | mask (16 bits, MSB = first step) | on / off shape |
|---|---|---|
| dial | `1111 1111 1111 1111` | continuous |
| busy | `1111 1111 0000 0000` | 2.048 / 2.048 s (8 on / 8 off) |
| cannot-complete | `1111 0000 1111 0000` | 1.024 / 1.024 s (4 / 4 / 4 / 4) |
| ringback | `1100 1100 0000 0000` | 0.512 / 0.512 / 0.512 / 2.560 s (2 on, 2 off, 2 on, 10 off) |

Busy is cannot-complete one stage slower, as in §4.2. Ringback matches §4.3's
double pulse. A ringback population also takes the cadence bit's complement out
the rear connector as `/RING_CAD`, same ownership rule as the ROM card (§4.3,
`tone-card.md` §5).

### 5.3 Against the ROM card

**One encoder makes one tone**, so four simultaneous tones are three or four
analog cards where the ROM is one.

| | ROM | analog |
|---|---|---|
| cards for four tones | **1** | 3–4 |
| packages | **7** | ≈ 8–10 each |
| rails | **+5 V only** | ±12 V and +5 |
| trims | **none** | **f0, f_w, level** |
| cadence | counter taps | 16 jumpers |
| frequency stability | **exact, forever** | RC drift; pots approximate §3 |
| warble SNR | exact sinusoidal | soft path preferred; square allowed |
| integration level | **the EPROM is LSI** | SSI/MSI and linear |

Both plug into the same socket. The ROM is the zero-trim multi-tone build; the
analog card is the one that needs no memory part and is set with pots and
jumpers.

---

## 6. Not measured, and open

- **Nothing perceptual.** `sim/tones.py render` writes `sim/out/tone_*.wav` as
  the card would produce them. **Nobody has listened.** Whether a −6.25 % warble
  rate, a −0.74 % carrier or §4.3's 1:1 burst-to-gap is noticeable is not an SNR
  question and this document cannot answer it.
- **The ring period is 4.096 s** against the 3.0 s it is modelled on, all of the
  stretch in the silence, and the bursts are 0.512 s against 0.400. Both follow
  from binary timing and neither has been heard.
- **The historical plans are from memory**, not a standard in hand. The pre-1976
  Bell values and whether they were AM or additive are least sure, and **plane B
  is built on them**.
- **No circuit, either card.** Oscillator start-up against a tone that must be
  present the instant a caller lifts is not worked, nor how clean a 555 carrier
  is after the encoder's band-limit, nor which soft warble path (§5) a board
  actually ships.
- **Analog cadence masks** (§5.2) are an assignment of the jumper field; nothing
  has been strapped or listened to. A different step rate is free if a later
  bench prefers it.
- **The overmodulated envelope** of a depth-1.0 warble reverses phase twice a
  cycle; what the syllabic filter makes of that at a cadence seam is not worked.
  The seam itself measures −44.7 dB worst over 32 cut points.
- **§4.4's punched outputs** are an assignment. No wiring field exists, and
  nothing prevents a card being seated in a punched slot.
