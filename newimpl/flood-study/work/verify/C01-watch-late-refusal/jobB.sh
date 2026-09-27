#!/bin/bash
# jobB: the cableb knob copy (knobs off == snapshot): +fixwatch and +fixatt
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C01-watch-late-refusal
cd $F
$D/build.sh $D/obj_c01r_k tb_c01r work/audit/cableb/RTL_k.list tb/site_net.v $D/tb_c01r.v
tail -1 $D/obj_c01r_k.vl.log
$D/run.sh $D/obj_c01r_k/tb_c01r $D/r_fw_s2.log 1200 +scen=2 +fixwatch
$D/run.sh $D/obj_c01r_k/tb_c01r $D/r_fw_s1.log 1200 +scen=1 +fixwatch
$D/run.sh $D/obj_c01r_k/tb_c01r $D/r_fa_s2.log 1200 +scen=2 +fixatt
rm -rf $D/obj_c01r_k
echo jobB done
