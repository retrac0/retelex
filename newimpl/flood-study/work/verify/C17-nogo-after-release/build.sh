#!/bin/bash
# build.sh <objname> <rtl list file> [extra verilator args...]
set -u
F=/home/joel/telco/newimpl/build/flood
D=$F/work/verify/C17-nogo-after-release
cd $F
O=$D/$1; L=$2; shift 2
rm -rf $O
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_c17 --Mdir $O -o tb_c17 "$@" \
   $(cat $L) tb/site_net.v $D/tb_c17.v > $O.vl.log 2>&1 && echo BUILD OK || { echo BUILD FAIL; tail -30 $O.vl.log; exit 1; }
