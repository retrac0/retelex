#!/usr/bin/env bash
# Run Yosys HC mapping for one top and pack the BOM.
# Usage: synth_hc.sh <top> [extra yosys cmds before hierarchy...]
# RTL files are taken from the environment variable RTL_FILES.
set -euo pipefail

TOP=${1:?top module name}
shift
EXTRA_CMDS=("$@")

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD=${BUILD:-"$ROOT/build"}
LIB=$ROOT/tech/hc/hc_ssi.lib
CELLS=$ROOT/tech/hc/hc_cells.v
MAP=$ROOT/tech/hc/hc_map.v
PACK=$ROOT/tech/hc/pack.py
YS=$BUILD/synth_hc_${TOP}.ys
LOG=$BUILD/synth_hc_${TOP}.log
JSON=$BUILD/synth_hc_${TOP}.json

mkdir -p "$BUILD"
: "${RTL_FILES:?RTL_FILES must list the Verilog sources}"

{
  echo "read_verilog -sv -I $ROOT/rtl -defer $RTL_FILES"
  echo "read_verilog $CELLS"
  for c in "${EXTRA_CMDS[@]}"; do
    [[ -n "$c" ]] && echo "$c"
  done
  echo "hierarchy -check -top $TOP"
  # Blackbox MSI so abc does not explode them into gates.  Missing names warn
  # and are ignored (not every top instantiates every part).
  echo "blackbox mux8 hc259 ctl_write hc151 hc164 hc165"
  echo "proc; opt; fsm; opt; memory; opt"
  echo "techmap; opt"
  echo "dfflibmap -prepare -liberty $LIB"
  # ABC liberty/genlib segfault on this Yosys build — map to simple gates,
  # then rename onto HC SSI packages with hc_map.v.
  echo "abc -g AND,NAND,OR,NOR"
  echo "dfflibmap -liberty $LIB"
  echo "techmap -map $MAP"
  echo "opt_clean"
  echo "stat -top $TOP"
  echo "write_json $JSON"
} > "$YS"

echo "==== $TOP ===="
yosys -ql "$LOG" -s "$YS"
tail -n 25 "$LOG"
python3 "$PACK" "$JSON"
