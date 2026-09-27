. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
build obj_hub || exit 2
B=$H/obj_hub/tb_hub
DIR="+dest_mode=4 +hold_ms=200 +hold_fixed=1 +ans_ms=100 +trace=1 +seed=1"
run r1_directed 5400 $B $DIR +pairs=B20C21,B21A21,B22Z23,D20B23,C20D24 +pair_gap_ms=1500 +dur_ms=7400 +grace_ms=1000 +drain_ms=800
run r2_three    2400 $B $DIR +pairs=B20Z21,C20Z22,D20C23 +pair_gap_ms=60 +dur_ms=300 +grace_ms=1500 +drain_ms=800
run r3_threeH   2400 $B $DIR +pairs=B20Z21,C20Z22,D20A21 +pair_gap_ms=60 +dur_ms=300 +grace_ms=1500 +drain_ms=800
