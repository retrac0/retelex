#!/bin/bash
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C20-misc
O=$V/obj_z
rm -rf $O
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_c20z --Mdir $O -o tb_c20z $(cat work/RTL.list) tb/site_net.v $V/tb_c20z.v > $V/vl_z.log 2>&1; echo build_z=$?
timeout 1500 $O/tb_c20z > $V/run_z.log 2>&1; echo run_z=$?
rm -rf $O
