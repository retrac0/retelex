#!/bin/bash
# real timers (T_REL = CLR = 256, T_CLAIM 2000, 10 pps dial), snapshot, T sweep 1742.5..1745.5 ms
D=/home/joel/telco/newimpl/build/flood/work/verify/C17-nogo-after-release
$D/build.sh obj_real work/RTL.list +define+REAL || exit 1
$D/run.sh obj_real real_T.log 3500 +mode=1 +tx0=1742500 +step=1000 +n=4
rm -rf $D/obj_real
echo JOBREAL DONE
