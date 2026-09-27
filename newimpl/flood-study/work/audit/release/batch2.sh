#!/bin/bash
# batch2.sh -- family 11 (re-seizure of a trunk inside the far end's release,
# ports' T_REL unequal), and its control.  One sim.sh slot.
set -u
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_rel"
build() {   # name, extra flags
    local s=$(date +%s)
    $VL --Mdir $W/obj_$1 -o tb_rel $(cat work/RTL.list) tb/site_net.v $W/tb_rc.v $2 > $W/vl_$1.log 2>&1
    local rc=$?
    echo "build=$rc secs=$(( $(date +%s) - s ))" >> $W/vl_$1.log
    return $rc
}
run() {
    local o=$1 n=$2 t=$3; shift 3
    local s=$(date +%s)
    timeout $t $W/obj_$o/tb_rel "$@" > $W/run_$n.log 2>&1
    echo "rc=$? secs=$(( $(date +%s) - s ))" >> $W/run_$n.log
}
build rcfast "+define+TRELA=16" && run rcfast H_rcfast 5400 +fams=2048 +wd=200
echo H >> $W/batch2.status
build rceq "" && run rceq H_rceq 5400 +fams=2048 +wd=200
echo ALLDONE >> $W/batch2.status
