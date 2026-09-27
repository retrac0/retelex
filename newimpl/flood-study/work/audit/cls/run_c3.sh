#!/bin/bash
# run_c3.sh -- build tb_cls3 (POOL8, REAL timers) on the SNAPSHOT RTL and run
# sc7, sc8, sc9, then the two load runs.  Run through ../../../sim.sh from the
# flood directory.  Each step has its own timeout; logs land beside this file.
F=/home/joel/telco/newimpl/build/flood
W=$F/work/audit/cls
cd $F || exit 9
export TMPDIR=$F/tmp
echo "build start $(date +%T)" > $W/c3.progress
verilator --binary --timing -j 2 -Irtl -Wno-fatal +define+POOL8 --top-module tb_cls \
  --Mdir $W/obj_c3 -o tb_cls $(cat work/RTL.list) tb/site_net.v $W/tb_cls3.v > $W/vl_c3.log 2>&1 \
  || { echo "BUILD FAILED $(date +%T)" >> $W/c3.progress; exit 8; }
echo "build done $(date +%T)" >> $W/c3.progress
run() {   # name timeout args...
  local n=$1 t=$2; shift 2
  local s=$(date +%s)
  timeout $t $W/obj_c3/tb_cls "$@" > $W/run_c3_$n.log 2>&1
  echo "rc=$? wall=$(( $(date +%s) - s ))" >> $W/run_c3_$n.log
  echo "$n done $(date +%T)" >> $W/c3.progress
}
run sc7 1200 +sc=7 +maxms=8000
run sc8 900  +sc=8 +maxms=4000
run sc9 900  +sc=9 +maxms=4000
run sc11 900 +sc=11 +maxms=5000
run ovl 4800 +sc=10 +mode=1 +lam=30000 +dur=15000 +t1lo=100 +t1hi=400 +pexp=150 +pown=0 +loc=8000 +pnet=300 +seed=3 +maxms=60000
run r1  4800 +sc=10 +mode=0 +lam=5000 +dur=30000 +t1lo=60 +t1hi=700 +pexp=500 +pown=100 +loc=8000 +pnet=300 +seed=1 +maxms=80000
echo "ALLDONE $(date +%T)" >> $W/c3.progress
