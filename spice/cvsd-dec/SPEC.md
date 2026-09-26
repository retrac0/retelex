# CVSD decoder — type A (breadboard)

Mirror of the encoder engine in `spice/cvsd-enc/` / `mf8-spec.md` §12.1 /
`cvsd-codec.md` §3.1, §3.2. **No comparator:** `BIT` and `CLK` come from
the line card or fabric; the rest of the analog law is identical.

> **Status:** proposed circuit; ngspice macromodel in this directory. Law and
> values match `mf8.params(64000)` and falstad `CVSD-DEC`.

---

## 1. What it does

| in | out |
|---|---|
| `BIT`, `CLK` (0/5 V, rising-edge sample) | `Y` — reconstructed baseband (±1 V FS) |
| | `AUDIO` — `Y` through the §12.1 reconstruction LPF (optional block) |
| | `SYL` — syllabic node (test) |

Same MIL-STD-188-113 parameters as the encoder: run-of-threes, τ_syl 5 ms,
τ_int 1 ms, 51:1, slew 16 000 → `I_max` 160 µA on 10 nF.

## 2. Block diagram

```
 BIT ──►[ 74HC74 ×3 run register ]──► Q, Q1, Q2
 CLK ─┘         │
                ├── coincidence (2× XOR + OR) ──► /COIN
                │                                      │
                │         syllabic RC (51.1k / 2.55M / 100n)
                │                                      ▼
                │                              SYL ──► Iabc (½ TL072 + 2N3906)
                │                                      │
                └── Q, /Q ──÷──► ±224 mV ──► LM13700 ──► C_int∥R_int ──► ½ TL072 ──► Y
                                                              │
                                                              └──[ RECON 3.4 kHz ]──► AUDIO
```

Differences from the encoder (`enc_a`):

| | encoder | decoder |
|---|---|---|
| bit source | LM311 (`AUDIO` vs `Y`) | external `BIT` into the first '74 |
| LM311 | yes | **no** |
| reconstruction LPF | no (loop closes on raw `Y`) | **yes**, on the card output |

## 3. Parts (decoder alone)

| block | part |
|---|---|
| Run register | 2× 74HC74 (3 halves used) |
| Coincidence | ½ 74HC86 (2 XOR) + ¼ 74HC32 |
| Syllabic | 51.1 kΩ, 2.55 MΩ, 100 nF 2% |
| `Iabc` | ½ TL072, 2N3906, 30.9 kΩ (+ trim), VA filter |
| OTA | ½ LM13700 |
| Integrator | 10 nF ∥ 100 kΩ, ½ TL072 follower |
| Reconstruction | ½–1× TL072 (RC + Sallen–Key), see §4 |

**≈ 5–6 packages** without the LPF; **≈ 6–7** with it. One LM13700 dual and one
TL072 dual cover encoder+decoder on a shared FXS-class card.

Rails: +5 V logic, ±12 V analog. Same `I_min` / syllabic tolerances as the
encoder (`mf8-spec.md` §12.1).

## 4. Reconstruction filter

3rd-order ~3.4 kHz low-pass (falstad `RECON` / `cvsd-codec.md` §3):

- 1st order: 10 kΩ + 4.7 nF, buffered  
- Sallen–Key: 2× 10 kΩ, 9.1 nF / 2.4 nF  

Driven from `Y`; output is the listen path.

## 5. Pins (engine subcircuit)

| pin | | |
|---|---|---|
| `BIT` | in | data, 0/5 V |
| `CLK` | in | 64 kHz bit clock, sample on rising edge |
| `Y` | out | integrator (pre-filter) |
| `SYL` | out | syllabic test point |
| `VDD` `VCC` `VEE` | in | +5, +12, −12 |

## 6. Bring-up

1. Engine alone: feed a known CVSD bit stream (or loop the type-A encoder).  
2. Trim `Iabc` against `C_int` (same procedure as the encoder).  
3. Card-to-card: encoder on one board, decoder on another — within 1 dB of a
   matched pair (`tolerance.py` / §12.1).  
4. Fit reconstruction filter; check DTMF / speech by ear and SINAD.

## 7. ngspice

| file | |
|---|---|
| `dec_a.sub` | type-A decoder engine |
| `recon.sub` | 3.4 kHz LPF |
| `test_loop.cir` | encoder A → decoder A loopback |
| `check.py` | Y / AUDIO vs source after settle |

```
make loop && python3 check.py
```
