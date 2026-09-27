#!/bin/bash
# run_r.sh <cfg> : build tb_c20r for one config and run its modes.  Called through sim.sh.
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C20-misc
cfg=$1
case $cfg in
  n11)  D="-DTRELA=256 -DTA=9";;
  s240) D="-DTRELA=240 -DTA=9";;
  n70)  D="-DTRELA=256 -DTA=56";;
  n11d) D="-DTRELA=256 -DTA=9";;
esac
O=$V/obj_$cfg
rm -rf $O
verilator --binary --timing -j 2 -Irtl -Wno-fatal $D --top-module tb_c20r --Mdir $O -o tb_c20r $(cat work/RTL.list) tb/site_net.v $V/tb_c20r.v > $V/vl_$cfg.log 2>&1; echo build_$cfg=$?
case $cfg in
  n11)  timeout 1500 $O/tb_c20r > $V/run_n11_full.log 2>&1; echo run_full=$?
        timeout 2400 $O/tb_c20r +scan=1 +rs0=254 +rs1=258 > $V/run_n11_scan.log 2>&1; echo run_scan=$?;;
  n11d) timeout 1500 $O/tb_c20r +scan=1 +rs0=256 +rs1=257 > $V/run_n11d_scan.log 2>&1; echo run_scan=$?;;
  s240) timeout 1500 $O/tb_c20r > $V/run_s240_full.log 2>&1; echo run_full=$?;;
  n70)  timeout 3000 $O/tb_c20r +scan=1 +rs0=244 +rs1=252 > $V/run_n70_scan.log 2>&1; echo run_scan=$?
        timeout 3000 $O/tb_c20r +scan=1 +rs0=246 +rs1=250 +fd=500 > $V/run_n70_fd500.log 2>&1; echo run_fd=$?;;
esac
rm -rf $O
