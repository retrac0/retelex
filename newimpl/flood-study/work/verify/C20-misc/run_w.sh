#!/bin/bash
cd /home/joel/telco/newimpl/build/flood
V=work/verify/C20-misc
O=$V/obj_wait
rm -rf $O
verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_wait --Mdir $O -o tb_wait rtl/ctl_write.v rtl/ctl_queue.v $V/tb_wait.v > $V/vl_wait.log 2>&1; echo build_w=$?
timeout 900 $O/tb_wait > $V/run_wait.log 2>&1; echo run_w=$?
rm -rf $O
