#!/bin/bash
# gate.sh <job>: wait (outside any slot) until jobA's snapshot scen 2 run shows the
# claim landing in B's WATCH, then take a slot for <job>.
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C01-watch-late-refusal
while ! grep -q "rc=" $D/r_snap_s2.log 2>/dev/null; do
  grep -q "build rc=[1-9]" $D/obj_c01r_snap.vl.log 2>/dev/null && { echo "snap build failed"; exit 1; }
  sleep 20
done
grep -q "ok    and B's marker is in S_WATCH" $D/r_snap_s2.log || { echo "alignment failed"; exit 1; }
cd $F && ./sim.sh $D/$1
