#!/bin/bash
# run_fx.sh <tag> <rtl-list> <run spec>...   run spec = "sc:load:dly"
# Builds work/audit/fwd/tb_fx.v on the given RTL, runs each spec, deletes the obj dir.
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C05-late-flood-guard-reach
cd $F
tag=$1; list=$2; shift 2
O=$D/obj_$tag
SECONDS=0
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_fx --Mdir $O -o tb_fx \
    $(cat $list) work/audit/fwd/site_fx.v work/audit/fwd/tb_fx.v > $D/vl_$tag.log 2>&1
echo "build rc=$? secs=$SECONDS" >> $D/vl_$tag.log
for spec in "$@"; do
  IFS=: read sc load dly <<< "$spec"
  L=$D/run_${tag}_sc${sc}_l${load}_d${dly}.log
  SECONDS=0
  timeout 1500 $O/tb_fx +sc=$sc +load=$load +dly=$dly > $L 2>&1
  echo "rc=$? secs=$SECONDS" >> $L
done
rm -rf $O
