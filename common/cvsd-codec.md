# CVSD codec card — common encoder / decoder riser

One **100 × 100 mm** board that holds both halves of the type-A CVSD engine
(`mf8-spec.md` §12.1, `circuit-review.md` §2.4 / §4, `spice/cvsd-enc/`,
`spice/cvsd-dec/`). It is a **riser**: it stacks on a subscriber base card
(FXS / FXO / E&M / adapter carrier) and talks to that base through a short
board-to-board header. The base keeps the channel socket, the hybrid / line
circuit, and the A-bit logic; this card keeps only the codec.

> **Status: proposed.** Circuit matches the ngspice type-A decks and falstad
> `CVSD-ENC` / `CVSD-DEC` / `RECON`. Outline and stack pitch match the MF8
> spacer-stack (`common-cards.md`, `mf8-psu.md`). Header P/N and layout not
> drawn.

```
  shelf C ══╗
            ║
     ┌──────╨──────┐
     │ subscriber  │  hybrid / feed / ring / slot logic / word
     │ base 100²   │
     └──────╥──────┘
            ║ R  (mezzanine — §3)
     ┌──────╨──────┐
     │ CVSD codec  │  enc + dec + recon   ← this card
     │ riser 100²  │
     └─────────────┘
```

---

## 1. Why a separate card

| | on the FXS/E&M board today (`channel-cards.md` §3) | this riser |
|---|---|---|
| Codec | stuffed on every analog subscriber population | **one** layout, shared |
| Bring-up | engine + hybrid + HV on one first article | engine alone on a bench carrier, then on a live base |
| Tolerance | enc and dec built together | same, and a spare riser swaps without touching the line side |
| CVSD line card | codec stays in the phone | unchanged — this riser is not for that card |

Hosts that fit the R header:

| host | what it puts on R |
|---|---|
| **FXS / FXO base** | `AUDIO_TX` from the hybrid trim, `AUDIO_RX` back to it; `TX_CLK` / `RX_CLK`; `C_TX` / `C_RX` as `BIT_ENC` / `BIT_DEC` |
| **E&M base** | the same, four-wire audio instead of a hybrid |
| **Subscriber-adapter carrier** | phone-side audio + recovered bit clock (`subscriber-adapter.md`) |
| **Bench carrier** | banana / SMA for `AUDIO`, 0/5 V `BIT`/`CLK`, ±12 / +5 — no shelf |

The CVSD **subscriber line** card (`channel-cards.md` §2) does **not** take
this riser: its codec is in the phone, and the card has no ±12 V path.

---

## 2. Mechanical

| | |
|---|---|
| Outline | **100 × 100 mm**, 1.6 mm, same as every MF8 channel layer |
| Role in the shelf | the **upper** layer of a two-layer channel sandwich; the base below it takes the through-stack **C** socket (`mf8-backplane.md` §8) |
| Stack pitch | **0.4″ (10.16 mm)** board-to-board — same datum family as `pcb/hookbusy/` (spacers are the datum; headers float) |
| Keep-outs | 5 mm from the front edge for a faceplate / test points; C area on the **base** only — this riser has no DIN / C footprint |
| Mounting | four M3 clearance holes on the common MF8 pattern (to be locked with the base); nylon spacers |

The riser does **not** pass C. Clocks and bits arrive already chosen by the
base (`TX_CLK`→encoder, `RX_CLK`→decoder). That keeps the two clock domains
from meeting on this board, as §3.2 of `channel-cards.md` requires.

---

## 3. Mezzanine header **R**

Keyed **2×10** 0.1″ stackable header (mate on the base top / riser bottom).
Pin 1 marked; keying blocks a 180° reverse. Names are from this card's view.

| pin | name | dir | |
|---|---|---|---|
| 1 | `GND` | — | analog/logic return (star to base GND plane) |
| 2 | `GND` | — | |
| 3 | `+5 V` | in | `VDD` — 74HC + LM311 pull-up |
| 4 | `+12 V` | in | `VCC` |
| 5 | `−12 V` | in | `VEE` |
| 6 | `GND` | — | |
| 7 | `TX_CLK` | in | 64 kHz, encoder sample (rising) |
| 8 | `RX_CLK` | in | 64 kHz, decoder sample (rising) — **separate net** |
| 9 | `BIT_ENC` | out | encoder bit → base `C_TX[n]` |
| 10 | `BIT_DEC` | in | from base `C_RX[n]` (after any `MUTE`/`1010` gate on the base) |
| 11 | `AUDIO_TX` | in | to encoder; nominal **0.15 rms** of FS (`mf8.NOMINAL_RMS`) |
| 12 | `AUDIO_RX` | out | decoder after reconstruction LPF |
| 13 | `GND` | — | audio return sense (tie to 1/2 at base) |
| 14 | `/OE` | in | pull-down to run; open or high three-states `BIT_ENC` (optional stuffing) |
| 15 | `SYL_E` | out | encoder syllabic test (or NC) |
| 16 | `SYL_D` | out | decoder syllabic test (or NC) |
| 17 | `Y_E` | out | encoder integrator test |
| 18 | `Y_D` | out | decoder integrator (pre-LPF) test |
| 19 | `GND` | — | |
| 20 | `GND` | — | |

