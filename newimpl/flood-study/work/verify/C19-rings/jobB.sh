#!/bin/bash
# C19 job B: control -- the same calls on the both-ends-strapped ring (hub study's obj_ringst binary, snapshot RTL).
F=/home/joel/telco/newimpl/build/flood; cd $F || exit 1
D=work/verify/C19-rings
export TMPDIR=$F/tmp
P="+dest_mode=4 +hold_ms=200 +hold_fixed=1 +ans_ms=100 +trace=1 +seed=1 +pairs=B20D21,B22A21,D22B23,C23D24 +pair_gap_ms=1500 +dur_ms=12000 +grace_ms=1000 +drain_ms=800"
t=$SECONDS
timeout 7200 work/load/hub/obj_ringst/tb_hub $P > $D/run_r2_bothstrap.log 2>&1
echo "run r2 rc=$? wall_s=$((SECONDS-t))" >> $D/jobB.out
