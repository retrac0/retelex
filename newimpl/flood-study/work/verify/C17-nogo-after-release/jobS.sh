#!/bin/bash
# snapshot: build tb_c17, T sweep then N sweep
D=/home/joel/telco/newimpl/build/flood/work/verify/C17-nogo-after-release
$D/build.sh obj_snap work/RTL.list || exit 1
$D/run.sh obj_snap snap_T.log 2400 +mode=1 +tx0=215500 +step=500 +n=10
$D/run.sh obj_snap snap_N.log 2400 +mode=2 +nx0=1216000 +step=500 +n=8
rm -rf $D/obj_snap
echo JOBS DONE