**Not on R:** `−48 V`, `RING`, A bits, the word, `FILL`, `MUTE`, tip/ring.
Those stay on the base and on C.

**Levels:** `AUDIO_*` are analog about ground, ±1 V FS class. `BIT_*` and
clocks are 0 / +5 V HC. Do not share a return pin between a clock edge and an
audio sense — that is why GND is repeated.

---

## 4. Block diagram

```
 AUDIO_TX ──►[  optional on base: 300–3400 ]──► ENCODER ──► BIT_ENC
 TX_CLK ──────────────────────────────────────┘              │
                                                             │  (base → C_TX)
 BIT_DEC ◄───────────────────────────────────────────────────┤
 RX_CLK ──► DECODER ──► Y_D ──►[ RECON 3.4 kHz ]──► AUDIO_RX │
                                                             │  (base ← C_RX)
```

Type A, both engines (`spice/cvsd-enc/enc_a.sub`, `spice/cvsd-dec/dec_a.sub`):

| | encoder | decoder |
|---|---|---|
| Bit source | LM311 (`AUDIO_TX` vs `Y_E`) | `BIT_DEC` into the first '74 |
| Run register | 3× ½ 74HC74 | 3× ½ 74HC74 |
| Coincidence | 2× XOR + OR → `/COIN` | same |
| Syllabic | 51.1 k / 2.55 M / 100 n | same |
| `Iabc` | ½ TL072 + 2N3906, R_set 30.9 k + trim | same, own half |
| OTA | ½ LM13700, ±±224 mV from Q/`NQ` | other ½ LM13700 |
| Integrator | 10 nF ∥ 100 k, ½ TL072 follower | same |
| Reconstruction | — | 3rd-order 3.4 kHz (`recon.sub`, `channel-cards.md` §3.3) |

Digital logic stays in HC; ADC/DAC bridges are a simulation concern only
(`spice/cvsd-enc/models/logic.inc`). On the board the '74 / '86 / '32 are real
packages with 0 / 5 V levels into the OTA dividers and the syllabic node
(`circuit-review.md` §4).

---

## 5. Parts

### 5.1 Packages

| ref | part | function |
|---|---|---|
| U1 | LM311 | encoder comparator |
| U2 | LM13700 | both OTAs (enc + dec) |
| U3 | TL072 | encoder `Iabc` + integrator follower |
| U4 | TL072 | decoder `Iabc` + integrator follower |
| U5 | TL072 | reconstruction LPF (buffer + Sallen–Key; one section spare or second-order pad) |
| U6–U8 | 74HC74 | six run-register halves (enc ×3, dec ×3) |
| U9 | 74HC86 | four XORs (both coincidence networks) |
| U10 | 74HC32 | two ORs (coincidence); spare gates for `/OE` or a local `MUTE→1010` option |
| Q1, Q2 | 2N3906 | `Iabc` PNPs |
| — | 1 % resistors, 2 % C_syl, 5 % film C_int | per §12.1 / `circuit-review.md` §2 |

**≈ 10 IC packages** + 2 transistors. Matches the spirit of `channel-cards.md`
§3.8's engine line, with coincidence as **'32** (type A / spice), not '08.

### 5.2 Law values (both engines)

| | |
|---|---|
| τ_syl / τ_int | 5 ms / 1 ms |
| Compression | 51:1 full scale (16:1 @ 30 % run-of-threes) |
| C_int ∥ R_int | 10 nF ∥ 100 kΩ |
| C_syl network | 51.1 kΩ, 2.55 MΩ, 100 nF 2 % |
| I_max / I_min | 160 µA / ≈ 3.1 µA — **one trimmer per engine** on R_set |
| OTA steer | 47 k / 2.2 k from Q and `/Q` → ±224 mV |
| LM311 pull-up | 4.7 kΩ to +5 V; emitter at GND |

