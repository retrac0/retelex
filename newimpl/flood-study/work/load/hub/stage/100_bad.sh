. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
B=$H/obj_hub/tb_hub
# every network attempt dials a code nobody has: pure resolver / link stress, no far registers
run ld_bad_idle20 14400 $B +orig_x=14 +dest_mode=3 +pnet=1000 +seed=24 +idle_ms=20000 +dur_ms=10000
