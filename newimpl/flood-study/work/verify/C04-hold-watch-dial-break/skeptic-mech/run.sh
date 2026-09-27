#!/bin/bash
# run.sh <tag> <rtl-list-file> <tb file> <top>   (skeptic-mech; builds + runs one bench under sim.sh)
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C04-hold-watch-dial-break/skeptic-mech
tag=$1; list=$2; tbf=$3; top=$4; shift 4
cd $F
obj=$D/obj_$tag
start=$(date +%s)
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module $top --Mdir $obj -o $top \
   $(cat $list) tb/site_net.v $tbf > $D/vl_$tag.log 2>&1
rc=$?
echo "build rc=$rc secs=$(( $(date +%s) - start ))" >> $D/vl_$tag.log
if [ $rc -eq 0 ]; then
  start=$(date +%s)
  timeout 3000 $obj/$top "$@" > $D/run_$tag.log 2>&1
  rc=$?
  echo "rc=$rc secs=$(( $(date +%s) - start ))" >> $D/run_$tag.log
fi
rm -rf $obj
exit $rc
