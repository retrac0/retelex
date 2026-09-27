#!/bin/bash
# run_net.sh <tag> <rtl-list>: tb_net (scale 8) on the given RTL; deletes the obj dir.
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C05-late-flood-guard-reach
cd $F
tag=$1; list=$2
O=$D/obj_net_$tag
SECONDS=0
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_net --Mdir $O -o tb_net \
    $(cat $list) tb/site_net.v tb/tb_net.v > $D/vl_net_$tag.log 2>&1
echo "build rc=$? secs=$SECONDS" >> $D/vl_net_$tag.log
SECONDS=0
timeout 3600 $O/tb_net > $D/run_net_$tag.log 2>&1
echo "rc=$? secs=$SECONDS" >> $D/run_net_$tag.log
rm -rf $O
