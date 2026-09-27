#!/bin/bash
# C19 job C (one): tb_ring4 (4-ring, baseband, s8) -- the double-claim race at the origin.
F=/home/joel/telco/newimpl/build/flood; cd $F || exit 1
D=work/verify/C19-rings
export TMPDIR=$F/tmp
t=$SECONDS
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal  --top-module tb_ring4 --Mdir $D/obj_r4one -o tb_ring4 \
   $(cat work/RTL.list) tb/site_net.v $D/tb_ring4.v > $D/vl_r4one.log 2>&1
echo "build obj_r4one rc=$? wall_s=$((SECONDS-t))" >> $D/jobC_one.out
[ -x $D/obj_r4one/tb_ring4 ] || exit 2
find $D/obj_r4one -type f ! -name tb_ring4 -delete
i=0
while read dx dy dz dv dd; do
  i=$((i+1)); t=$SECONDS
  timeout 1500 $D/obj_r4one/tb_ring4 +b=4 +dx=$dx +dy=$dy +dz=$dz +dv=$dv +dd=$dd > $D/run_r4one_b4_p$i.log 2>&1
  echo "run p$i (one b=4 $dx $dy $dz $dv $dd) rc=$? wall_s=$((SECONDS-t)) $(grep OUTCOME $D/run_r4one_b4_p$i.log)" >> $D/jobC_one.out
done <<'PH'
0 0 0 0 0
500 130 870 310 250
910 450 60 720 640
230 780 390 950 90
670 20 540 180 830
120 610 290 460 370
PH
rm -rf $D/obj_r4one
