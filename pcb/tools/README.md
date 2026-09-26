# pcb/tools

Scripts that draw, check and lay out the block stack (`exchange/block-stack.md`),
and that turn any KiCad schematic here into structural Verilog.

| Script | Does |
|---|---|
| `stackdef.py` | the block stack described part by part and pin by pin; writes `pcb/lib/block-stack.json` |
| `gen_cards.py` | draws `blkhdr_bus_RevA` (header A), `blkhdr_logic_RevA` (header B) and, only with `--force-portcard`, the generated `portcard` from that JSON (first draft only; it overwrites). `--check` holds each schematic's connector pins to the JSON |
| `sch.py` | writes KiCad 10 schematics: parts, labels on pin ends, hierarchical sheets, macro fields. UUIDs are keyed by sheet, reference and unit, so a regeneration is byte-identical and keeps the board linked |
| `kisexp.py` | S-expressions, symbol libraries, pin geometry |
| `netlist.py` | `kicad-cli` netlist export, plus the checks it skips: missing `lib_symbols`, duplicate references |
| `net2v.py` | netlist → structural Verilog over `pcb/models/74hc.v`. It resolves every multi-driver net with no z, turns jumpers into parameters (`Sim.Jumper`), swaps RC sheets for macro cells (`Sim.Macro`), and takes a resistor's direction from `Sim.R`. It also writes a sidecar JSON of every port's class |
| `pcb.py` | places a board from its netlist. What mates with another board (the stack, the link J8, the bus and edge IDCs) goes where the JSON says, checked pad by pad; DIPs go on a grid with their 100 nF beside VCC, the rest where they fit. `relink` points footprints at their symbols again |
| `anneal.py` | a better first placement: simulated annealing of every part not fixed or pinned, minimising wirelength with each 100 nF tied to its VCC pin and a routing channel around each package; `place.py apply` writes the result |
| `place.py` | `info` (what is fixed, what to place), `apply` (a placement JSON to a board; `"edge"` lets a right-angle part overhang), `hpwl`, `score` (route, pour, DRC with parity) |
| `route.py` | Freerouting 2.4.1, headless and routing only, then a GND pour. The jar is not in git: set `FREEROUTING_JAR` |
| `capped` | runs a command in its own cgroup with a memory ceiling (`CAP_MEM`, default 3G) |

The drawing contract for a schematic `net2v.py` can read:
- Every package's Value names its model (`74HC151`, via `pcb/models/pinmap.json`).
- An open drain is a part whose model says `od`.
- A jumper carries `Sim.Jumper`, for example `one:LANE` or `nbits:POS`.
- An RC network sits on its own sheet, whose symbol carries `Sim.Macro`, for example `rc_det T_ARM=T_ARM T_REL=T_REL`.
- A resistor between two driven nets carries `Sim.R = from:N`.

The netlist check itself is `pcb/sim/` (`make -C pcb netcheck` / `lockstep`).
