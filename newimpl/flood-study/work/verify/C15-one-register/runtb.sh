#!/bin/bash
# runtb.sh <bench> <rtl.list> <tag> <timeout s> : a tree bench (tb/site_net.v tb/tb_<bench>.v) on the given RTL
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C15-one-register
b=$1; list=$2; tag=$3; to=$4
cd $F
start=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_$b \
  --Mdir $D/obj_${b}_$tag -o tb_$b $(cat $list) tb/site_net.v tb/tb_$b.v > $D/vl_${b}_$tag.log 2>&1 \
  || { echo "BUILD FAILED" >> $D/vl_${b}_$tag.log; exit 1; }
timeout $to $D/obj_${b}_$tag/tb_$b > $D/run_${b}_$tag.log 2>&1
rc=$?
echo "rc=$rc secs=$(( $(date +%s) - start ))" >> $D/run_${b}_$tag.log
rm -rf $D/obj_${b}_$tag
