#!/bin/bash
# jobC: hook-gated wait (rtl_hk) and the origin auditor's a+a' (rtl_of), mini_marker only
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C01-watch-late-refusal
cd $F
for v in hk of; do
  $D/build.sh $D/obj_c01r_$v tb_c01r $D/RTL_$v.list tb/site_net.v $D/tb_c01r.v
  tail -1 $D/obj_c01r_$v.vl.log
  for s in 2 3 1; do
    $D/run.sh $D/obj_c01r_$v/tb_c01r $D/r_${v}_s$s.log 1200 +scen=$s
  done
  rm -rf $D/obj_c01r_$v
done
echo jobC done
