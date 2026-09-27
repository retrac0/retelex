#!/bin/bash
# C10 verify: tb_fx with the LTU's MUTE_BLK not ORed into BUSY (alternative fix, bench-level jumper), snapshot RTL
set -u
F=/home/joel/telco/newimpl/build/flood
cd $F
D=work/verify/C10-resolver-muted-incoming
export TMPDIR=$F/tmp
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal"
$VL --top-module tb_fx --Mdir $D/obj_fx_nm -o tb_fx $D/site_fx_nomute.v work/audit/fwd/tb_fx.v $(cat work/RTL.list) > $D/vl_fx_nm.log 2>&1; echo "build rc=$?" >> $D/vl_fx_nm.log
