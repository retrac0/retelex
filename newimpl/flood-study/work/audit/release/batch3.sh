#!/bin/bash
# batch3.sh -- the release slice's runs after run A, trimmed to the machine's
# speed (~8 ms of simulated time a second with three sites).  One sim.sh slot.
set -u
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_rel"
build() {   # name, file list, extra flags
    local s=$(date +%s)
    $VL --Mdir $W/obj_$1 -o tb_rel $(cat $2) tb/site_net.v $W/tb_rc.v $3 > $W/vl_$1.log 2>&1
    local rc=$?
    echo "build=$rc secs=$(( $(date +%s) - s ))" >> $W/vl_$1.log
    return $rc
}
run() {     # obj, log name, wall timeout, plusargs...
    local o=$1 n=$2 t=$3; shift 3
    local s=$(date +%s)
    timeout $t $W/obj_$o/tb_rel "$@" > $W/run_$n.log 2>&1
    echo "rc=$? secs=$(( $(date +%s) - s ))" >> $W/run_$n.log
    echo $n >> $W/batch3.status
}
echo start > $W/batch3.status

# the owner's no-digit timer against the far caller's hang-up (old build)
run base D_nodig 7200 +fams=1024 +d0us=1213500 +stus=500 +n=10 +wd=100

# the fix: a timer's BUSY write only on a hook that stood at its last sample
build fix2 $W/RTL_fix.list "" && {
    run fix2 FIX8  5400 +fams=256  +d0us=217250  +stus=250 +n=7 +wd=100
    run fix2 FIX10 5400 +fams=1024 +d0us=1214000 +stus=500 +n=7 +wd=100
}

# the call-setup sweep, trimmed: 1.13 ms steps walk the sub-ms phase
build base2 work/RTL.list "" && {
    run base2 B1 5400 +fams=2  +d0us=-1000 +stus=1130 +n=11 +wd=100
    run base2 B3 5400 +fams=8  +d0us=-1000 +stus=1130 +n=9  +wd=100
    run base2 B4 5400 +fams=16 +d0us=-2000 +stus=1130 +n=8  +wd=100
    run base2 B5 5400 +fams=32 +d0us=-3000 +stus=1130 +n=8  +wd=100
    run base2 B2 5400 +fams=4  +d0us=0     +stus=1130 +n=6  +wd=100
    run base2 B6 5400 +fams=64 +d0us=0     +stus=4900 +n=6  +wd=100
}

# re-seizure inside the far end's release: A's ports release 16 ms, X's 32
build rcfast work/RTL.list "+define+TRELA=16" && \
    run rcfast H_rcfast 5400 +fams=2048 +d0us=-3000 +stus=1000 +n=11 +wd=100
run base2 H_rceq 5400 +fams=2048 +d0us=-3000 +stus=3000 +n=4 +wd=100

# the chain transit (one leg), and the coarse whole-call sweep
run base2 F3_stub0 5400 +fams=8 +stub=0 +d0us=-1000 +stus=1130 +n=9 +wd=100
run base2 F2_stub0 5400 +fams=4 +stub=0 +d0us=0 +stus=1130 +n=6 +wd=100
run base2 E_coarse 5400 +fams=1 +d0us=3000 +stus=12700 +n=40 +wd=100
echo ALLDONE >> $W/batch3.status
