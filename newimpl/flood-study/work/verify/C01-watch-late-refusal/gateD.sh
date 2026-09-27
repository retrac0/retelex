#!/bin/bash
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C01-watch-late-refusal
while ! grep -q "^rc=" $D/r_hk_s3.log 2>/dev/null; do
  grep -q "alignment failed\|build failed" $D/jobC.out 2>/dev/null && exit 1
  sleep 20
done
grep -q "PASS" $D/r_hk_s2.log && grep -q "PASS" $D/r_hk_s3.log || { echo "hk failed its own bench"; exit 1; }
cd $F && ./sim.sh $D/jobD.sh
