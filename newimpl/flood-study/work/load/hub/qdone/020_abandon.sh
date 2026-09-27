. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
B=$H/obj_hub/tb_hub
run r4_abandon 7200 $B +dest_mode=4 +hold_ms=200 +hold_fixed=1 +ans_ms=100 +trace=1 +seed=3 +abandon=1000 +pairs=B20C21 +pair_gap_ms=1200 +dur_ms=14000 +grace_ms=1000 +drain_ms=800
