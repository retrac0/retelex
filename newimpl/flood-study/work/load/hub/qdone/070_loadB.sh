. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
B=$H/obj_hub/tb_hub
LD="+orig_x=14 +net_to=14 +pnet=1000 +abandon=30"
run lb_idle20 14400 $B $LD +seed=22 +idle_ms=20000 +dur_ms=12000
