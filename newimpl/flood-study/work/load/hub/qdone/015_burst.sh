. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
B=$H/obj_hub/tb_hub
run r5_burst 2400 $B +dest_mode=4 +hold_ms=200 +hold_fixed=1 +ans_ms=100 +trace=1 +seed=1 +pairs=B20Z21,C20Z22,D20C23 +pair_gap_ms=3 +dur_ms=50 +grace_ms=1500 +drain_ms=800
