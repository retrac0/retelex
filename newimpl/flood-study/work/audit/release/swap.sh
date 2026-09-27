#!/bin/bash
# swap.sh -- once batch 1's run A is done, stop batch 1 (pid given) and its
# next run, then take a slot for batch 3.
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
BPID=$1
until grep -qx "A" $W/batch.status 2>/dev/null; do sleep 2; done
kill $BPID 2>/dev/null
sleep 0.3
for p in $(pgrep -P $BPID) ; do pkill -P $p; kill $p; done 2>/dev/null
# the run B binary, if it started
for p in $(pgrep -f "obj_base/tb_rel \+fams=30"); do kill $p; done 2>/dev/null
echo "swapped at $(date)" >> $W/batch.status
./sim.sh bash $W/batch3.sh > $W/batch3.out 2>&1
echo "exit=$?" >> $W/batch3.out
