# CVSD codec riser — both engines on one board

One 100 × 100 mm board with both halves of the type-A CVSD engine: the circuit
for the law of `mf8-spec.md` §12.1. It stacks on a base card through header R.
The base keeps the channel socket, the line circuit and the A-bit logic; the
riser keeps only the codec. The CVSD subscriber line card does not take it,
because its codec is in the phone.

> **Proposed.** The circuit matches the ngspice type-A decks (`spice/cvsd-enc/`, `spice/cvsd-dec/`) and falstad
> `CVSD-ENC`, `CVSD-DEC`, `RECON`. Header part, layout and `pcb/cvsd-codec/` are not drawn.
> **Measured in:** `tolerance.py` (`mf8-spec.md` §12.1's tolerances); §3.1's drive comparison is a scratch script.

## 1. Hosts and form

The FXS/FXO base (`channel-cards.md` §3) and the E&M base put audio, `TX_CLK`,
`RX_CLK` and the channel bits on R; the subscriber-adapter carrier puts
phone-side audio and its bit clock (`subscriber-adapter.md`); a bench carrier
takes banana or SMA audio. One layout serves every analog card, the engine is
brought up alone before it meets a line, and a spare swaps without touching the
line side. The riser is 1.6 mm, the upper layer of a two-layer sandwich, on the
base's four M3 holes with spacers as the datum and a 5 mm front keep-out; the
pitch is §6's. It does not pass the socket: clocks and bits arrive already chosen
by the base, so the two clock domains never meet on it.

## 2. Header R

A keyed 2×10, 0.1″, stackable (base top, riser bottom). Names from this card:

| pin | name | dir | |
|---|---|---|---|
| 1, 2, 6, 19, 20 | `GND` | | analog and logic return, starred at the base |
| 3 | `+5 V` | in | 74HC, the LM311 pull-up, V_A (§3.1) |
| 4, 5 | `+12 V`, `−12 V` | in | the op-amps, the OTA, the LM311 |
| 7 | `TX_CLK` | in | 64 kHz, encoder sample on the rise |
| 8 | `RX_CLK` | in | 64 kHz, decoder sample on the rise: **a separate net** |
| 9 | `BIT_ENC` | out | encoder bit → the base's `C_TX` |
| 10 | `BIT_DEC` | in | from the base's `C_RX`, after any `MUTE` gate there |
| 11 | `AUDIO_TX` | in | to the encoder at `mf8.NOMINAL_RMS`, 0.15 rms of full scale |
| 12 | `AUDIO_RX` | out | the decoder after reconstruction |
| 13 | `GND` | | audio return sense, tied to 1–2 at the base |
| 14 | `/OE` | in | low to run; open or high three-states `BIT_ENC` (optional) |
| 15, 16 | `SYL_E`, `SYL_D` | out | syllabic test points |
| 17, 18 | `Y_E`, `Y_D` | out | integrator test points (the decoder's before the low-pass) |

Not on R: −48 V, ringing, A bits, the word, `FILL`, `MUTE`, tip and ring. Audio is
±1 V full scale about ground; bits and clocks are 0/5 V HC. A clock edge and an
audio sense never share a return pin.

## 3. The engines

| | encoder | decoder |
|---|---|---|
| bit | LM311, `AUDIO_TX` against `Y_E` | `BIT_DEC` into the first '74 |
| run register | 3 × ½ 74HC74 | 3 × ½ 74HC74 |
| coincidence | 2 × XOR ('86) + OR ('32) → `/COIN` | the same |
| syllabic | 51.1 kΩ, 2.55 MΩ, 100 nF | the same |
| `Iabc` | ½ TL072 + 2N3906, R_set 30.9 kΩ with trim | the same, its own |
| OTA | ½ LM13700, ±224 mV from Q and /Q | the other ½ |
| integrator | 10 nF ∥ 100 kΩ, ½ TL072 follower | the same |
| reconstruction | — | 3rd order, 3.4 kHz: 10 kΩ + 4.7 nF buffered, then Sallen–Key 2 × 10 kΩ, 9.1 nF / 2.4 nF |

### 3.1 The `Iabc` drive

The LM13700's bias pin sits two diode drops above V−, so resistors alone make
`I_min` a small difference of two junction-set currents. One resistor from the
node on ±12 V gives 1.47:1 and the codec does not compand (segSNR 9.0 / 7.8 dB
against the law's 27.6 / 18.0); with the pin at +1.3 V, `I_min` doubles in under
20 °C. So the law is set by resistor ratios, with the pin out of it:

```
 /COIN ── R1 51.1k ──┬── V_node ──── (+) op-amp ── base ─┐  PNP 2N3906
 (¼ '32, on V_A)     C_syl 100n ∥ R2 2.55M to gnd        (−) ─────────┬── emitter
                                       V_A ── R_set ──────────────────┘   collector ──▶ Iabc pin
 V_node = k·V_A·(1 − syl), k = R2/(R1 + R2) = 0.9804;  Iabc = (V_A − V_node) / R_set
 I_max = V_A / R_set,  I_min = I_max·(1 − k): a ratio of 50.9, set by two resistors
```

| item | value | sets |
|---|---|---|
| R1, R2 | 51.1 kΩ, 2.55 MΩ, 1 % | the ratio by two resistors; R1 ∥ R2 = 50.1 kΩ keeps τ_syl 5 ms on 100 nF 2 % |
| R_set | 26.1 kΩ + 10 kΩ trimmer, 30.9 kΩ set | `I_max` 160 µA; the one trim, scaling `I_min` with it, which is pure gain |
| V_A | +5 V through 100 Ω and 100 µF, feeding R_set and the coincidence gate's package | one node, so the law is ratiometric in it |
| op-amp | JFET input, ±12 V | **its offset is the `I_min` spec**: 98 mV of control at `I_min`, so a TL072's 3 mV typical is 3 % and its 10 mV worst is the whole ±10 % budget. A low-offset grade, or trim |

Expected `I_min` accuracy is ±5 %, against `mf8-spec.md` §12.1's ±10 %,
independent of temperature, the rails and the OTA.

### 3.2 Between the logic and the engine

- **The LM311's output is a floating transistor**: collector to +5 V through
  4.7 kΩ, emitter to logic ground.
- **The bit into the OTA is differential**: Q and /Q each through 47 kΩ / 2.2 kΩ,
  ±224 mV, which steers 99.96 % of `Iabc` either way. A 0/5 V bit divided down on
  one input is 0 or +`Iabc`, with no down-step. **Check the sign**: a 1 must raise
  the integrator the LM311 compares against. A reversed encoder sits on a rail; a
  reversed decoder only inverts, and passes a listening test.
- **One ground, clocks off the integrator**: the smallest step on `C_int` is
  3.1 µA × 15.6 µs / 10 nF = 4.9 mV, so millivolts of clock there are the idle
  step. 100 nF at every package, 10 µF each rail.

## 4. Parts

| ref | part | function |
|---|---|---|
| U1 | LM311 | encoder comparator |
| U2 | LM13700 | both OTAs |
| U3–U5 | TL072 | `Iabc` source and integrator follower, one per engine; reconstruction |
| U6–U8 | 74HC74 | six run-register halves |
| U9, U10 | 74HC86, 74HC32 | coincidence; the '32's spare gates for `/OE` or a local `MUTE` gate |
| Q1, Q2 | 2N3906 | `Iabc` PNPs |

About ten ICs and two transistors; 1 % resistors, 2 % `C_syl`, 5 % film `C_int`.
Encoder and decoder side by side, the LM13700 and logic between, R at the rear,
the two `Iabc` trims and the test points at the front; no HV on the board.

## 5. Host contract and bring-up

The base powers R, drives `TX_CLK` and `RX_CLK` from socket a1 and a7 (never
tied on the riser), gates `BIT_DEC` if it has a `MUTE` gate, and presents
`AUDIO_TX` trimmed to nominal **before** the riser's `Iabc` trim. R is left open
where the codec is stuffed on the base.

Bring-up: `BIT_ENC` looped to `BIT_DEC` on a bench carrier, to the order of
`spice/cvsd-dec`'s loopback (~17 dB tone SINAD, 20–25 dB speech segSNR); each
`Iabc` trimmed against its `C_int`, not by ear; then on a base, then card to
card, within ~1 dB of a matched pair (`tolerance.py`).

## 6. Open

- **Stack pitch.** Drawn at 0.4″ (10.16 mm). That does not close with stock
  parts: an 8.5 mm socket under a 1.6 mm board leaves 0.05 mm of air
  (`block-stack.md` §1, which moved the block to an 11 mm gap). It blocks the
  header choice and the mechanical drawing.
- **±12 V in an exchange block.** The port card's edge header carries +5 V only
  (`block-stack.md` §5), so a base in a block feeds R's ±12 V from its own
  harness.
- **Stuffing:** `/OE` or not; a `MUTE` gate on the riser or the base
  (`channel-cards.md` §6); the hole pattern shared with the base.
- **Not measured:** the drive's ±5 % is a sum of tolerances; scope V_A's ripple
  at `I_min` first, the offset second. How `I_min` mismatch sounds (10 % moves the
  level 0.4 dB between nominal and −20 dB) wants a render. §3.1's comparison
  would be reproducible with a pluggable step law in `tolerance.py`.
