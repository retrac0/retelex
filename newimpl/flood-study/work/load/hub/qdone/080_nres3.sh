. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
build obj_hub_r3 +define+LD_NRES=3 || exit 2
LD="+orig_x=14 +net_to=14 +pnet=1000 +abandon=30"
# the same traffic as lb_idle20 (seed 22), with three resolvers at every unit
run lb_idle20_nres3 14400 $H/obj_hub_r3/tb_hub $LD +seed=22 +idle_ms=20000 +dur_ms=12000
