#!/bin/bash
# tb_c03r: A's T_REL 200 (RC 22% short) on the snapshot and on the monclaim fix; control at 256
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C03-stale-monitor-cell
M=work/audit/monclaim
for cfg in snap200 fix200 snap256; do
  case $cfg in
    snap200) L="$(cat work/RTL.list)"; I="-Irtl"; D="-DTRELA=200";;
    fix200)  L="$(cat $M/RTL_fix.list)"; I="-I$M/rtl_fix -Irtl"; D="-DTRELA=200";;
    snap256) L="$(cat work/RTL.list)"; I="-Irtl"; D="-DTRELA=256";;
  esac
  rm -rf $V/obj_r_$cfg
  verilator --binary --timing -j 2 $I -Wno-fatal $D --top-module tb_c03r --Mdir $V/obj_r_$cfg -o tb_c03r $L tb/site_net.v $V/tb_c03r.v > $V/vl_r_$cfg.log 2>&1; echo b_$cfg=$?
  timeout 1500 $V/obj_r_$cfg/tb_c03r > $V/run_r_$cfg.log 2>&1; echo r_$cfg=$?
  rm -rf $V/obj_r_$cfg
done
