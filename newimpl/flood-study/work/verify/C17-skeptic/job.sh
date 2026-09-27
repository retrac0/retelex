#!/bin/bash
# C17 skeptic: ONE run -- far-end form (claimed trunk as caller, B's NODIG vs B11's release), snapshot, scale 8
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C17-skeptic
O=$D/obj_far
cd $F
rm -rf $O
timeout 1200 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_c17f --Mdir $O -o tb_c17f \
   $(cat work/RTL.list) tb/site_net.v $D/tb_c17f.v > $D/vl_far.log 2>&1 || { echo BUILD FAIL; tail -30 $D/vl_far.log; rm -rf $O; exit 1; }
echo BUILD OK
timeout 1800 $O/tb_c17f +n=8 +f0=0 +step=500 > $D/far.log 2>&1
echo "rc=$?" >> $D/far.log
rm -rf $O
echo JOB DONE
