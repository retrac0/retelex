. /home/joel/telco/newimpl/build/flood/work/load/hub/lib.sh
# leaf-to-leaf traffic on the UNSTRAPPED ring (H-L1-L2 triangle + L3 spoke), then the strapped one
LD="+orig_x=14 +net_to=14 +pnet=1000 +abandon=30 +seed=28 +idle_ms=30000 +dur_ms=12000"
run g3_ringload_unstrapped 14400 $H/obj_ring/tb_hub $LD
