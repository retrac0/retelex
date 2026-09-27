#!/bin/bash
# one slot, the C08 runs in priority order; each run has its own timeouts
cd /home/joel/telco/newimpl/build/flood
D=work/verify/C08-phantom-seizure
$D/run_tb.sh $D/RTL_fix.list tb_c08 "tb/site_net.v $D/tb_c08.v" c08_fix +sc=2
$D/run_tb.sh work/RTL.list tb_c08lt "tb/site_net.v $D/tb_c08lt.v" lt_base
$D/run_tb.sh $D/RTL_naive.list tb_c08 "tb/site_net.v $D/tb_c08.v" c08_naive +sc=2
$D/run_tb.sh work/RTL.list tb_c08 "tb/site_net.v $D/tb_c08.v" c08_base +sc=2
