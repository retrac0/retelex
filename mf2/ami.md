# MF2 AMI encoder and decoder

> **Status: spice bring-up.** Geometry and AMI choice: [`spec.md`](spec.md).
> **74HC + line PHY ngspice:** [`../spice/mf2-ami/SPEC.md`](../spice/mf2-ami/SPEC.md)
> (`make -C spice/mf2-ami all`). Python plant model remains `mf8_line.rx_ami`
> at 256 kbps via `sim/mf2_line.py`.

Parent: [`spec.md`](spec.md). Checklist: [`sim.md`](sim.md).

---

## 1. Code

**AMI (alternate mark inversion), one symbol per bit:**

| data bit | line level |
|---|---|
| `0` | 0 V (space) |
| `1` | pulse ±A, polarity **alternating** on successive marks |

At MF2: **256 kbps / 256 kBaud**, 3.906 µs cell. Transformer OK (disparity ±1 mark).
Tip/ring swap OK if mark detect is full-wave / `|v|`.

---

## 2. Clocks

```
4.096 MHz ─→ ÷16 ─→ H = 256 kHz (symbol)
                 └─→ DPLL mid tap HS (sample) when locked
```

Loopback spice uses a fixed `HS = H + ½ cell + RX delay` until the discrete DPLL
is in the deck.

---

## 3. Encoder (74HC) — implemented

```
D = Q ⊕ B          ½ 74HC86
Q = FF(D) @ H      ½ 74HC74
EP = B · Q         ½ 74HC08
EM = B · /Q
```

Spice: `AMI_ENC` in `spice/mf2-ami/models/logic.inc`.

---

## 4. Transmitter — implemented (behavioral HV bridge)

| item | value |
|---|---|
| Drive | `TIP = ±VDRV` from EP/EM; `RING = −TIP` (MOSFET H-bridge stand-in) |
| Match | 50 Ω each leg |
| Clamp | back-to-back **56 V** zeners tip–ring (above −48 V phantom / 50 V abuse) |
| Nominal VDRV | **±12 V** (rails may rise toward ±50 V for span) |
| Magnetics | optional `ami_xfmr.sub`; ≥33 mH class on the card |

**Do not** put ordinary diodes tip–ring — they forward-clamp AMI to ~0.7 V.

---

## 5. Receiver — implemented front end + 74HC latch

### 5.1 Analog (`ami_rx.sub`)

120 Ω terminate → 1 kΩ → **±5 V clamps** → diff → LP @ symbol rate → `|v|` →
peak hold → `MARK = (|v| > ~0.4·peak)`.

50 V on the pair is dropped in the series R / TVS; clamps protect HC rails
(`test_50v.cir`).

### 5.2 Digital (`AMI_DEC_LATCH`)

½ **74HC74**: `BIT ← MARK` on rising `HS`; `STROBE = HS`.

### 5.3 DPLL (field)

Oversample 4.096 MHz, `/16` phase, clear/nudge on mark leading edge, `HS` at
count 8 — `line-codes.md` option C. Spice loopback substitutes locked-phase `HS`
(see `spice/mf2-ami/SPEC.md`).

---

## 6. Simulation map

| layer | where |
|---|---|
| Bit/plant (Python) | `sim/mf2_line.py` → `mf8_line.rx_ami` |
| Circuit (ngspice) | `spice/mf2-ami/` — **PASS** `make all` |

---

## 7. Open

1. MOSFET + gate-drive BOM for ±12…50 V  
2. XSPICE mark-cleared `/16` DPLL in the spice deck  
3. Default-in transformer once L is fixed for 256 kBaud  
