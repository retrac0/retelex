# CVSD codec PCB

KiCad project for the common encoder/decoder riser in `common/cvsd-codec.md`.

| Project | Role | Copies |
|---|---|---|
| [`codec_card/`](codec_card/) | Type-A enc + dec + recon, 100 × 100 mm mezzanine | 1 per analog subscriber slot that uses the riser |

## Locked for this design pass

| | |
|---|---|
| Outline | **100 × 100 mm**, 1.6 mm |
| Stack pitch | **0.4″ (10.16 mm)** over the subscriber base — spacers datum; headers float |
| Mezzanine | **R** 2×10 0.1″ keyed — pin map = `cvsd-codec.md` §3 |
| Circuit | type A — LM311 + 2×TL072 engines + TL072 recon + LM13700 + 3×'74 + '86 + '32 |
| Rails on R | +5, ±12, GND only (no −48 / RING) |
| Clocks | `TX_CLK` and `RX_CLK` both enter on R; domains do not meet on this board |

## Status

- **Spec:** `common/cvsd-codec.md` (proposed).  
- **Schematic / PCB:** not drawn yet — create `codec_card/` when laying out.  
- **Header P/N:** not chosen (need ~10.16 mm engagement, keyed).  
- **Spice reference:** `spice/cvsd-enc/`, `spice/cvsd-dec/` (loopback + `talker_snr.py`).

## Next

1. Draw schematic from §4–§5 of `cvsd-codec.md` (refs U1–U10, Q1–Q2, R header).  
2. Pick stackable header + spacer; fix hole pattern with the FXS/E&M base.  
3. Place zones per §6; pour GND; route; DRC.  
4. Bench carrier (R only) before first stack-up.
