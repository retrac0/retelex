#!/bin/bash
# fixes: tb_late on rtl_fix (F1 gate + F2) and on the monclaim auditor's fix; tb_pchain sc1 and tb_net on rtl_fix
set -u
F=/home/joel/telco/newimpl/build/flood
V=$F/work/verify/C18-late-claims
D="31000 32000 32500 33000 33500 34000 35000"
$V/job_late.sh fix $V/RTL_fix.list $D
$V/job_late.sh mc $F/work/audit/monclaim/RTL_fix.list $D
cd $F
export TMPDIR=$F/tmp
O=$V/obj_pchain_fix
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_pchain --Mdir $O -o tb_pchain $(cat $V/RTL_fix.list) tb/site_net.v work/verify/C13-leg-glare/tb_pchain.v > $V/vl_pchain_fix.log 2>&1; echo "BUILD rc=$?" >> $V/vl_pchain_fix.log
s=$(date +%s); timeout 2400 $O/tb_pchain +sc=1 +trace > $V/run_pchain_fix.log 2>&1; echo "rc=$? secs=$(( $(date +%s) - s ))" >> $V/run_pchain_fix.log
echo "[pchain] done $(date +%T) $(tail -2 $V/run_pchain_fix.log | head -1)"
rm -rf $O
O=$V/obj_net_fix
timeout 1800 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_net --Mdir $O -o tb_net $(cat $V/RTL_fix.list) tb/site_net.v tb/tb_net.v > $V/vl_net_fix.log 2>&1; echo "BUILD rc=$?" >> $V/vl_net_fix.log
s=$(date +%s); timeout 3000 $O/tb_net > $V/run_net_fix.log 2>&1; echo "rc=$? secs=$(( $(date +%s) - s ))" >> $V/run_net_fix.log
echo "[net] done $(date +%T) $(grep -E 'checks' $V/run_net_fix.log | tail -1)"
rm -rf $O
