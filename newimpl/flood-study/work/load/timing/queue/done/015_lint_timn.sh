cd /home/joel/telco/newimpl/build/flood
timeout 1200 verilator --lint-only --timing -Irtl -Iwork/load/timing -Wno-fatal +define+SCALE1 --top-module tb_timn $(cat work/RTL.list) tb/site_net.v work/load/timing/tb_timn.sv > work/load/timing/lint_timn.log 2>&1
echo "lint timn rc=$?"
