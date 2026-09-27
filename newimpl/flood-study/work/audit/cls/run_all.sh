#!/bin/bash
# run_all.sh -- the cls slice's round-2 sims in ONE throttle slot, in order of
# value: snapshot directed (tb_cls3 sc7 sc8 sc9 sc11), fix2 directed (tb_cls2
# sc1-6, tb_cls3 sc7-11), snapshot overload, tree benches on fix2, snapshot
# load r1, fix2 overload.  REAL timers for tb_cls*.  Run as
#   ./sim.sh bash work/audit/cls/run_all.sh     (from the flood directory)
# Progress: all.progress; logs run_<name>.log; builds removed when done.
F=/home/joel/telco/newimpl/build/flood
W=$F/work/audit/cls
cd $F || exit 9
export TMPDIR=$F/tmp
P=$W/all.progress
echo "start $(date +%T)" > $P
RTLS=$(cat work/RTL.list)
RTLF=$(cat $W/RTL_fix2.list)
bld() {   # objdir top args...
  local o=$1 top=$2; shift 2
  local s=$(date +%s)
  verilator --binary --timing -j 2 -Irtl -Wno-fatal "$@" --top-module $top --Mdir $W/$o -o $top \
    > $W/vl_$o.log 2>&1 || { echo "BUILD FAILED $o $(date +%T)" >> $P; return 1; }
  echo "built $o $(( $(date +%s) - s ))s $(date +%T)" >> $P
}
run() {   # name bin timeout args...
  local n=$1 b=$2 t=$3; shift 3
  local s=$(date +%s)
  timeout $t $b "$@" > $W/run_$n.log 2>&1
  echo "rc=$? wall=$(( $(date +%s) - s ))" >> $W/run_$n.log
  echo "$n done $(( $(date +%s) - s ))s $(date +%T) $(grep -E 'checks,' $W/run_$n.log | tail -1)" >> $P
}
# 1. snapshot, tb_cls3 POOL8: directed
if bld obj_c3 tb_cls +define+POOL8 $RTLS tb/site_net.v $W/tb_cls3.v; then
  run c3_sc7  $W/obj_c3/tb_cls 1200 +sc=7 +maxms=8000
  run c3_sc8  $W/obj_c3/tb_cls 900  +sc=8 +maxms=4000
  run c3_sc9  $W/obj_c3/tb_cls 900  +sc=9 +maxms=4000
  run c3_sc11 $W/obj_c3/tb_cls 900  +sc=11 +maxms=5000
fi
# 2. fix2 directed: tb_cls2 (NMON 2) and tb_cls3 (POOL8)
if bld obj_f4a tb_cls $RTLF tb/site_net.v $W/tb_cls2.v; then
  for a in "sc=2" "sc=3" "sc=4" "sc=5" "sc=6" "sc=1 +K=8"; do
    n=f4_c2_$(echo $a | tr -d "+= "); run $n $W/obj_f4a/tb_cls 1500 +$a
  done
  rm -rf $W/obj_f4a
fi
if bld obj_f4b tb_cls +define+POOL8 $RTLF tb/site_net.v $W/tb_cls3.v; then
  run f4_c3_sc7  $W/obj_f4b/tb_cls 1200 +sc=7 +maxms=8000
  run f4_c3_sc8  $W/obj_f4b/tb_cls 900  +sc=8 +maxms=4000
  run f4_c3_sc9  $W/obj_f4b/tb_cls 900  +sc=9 +maxms=4000
  run f4_c3_sc11 $W/obj_f4b/tb_cls 900  +sc=11 +maxms=5000
fi
# 3. snapshot overload
[ -x $W/obj_c3/tb_cls ] && run c3_ovl $W/obj_c3/tb_cls 4800 +sc=10 +mode=1 +lam=30000 +dur=15000 +t1lo=100 +t1hi=400 +pexp=150 +pown=0 +loc=8000 +pnet=300 +seed=3 +maxms=60000
# 4. the tree's network benches on fix2
for b in net lfull chain; do
  if bld obj_f4_$b tb_$b $RTLF tb/site_net.v tb/tb_$b.v; then
    run f4_tree_$b $W/obj_f4_$b/tb_$b 5400
    rm -rf $W/obj_f4_$b
  fi
done
# 5. snapshot load r1
[ -x $W/obj_c3/tb_cls ] && run c3_r1 $W/obj_c3/tb_cls 4800 +sc=10 +mode=0 +lam=5000 +dur=30000 +t1lo=60 +t1hi=700 +pexp=500 +pown=100 +loc=8000 +pnet=300 +seed=1 +maxms=80000
rm -rf $W/obj_c3
# 6. fix2 overload
[ -x $W/obj_f4b/tb_cls ] && run f4_c3_ovl $W/obj_f4b/tb_cls 4800 +sc=10 +mode=1 +lam=30000 +dur=15000 +t1lo=100 +t1hi=400 +pexp=150 +pown=0 +loc=8000 +pnet=300 +seed=3 +maxms=60000
rm -rf $W/obj_f4b
echo "ALLDONE $(date +%T)" >> $P
