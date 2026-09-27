#!/bin/bash
# build + run tb_c03g on the snapshot and on the monclaim fixed RTL
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C03-stale-monitor-cell
M=work/audit/monclaim
rm -rf $V/obj_g $V/obj_gf
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_c03g --Mdir $V/obj_g -o tb_c03g $(cat work/RTL.list) tb/site_net.v $V/tb_c03g.v > $V/vl_g.log 2>&1; echo bg=$?
timeout 1500 $V/obj_g/tb_c03g > $V/run_g_snap.log 2>&1; echo rg=$?
verilator --binary --timing -j 2 -I$M/rtl_fix -Irtl -Wno-fatal --top-module tb_c03g --Mdir $V/obj_gf -o tb_c03g $(cat $M/RTL_fix.list) tb/site_net.v $V/tb_c03g.v > $V/vl_gf.log 2>&1; echo bgf=$?
timeout 1500 $V/obj_gf/tb_c03g > $V/run_g_fix.log 2>&1; echo rgf=$?
