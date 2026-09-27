#!/bin/bash
# SKEPTIC C13: tb_pchain on the F3' copy, pass 1 only, C20 dialling 150 ms after A20; delete obj
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C13-skeptic-mechanism
L=work/verify/C13-leg-glare/RTL_f3.list
O=$V/obj_pchain_f3
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_pchain --Mdir $O -o tb_pchain $(cat $L) tb/site_net.v $V/tb_pchain.v > $V/vl_pchain_f3.log 2>&1; echo "BUILD rc=$?" >> $V/vl_pchain_f3.log
s=$(date +%s); timeout 1800 $O/tb_pchain +sc=1 +p0=1 +cdly=150 +trace > $V/run_pchain_f3_cdly150.log 2>&1; echo "rc=$? secs=$(( $(date +%s) - s ))" >> $V/run_pchain_f3_cdly150.log
rm -rf $O
