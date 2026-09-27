#!/bin/bash
# one slot: fix-b-only RTL, tb_orig +scen=4 then tb_net
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C06-pre-seizure-break
timeout 900 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_orig --Mdir $V/obj_orig_fixb -o tb_orig $(cat $V/RTL_fixb.list) tb/site_net.v work/audit/origin/tb_orig.v > $V/vl_orig_fixb.log 2>&1 \
  && timeout 2400 $V/obj_orig_fixb/tb_orig +scen=4 > $V/run_orig_s3_fixb.log 2>&1
echo "orig rc=$?" >> $V/job_fixb.rc
rm -rf $V/obj_orig_fixb
timeout 900 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_net --Mdir $V/obj_net_fixb -o tb_net $(cat $V/RTL_fixb.list) tb/site_net.v tb/tb_net.v > $V/vl_net_fixb.log 2>&1 \
  && timeout 3000 $V/obj_net_fixb/tb_net > $V/run_net_fixb.log 2>&1
echo "net rc=$?" >> $V/job_fixb.rc
rm -rf $V/obj_net_fixb
