#!/bin/bash
# C10 verify: run tb_fx; $1 = tag, $2 = log name, rest = plusargs
set -u
F=/home/joel/telco/newimpl/build/flood
cd $F
D=work/verify/C10-resolver-muted-incoming
tag=$1; log=$2; shift 2
s=$(date +%s)
timeout 1800 $D/obj_fx_$tag/tb_fx "$@" > $D/$log 2>&1; echo "rc=$? secs=$(( $(date +%s) - s ))" >> $D/$log
