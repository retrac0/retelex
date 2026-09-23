# Formant cell — residual-first + 8-band envelope bank

Voice-excited **residual** (first-class LINE slot) + **8 log-spaced**
`logenv` channels with per-band τ / gain and voiced/unvoiced excitation.
Independent of CVSD / MF8.

> **Status: proposed.** Speech path is `sim/formant_cell.py`. ngspice smoke
> deck is still the old 1-carrier path.

---

## 1. LINE rebudget

Was: residual squeezed under three env carriers in 400–1200 Hz (env dominated).

Now:

| slot | Hz | |
|---|---|---|
| **residual** | **300–1100** | baseband 80–600 Hz, DSB @ 700 Hz — first-class (~half of LINE) |
| **8 envs** | **1200–1830** | AM @ ~1200…1830 Hz (90 Hz spacing); τ 12→3 ms; gain trim |
| **V/UV** | **1950** | explicit voiced gate from fullband analysis |
| full `LINE` | **300–2000** | widened pipe |

## 2. Signal path

```
  AUDIO ─┬─► BP 80–600 ──► flatten ──► DSB × 700 Hz ──► residual lane (300–1100)
         ├─► voiced_gate ──► AM × 1950 Hz ──► V/UV lane
         └─► 8× log-spaced BP 300–3400 ──► logenv(τ_i)·G_i ──► AM × f_c,i
                                                              → env lane (1200–1830)

  LINE ──► demod residual ──► enrich ──┐
           demod V/UV ─────────────────┼─► exc = v·buzz + (1−v)·noise
           8× logenv from carriers ────┘
                      │
                      └─► Σ BP_i(exc) · env̂_i ──► AUDIO
```

| band | approx Hz | τ | gain trim |
|---|---|---|---|
| 0…2 | low | 12→8 ms | 0.55–0.85 (cut F1 dominance) |
| 3…5 | mid | 6→4 ms | ~1.0–1.2 |
| 6…7 | high | **3 ms** | 1.3–1.4 |

## 3. Excitation

- **Voiced:** mild `tanh` enrich of recovered residual (already 80–600 Hz)
- **Unvoiced:** unit noise
- **Gate:** soft mix from low/high energy ratio + ZCR on residual, nudged by top-band env

## 4. How to run

```
python3 sim/formant_cell.py                  # 8-band residual-first
python3 sim/formant_cell.py --mode fixed     # legacy robotic A/B
make -C spice/formant-cell speech
```

Reports residual LINE power fraction, mean V/UV, crude SNR, F0 track.
