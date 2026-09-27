#!/bin/bash
# jobD: tb_net on the origin a+a (rtl_of)
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C01-watch-late-refusal
cd $F
$D/build.sh $D/obj_net_of tb_net $D/RTL_of.list tb/site_net.v tb/tb_net.v
tail -1 $D/obj_net_of.vl.log
$D/run.sh $D/obj_net_of/tb_net $D/net_of.log 2400
rm -rf $D/obj_net_of
echo jobE done
