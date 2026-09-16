# Channel card — E&M 4-wire, semi-analog CVSD

One card type. Both ends identical. Four slots per terminal.

No hybrid, no ringing generator, no loop feed, no high voltage anywhere on this
card. E&M 4-wire was chosen precisely to remove all of that; the FXO/FXS
variant is a separate optional card and carries those problems on its own.

---

## 1. What the card contains

```
   E&M transmit pair ─→ input filter ─→ CVSD ENCODER ─→ C bit  ─┐
                                              ↑ TX 32 kHz clock │ to TX card
   M lead ─→ opto ─────────────────────────────────→ A bit  ────┘

   E&M receive pair ←─ recon filter ←─ CVSD DECODER ←─ C bit  ←─┐
                                              ↑ RX 32 kHz clock │ from RX card
   E lead ←─ opto ←─ RC + Schmitt ←──────────────── A bit  ←────┘
```

**The two halves never meet.** The encoder is clocked by the local transmit
oscillator; the decoder is clocked by the clock recovered from the far end.
These are different clock domains and are never compared — that is the whole
point of the two-independent-directions architecture (spec §1). Do not be
tempted to run both from one clock.

---

## 2. CVSD engine

The encoder contains a decoder: its integrator reconstructs exactly what the
far end will reconstruct. **Draw the engine once and populate it twice.** The
only difference is where the data bit comes from.

```
                    ┌──────────────── integrator out ───────────────┐
                    │                                               │
   audio in ──→ [+]                                                 │
                 LM311 ──→ D  Q ──→ C bit out        (ENCODE)       │
   integrator ─→ [−]        │  (74HC74, clk 32 kHz)                 │
                            │                                       │
   C bit in ────────────────┘                        (DECODE)       │
                            │                                       │
                            ├──→ 2 more FFs ──→ 3-bit run register  │
                            │                         │             │
                            │                    coincidence        │
                            │                  (all three equal)    │
                            │                         │             │
                            │                    syllabic RC        │
                            │                     τ = 6 ms          │
                            │                         │             │
                            │                        Iabc           │
                            ↓                         ↓             │
                      polarity ──────→ LM13700 OTA ───┴→ Iout ──────┤
                                                                    │
                                              C_int ∥ R_int ────────┘
                                              τ = 3 ms → buffer
```

### 2.1 The OTA does two jobs

An LM13700 transconductance amplifier gives output current proportional to its
`Iabc` control current, with sign set by its differential input. That is
**both** the voltage-controlled current source and the ± steering switch, in one
part. It removes the discrete current source that would otherwise be the least
stable thing on the card, and it is a dual — one package serves both engines.

- **`Iabc`** ← syllabic filter voltage through two resistors: one from a fixed
  bias setting `I_min`, one from the syllabic node adding up to `I_max − I_min`.
  Two resistors give the linear map `step = step_min + syl·(step_max − step_min)`
  that the model uses.
- **Differential input** ← the data bit, resistively divided to roughly ±100 mV
  about the bias point. That is well past the input stage's ~±25 mV linear
  range, so `Iout = ±Iabc` — a clean current-steering switch rather than a
  linear multiplier.

### 2.2 Integrator

