#!/bin/bash
# step <tag> <top> <rtl.list> <timeout> "<extra verilator args>" "<plusargs>" <tb files...>
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C11-claimed-trunk-loss
cd $F
step() {
  local tag=$1 top=$2 list=$3 to=$4 vargs=$5 pargs=$6; shift 6
  grep -q "^$tag start" $D/progress.txt && return 0
  echo "$tag start $(date +%T)" >> $D/progress.txt
  mkdir -p $D/obj_$tag
  timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal $vargs --top-module $top --Mdir $D/obj_$tag -o $top $(cat $list) "$@" > $D/obj_$tag.vl.log 2>&1
  local rc=$?
  echo "$tag build rc=$rc $(date +%T)" >> $D/progress.txt
  if [ $rc -eq 0 ]; then
    local t0=$(date +%s)
    timeout $to $D/obj_$tag/$top $pargs > $D/$tag.log 2>&1
    echo "rc=$? secs=$(( $(date +%s)-t0 ))" >> $D/$tag.log
    echo "$tag run $(grep -E 'checks,|TIMEOUT' $D/$tag.log | tail -1) $(tail -1 $D/$tag.log) $(date +%T)" >> $D/progress.txt
  fi
  rm -rf $D/obj_$tag
}
