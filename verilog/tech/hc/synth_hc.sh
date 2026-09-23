#!/usr/bin/env bash
# Run Yosys HC mapping for one top and pack the BOM.
# Usage: synth_hc.sh <top> [extra yosys cmds before hierarchy...]
# RTL files are taken from the environment variable RTL_FILES.
# Optional HC_BB=tech/hc/hc_bb.v: read as -lib blackboxes first (preferred for
# MSI / mini_core / pulse_reg so package counts stay at the hand BOM).
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
BB=${HC_BB:-}
YS=$BUILD/synth_hc_${TOP}.ys
LOG=$BUILD/synth_hc_${TOP}.log
JSON=$BUILD/synth_hc_${TOP}.json

mkdir -p "$BUILD"
: "${RTL_FILES:?RTL_FILES must list the Verilog sources}"

{
  if [[ -n "$BB" ]]; then
    echo "read_verilog -lib $BB"
  fi
  echo "read_verilog -sv -I $ROOT/rtl -defer $RTL_FILES"
  echo "read_verilog $CELLS"
  for c in "${EXTRA_CMDS[@]}"; do
    [[ -n "$c" ]] && echo "$c"
  done
  echo "hierarchy -check -top $TOP"
  if [[ -z "$BB" ]]; then
    echo "blackbox mux8 hc259 ctl_write hc151 hc164 hc165 hc393 hc4040 hc163 hc175 hc670 hc174 hc74_dff hc86_xor2 hc157 hc138"
  fi
  echo "proc; opt; fsm; opt; memory; opt"
  echo "techmap; opt"
  echo "dfflibmap -prepare -liberty $LIB"
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
