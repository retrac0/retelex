#!/bin/bash
# C10 verify: one slot = build tb_fx ($1 = snap | nm), run sc2 var0 and var1, delete obj
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C10-resolver-muted-incoming
cd $F
tag=$1
if [ $tag = nm ]; then bash $D/jobFxNm.sh; else bash $D/jobFx.sh snap work/RTL.list; fi
if grep -q "build rc=0" $D/vl_fx_$tag.log; then
  $D/runFx.sh $tag run_${tag}_sc2var0.log +sc=2 +var=0
  $D/runFx.sh $tag run_${tag}_sc2var1.log +sc=2 +var=1
fi
rm -rf $D/obj_fx_$tag
