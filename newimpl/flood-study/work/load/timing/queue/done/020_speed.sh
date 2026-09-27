cd /home/joel/telco/newimpl/build/flood
[ -x work/load/timing/obj_tim5/tb_tim5 ] || exit 3
SECONDS=0
timeout 7200 work/load/timing/obj_tim5/tb_tim5 +seed=1 +dest_mode=4 +pairs=A20E20 +pair_gap_ms=1 +burst_ms=100000 +dur_ms=1000 +max_ms=4000 +prog_ms=500 > work/load/timing/run_speed.log 2>&1
echo "speed rc=$? wall=$SECONDS"
