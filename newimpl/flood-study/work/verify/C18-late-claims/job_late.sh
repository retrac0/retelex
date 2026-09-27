#!/bin/bash
# usage: job_late.sh <tag> <rtl list> <dly_us...>
# build tb_late against the list, run one fresh sim per DLY -> run_late_<tag>_<dly>.log; delete obj
set -u
F=/home/joel/telco/newimpl/build/flood
V=$F/work/verify/C18-late-claims
T=$1; L=$2; shift 2
cd $F
export TMPDIR=$F/tmp
O=$V/obj_late_$T
echo "[$T] build start $(date +%T)"
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_late --Mdir $O -o tb_late \
   $(cat $L) tb/site_net.v $V/tb_late.v > $V/vl_late_$T.log 2>&1 || { echo "[$T] BUILD FAIL"; tail -30 $V/vl_late_$T.log; rm -rf $O; exit 1; }
echo "[$T] build done $(date +%T)"
cd $V
for d in "$@"; do
  s=$(date +%s); timeout 1500 $O/tb_late +scen=64 +d0=$d +dn=$d +dstep=1000 > run_late_${T}_$d.log 2>&1; rc=$?
  echo "rc=$rc secs=$(( $(date +%s) - s ))" >> run_late_${T}_$d.log
  echo "[$T] DLY $d rc=$rc $(date +%T) $(grep -c FAIL run_late_${T}_$d.log) FAIL"
done
rm -rf $O
