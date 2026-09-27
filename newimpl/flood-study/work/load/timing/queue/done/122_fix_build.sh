cd /home/joel/telco/newimpl/build/flood
timeout 3600 verilator --binary --timing -j 2 -Irtl -Iwork/load/timing -Wno-fatal +define+SCALE1 +define+LD_NMON=4 +define+LD_NRES=4 +define+TIM_FIX --top-module tb_timn --Mdir work/load/timing/obj_timn4fix -o tb_timn $(cat work/load/timing/fix/RTL_fix.list) tb/site_net.v work/load/timing/tb_timn.sv > work/load/timing/vl_timn4fix.log 2>&1
echo "build timn4fix rc=$?"
grep -c "%Error" work/load/timing/vl_timn4fix.log
rm -f work/load/timing/obj_timn4fix/*.gch work/load/timing/obj_timn4fix/*.o work/load/timing/obj_timn4fix/*.a
