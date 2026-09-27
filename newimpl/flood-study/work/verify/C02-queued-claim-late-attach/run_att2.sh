#!/bin/bash
# usage: run_att2.sh <tag> <rtl.list> [plusargs...]
F=/home/joel/telco/newimpl/build/flood; D=$F/work/verify/C02-queued-claim-late-attach
tag=$1; list=$2; shift 2
cd $F
t0=$(date +%s)
timeout 900 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_att2 --Mdir $D/obj_att2_$tag -o tb_att2 \
   $(cat $list) tb/site_net.v work/audit/cableb/tb_att2.v > $D/vl_att2_$tag.log 2>&1
echo "build rc=$? secs=$(( $(date +%s)-t0 ))" >> $D/vl_att2_$tag.log
