. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
buildf obj_hubb tb_hubb.sv || exit 2
B=$H/obj_hubb/tb_hub
# two baseband channels a direction: one directed leaf-to-leaf call, then leaf-to-leaf load (links the bottleneck)
run bb_directed 2400 $B +dest_mode=4 +hold_ms=200 +hold_fixed=1 +ans_ms=100 +trace=1 +seed=1 +pairs=B20C21 +pair_gap_ms=1500 +dur_ms=1400 +grace_ms=500 +drain_ms=800
run bb_idle20 14400 $B +orig_x=14 +net_to=14 +pnet=1000 +abandon=30 +seed=27 +idle_ms=20000 +dur_ms=12000
