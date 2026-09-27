#!/bin/bash
# C09 verify, job A: the auditor's tb_fcan (knob RTL), then tb_c09 on the snapshot and on rtl_fix
set -u
F=/home/joel/telco/newimpl/build/flood
cd $F
D=work/verify/C09-fwrite-ignores-fcancel
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal"
echo "jobA start $(date +%T)"
$VL --top-module tb_fcan --Mdir $D/obj_fcan -o tb_fcan tb/site_net.v work/audit/cableb/tb_fcan.v $(cat work/audit/cableb/RTL_k.list) > $D/vl_fcan.log 2>&1; echo "build rc=$?" >> $D/vl_fcan.log
for m in "+mode=0" "+mode=1" "+mode=0 +fixfc"; do
  n=$(echo $m | tr -d '+= ' ); timeout 600 $D/obj_fcan/tb_fcan $m > $D/run_fcan_$n.log 2>&1; echo "rc=$?" >> $D/run_fcan_$n.log
done
rm -rf $D/obj_fcan
echo "fcan done $(date +%T)"
for v in base fix; do
  if [ $v = base ]; then L=work/RTL.list; else L=$D/RTL_fix.list; fi
  $VL --top-module tb_c09 --Mdir $D/obj_c09_$v -o tb_c09 tb/site_net.v $D/tb_c09.v $(cat $L) > $D/vl_c09_$v.log 2>&1; echo "build rc=$?" >> $D/vl_c09_$v.log
  timeout 1800 $D/obj_c09_$v/tb_c09 > $D/run_c09_$v.log 2>&1; echo "rc=$?" >> $D/run_c09_$v.log
  rm -rf $D/obj_c09_$v
  echo "c09 $v done $(date +%T)"
done
echo "jobA end $(date +%T)"
