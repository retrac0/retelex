cd /home/joel/telco/newimpl/build/flood
timeout 3600 verilator --binary --timing -j 2 -Irtl -Iwork/load/timing -Wno-fatal +define+SCALE1 --top-module tb_tim5 --Mdir work/load/timing/obj_tim5 -o tb_tim5 $(cat work/RTL.list) tb/site_net.v work/load/timing/tb_tim5.sv > work/load/timing/vl_tim5.log 2>&1
echo "rebuild tim5 rc=$?"
