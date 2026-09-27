#!/bin/bash
D=/home/joel/telco/newimpl/build/flood/work/verify/C15-one-register
$D/run.sh fixR $D/RTL_fix.list "-DREAL" "+scen=2" 3600
$D/runtb.sh lfull $D/RTL_fix.list fix 5400
