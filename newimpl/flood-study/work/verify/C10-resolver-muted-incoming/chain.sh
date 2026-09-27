#!/bin/bash
# wait for a tb_fx build ($1 = tag), then run sc2 var0 and var1 in one sim.sh slot, then delete the obj dir
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C10-resolver-muted-incoming
tag=$1
until grep -q "build rc" $D/vl_fx_$tag.log 2>/dev/null; do sleep 20; done
if ! grep -q "build rc=0" $D/vl_fx_$tag.log; then echo "build failed $tag"; exit 1; fi
cd $F
./sim.sh bash -c "$D/runFx.sh $tag run_${tag}_sc2var0.log +sc=2 +var=0; $D/runFx.sh $tag run_${tag}_sc2var1.log +sc=2 +var=1"
rm -rf $D/obj_fx_$tag
echo "done $tag"
