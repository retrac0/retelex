#!/bin/bash
# run_f4.sh -- the cheap fix set (fix2/, RTL_fix2.list) against the directed
# benches (tb_cls2 sc1-6 NMON 2, tb_cls3 sc7-9 POOL8), then the tree's network
# benches, then the overload run.  REAL timers for tb_cls*.  Through sim.sh.
F=/home/joel/telco/newimpl/build/flood
W=$F/work/audit/cls
cd $F || exit 9
export TMPDIR=$F/tmp
P=$W/f4.progress
echo "start $(date +%T)" > $P
RTLF=$(cat $W/RTL_fix2.list)
bld() {   # objdir top defines... -- files
  local o=$1 top=$2; shift 2
  verilator --binary --timing -j 2 -Irtl -Wno-fatal "$@" --top-module $top --Mdir $W/$o -o $top \
    > $W/vl_$o.log 2>&1 || { echo "BUILD FAILED $o $(date +%T)" >> $P; return 1; }
  echo "built $o $(date +%T)" >> $P
}
run() {   # name bin timeout args...
  local n=$1 b=$2 t=$3; shift 3
  local s=$(date +%s)
  timeout $t $b "$@" > $W/run_f4_$n.log 2>&1
  echo "rc=$? wall=$(( $(date +%s) - s ))" >> $W/run_f4_$n.log
  echo "$n done $(date +%T) $(grep -E 'checks,' $W/run_f4_$n.log | tail -1)" >> $P
}
# 1. tb_cls2, NMON 2 NRES 2
if bld obj_f4a tb_cls $RTLF tb/site_net.v $W/tb_cls2.v; then
  for a in "sc=2" "sc=3" "sc=4" "sc=5" "sc=6" "sc=1 +K=8"; do
    n=c2_$(echo $a | tr -d "+= "); run $n $W/obj_f4a/tb_cls 1500 +$a
  done
  rm -rf $W/obj_f4a
fi
# 2. tb_cls3, POOL8
if bld obj_f4b tb_cls +define+POOL8 $RTLF tb/site_net.v $W/tb_cls3.v; then
  run c3_sc7 $W/obj_f4b/tb_cls 1200 +sc=7 +maxms=8000
  run c3_sc8 $W/obj_f4b/tb_cls 900  +sc=8 +maxms=4000
  run c3_sc9 $W/obj_f4b/tb_cls 900  +sc=9 +maxms=4000
  run c3_sc11 $W/obj_f4b/tb_cls 900 +sc=11 +maxms=5000
fi
# 3. the tree's network benches on fix2
for b in net lfull chain; do
  if bld obj_f4_$b tb_$b $RTLF tb/site_net.v tb/tb_$b.v; then
    run tree_$b $W/obj_f4_$b/tb_$b 5400
    rm -rf $W/obj_f4_$b
  fi
done
# 4. the overload run on fix2
if [ -x $W/obj_f4b/tb_cls ]; then
  run c3_ovl $W/obj_f4b/tb_cls 4800 +sc=10 +mode=1 +lam=30000 +dur=15000 +t1lo=100 +t1hi=400 +pexp=150 +pown=0 +loc=8000 +pnet=300 +seed=3 +maxms=60000
  rm -rf $W/obj_f4b
fi
echo "ALLDONE $(date +%T)" >> $P
