#!/bin/bash
# build tb_fx (snapshot RTL) and run sc3, sc7 (late far M); delete obj
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C13-leg-glare
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_fx --Mdir $V/obj_fx -o tb_fx $(cat work/RTL.list) $V/site_fx.v $V/tb_fx.v > $V/vl_fx.log 2>&1; echo "BUILD rc=$?" >> $V/vl_fx.log
for a in "+sc=3:run_fx_sc3" "+sc=7 +dly=300:run_fx_sc7_d300" "+sc=7 +dly=1200:run_fx_sc7_d1200"; do
  args=${a%%:*}; log=${a##*:}
  s=$(date +%s); timeout 900 $V/obj_fx/tb_fx $args > $V/$log.log 2>&1; echo "rc=$? secs=$(( $(date +%s) - s ))" >> $V/$log.log
done
rm -rf $V/obj_fx
