#!/bin/bash
# run_late.sh: tb_fx sc6 l1 d112 at real timers on the snapshot + the lateness bit alone; deletes the obj dir.
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C05-late-flood-guard-reach/skeptic-mechanism
cd $F
O=$D/obj_late
SECONDS=0
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_fx --Mdir $O -o tb_fx \
    $(cat $D/RTL_late.list) work/audit/fwd/site_fx.v work/audit/fwd/tb_fx.v > $D/vl_late.log 2>&1
echo "build rc=$? secs=$SECONDS" >> $D/vl_late.log
SECONDS=0
timeout 1200 $O/tb_fx +sc=6 +load=1 +dly=112 > $D/run_late_sc6_l1_d112.log 2>&1
echo "rc=$? secs=$SECONDS" >> $D/run_late_sc6_l1_d112.log
rm -rf $O
