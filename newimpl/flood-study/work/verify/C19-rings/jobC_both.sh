#!/bin/bash
# C19 job C (both): tb_ring4 (4-ring, baseband, s8) -- the double-claim race at the origin.
F=/home/joel/telco/newimpl/build/flood; cd $F || exit 1
D=work/verify/C19-rings
export TMPDIR=$F/tmp
t=$SECONDS
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal +define+BOTH --top-module tb_ring4 --Mdir $D/obj_r4both -o tb_ring4 \
   $(cat work/RTL.list) tb/site_net.v $D/tb_ring4.v > $D/vl_r4both.log 2>&1
echo "build obj_r4both rc=$? wall_s=$((SECONDS-t))" >> $D/jobC_both.out
[ -x $D/obj_r4both/tb_ring4 ] || exit 2
find $D/obj_r4both -type f ! -name tb_ring4 -delete
i=0
while read dx dy dz dv dd; do
  i=$((i+1)); t=$SECONDS
  timeout 1500 $D/obj_r4both/tb_ring4 +b=3 +dx=$dx +dy=$dy +dz=$dz +dv=$dv +dd=$dd > $D/run_r4both_b3_p$i.log 2>&1
  echo "run p$i (both b=3 $dx $dy $dz $dv $dd) rc=$? wall_s=$((SECONDS-t)) $(grep OUTCOME $D/run_r4both_b3_p$i.log)" >> $D/jobC_both.out
done <<'PH'
0 0 0 0 0
500 130 870 310 250
910 450 60 720 640
230 780 390 950 90
670 20 540 180 830
120 610 290 460 370
840 330 710 50 560
360 900 150 620 10
50 470 980 270 710
760 240 430 810 480
290 560 20 390 940
980 80 650 530 200
PH
rm -rf $D/obj_r4both
