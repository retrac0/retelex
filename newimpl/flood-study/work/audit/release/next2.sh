#!/bin/bash
# next2.sh -- job 3, real timers (+define+SCALE1), chained after next1.sh.
# NODIGR=3000 shortens only the no-digit timer (family 10's race is at its
# expiry, whatever its length).  Builds from tb_j3.v.
set -u
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
ST=$W/next2.status
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_rel"
build() {   # name, file list, extra flags
    local s=$(date +%s)
    $VL --Mdir $W/obj_$1 -o tb_rel $(cat $2) tb/site_net.v $W/tb_j3.v $3 > $W/vl_$1.log 2>&1
    local rc=$?
    echo "build=$rc secs=$(( $(date +%s) - s ))" >> $W/vl_$1.log
    echo "build $1 rc=$rc" >> $ST
    return $rc
}
run() {     # obj, log name, wall timeout, plusargs...
    local o=$1 n=$2 t=$3; shift 3
    local s=$(date +%s)
    timeout $t $W/obj_$o/tb_rel "$@" > $W/run_$n.log 2>&1
    echo "rc=$? secs=$(( $(date +%s) - s ))" >> $W/run_$n.log
    echo "$n done $(date +%H:%M) $(grep -c ' LEAK ' $W/run_$n.log) leaks $(grep -c WRONG-NUMBER $W/run_$n.log) wrong" >> $ST
}
echo "start $(date +%H:%M)" > $ST
build rx work/RTL.list "+define+SCALE1 +define+TRELX=9'd205" && {
    run rx R12x205 9000 +fams=4096 +d0us=60000 +stus=9130 +n=8 +lim=2000 +wd=400
}
rm -rf $W/obj_rx
build sr work/RTL.list "+define+SCALE1 +define+NODIGR=3000" && {
    # R10: S10 leaked at d = NODIG - T_REL - (1..4) ms after att_ack
    run sr R10 9000 +fams=1024 +d0us=2739000 +stus=600 +n=8 +lim=2000 +wd=400
    run sr R2  7200 +fams=4    +d0us=-8000 +stus=1130 +n=26 +lim=2000 +wd=400
    run sr R1  7200 +fams=2    +d0us=-4000 +stus=2260 +n=16 +lim=2000 +wd=400
}
echo "ALLDONE $(date +%H:%M)" >> $ST
[ -f $W/next3.sh ] && { echo "next3 $(date +%H:%M)" >> $ST; bash $W/next3.sh; }
