#!/bin/bash
cd /home/joel/telco/newimpl/build/flood
D=work/verify/C08-phantom-seizure
$D/run_tb.sh $D/RTL_fix.list tb_net "tb/site_net.v tb/tb_net.v" net_fix
$D/run_tb.sh $D/RTL_fix.list tb_chain "tb/site_net.v tb/tb_chain.v" chain_fix
