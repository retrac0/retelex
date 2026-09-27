#!/bin/bash
# step <tag> <rtl.list> <top> <tb files...> -- <run timeout s> [plusargs...]
F=/home/joel/telco/newimpl/build/flood
V=$F/work/verify/C12-origin-claim-acceptance
cd $F
export TMPDIR=$F/tmp
step() {
  local tag=$1 list=$2 top=$3 defs=$4 tbs=$5 to=$6; shift 6
  echo "$(date +%T) start $tag" >> $V/progress.txt
  rm -rf $V/obj_$tag
  verilator --binary --timing -j 2 -Irtl -Wno-fatal $defs --top-module $top --Mdir $V/obj_$tag -o $top \
      $(cat $list) $tbs > $V/vl_$tag.log 2>&1
  local b=$?
  if [ $b -ne 0 ]; then echo "$(date +%T) BUILD FAIL $tag rc=$b" >> $V/progress.txt; rm -rf $V/obj_$tag; return; fi
  local t0=$(date +%s)
  timeout $to $V/obj_$tag/$top "$@" > $V/$tag.log 2>&1
  local r=$?
  echo "rc=$r secs=$(( $(date +%s) - t0 ))" >> $V/$tag.log
  echo "$(date +%T) done $tag rc=$r $(grep -E 'checks, [0-9]+ errors' $V/$tag.log | tail -1)" >> $V/progress.txt
  rm -rf $V/obj_$tag
}
