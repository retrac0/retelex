#!/bin/bash
# batch.sh -- the release slice's runs, in ONE sim.sh slot, one after another.
# Run from /home/joel/telco/newimpl/build/flood as:  ./sim.sh bash work/audit/release/batch.sh
set -u
cd /home/joel/telco/newimpl/build/flood
W=work/audit/release
VL="verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_rel"

build() {   # name, file list, extra flags
    local s=$(date +%s)
    $VL --Mdir $W/obj_$1 -o tb_rel $(cat $2) tb/site_net.v $W/tb_rel.v $3 > $W/vl_$1.log 2>&1
    local rc=$?
    echo "build=$rc secs=$(( $(date +%s) - s ))" >> $W/vl_$1.log
    return $rc
}
run() {     # obj, log name, wall timeout, plusargs...
    local o=$1 n=$2 t=$3; shift 3
    local s=$(date +%s)
    timeout $t $W/obj_$o/tb_rel "$@" > $W/run_$n.log 2>&1
    echo "rc=$? secs=$(( $(date +%s) - s ))" >> $W/run_$n.log
}

build base work/RTL.list "" || { echo BUILD-FAILED > $W/batch.status; exit 1; }
echo built > $W/batch.status
run base smoke 900 +fams=4 +nmax=2 +wd=5
if ! grep -q "REF talk path A20 <-> B21: ok" $W/run_smoke.log || [ "$(grep -c '^T fam=2' $W/run_smoke.log)" -lt 2 ]; then
    echo SMOKE-FAILED >> $W/batch.status; exit 2
fi
echo smoke-ok >> $W/batch.status

run base A_timers 5400 +fams=768 +wd=200          ; echo A >> $W/batch.status
run base B_setup  5400 +fams=30  +wd=200          ; echo B >> $W/batch.status
run base D_nodig  5400 +fams=1024 +wd=200         ; echo D >> $W/batch.status
run base C_called 5400 +fams=224 +wd=200          ; echo C >> $W/batch.status

build fix $W/RTL_fix.list "" && {
    run fix FIX_timers 5400 +fams=1792 +wd=200    ; echo FIX >> $W/batch.status
}

run base E_coarse 5400 +fams=1 +wd=200            ; echo E >> $W/batch.status
run base F_stub0  5400 +fams=12 +stub=0 +wd=200   ; echo F >> $W/batch.status

build trel28 work/RTL.list "+define+TRELP=28" && {
    run trel28 G_trel28 5400 +fams=256 +d0us=209000 +stus=500 +n=28 +wd=200 ; echo G >> $W/batch.status
}
echo ALLDONE >> $W/batch.status
