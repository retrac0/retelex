#!/bin/bash
# jobD: tb_net on the hook-gated fix (rtl_hk)
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C01-watch-late-refusal
cd $F
$D/build.sh $D/obj_net_hk tb_net $D/RTL_hk.list tb/site_net.v tb/tb_net.v
tail -1 $D/obj_net_hk.vl.log
$D/run.sh $D/obj_net_hk/tb_net $D/net_hk.log 2400
rm -rf $D/obj_net_hk
echo jobD done
