#!/bin/bash
# C19 job A: one-end strap (L1's E only) ring, s8, directed calls. Build + run + delete obj.
F=/home/joel/telco/newimpl/build/flood; cd $F || exit 1
D=work/verify/C19-rings
export TMPDIR=$F/tmp
t=$SECONDS
if [ ! -x $D/obj_r1/tb_hub ]; then
  timeout 1800 verilator --binary --timing -j 2 -Irtl -I$D -Wno-fatal +define+HUB_RING +define+HUB_STRAP1 \
     --top-module tb_hub --Mdir $D/obj_r1 -o tb_hub $(cat work/RTL.list) tb/site_net.v $D/tb_hub1.sv > $D/vl_r1.log 2>&1
  echo "build obj_r1 rc=$? wall_s=$((SECONDS-t))" >> $D/jobA.out
  [ -x $D/obj_r1/tb_hub ] && find $D/obj_r1 -type f ! -name tb_hub -delete
fi
P="+dest_mode=4 +hold_ms=200 +hold_fixed=1 +ans_ms=100 +trace=1 +seed=1 +pairs=B20D21,B22A21,D22B23,C23D24 +pair_gap_ms=1500 +dur_ms=12000 +grace_ms=1000 +drain_ms=800"
t=$SECONDS
timeout 7200 $D/obj_r1/tb_hub $P > $D/run_r1_onestrap.log 2>&1
echo "run r1 rc=$? wall_s=$((SECONDS-t))" >> $D/jobA.out
rm -rf $D/obj_r1