### 5.3 Reconstruction

As `spice/cvsd-dec/SPEC.md` §4 / falstad `RECON`:

- first order: 10 kΩ + 4.7 nF, buffered  
- Sallen–Key: 2× 10 kΩ, 9.1 nF / 2.4 nF  

Input anti-alias (300–3400 Hz) stays on the **base** with the hybrid trim
(`channel-cards.md` §3.3), so one riser layout serves every host.

---

## 6. Layout zones (100 × 100)

```
  front (test points / faceplate)
  ┌──────────────────────────────────────────┐
  │  TP: Y_E Y_D SYL_E SYL_D BIT_ENC BIT_DEC │
  ├───────────────┬──────────────────────────┤
  │  ENCODER      │  DECODER + RECON         │
  │  LM311        │  U4 TL072, ½ LM13700     │
  │  U3 TL072     │  U5 recon                │
  │  ½ LM13700    │  '74 ×1½, ½ '86, ¼ '32   │
  │  '74 ×1½      │                          │
  │  ½ '86, ¼ '32 │                          │
  ├───────────────┴──────────────────────────┤
  │  U2 LM13700 centre  ·  logic U6–U10      │
  │  +5 decouple near 'HC   ±12 near OTAs    │
  ├──────────────────────────────────────────┤
  │           R header (rear / stack)        │
  └──────────────────────────────────────────┘
  rear (toward shelf / base)
```

- **Split ground:** single GND poured, with the analog steer/divider cluster
  and C_int next to each OTA; HC clocks routed away from `AUDIO_*`.  
- **Decouple:** 100 nF on every VDD/VCC/VEE pin; 10 µF bulk per rail at R.  
- **Trimmers:** two R_set pots on the front edge, silk `Iabc E` / `Iabc D`.  
- **Clearance:** no −48 / RING on this board — no HV creepage budget.

---

## 7. Host contract

The base must:

1. Power R from the socket's `+5` and `±12` (FXS/E&M already take those pins).  
2. Drive `TX_CLK` / `RX_CLK` from C `a1` / `a7` — never short them on the riser.  
3. Gate `BIT_DEC` if it implements the `MUTE`→`1010` fix (`channel-cards.md`
   §3.7); otherwise the decoder sees raw `C_RX[n]`.  
4. Present `AUDIO_TX` already trimmed to nominal line level **before** the
   riser's `Iabc` trim (`channel-cards.md` §3.3).  
5. Leave R unpopulated / open if the codec is stuffed on-base instead (older
   one-board builds) — the riser is optional per slot.

---

## 8. Bring-up

1. **Bench carrier:** loop `BIT_ENC`→`BIT_DEC`, tie `TX_CLK`=`RX_CLK`, feed
   `AUDIO_TX`, listen on `AUDIO_RX`. Match `spice/cvsd-dec` loopback /
   `talker_snr.py` order of magnitude (~17 dB tone SINAD, ~20–25 dB speech
   segSNR).  
2. Trim each `Iabc` against its `C_int` (`circuit-review.md` §2), not by ear.  
3. **On base, no line:** same loop through the base's bit path.  
4. **On base, live trunk:** levels at the hybrid, then card-to-card over C.  
5. Card-to-card encoder/decoder mismatch within ~1 dB of a matched pair
   (`tolerance.py`).

---

## 9. Documents and models

| | |
|---|---|
| Law / tolerances | `mf8-spec.md` §12.1, `circuit-review.md` §2–§4 |
| FXS engine placement (before split) | `channel-cards.md` §3.2, §3.8 |
| Encoder / decoder spice | `spice/cvsd-enc/enc_a.sub`, `spice/cvsd-dec/dec_a.sub`, `recon.sub` |
| Falstad | `falstad/cvsd_engine.txt` — `CVSD-ENC`, `CVSD-DEC`, `RECON` |
| PCB project (layout TBD) | `pcb/cvsd-codec/` |

---

## 10. Open

- Stackable header manufacturer / height for 0.4″ pitch with reliable wipe.  
- Whether `/OE` on `BIT_ENC` is stuffed, or the base always sinks the bit.  
- Whether a local `MUTE`→`1010` gate lives on this riser (spare '32) or only on
  the base.  
- MF8 hole pattern coordinates shared with the base drawing.  
- One-board FXS stuffing option: do not delete the footprints from the base
  library until the riser is the default.
