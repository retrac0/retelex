#!/bin/bash
# build tb_pchain on snapshot ($1=snap) or F3 ($1=f3), run sc=1 +trace; delete obj
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C13-leg-glare
if [ "$1" = f3 ]; then L=$V/RTL_f3.list; else L=work/RTL.list; fi
O=$V/obj_pchain_$1
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_pchain --Mdir $O -o tb_pchain $(cat $L) tb/site_net.v $V/tb_pchain.v > $V/vl_pchain_$1.log 2>&1; echo "BUILD rc=$?" >> $V/vl_pchain_$1.log
s=$(date +%s); timeout 2400 $O/tb_pchain +sc=1 +trace > $V/run_pchain_$1.log 2>&1; echo "rc=$? secs=$(( $(date +%s) - s ))" >> $V/run_pchain_$1.log
rm -rf $O
