echo "q: $(date +%T) start r21_l3_i1500_step"
SECONDS=0; timeout 5400 work/load/obj_load3/tb_load3 +seed=41 +dur_ms=14000 +idle_ms=1500 +switch_ms=6000 +idle2_ms=60000 +prog_ms=1000 > /home/joel/telco/newimpl/build/flood/work/load/overload/r21_l3_i1500_step.log 2>&1; echo rc=$? secs=$SECONDS > /home/joel/telco/newimpl/build/flood/work/load/overload/r21_l3_i1500_step.rc
echo "q: $(date +%T) end r21_l3_i1500_step $(cat /home/joel/telco/newimpl/build/flood/work/load/overload/r21_l3_i1500_step.rc)"
echo "q: $(date +%T) start r22_l3_always"
SECONDS=0; timeout 5400 work/load/obj_load3/tb_load3 +seed=42 +dur_ms=6000 +idle_ms=50 +prog_ms=1000 > /home/joel/telco/newimpl/build/flood/work/load/overload/r22_l3_always.log 2>&1; echo rc=$? secs=$SECONDS > /home/joel/telco/newimpl/build/flood/work/load/overload/r22_l3_always.rc
echo "q: $(date +%T) end r22_l3_always $(cat /home/joel/telco/newimpl/build/flood/work/load/overload/r22_l3_always.rc)"
