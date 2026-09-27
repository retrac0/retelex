#!/bin/bash
# run.sh <objname> <log> <timeout s> plusargs...
set -u
D=/home/joel/telco/newimpl/build/flood/work/verify/C17-nogo-after-release
O=$D/$1; LOG=$D/$2; T=$3; shift 3
cd /home/joel/telco/newimpl/build/flood
timeout $T $O/tb_c17 "$@" > $LOG 2>&1
echo "rc=$?" >> $LOG
