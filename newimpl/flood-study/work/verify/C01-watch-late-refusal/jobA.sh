#!/bin/bash
# jobA: snapshot runs.  tb_c01r (real timers) first, then the auditor's tb_attw.
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C01-watch-late-refusal
cd $F
$D/build.sh $D/obj_c01r_snap tb_c01r work/RTL.list tb/site_net.v $D/tb_c01r.v
tail -1 $D/obj_c01r_snap.vl.log
$D/run.sh $D/obj_c01r_snap/tb_c01r $D/r_snap_s2.log 1200 +scen=2
$D/run.sh $D/obj_c01r_snap/tb_c01r $D/r_snap_s1.log 1200 +scen=1
$D/run.sh $D/obj_c01r_snap/tb_c01r $D/r_snap_s3.log 1200 +scen=3
rm -rf $D/obj_c01r_snap
$D/build.sh $D/obj_attw tb_attw work/RTL.list tb/site_net.v work/audit/cableb/tb_attw.v
tail -1 $D/obj_attw.vl.log
$D/run.sh $D/obj_attw/tb_attw $D/attw_snap_scen2.log 600 +scen=2
$D/run.sh $D/obj_attw/tb_attw $D/attw_snap_scen1.log 600 +scen=1
rm -rf $D/obj_attw
echo jobA done
