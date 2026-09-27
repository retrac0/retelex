. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
B=$H/obj_hub/tb_hub
# everyone originates, every exchange a destination (H's 16 lines too)
run le_all_idle20 14400 $B +orig_x=15 +net_to=15 +pnet=1000 +abandon=30 +seed=25 +idle_ms=20000 +dur_ms=12000
