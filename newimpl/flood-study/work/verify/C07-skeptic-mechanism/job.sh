#!/bin/bash
# job.sh -- ONE run: tb_c07k (sc6 chatter, sc7 B restart) against the verifier's rtl_mut card, TRACE_B.
set -u
F=/home/joel/telco/newimpl/build/flood; D=$F/work/verify/C07-skeptic-mechanism
cd $F
verilator --binary --timing -j 2 -Irtl -Wno-fatal -DTRACE_B --top-module tb_c07 --Mdir $D/obj_k -o tb_c07 \
  $(cat work/verify/C07-link-outage-pulse/RTL_mut.list) tb/site_net.v $D/tb_c07k.v > $D/vl_k.log 2>&1
echo "build rc=$?" >> $D/vl_k.log
s0=$(date +%s)
timeout 2400 $D/obj_k/tb_c07 +sc=192 +pause=680 > $D/run_mut_sc192_p680.log 2>&1
echo "rc=$? secs=$(( $(date +%s) - s0 ))" >> $D/run_mut_sc192_p680.log
rm -rf $D/obj_k
