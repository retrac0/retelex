. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
build obj_hub_s1 +define+SCALE1 || exit 2
B=$H/obj_hub_s1/tb_hub
# real timers: a leaf-to-leaf call and a call to the hub, then a burst of three floods within ~10 ms
run s1_directed 5400 $B +dest_mode=4 +hold_ms=1000 +hold_fixed=1 +ans_ms=500 +trace=1 +seed=1 +pairs=B20C21,D20A21 +pair_gap_ms=4000 +dur_ms=4100 +grace_ms=7500 +drain_ms=2000
run s1_burst 5400 $B +dest_mode=4 +hold_ms=1000 +hold_fixed=1 +ans_ms=500 +trace=1 +seed=1 +pairs=B20Z21,C20Z22,D20C23 +pair_gap_ms=3 +dur_ms=50 +grace_ms=7000 +drain_ms=2000
