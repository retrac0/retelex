#!/bin/bash
# usage: run_bin.sh <binary> <log> <timeout> [plusargs...]
F=/home/joel/telco/newimpl/build/flood
bin=$1; log=$2; to=$3; shift 3
cd $F
t0=$(date +%s)
timeout $to $bin "$@" > $log 2>&1
echo "rc=$? secs=$(( $(date +%s)-t0 ))" >> $log
