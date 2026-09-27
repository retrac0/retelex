. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
LD="+orig_x=14 +net_to=14 +pnet=1000 +abandon=30 +seed=28 +idle_ms=30000 +dur_ms=12000"
run g4_ringload_strapped 14400 $H/obj_ringst/tb_hub $LD
