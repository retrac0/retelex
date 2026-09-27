#!/bin/bash
# F3 regression: tb_chain and tb_net on the F3 copy; delete objs
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C13-leg-glare
for b in chain net; do
  O=$V/obj_f3_$b
  verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_$b --Mdir $O -o tb_$b $(cat $V/RTL_f3.list) tb/site_net.v tb/tb_$b.v > $V/vl_f3_$b.log 2>&1; echo "BUILD rc=$?" >> $V/vl_f3_$b.log
  s=$(date +%s); timeout 2400 $O/tb_$b > $V/run_f3_$b.log 2>&1; echo "rc=$? secs=$(( $(date +%s) - s ))" >> $V/run_f3_$b.log
  rm -rf $O
done
