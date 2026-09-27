#!/bin/bash
# re-run the auditor's reproducers on the snapshot: tb_mc -DREAL sc=1, sc=3 ; tb_mc2 (real)
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C03-stale-monitor-cell
M=work/audit/monclaim
rm -rf $V/obj_r13 $V/obj_mc2
verilator --binary --timing -j 2 -Irtl -Wno-fatal -DREAL --top-module tb_mc --Mdir $V/obj_r13 -o tb_mc $(cat work/RTL.list) tb/site_net.v $M/tb_mc.v > $V/vl_r13.log 2>&1; echo b1=$?
timeout 1200 $V/obj_r13/tb_mc +sc=1 > $V/rerun_real13_sc1.log 2>&1; echo r1=$?
timeout 1200 $V/obj_r13/tb_mc +sc=3 > $V/rerun_real13_sc3.log 2>&1; echo r3=$?
rm -rf $V/obj_r13
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_mc2 --Mdir $V/obj_mc2 -o tb_mc2 $(cat work/RTL.list) tb/site_net.v $M/tb_mc2.v > $V/vl_mc2.log 2>&1; echo b2=$?
timeout 2400 $V/obj_mc2/tb_mc2 > $V/rerun_mc2.log 2>&1; echo r2=$?
rm -rf $V/obj_mc2
