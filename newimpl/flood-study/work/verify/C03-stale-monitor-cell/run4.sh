#!/bin/bash
# tb_c03g on C03 fix (a)+(b) merged with C04's C_LOW fix (default C_LOWT=CLR, and +lowid)
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C03-stale-monitor-cell
M=work/audit/monclaim
rm -rf $V/obj_gm
verilator --binary --timing -j 2 -I$V/merge -I$M/rtl_fix -Irtl -Wno-fatal --top-module tb_c03g --Mdir $V/obj_gm -o tb_c03g $(cat $V/merge/RTL_merge.list) tb/site_net.v $V/tb_c03g.v > $V/vl_gm.log 2>&1; echo bgm=$?
timeout 1500 $V/obj_gm/tb_c03g > $V/run_g_merge.log 2>&1; echo rgm=$?
timeout 1500 $V/obj_gm/tb_c03g +lowid > $V/run_g_merge_lowid.log 2>&1; echo rgml=$?
rm -rf $V/obj_gm
