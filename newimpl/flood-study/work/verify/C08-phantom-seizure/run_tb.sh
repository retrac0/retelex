#!/bin/bash
# usage: run_tb.sh <rtl.list> <top> <tbfile(s) quoted> <tag> <plusargs...>
cd /home/joel/telco/newimpl/build/flood
D=work/verify/C08-phantom-seizure
L=$1; TOP=$2; TBF=$3; T=$4; shift 4
O=$D/obj_$T
start=$(date +%s)
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module $TOP --Mdir $O -o $TOP \
   $(cat $L) $TBF > $D/vl_$T.log 2>&1 || { echo BUILD FAIL > $D/run_$T.log; tail -30 $D/vl_$T.log >> $D/run_$T.log; rm -rf $O; exit 1; }
timeout 4000 $O/$TOP "$@" > $D/run_$T.log 2>&1
echo "rc=$? secs=$(( $(date +%s) - start ))" >> $D/run_$T.log
rm -rf $O
