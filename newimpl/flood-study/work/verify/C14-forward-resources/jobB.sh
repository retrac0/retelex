#!/bin/bash
# C14 job B: the transit agent's pending-forward fix (work/load/transit/fix/net_unit.v): tb_fx sc5, sc4; tb_net
cd /home/joel/telco/newimpl/build/flood
W=work/verify/C14-forward-resources
export TMPDIR=/home/joel/telco/newimpl/build/flood/tmp
t0=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_fx --Mdir $W/obj_fxpf -o tb_fx $(cat $W/RTL_pf.list) work/audit/fwd/site_fx.v work/audit/fwd/tb_fx.v > $W/vl_fxpf.log 2>&1; echo "B build fxpf rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 3000 $W/obj_fxpf/tb_fx +sc=5 > $W/runpf_fx_sc5.log 2>&1; echo "B pf sc5 rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 1500 $W/obj_fxpf/tb_fx +sc=4 > $W/runpf_fx_sc4.log 2>&1; echo "B pf sc4 rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
rm -rf $W/obj_fxpf
t0=$(date +%s)
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_net --Mdir $W/obj_netpf -o tb_net $(cat $W/RTL_pf.list) tb/site_net.v tb/tb_net.v > $W/vl_netpf.log 2>&1; echo "B build netpf rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
t0=$(date +%s); timeout 3000 $W/obj_netpf/tb_net > $W/runpf_net.log 2>&1; echo "B pf tb_net rc=$? $(( $(date +%s)-t0 ))s" >> $W/job.progress
rm -rf $W/obj_netpf
echo "B DONE" >> $W/job.progress
