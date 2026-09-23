# Analog tone front-end — up to the CVSD encoder

`common/tone-plan.md` §5's analog card, simulated alone: carrier, warbler,
pure/mod path, cadence mute of the encoder **input**, and a level trim. Stops
at `AUDIO` — the §12.1 encoder is `spice/cvsd-enc/`, not this deck.

> **Status: proposed.** ngspice macromodel. No PCB. Values are a starting
> point so `make check` can see a ~425 Hz carrier, a ~25 Hz warble, and the
> soft-vs-hard line-count trade from `sim/tones.py warble`.

---

## 1. What it does

| in | out |
|---|---|
| ±12 V, +5 V | `AUDIO` — baseband into an encoder half at ~`NOMINAL_RMS` |
| `CAD` (0/5 V) | high = tone on; low = mute (encoder would sit on its own `1010`) |

Three populations of the same front-end, selected by which test deck you run:

| deck | warble path |
|---|---|
| `test_pure.cir` | carrier only |
| `test_soft.cir` | LFO → 4 ms RC → multiply (preferred mod jumper) |
| `test_hard.cir` | LFO square-gates the carrier (parts trade; many lines) |
| `test_cadence.cir` | soft path + a short on/off cadence on `CAD` |
| `test_rbt.cir` | soft + UK-style ringback mask (`1101 1000…`) → `make rbt-spice` → `out/rbt.wav` (10 s) |

## 2. Block diagram

```
  [Wien osc]────── f0 ~425 Hz sine ──► AC couple ──┬── pure ─────────────────┐
  ½ TL072 + RC                                    │                         │
                                                  ├── soft: × env(LFO, 4 ms)─┤
  [Schmitt osc]── f_w ~25 Hz square ──────────────┤                         ▼
  ½ TL072 + RC                                    └── hard: gate ──────► × env(CAD)
                                                                          │
                                                              CAD → 4 ms RC (soft mute)
                                                                          │
                                                                   level trim ──► AUDIO
```

Cadence counter / 16 jumpers (`tone-plan.md` §5.2) are **not** in this deck —
`CAD` is a pulse source so a short run can show mute. Mute is softened on both
sides: ~4 ms RC on `CAD` (envelope), then ~0.15 ms RC after the multiply (edge
de-click without lowpassing the carrier).

## 3. Packages (front-end alone)

| | |
|---|---|
| 1× TL072 | Wien carrier + Schmitt LFO |
| diodes | soft amplitude clamp on the Wien |
| passives | Wien R/C, LFO timing, AC couple, 4 ms soft RC (warble + cadence), level |
| | **no LM13700** on this side of the encoder; cadence mute is RC× not a hard SW |

## 4. How to run

```
make          # pure, soft, hard, cadence → out/*.log + wrdata
make check    # Hz, RMS, in-band FFT lines (soft vs hard)
```
