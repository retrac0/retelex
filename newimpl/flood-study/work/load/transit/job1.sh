#!/bin/bash
# job1.sh -- the transit study's whole batch, ONE sim.sh slot, every step in turn.
# Run from /home/joel/telco/newimpl/build/flood as:  ./sim.sh bash work/load/transit/job1.sh
# Each step appends a line to work/load/transit/job1.progress (start, end, rc, wall s).
set -u
F=/home/joel/telco/newimpl/build/flood
cd $F
T=work/load/transit
P=$T/job1.progress
RTL=$(cat work/RTL.list)
step() {   # step NAME TIMEOUT_S CMD...
    local name=$1 to=$2; shift 2
    echo "$(date +%T) START $name" >> $P
    SECONDS=0
    timeout $to "$@"
    local rc=$?
    echo "$(date +%T) END $name rc=$rc wall_s=$SECONDS" >> $P
    return $rc
}
build() {  # build NAME DEFINES...
    local name=$1; shift
    step build_$name 2400 bash -c "verilator --binary --timing -j 2 -Irtl -I$T -Wno-fatal $* --top-module tb_tr3 --Mdir $T/obj_$name -o tb_tr3 $RTL tb/site_net.v $T/tb_tr3.sv > $T/vl_$name.log 2>&1"
}
run() {    # run OBJ LOGNAME TIMEOUT_S PLUSARGS...
    local obj=$1 name=$2 to=$3; shift 3
    step $name $to bash -c "$T/obj_$obj/tb_tr3 $* > $T/$name.log 2>&1"
}
alive() {  # a run's log has the probe's end block
    grep -q '^TPSUM' $T/$1.log
}

echo "$(date +%T) JOB1 begin $(hostname) load $(cut -d' ' -f1-3 /proc/loadavg)" >> $P

# ---- scale 8, NMON = NRES = 2 --------------------------------------------------------------
build s8 || { echo "build s8 failed" >> $P; exit 1; }
# T1: uniform mix (b), heavy
run s8 t1_unif_heavy 7200 +seed=5 +dur_ms=15000 +idle_ms=30000 +pnet=600 +prog_ms=1000
alive t1_unif_heavy || { echo "T1 has no TPSUM: stop" >> $P; exit 2; }
# T3: end to end (a), heavy
run s8 t3_e2e_heavy 7200 +seed=7 +dur_ms=20000 +idle_ms=40000 +dest_mode=5 +orig_x=5 +pnet=1000 +prog_ms=2000
# T4: crossing floods (d), scale 8: A21 -> C22 and C21 -> A22 lift within 0-30 ms, every 1.4 s
run s8 t4_cross_s8 7200 +seed=9 +dur_ms=21000 +dest_mode=4 +pairs=A21C22,C21A22 +pair_gap_ms=1 +pair_per_ms=1400 +pair_jit_ms=30 +prog_ms=3000

# ---- real timers ------------------------------------------------------------------------------
build s1 +define+SCALE1 || echo "build s1 failed" >> $P
# T9: crossing floods at real timers, every 7 s
[ -x $T/obj_s1/tb_tr3 ] && run s1 t9_cross_s1 14400 +seed=9 +dur_ms=63000 +drain_ms=10000 +dest_mode=4 +pairs=A21C22,C21A22 +pair_gap_ms=1 +pair_per_ms=7000 +pair_jit_ms=30 +prog_ms=7000

# ---- one resolver: the mechanism of C14 on the chain -----------------------------------------
build n1 +define+LD_NRES=1 || echo "build n1 failed" >> $P
[ -x $T/obj_n1/tb_tr3 ] && run n1 t8_e2e_heavy_nres1 7200 +seed=7 +dur_ms=20000 +idle_ms=40000 +dest_mode=5 +orig_x=5 +pnet=1000 +prog_ms=2000

# ---- more scale-8 load points -----------------------------------------------------------------
# T2: end to end (a), medium
run s8 t2_e2e_med 7200 +seed=3 +dur_ms=24000 +idle_ms=90000 +dest_mode=5 +orig_x=5 +pnet=1000 +prog_ms=3000
# T5: B-originated both ways (c)
run s8 t5_borig 7200 +seed=4 +dur_ms=20000 +idle_ms=40000 +orig_x=2 +pnet=1000 +prog_ms=2000
# T6: long holds fill the links: uniform, all network
run s8 t6_links 7200 +seed=6 +dur_ms=20000 +idle_ms=20000 +pnet=1000 +hold_ms=6000 +ringmax_ms=1500 +prog_ms=2000
# T7: overload then recovery: idle 8 s for 10 s, then 120 s
run s8 t7_step 7200 +seed=8 +dur_ms=22000 +idle_ms=8000 +switch_ms=10000 +idle2_ms=120000 +pnet=600 +prog_ms=1000

echo "$(date +%T) JOB1 end" >> $P

# ==== APPENDED 16:55 (job2 content, same slot, after T7) ======================================
# the pending-forward fix (work/load/transit/fix/net_unit.v), scale 8
echo "$(date +%T) JOB1b begin" >> $P
RTLFX=$(cat $T/fix/RTL_fix.list)
step build_fx 2400 bash -c "verilator --binary --timing -j 2 -Irtl -I$T -Wno-fatal --top-module tb_tr3 --Mdir $T/obj_fx -o tb_tr3 $RTLFX tb/site_net.v $T/tb_tr3.sv > $T/vl_fx.log 2>&1"
[ -x $T/obj_fx/tb_tr3 ] && run fx t4_cross_s8_fix 7200 +seed=9 +dur_ms=21000 +dest_mode=4 +pairs=A21C22,C21A22 +pair_gap_ms=1 +pair_per_ms=1400 +pair_jit_ms=30 +prog_ms=3000
[ -x $T/obj_fx/tb_tr3 ] && run fx t3_e2e_heavy_fix 7200 +seed=7 +dur_ms=20000 +idle_ms=40000 +dest_mode=5 +orig_x=5 +pnet=1000 +prog_ms=2000
# a real-timer load point, end to end A<->C, heavy (idle 320 s real = 40 s at scale 8)
[ -x $T/obj_s1/tb_tr3 ] && run s1 t10_e2e_heavy_s1 14400 +seed=7 +dur_ms=60000 +drain_ms=10000 +idle_ms=320000 +dest_mode=5 +orig_x=5 +pnet=1000 +prog_ms=10000
echo "$(date +%T) JOB1b end" >> $P
