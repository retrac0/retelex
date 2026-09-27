#!/bin/bash
source /home/joel/telco/newimpl/build/flood/work/verify/C12-origin-claim-acceptance/lib.sh
L=$V/RTL_fix.list
step c12_fix $L tb_c12 "-DC12_TRACE" "tb/site_net.v $V/tb_c12.v" 3600 +sc=0
step mc2_fix $L tb_mc2 "-DC12_TRACE" "tb/site_net.v work/audit/monclaim/tb_mc2.v" 2400
