#!/bin/bash
. /home/joel/telco/newimpl/build/flood/work/verify/C11-claimed-trunk-loss/lib.sh
step c11_fix_trel26 tb_c11 $D/RTL_c11.list 1500 "+define+TREL_V=9'd26" "+scen=2 +ntr=12 +bppm=100" tb/site_net.v $D/tb_c11.v
