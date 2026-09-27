#!/bin/bash
. /home/joel/telco/newimpl/build/flood/work/verify/C11-claimed-trunk-loss/lib.sh
step net_alt tb_net $D/RTL_alt.list 3000 "" "" tb/site_net.v tb/tb_net.v
step c11_snap tb_c11 work/RTL.list 1500 "" "+scen=3 +ntr=12 +bppm=100" tb/site_net.v $D/tb_c11.v
step c11_fix  tb_c11 $D/RTL_c11.list 1500 "" "+scen=3 +ntr=12 +bppm=100" tb/site_net.v $D/tb_c11.v
step lfull_alt tb_lfull $D/RTL_alt.list 3600 "" "" tb/site_net.v tb/tb_lfull.v
grep -q "^c11_fix_trel26 start" $D/progress.txt || step c11_fix_trel26 tb_c11 $D/RTL_c11.list 1500 "+define+TREL_V=9'd26" "+scen=2 +ntr=12 +bppm=100" tb/site_net.v $D/tb_c11.v
grep -q "^c11_alt_trel26 start" $D/progress.txt || step c11_alt_trel26 tb_c11 $D/RTL_alt.list 1500 "+define+TREL_V=9'd26" "+scen=2 +ntr=12 +bppm=100" tb/site_net.v $D/tb_c11.v
grep -q "^c11_alt start" $D/progress.txt || step c11_alt tb_c11 $D/RTL_alt.list 1500 "" "+scen=3 +ntr=12 +bppm=100" tb/site_net.v $D/tb_c11.v
grep -q "^net_c11 start" $D/progress.txt || step net_c11 tb_net $D/RTL_c11.list 3000 "" "" tb/site_net.v tb/tb_net.v
grep -q "^lfull_c11 start" $D/progress.txt || step lfull_c11 tb_lfull $D/RTL_c11.list 3600 "" "" tb/site_net.v tb/tb_lfull.v
