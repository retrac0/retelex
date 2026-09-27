. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
build obj_ring +define+HUB_RING || exit 2
build obj_ringst +define+HUB_RING +define+HUB_STRAP || exit 2
P="+dest_mode=4 +hold_ms=200 +hold_fixed=1 +ans_ms=100 +trace=1 +seed=1 +pairs=D20C21,B20C22,C23B24,A20C24,D21B25 +pair_gap_ms=1500 +dur_ms=7400 +grace_ms=1000 +drain_ms=800"
run g1_ring_unstrapped 5400 $H/obj_ring/tb_hub $P
run g2_ring_strapped   5400 $H/obj_ringst/tb_hub $P
