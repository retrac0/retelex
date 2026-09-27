#!/bin/bash
# C10 verify: build tb_fx (work/audit/fwd) on a given RTL list; $1 = tag, $2 = RTL list
set -u
F=/home/joel/telco/newimpl/build/flood
cd $F
D=work/verify/C10-resolver-muted-incoming
export TMPDIR=$F/tmp
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal"
$VL --top-module tb_fx --Mdir $D/obj_fx_$1 -o tb_fx work/audit/fwd/site_fx.v work/audit/fwd/tb_fx.v $(cat $2) > $D/vl_fx_$1.log 2>&1; echo "build rc=$?" >> $D/vl_fx_$1.log
