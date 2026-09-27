#!/bin/bash
# job.sh <tag> <rtl.list> <tb_c07 runs "sc:pause" ...> [--net]
# builds tb_c07 (and tb_net with --net) against the list, runs, cleans obj dirs.
set -u
F=/home/joel/telco/newimpl/build/flood; D=$F/work/verify/C07-link-outage-pulse
cd $F
tag=$1; list=$2; shift 2
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal"
$VL --top-module tb_c07 --Mdir $D/obj_$tag -o tb_c07 $(cat $list) tb/site_net.v $D/tb_c07.v > $D/vl_$tag.log 2>&1
echo "build rc=$?" >> $D/vl_$tag.log
net=0
for r in "$@"; do
  if [ "$r" = "--net" ]; then net=1; continue; fi
  sc=${r%%:*}; p=${r##*:}
  s0=$(date +%s)
  timeout 4000 $D/obj_$tag/tb_c07 +sc=$sc +pause=$p > $D/run_${tag}_sc${sc}_p${p}.log 2>&1
  echo "rc=$? secs=$(( $(date +%s) - s0 ))" >> $D/run_${tag}_sc${sc}_p${p}.log
done
rm -rf $D/obj_$tag
if [ $net = 1 ]; then
  $VL --top-module tb_net --Mdir $D/obj_net_$tag -o tb_net $(cat $list) tb/site_net.v tb/tb_net.v > $D/vl_net_$tag.log 2>&1
  echo "build rc=$?" >> $D/vl_net_$tag.log
  s0=$(date +%s)
  timeout 4000 $D/obj_net_$tag/tb_net > $D/run_net_$tag.log 2>&1
  echo "rc=$? secs=$(( $(date +%s) - s0 ))" >> $D/run_net_$tag.log
  rm -rf $D/obj_net_$tag
fi
