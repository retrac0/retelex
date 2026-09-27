#!/bin/bash
# C19 job D: tb_ring4r (REAL timers), one-end strap, X20 -> Z21, the p5 phase set (and p1 as control).
F=/home/joel/telco/newimpl/build/flood; cd $F || exit 1
D=work/verify/C19-rings
export TMPDIR=$F/tmp
t=$SECONDS
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_ring4r --Mdir $D/obj_r4r -o tb_ring4r \
   $(cat work/RTL.list) tb/site_net.v $D/tb_ring4r.v > $D/vl_r4r.log 2>&1
echo "build obj_r4r rc=$? wall_s=$((SECONDS-t))" >> $D/jobD.out
[ -x $D/obj_r4r/tb_ring4r ] || exit 2
find $D/obj_r4r -type f ! -name tb_ring4r -delete
i=0
while read nm dx dy dz dv dd; do
  t=$SECONDS
  timeout 2400 $D/obj_r4r/tb_ring4r +b=4 +dx=$dx +dy=$dy +dz=$dz +dv=$dv +dd=$dd > $D/run_r4real_b4_$nm.log 2>&1
  echo "run $nm (REAL one b=4 $dx $dy $dz $dv $dd) rc=$? wall_s=$((SECONDS-t)) $(grep OUTCOME $D/run_r4real_b4_$nm.log)" >> $D/jobD.out
done <<'PH'
p5 670 20 540 180 830
p1 0 0 0 0 0
PH
rm -rf $D/obj_r4r
