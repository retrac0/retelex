#!/bin/bash
source /home/joel/telco/newimpl/build/flood/work/verify/C12-origin-claim-acceptance/lib.sh
L=$V/RTL_fix.list
step net_fix $L tb_net "-DC12_TRACE" "tb/site_net.v tb/tb_net.v" 3600
step chain_fix $L tb_chain "-DC12_TRACE" "tb/site_net.v tb/tb_chain.v" 2000
step lfull_fix $L tb_lfull "-DC12_TRACE" "tb/site_net.v tb/tb_lfull.v" 4000
