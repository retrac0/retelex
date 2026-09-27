cd /home/joel/telco/newimpl/build/flood
grep -q "%Error" work/load/timing/lint_timn.log && { echo "timn lint errors, skip build"; exit 2; }
timeout 3600 verilator --binary --timing -j 2 -Irtl -Iwork/load/timing -Wno-fatal +define+SCALE1 --top-module tb_timn --Mdir work/load/timing/obj_timn -o tb_timn $(cat work/RTL.list) tb/site_net.v work/load/timing/tb_timn.sv > work/load/timing/vl_timn.log 2>&1
echo "build timn rc=$?"
