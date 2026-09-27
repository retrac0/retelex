#!/bin/bash
# one run: tb_c03b (M_WANT_B variant of rc-tolerance-reseize) on the SNAPSHOT, A's T_REL 200
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C03-skeptic-realism
rm -rf $V/obj_b
verilator --binary --timing -j 2 -Irtl -Wno-fatal -DTRELA=200 --top-module tb_c03b --Mdir $V/obj_b -o tb_c03b $(cat work/RTL.list) tb/site_net.v $V/tb_c03b.v > $V/vl_b.log 2>&1; echo build=$?
timeout 1500 $V/obj_b/tb_c03b > $V/run_b_snap200.log 2>&1; echo run=$?
rm -rf $V/obj_b
