#!/bin/bash
# usage: build.sh <objdir> <top> <rtl.list> <tb files...>
F=/home/joel/telco/newimpl/build/flood
cd $F
obj=$1; top=$2; list=$3; shift 3
mkdir -p $obj
timeout 1500 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module $top --Mdir $obj -o $top $(cat $list) "$@" > $obj.vl.log 2>&1
echo "build rc=$?" >> $obj.vl.log
