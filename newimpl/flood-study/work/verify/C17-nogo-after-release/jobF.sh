#!/bin/bash
# fix B: sweeps, then tb_net
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C17-nogo-after-release
$D/build.sh obj_fixB $D/RTL_fixB.list || exit 1
$D/run.sh obj_fixB fixB_TN.log 3600 +mode=3 +tx0=215500 +nx0=1216000 +step=500 +n=8
rm -rf $D/obj_fixB
cd $F
rm -rf $D/obj_fnet
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_net --Mdir $D/obj_fnet -o tb_net \
   $(cat $D/RTL_fixB.list) tb/site_net.v tb/tb_net.v > $D/vl_fixB_net.log 2>&1 || { echo NET BUILD FAIL; exit 1; }
timeout 3000 $D/obj_fnet/tb_net > $D/fixB_tbnet.log 2>&1
echo "rc=$?" >> $D/fixB_tbnet.log
rm -rf $D/obj_fnet
echo JOBF DONE
