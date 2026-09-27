#!/bin/bash
# tb_c03b on the snapshot, A's T_REL 200: the M_WANT_B stale-cell variant (one run)
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C03-stale-monitor-cell/skeptic-mechanism
rm -rf $V/obj_b
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal -DTRELA=200 --top-module tb_c03b --Mdir $V/obj_b -o tb_c03b $(cat work/RTL.list) tb/site_net.v $V/tb_c03b.v > $V/vl_b.log 2>&1; echo b=$?
timeout 1500 $V/obj_b/tb_c03b > $V/run_b_snap200.log 2>&1; echo r=$?
rm -rf $V/obj_b
