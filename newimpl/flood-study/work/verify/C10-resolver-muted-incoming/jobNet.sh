#!/bin/bash
# C10 verify: tb_net on the fwd auditor's fixed copy (work/audit/fwd/RTL_fix.list)
set -u
F=/home/joel/telco/newimpl/build/flood
cd $F
D=work/verify/C10-resolver-muted-incoming
export TMPDIR=$F/tmp
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal"
echo "start $(date +%T)"
$VL --top-module tb_net --Mdir $D/obj_net_fix -o tb_net tb/site_net.v tb/tb_net.v $(cat work/audit/fwd/RTL_fix.list) > $D/vl_net_fix.log 2>&1; echo "build rc=$?" >> $D/vl_net_fix.log
timeout 2700 $D/obj_net_fix/tb_net > $D/run_net_fix.log 2>&1; echo "rc=$?" >> $D/run_net_fix.log
rm -rf $D/obj_net_fix
echo "end $(date +%T)"
