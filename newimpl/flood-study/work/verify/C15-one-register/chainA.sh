#!/bin/bash
D=/home/joel/telco/newimpl/build/flood/work/verify/C15-one-register
$D/runtb.sh net $D/RTL_fix.list fix 3600
$D/run.sh snapR /home/joel/telco/newimpl/build/flood/work/RTL.list "-DREAL" "+scen=2" 3600
