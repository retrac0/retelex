# MF2 AMI PHY — 74HC + line interface (ngspice)

Discrete AMI encoder/decoder for [`../../mf2/ami.md`](../../mf2/ami.md), simulated here.

```
B,H ─► AMI_ENC (74HC) ─► EP,EM ─► AMI_TX (±VDRV, TVS) ─► tip/ring
                                                              │
BIT,STROBE ◄─ AMI_DEC_LATCH (74HC) ◄─ MARK ◄─ AMI_RX_FRONT ◄─┘
                     ▲
                     └── HS (mid-cell; DPLL tap when locked)
```

## Run

```
make all          # loop + 50 V surge + check.py
make loop surge
```

`check.py` requires tip |V| ≳ 3 V, ≥90% bit match on strobes, and post-surge recovery with Vdd stable.

## Encoder (74HC)

| package | function |
|---|---|
| ½ **74HC86** | `D = Q ⊕ B` |
| ½ **74HC74** | polarity FF, clock `H` (256 kHz) |
| ½ **74HC08** | `EP = B·Q`, `EM = B·/Q` |

Model: `models/logic.inc` → `AMI_ENC`.

## Transmitter

Behavioral H-bridge stand-in for a **HV MOSFET** half-bridge (`ami_tx.sub`):

- `TIP = +(VDRV)·EP/5 + (−VDRV)·EM/5`, `RING = −TIP`
- Series 50 Ω match
- **Back-to-back 56 V zeners** (anode–anode) tip–ring — clamps abuse, does not forward-clip signal
- Nominal **±12 V** signalling; rails can be raised toward **±50 V** for long span
- Optional isolation: `ami_xfmr.sub` (3.3 mH sim / ≥33 mH family magnetics)

## Receiver front end

`ami_rx.sub`:

- 120 Ω terminate
- 1 kΩ into **±5 V clamps** (74HC / comparator survival under 50 V line)
- Diff → two-pole LP ~256 kHz → `|v|` → peak hold → mark = `|v| > ~0.4·peak`

## Decoder (74HC)

| package | function |
|---|---|
| ½ **74HC74** | sample `MARK` on rising `HS` → `BIT`; `STROBE = HS` |

`HS` is the **mid-cell** strobe. In the field it is the DPLL `/16` mid tap from 4.096 MHz, cleared/nudged on mark edges (`mf2/ami.md` §4). Loopback uses a fixed delay (`H + ½ cell + ~0.55 µs` group delay) — same node once the DPLL is locked.

## 50 V robustness

`test_50v.cir`: 50 V tip–ring through 200 Ω for 15 µs, then AMI ones. TVS + series R + RX clamps keep `Vdd` at 5 V; traffic resumes (`check.py` surge).

## Files

| file | role |
|---|---|
| `models/logic.inc` | `AMI_ENC`, `AMI_DEC_LATCH` |
| `ami_tx.sub` / `ami_rx.sub` | line PHY |
| `test_loop.cir` | encode → wire → decode |
| `test_50v.cir` | surge survival |
| `check.py` | pass/fail |

## Open

- Real MOSFET + gate-drive part numbers for ±12…50 V
- Full XSPICE DPLL counter (mark-clear `/16`) replacing fixed `HS` delay
- Populate `ami_xfmr.sub` in the default loop once magnetizing L is settled
