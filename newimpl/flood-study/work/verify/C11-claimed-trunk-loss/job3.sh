#!/bin/bash
. /home/joel/telco/newimpl/build/flood/work/verify/C11-claimed-trunk-loss/lib.sh
step net_c11 tb_net $D/RTL_c11.list 3000 "" "" tb/site_net.v tb/tb_net.v
step lfull_c11 tb_lfull $D/RTL_c11.list 3600 "" "" tb/site_net.v tb/tb_lfull.v
