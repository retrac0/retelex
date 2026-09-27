#!/bin/bash
# re-run the auditor's S6 reproducer on its fixed RTL, with A20/r_gone traces
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C17-nogo-after-release
cd $F
O=$D/obj_orig
rm -rf $O
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_orig --Mdir $O -o tb_orig \
   $(cat work/audit/origin/RTL_fix.list) tb/site_net.v $D/tb_orig_c17.v > $D/vl_orig.log 2>&1 || { echo BUILD FAIL; exit 1; }
timeout 1500 $O/tb_orig +scen=32 > $D/run_orig_s6.log 2>&1
echo "rc=$?" >> $D/run_orig_s6.log
rm -rf $O
