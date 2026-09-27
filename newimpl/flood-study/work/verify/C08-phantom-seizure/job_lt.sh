#!/bin/bash
cd /home/joel/telco/newimpl/build/flood
D=work/verify/C08-phantom-seizure
$D/run_tb.sh work/RTL.list tb_c08lt "tb/site_net.v $D/tb_c08lt.v" lt_base
