#!/bin/bash
# next1.sh -- job 2, run in job 1's slot when job 1 ends (batch4.sh's hook).
# scale 8: the r_hook fix on families 8 and 10; family 12 (rc re-seizure) with
# X's ports 20 % fast and its equal-RC control.  Builds from tb_j2.v.
set -u
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
ST=$W/next1.status
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_rel"
build() {   # name, file list, extra flags
    local s=$(date +%s)
    $VL --Mdir $W/obj_$1 -o tb_rel $(cat $2) tb/site_net.v $W/tb_j2.v $3 > $W/vl_$1.log 2>&1
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
# equal RCs, fine steps where X13 has just released (~ t_h+33): does the cells'
# extra tick of CLR (pulse_rx clear 32 ticks after detection) leave a window?
[ -x $W/obj_s8/tb_rel ] && run s8 S12eqf 5400 +fams=4096 +d0us=7000 +stus=370 +n=12 +wd=100
# the setup families again at finer steps (sub-ms phases), and the whole call
if [ -x $W/obj_s8/tb_rel ]; then
    run s8 S0   5400 +fams=1   +wd=200
    run s8 S4f  5400 +fams=16  +d0us=-3000 +stus=370 +n=33 +wd=100
    run s8 S2f  5400 +fams=4   +d0us=-1000 +stus=370 +n=28 +wd=100
    run s8 S1f  5400 +fams=2   +d0us=-2000 +stus=500 +n=33 +wd=100
    run s8 S7f  5400 +fams=128 +d0us=-2000 +stus=500 +n=23 +wd=100
    run s8 S3f  5400 +fams=8   +d0us=-2000 +stus=370 +n=38 +wd=100
fi
rm -rf $W/obj_s8
# family 11: re-seizure of the trunk inside the far end's release after a
# completed call (A20 and B21 hang up; A21 keys, dials 1 1 2 0 = B20); A's
# ports 20 % fast (26), X and B 32
build a26 work/RTL.list "+define+TRELA=9'd26" && \
    run a26 S11a26 5400 +fams=2048 +d0us=24000 +stus=750 +n=24 +wd=150
rm -rf $W/obj_a26
# C03's fix (b) (work/audit/monclaim/rtl_fix: a cell drops on a break >= ID)
# against family 12's wrong number, X's ports 26 ms
build mcx26 work/audit/monclaim/RTL_fix.list "+define+TRELX=9'd26" && \
    run mcx26 S12x26mc 3600 +fams=4096 +d0us=1910 +stus=1130 +n=5 +wd=100
rm -rf $W/obj_mcx26
# the r_hook fix (mini_marker writes a timer's BUSY only on a hook that stood)
build fix $W/RTL_fix.list "" && {
    run fix FIX10 7200 +fams=1024 +d0us=1213790 +stus=430 +n=10 +wd=100
    run fix FIX8  3600 +fams=256  +d0us=216750  +stus=250 +n=12 +wd=100
}
rm -rf $W/obj_fix
# regressions of the fix: tb_net and tb_chain on RTL_fix.list
for b in net chain; do
    s0=$(date +%s)
    verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_$b --Mdir $W/obj_fx$b -o tb_$b \
        $(cat $W/RTL_fix.list) tb/site_net.v tb/tb_$b.v > $W/vl_fx$b.log 2>&1 && \
    timeout 3600 $W/obj_fx$b/tb_$b > $W/run_fix_$b.log 2>&1
    echo "fix tb_$b rc=$? secs=$(( $(date +%s) - s0 )) $(grep -E 'checks,' $W/run_fix_$b.log)" >> $ST
    rm -rf $W/obj_fx$b
done
echo "ALLDONE $(date +%H:%M)" >> $ST
[ -f $W/next2.sh ] && { echo "next2 $(date +%H:%M)" >> $ST; bash $W/next2.sh; }
