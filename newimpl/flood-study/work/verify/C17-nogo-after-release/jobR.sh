#!/bin/bash
# RC spread: the port's T_REL 20 % short of CLR (26 vs 32), snapshot, T sweep 1 ms steps
D=/home/joel/telco/newimpl/build/flood/work/verify/C17-nogo-after-release
$D/build.sh obj_rc work/RTL.list +define+TREL_FIX=9\'d26 || exit 1
$D/run.sh obj_rc rc26_T.log 3000 +mode=1 +tx0=215500 +step=1000 +n=12
rm -rf $D/obj_rc
echo JOBR DONE
