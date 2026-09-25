# Hook/busy PCB

KiCad 10 projects for the two boards in `exchange/hookbusy.md`, drawn for the
folded plane: both fields read the scanned `/HA` and `/HB` off cable A, and
nothing comes off cable B.

| Project | Role | Copies |
|---|---|---|
| [`lamp_card/`](lamp_card/) | One column of eight lamps + '259 + BLK/MODE | **16** |
| [`interface_card/`](interface_card/) | Cable A tap, '138 window decode onto `LE`, control '244, PWR inject | **1** |

The first placement came from a generator script (removed; see git history
before this commit). The boards are now edited by hand in KiCad. `make check`
in `pcb/` runs ERC and DRC on both.

Open `lamp_card/lamp_card.kicad_pro` or `interface_card/interface_card.kicad_pro` in KiCad 10.

## Locked for this layout pass

| | |
|---|---|
| Outline | **50 × 100 mm** (50 deep × 100 tall), 1.6 mm thick |
| Stack pitch | **0.4″ (10.16 mm)** — spacers are the datum; headers float |
| LED pitch | 0.4″ along the front edge (slot 0…7), centred on 100 mm |
| LED holes | **one** front-edge column, **D1…D8** only |
| Stuffing | HOOK green / BUSY orange in the same holes (by card MODE) |
| LED drive | anode to +5 V, cathode through **1k5** into the '259: lit while the latch is low (≈ 2 mA) |
| Stack headers | `J1` LE 1×8, `J3` PWR 1×4, `J4` control 1×6 — pin maps = `hookbusy.md` §3.3 |
| BLK | `JP1`, 2×8: one shunt routes `LE[h]` to the '259's `/LE` |
| MODE | `JP3`, 1×3 H\|C\|B: `/HA` or `/HB` into the '259's `D` |
| '259 | `A0..A2` = `SCAN[2:0]`, `/CLR` tied high |
| '138 (interface) | `A` = `SCAN[5:3]`, `/E1` = `HCLK`, `/E2` = `SLOTQ1`, `E3` = `SLOTQ2` → `LE0_N..LE7_N` |

## Status

- **PCB:** outline, footprints, nets on pads (ratsnest), no collisions. **Not routed.**
- **Schematic:** title-block stub only — draw next to match the refs on the board (`U1`, `D*`, `J*`, …).
- **Cable A tap `J5`:** a 2×8 placeholder, the eleven nets on pins 1–11 and GND on 12–16. The folded plane has no cable A pin table yet (`hookbusy.md` §3.2).
- **Stacking header P/N:** not chosen (need ~10.16 mm engagement).
- **Footprints** carry no library name (placed by the old script); "Update PCB from Schematic" will reassign them.

## Next

1. Draw schematics to match board refs (or reverse: schematic first, then Update PCB).
2. Pick stackable header + spacer; fix hole sizes.
3. Route; pour GND; DRC.
4. Bezel / panel drawing separate from these cards.
