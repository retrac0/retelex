. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
B=$H/obj_hub/tb_hub
LD="+orig_x=14 +net_to=14 +pnet=1000 +abandon=30"
run la_idle60 14400 $B $LD +seed=21 +idle_ms=60000 +dur_ms=16000
