#!/bin/bash
set -u
F=/home/joel/telco/newimpl/build/flood; D=$F/work/verify/C07-link-outage-pulse
cd $F
verilator --binary --timing -j 2 -Irtl -Wno-fatal -DTRACE_B --top-module tb_c07 --Mdir $D/obj_tr -o tb_c07 $(cat work/RTL.list) tb/site_net.v $D/tb_c07.v > $D/vl_tr.log 2>&1
echo "build rc=$?" >> $D/vl_tr.log
for r in "$@"; do
  sc=${r%%:*}; p=${r##*:}
  s0=$(date +%s)
  timeout 3000 $D/obj_tr/tb_c07 +sc=$sc +pause=$p > $D/run_tr_sc${sc}_p${p}.log 2>&1
  echo "rc=$? secs=$(( $(date +%s) - s0 ))" >> $D/run_tr_sc${sc}_p${p}.log
done
