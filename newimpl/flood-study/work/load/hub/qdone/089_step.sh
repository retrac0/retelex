. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
B=$H/obj_hub/tb_hub
# overload 5 s, then light: does it recover?
run lstep_5to120 14400 $B +orig_x=14 +net_to=14 +pnet=1000 +abandon=30 +seed=26 +idle_ms=5000 +switch_ms=5000 +idle2_ms=120000 +dur_ms=15000
