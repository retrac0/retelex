#!/bin/bash
# run.sh <tag> <rtl.list> <extra verilator flags> <plusargs> <timeout s>
# builds tb_c15 against the RTL list and runs it; obj dir removed afterwards
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C15-one-register
tag=$1; list=$2; vflags=$3; plus=$4; to=$5
cd $F
start=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal $vflags --top-module tb_c15 \
  --Mdir $D/obj_$tag -o tb_c15 $(cat $list) tb/site_net.v $D/tb_c15.v > $D/vl_$tag.log 2>&1 \
  || { echo "BUILD FAILED" >> $D/vl_$tag.log; exit 1; }
timeout $to $D/obj_$tag/tb_c15 $plus > $D/run_$tag.log 2>&1
rc=$?
echo "rc=$rc secs=$(( $(date +%s) - start ))" >> $D/run_$tag.log
rm -rf $D/obj_$tag
