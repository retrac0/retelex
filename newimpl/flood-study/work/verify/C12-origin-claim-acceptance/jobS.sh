#!/bin/bash
source /home/joel/telco/newimpl/build/flood/work/verify/C12-origin-claim-acceptance/lib.sh
step c12_snap work/RTL.list tb_c12 "" "tb/site_net.v $V/tb_c12.v" 3600 +sc=0
step mc2_snap work/RTL.list tb_mc2 "" "tb/site_net.v work/audit/monclaim/tb_mc2.v" 2400
