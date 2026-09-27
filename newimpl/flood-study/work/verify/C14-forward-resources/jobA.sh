#!/bin/bash
# C14 job A: tb_fx on the SNAPSHOT RTL (sc4, sc5), and tb_fx with NRES=3 (sc4)
cd /home/joel/telco/newimpl/build/flood
W=work/verify/C14-forward-resources
export TMPDIR=/home/joel/telco/newimpl/build/flood/tmp
t0=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_fx --Mdir $W/obj_fx -o tb_fx $(cat work/RTL.list) work/audit/fwd/site_fx.v work/audit/fwd/tb_fx.v > $W/vl_fx.log 2>&1; echo "A build fx rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 1500 $W/obj_fx/tb_fx +sc=4 > $W/run_fx_sc4.log 2>&1; echo "A sc4 rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 3000 $W/obj_fx/tb_fx +sc=5 > $W/run_fx_sc5.log 2>&1; echo "A sc5 rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
rm -rf $W/obj_fx
t0=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_fx --Mdir $W/obj_fx3 -o tb_fx $(cat work/RTL.list) work/audit/fwd/site_fx.v $W/tb_fx_nres3.v > $W/vl_fx3.log 2>&1; echo "A build fx nres3 rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 1500 $W/obj_fx3/tb_fx +sc=4 > $W/run_fx3_sc4.log 2>&1; echo "A nres3 sc4 rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
rm -rf $W/obj_fx3
echo "A DONE" >> $W/job.progress
