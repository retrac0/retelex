#!/bin/bash
cd /home/joel/telco/newimpl/build/flood
S=work/verify/C06-pre-seizure-break/skeptic-mechanism
timeout 900 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_c06sk --Mdir $S/obj_sk -o tb_c06sk $(cat work/RTL.list) tb/site_net.v $S/tb_c06sk.v > $S/vl_sk.log 2>&1 \
  && timeout 1800 $S/obj_sk/tb_c06sk > $S/run_sk.log 2>&1
echo "rc=$?" > $S/job.rc
rm -rf $S/obj_sk
