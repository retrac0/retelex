#!/bin/bash
# next3.sh -- job 4, more real-timer families on next2's obj_sr (SCALE1, NODIGR 3000)
set -u
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
ST=$W/next3.status
run() {     # obj, log name, wall timeout, plusargs...
    local o=$1 n=$2 t=$3; shift 3
    local s=$(date +%s)
    timeout $t $W/obj_$o/tb_rel "$@" > $W/run_$n.log 2>&1
    echo "rc=$? secs=$(( $(date +%s) - s ))" >> $W/run_$n.log
    echo "$n done $(date +%H:%M) $(grep -c ' LEAK ' $W/run_$n.log) leaks $(grep -c WRONG-NUMBER $W/run_$n.log) wrong" >> $ST
}
echo "start $(date +%H:%M)" > $ST
if [ ! -x $W/obj_sr/tb_rel ]; then
    verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_rel --Mdir $W/obj_sr -o tb_rel \
        $(cat work/RTL.list) tb/site_net.v $W/tb_j3.v +define+SCALE1 +define+NODIGR=3000 > $W/vl_sr3.log 2>&1
    echo "build sr rc=$?" >> $ST
fi
# C17 at real timers: T_CLAIM 2000 - T_REL 256 after A's b
run sr R8 7200 +fams=256 +d0us=1742000 +stus=400 +n=10 +lim=2000 +wd=400
# the claim and the connect at real timers (T_ARM 16, SETTLE 32, watch 18)
run sr R3 7200 +fams=8   +d0us=-4000 +stus=2260 +n=16 +lim=2000 +wd=400
run sr R4 7200 +fams=16  +d0us=-4000 +stus=2900 +n=16 +lim=2000 +wd=400
run sr R7 7200 +fams=128 +d0us=-4000 +stus=2900 +n=12 +lim=2000 +wd=400
rm -rf $W/obj_sr
echo "ALLDONE $(date +%H:%M)" >> $ST
