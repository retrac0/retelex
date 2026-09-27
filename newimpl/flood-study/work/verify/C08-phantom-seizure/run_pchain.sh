#!/bin/bash
# usage: run_pchain.sh <rtl.list> <tag> <plusargs...>
cd /home/joel/telco/newimpl/build/flood
D=work/verify/C08-phantom-seizure
L=$1; T=$2; shift 2
O=$D/obj_$T
start=$(date +%s)
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_pchain --Mdir $O -o tb_pchain \
   $(cat $L) tb/site_net.v work/audit/proto/tb_pchain.v > $D/vl_$T.log 2>&1 || { echo BUILD FAIL; tail -20 $D/vl_$T.log; exit 1; }
timeout 3000 $O/tb_pchain "$@" > $D/run_$T.log 2>&1
echo "rc=$? secs=$(( $(date +%s) - start ))" >> $D/run_$T.log
rm -rf $O
