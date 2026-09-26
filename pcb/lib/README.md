# Shared KiCad library

Parts drawn for this project, used by every board under `pcb/`.

| File | Library name | Holds |
|---|---|---|
| `telco.kicad_sym` | `telco` | Symbols |
| `telco.pretty/` | `telco` | Footprints, one `.kicad_mod` each |

Each board project has its own `sym-lib-table` and `fp-lib-table` that point
here through `${KIPRJMOD}`, so a fresh clone opens without any global library
setup. A new board copies those two files and fixes the number of `../`.

Stock KiCad parts stay in the stock libraries. A part goes here only when the
stock one is missing or wrong, or when every card must share it: the
backplane edge connector belongs here, with pin names that match the specs in
`exchange/`.

## What is here now

| Item | For |
|---|---|
| `telco.pretty/Stack_2x25_P2.54mm_LongTail` | the block stack's pass-through stacking header, J1 and J2 (header B and every port card); the stock 2×25 socket's pads, so every board in a stack drills the same holes |
| `telco.pretty/Stack_2x20_P2.54mm_LongTail` | the three-2×20 stack before 2026-09-26; still on `portcard_RevC` until its stack is redrawn |
| `telco.pretty/LED_D3.0mm_Horizontal_Row` | a right-angle 3 mm LED for a row at 5 mm pitch at a board edge (header B's sixteen lamps): the stock horizontal LED, courtyard cut across the row to the body |
| `telco.pretty/Bus_2x25_P2.54mm_Mirror` | the one bus's left-edge header: the stock 2×25 with every x negated, so a card position's two bus edges are mirror images (`exchange/bus.md` §2.3). The block header no longer uses it: it takes the bus on one right-angle IDC for the ribbon |
| `block-stack.json` | the block stack's pin and part contract, written by `pcb/tools/stackdef.py` (`exchange/block-stack.md`); `gen_cards.py --check` and `pcb.py` hold the schematics and boards to it |
