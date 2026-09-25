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
