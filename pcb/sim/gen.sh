#!/bin/sh
# gen.sh -- the three block-stack schematics to Verilog: kicad-cli netlist, the
# checks kicad-cli skips, net2v.py, and the stack wrapper that wires the three
# modules together the way the stacking headers and the header link do.
# Output in pcb/out/gen.  Then sim/run.py.
set -e
cd "$(dirname "$0")/.."
mkdir -p out/gen
A=blkhdr_bus_RevA
B=blkhdr_logic_RevA
C=portcard_RevC
python3 tools/gen_cards.py --check
quiet='floats when every driver lets go\|connector .* ignored (not in --ports)\|pinmap .74HC4002. pins'
for card in $A $B $C; do
    python3 tools/netlist.py export $card/$card.kicad_sch -o out/gen/$card.xml
done
python3 tools/net2v.py out/gen/$A.xml --top ${A}_net --ports J1,J2,J4,J6,J7,J8 \
    -o out/gen/${A}_net.v 2>&1 | grep -v "$quiet" || true
python3 tools/net2v.py out/gen/$B.xml --top ${B}_net --ports J1,J2,J8,J9 --portmap sim/lamps.json \
    -o out/gen/${B}_net.v 2>&1 | grep -v "$quiet" || true
python3 tools/net2v.py out/gen/$C.xml --top ${C}_net --ports J1,J2,J4,J5 \
    --param T_ARM=16 --param T_REL=256 -o out/gen/${C}_net.v 2>&1 | grep -v "$quiet" || true
python3 sim/mkstack.py
test -s out/gen/${A}_net.v && test -s out/gen/${B}_net.v && test -s out/gen/${C}_net.v \
    && test -s out/gen/block_stack.v
