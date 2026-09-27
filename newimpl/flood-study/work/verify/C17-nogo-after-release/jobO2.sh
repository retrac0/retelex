#!/bin/bash
# auditor's S6 with every port's T_REL 26 (RC ~19 % short) against CLR 32: current audit fix, then audit fix + FIX B
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C17-nogo-after-release
cd $F
for v in fix:work/audit/origin/RTL_fix.list fixcB:$D/RTL_fixcB.list; do
  n=${v%%:*}; L=${v#*:}; O=$D/obj_o2_$n
  rm -rf $O
  timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_orig --Mdir $O -o tb_orig \
     $(cat $L) tb/site_net.v $D/tb_orig_c17r.v > $D/vl_o2_$n.log 2>&1 || { echo BUILD FAIL $n; continue; }
  timeout 1500 $O/tb_orig +scen=32 > $D/run_o2_$n.log 2>&1
  echo "rc=$?" >> $D/run_o2_$n.log
  rm -rf $O
done
echo JOBO2 DONE
