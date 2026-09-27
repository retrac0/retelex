#!/bin/bash
# batch4.sh -- successor's job 1: tb_rc.v at scale 8, the call-setup and
# connect families, one sim.sh slot, runs one after another.
#   ./sim.sh bash work/audit/release/batch4.sh
set -u
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
ST=$W/batch4.status
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_rel"
build() {   # name, file list, extra flags, bench
    local s=$(date +%s)
    $VL --Mdir $W/obj_$1 -o tb_rel $(cat $2) tb/site_net.v $W/$4 $3 > $W/vl_$1.log 2>&1
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
    echo "$n done $(date +%H:%M) $(grep -c ' LEAK ' $W/run_$n.log) leaks" >> $ST
}
echo "start $(date +%H:%M)" > $ST
# lint the benches the later jobs will build (seconds each)
for v in "tb_rc.v:" "tb_rc.v:+define+SCALE1" "tb_rc.v:+define+SCALE1 +define+NODIGR=3000 +define+TRELX=9'd205"; do
    f=${v%%:*}; d=${v#*:}
    verilator --lint-only -Wno-fatal -Wno-lint -Wno-style --timing -Irtl --top-module tb_rel $(cat work/RTL.list) tb/site_net.v $W/$f $d > $W/lint_last.log 2>&1
    echo "lint $f [$d] rc=$? errors=$(grep -c '%Error' $W/lint_last.log)" >> $ST
    grep '%Error' $W/lint_last.log | head -5 >> $ST
done
build s8 work/RTL.list "" tb_j1.v || { rm -rf $W/obj_s8; build s8 work/RTL.list "" tb_rc.v.orig || exit 1; }
run s8 S10 7200 +fams=1024 +d0us=1212500 +stus=430 +n=16 +wd=100
build x26 work/RTL.list "+define+TRELX=9'd26" tb_j1.v && run x26 S12x26 5400 +fams=4096 +d0us=-6000 +stus=1130 +n=17 +wd=100
rm -rf $W/obj_x26
run s8 S12eq 5400 +fams=4096 +d0us=-6000 +stus=2260 +n=9 +wd=100
run s8 S3  3600 +fams=8    +d0us=-2000 +stus=1130 +n=13 +wd=100
run s8 S4  3600 +fams=16   +d0us=-3000 +stus=1130 +n=11 +wd=100
run s8 S7  3600 +fams=128  +d0us=-2000 +stus=1130 +n=10 +wd=100
run s8 S2  3600 +fams=4    +d0us=-1000 +stus=1130 +n=9  +wd=100
run s8 S1  3600 +fams=2    +d0us=-2000 +stus=1130 +n=14 +wd=100
run s8 S5  3600 +fams=32   +d0us=-4000 +stus=1130 +n=11 +wd=100
run s8 S6  3600 +fams=64   +d0us=0     +stus=4900 +n=6  +wd=100
run s8 S9  3600 +fams=512  +d0us=588000 +stus=500 +n=14 +wd=100
echo "ALLDONE $(date +%H:%M)" >> $ST
# the next job, if one has been written by then, in this same slot
[ -f $W/next1.sh ] && { echo "next1 $(date +%H:%M)" >> $ST; bash $W/next1.sh; }
