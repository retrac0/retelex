#!/bin/bash
# C14 job C: tb_chain with the leaves' absent directions strapped (zero-part fix for leaf-sweeps-for-nothing)
cd /home/joel/telco/newimpl/build/flood
W=work/verify/C14-forward-resources
export TMPDIR=/home/joel/telco/newimpl/build/flood/tmp
t0=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_chain --Mdir $W/obj_chls -o tb_chain $(cat work/RTL.list) tb/site_net.v $W/tb_chain_leafstrap.v > $W/vl_chls.log 2>&1; echo "C build chain-leafstrap rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 1500 $W/obj_chls/tb_chain > $W/run_chain_leafstrap.log 2>&1; echo "C chain-leafstrap rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
rm -rf $W/obj_chls
echo "C DONE" >> $W/job.progress
t0=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_chain --Mdir $W/obj_chct -o tb_chain $(cat work/RTL.list) tb/site_net.v $W/tb_chain_counters.v > $W/vl_chct.log 2>&1; echo "C build chain-counters(no strap) rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 1500 $W/obj_chct/tb_chain > $W/run_chain_counters.log 2>&1; echo "C chain-counters rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
rm -rf $W/obj_chct
echo "C2 DONE" >> $W/job.progress
