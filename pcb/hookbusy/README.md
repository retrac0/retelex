# Hook/busy PCB

KiCad 10 projects for the two boards in `exchange/hookbusy.md`.

| Project | Role | Copies |
|---|---|---|
| [`lamp_card/`](lamp_card/) | One column of eight lamps + '259 + BLK/MODE | **16** |
| [`interface_card/`](interface_card/) | Cable tap, word decode, `LEB`, control '244, PWR inject | **1** |

Regenerate placement from the script (after editing rules):

```bash
export KICAD_CONFIG_HOME="$(pwd)/../.kicad-config"
python3 build_boards.py
```

Open `lamp_card/lamp_card.kicad_pro` or `interface_card/interface_card.kicad_pro` in KiCad 10.

## Locked for this layout pass

| | |
|---|---|
| Outline | **50 × 100 mm** (50 deep × 100 tall), 1.6 mm thick |
| Stack pitch | **0.4″ (10.16 mm)** — spacers are the datum; headers float |
| LED pitch | 0.4″ along the front edge (slot 0…7), centred on 100 mm |
| LED holes | **one** front-edge column, **D1…D8** only |
| Stuffing | HOOK green / BUSY orange in the same holes (by card MODE) |
| Series R | **1k5** (≈ 2 mA into a 5 mm LED at 5 V) |
| Stack headers | `J1` HA 1×8, `J2` LEB 1×8, `J3` PWR 1×4, `J4` control 1×6 — pin maps = `hookbusy.md` §3.3 |
| BLK | `JP1` HA→`D_HOOK`, `JP2` LEB→`LE_BUSY_N` — two shunts in one silkscreen column |
| MODE | `JP3`/`JP4`/`JP5` — 1×3 HOOK\|COMMON\|BUSY for D, `/LE`, `/CLR` |

## Status

- **PCB:** outline, footprints, nets assigned on pads (ratsnest). **Not routed.**
- **Schematic:** title-block stub only — draw next to match the refs on the board (`U1`, `D*`, `J*`, …).
- **Stacking header P/N:** not chosen (need ~10.16 mm engagement).
- **Cable IDC** on the interface card: placeholder pin headers; map to `mainboard.md` §3 IDC next.
- **'123 RC:** `R1`/`C6` value TBD on the bench (~1½ cell).

## Next

1. Draw schematics to match board refs (or reverse: schematic first, then Update PCB).
2. Pick stackable header + spacer; fix hole sizes.
3. Route; pour GND; DRC.
4. Bezel / panel drawing separate from these cards.
