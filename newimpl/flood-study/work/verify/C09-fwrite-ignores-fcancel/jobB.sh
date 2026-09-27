#!/bin/bash
# C09 verify, job B: tb_net and tb_chain on rtl_fix (the minimal F_WRITE gate)
set -u
F=/home/joel/telco/newimpl/build/flood
cd $F
D=work/verify/C09-fwrite-ignores-fcancel
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal"
echo "jobB start $(date +%T)"
for b in net chain; do
  $VL --top-module tb_$b --Mdir $D/obj_${b}_fix -o tb_$b tb/site_net.v tb/tb_$b.v $(cat $D/RTL_fix.list) > $D/vl_${b}_fix.log 2>&1; echo "build rc=$?" >> $D/vl_${b}_fix.log
  timeout 2700 $D/obj_${b}_fix/tb_$b > $D/run_${b}_fix.log 2>&1; echo "rc=$?" >> $D/run_${b}_fix.log
  rm -rf $D/obj_${b}_fix
  echo "$b done $(date +%T)"
done
echo "jobB end $(date +%T)"