OTA output current into `C_int ∥ R_int` to ground, then a high-impedance buffer
(TL072 follower, or the LM13700's own Darlington).

This gives `step = I · t_bit / C` and leak `τ = R_int · C_int` directly — the
same two relationships the simulation models, so bench results and simulation
stay comparable.

### 2.3 Values

Target parameters, from `run.BASE` and `run.SLEW` (the values the codec model
was tuned to):

| parameter | value |
|---|---|
| bit rate | 32 kbps |
| run window | 3 bits |
| τ_syl | 6 ms |
| τ_int | 3 ms |
| companding | 30 dB (31.6:1) |
| slew | 12000 full-scale units/s |
| step_max | 0.375 of full scale per bit |

Worked starting point, full scale ±1 V about bias:

| | value | note |
|---|---|---|
| `C_int` | 10 nF | film |
| `R_int` | 300 kΩ | τ_int = 3 ms |
| `Iabc` max | **120 µA** | `slew · C_int` — the bit rate cancels |
| `Iabc` min | 3.8 µA | 31.6:1 companding |
| `C_syl` | 100 nF | film |
| `R_syl` | 60 kΩ | τ_syl = 6 ms |

Both `Iabc` endpoints sit comfortably inside the LM13700's useful range.

**`Iabc max` is the one trimmer on the card.** Note that `slew = Iabc / C_int`
with the bit rate cancelling entirely, so it is set by two components and
nothing else.

Measured sensitivity at 32 kbps (speech, matched pair):

| slew | segSNR | |
|---|---|---|
| 9000 | 18.84 dB | slope overload begins |
| 11000 | 18.94 dB | |
| **12000** | **18.90 dB** | chosen — 120 µA is a round target |
| 15000 | 18.68 dB | granular noise begins |

A broad optimum: within 1 dB of peak runs roughly 6000–18000, i.e. 0.5× to 1.5×
nominal, so a 3:1 trim range on `R_abc` covers it with margin.

**Set it by measurement, not by ear.** Measure the actual `C_int`, compute
`Iabc = 12000 × C_int`, set the current, then confirm with a 1 kHz tone at
nominal level looped encoder-to-decoder on the card. The optimum is too flat to
find reliably by listening.

**The trims need not match between cards** — §2.4 shows step-size mismatch is
pure gain error, ±30% tolerable. Trim each card to its own computed target.

**Expect thermal drift.** The LM13700's transconductance follows `Iabc/2V_T`, so
it carries the thermal-voltage tempco, about −0.33%/°C — roughly 17% over a 50°C
range. That is inside the ±30% gain budget and shows up as level, not
distortion, so leave it alone in the first build. Driving `Iabc` from a PTAT
reference cancels it if it ever matters.

### 2.4 Component tolerance — measured, and looser than expected

`tolerance.py` sweeps encoder-on-one-card against decoder-on-another and finds
the mismatch at which segmental SNR drops 1 dB:

| network | tolerance | failure mode |
|---|---|---|
| integrator R·C | ±30% | distortion |
| **syllabic R·C** | **±20%** | distortion — this is the binding spec |
| step size | ±30% | **pure gain error, no distortion at all** |

The step-size result is the useful one: a 15% mismatch produces 1.19× gain with
segmental SNR unchanged at 17.4 dB across the entire sweep. It is a level
offset, not degradation, and a decibel or two of level error on a trunk is not
worth engineering away.

**BOM consequence: 1% resistors and 5% film capacitors.** That gives ±6% per
card and ±12% worst-case card-to-card, against a ±20% budget. No C0G is
required anywhere on this card — the tight-tolerance part is the monostable RC
on the receive card, not here. This was the main risk in choosing semi-analog
over a codec chip, and it has largely evaporated.

### 2.5 Coincidence detector

All three run-register bits equal:

```
coincidence = XNOR(Q0,Q1) · XNOR(Q1,Q2)
```

Two XORs from a 74HC86 and one AND. One 74HC86 and one 74HC08 cover both
engines on the card.

---

## 3. Audio path

**Input (E&M transmit pair → encoder):** 600 Ω transformer, then band-limit
300–3400 Hz. Two op-amp sections.

**Output (decoder → E&M receive pair):** reconstruction lowpass at 3400 Hz,
then 600 Ω transformer. **This filter is not optional.** CVSD's output carries
large quantisation noise above the audio band and the reconstruction filter is
what makes it listenable; build it at 3rd or 4th order, not 1st.

Nominal level: the codec parameters were tuned at 0.15 rms of full scale, so
set the input gain to place nominal trunk level there. Getting this wrong
costs SNR directly — the companding is tuned around a level.

One TL074 covers both filters.

---

## 4. E&M signalling

One bit each way, which is an exact fit rather than a compromise: E&M is a
two-lead interface with one lead driven outward and one sensed.

| lead | direction | on this card |
|---|---|---|
| **M** | sensed locally, transmitted | opto isolator → A bit to the TX card |
| **E** | received, driven locally | A bit → RC + 74HC14 → opto → E lead |

### 4.1 Type V, laid out type-agnostic

**Build Type V.** Both leads operate identically — assert by grounding, idle
open — so the circuit is symmetric and the same card works at both ends,
matching the "identical cards everywhere" property the rest of the system has.

All five E&M types carry one binary state each way, so **the frame, the A bit
and every digital block on this card are unaffected by the choice.** What
differs is only the lead circuit:

| Type | Leads | M lead | E lead | Common ground needed |
|---|---|---|---|---|
| I | 2 | ground / −48 V | open / ground | yes |
| II | 4 (+SB, SG) | open / to SB | open / to SG | **no — isolated** |
| **V** | **2** | **open / ground** | **open / ground** | yes |

(Types III and IV are four-lead variants, uncommon and largely obsolete;
confirm their details against whatever you are actually connecting to rather
than against this table.)

**Opto-isolating both leads makes the card nearly type-agnostic**, because the
opto already provides the isolation each type arranges differently. What
actually changes between Type I and Type V is the current-limit resistor and
whether −48 V is routed to the connector — both jumperable.

So: populate for Type V, jumper for Type I, and **lay out four connector
positions per channel even though only two are populated.** That leaves Type II
available later without a board re-spin, which is the one you would want if the
switch ever ends up in a different building with a different ground reference.
Since the E&M run is local — the long haul is the carrier itself — a common
ground is normally fine, so this is insurance rather than a likely need.

**Integration:** RC, τ = 2 ms, into a 74HC14 Schmitt. One resistor, one
capacitor, one gate — this is both the error filter and the contact debounce.
Measured zero spurious assertions at line error rates to 6e-2, and dial pulses
recovered 78/78 with 0.16% ratio error (spec §7.1).

`A = 1` means active. Idle is 0, so the loss-of-frame clear on the receive card
drives the E lead to idle with no extra logic.

---

## 5. Package count

| function | parts |
|---|---|
| Sampling + run registers, both engines | 3 × 74HC74 |
| Coincidence, both engines | 74HC86, 74HC08 |
| Signalling Schmitt | 74HC14 |
| OTA step size and steering, both engines | LM13700 |
| Integrator buffers | TL072 |
| Encoder comparator | LM311 |
| Audio filters | TL074 |
| E&M lead isolation | 2 optos + drive transistor |
| Audio transformers | 2 × 600 Ω |

**~11 packages plus two transformers.** No high voltage, single +5 V for the
logic plus a small analog rail.

---

## 6. Backplane

Per slot: 7 signals plus power.

| signal | direction | from/to |
|---|---|---|
| TX 32 kHz clock | in | TX card |
| C bit out | out | TX card mux |
| A bit out | out | TX card mux |
| RX 32 kHz clock | in | RX card |
| C bit in | in | RX card demux |
| A bit in | in | RX card demux |
| Mute / LOF | in | RX card |

Adding a channel is a card and a slot strap; nothing on the common cards
changes. Unequipped slots need pull resistors on their mux inputs, not logic.

---

## 7. Bring-up order

1. **Encoder alone, looped to its own decoder** on the same card — bypass the
   line entirely. This proves the CVSD engine and the filters, and any tracking
   problem here is a component error, not a link error.
2. **Trim `Iabc` max** for best audio, and record the value. This is the one
   adjustment.
3. **Card to card over the backplane**, still no line. Confirms the ±20%
   tolerance holds between two independently built cards — this is the
   measurement that validates choosing semi-analog over a codec chip.
4. Only then connect the transmitter and receiver.
