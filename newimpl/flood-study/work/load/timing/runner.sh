#!/bin/bash
# runner.sh -- holds ONE sim.sh slot and runs this agent's jobs one at a time,
# in name order, from work/load/timing/queue/*.sh.  Exits when the queue has
# been empty 10 minutes, or on queue/STOP.  Each job carries its own timeouts.
cd /home/joel/telco/newimpl/build/flood || exit 1
Q=work/load/timing/queue
L=work/load/timing/runner.log
export TMPDIR=/home/joel/telco/newimpl/build/flood/tmp
idle=0
echo "[runner] $(date +%T) got the slot" >> $L
while :; do
  j=$(ls $Q/*.sh 2>/dev/null | sort | head -1)
  if [ -z "$j" ]; then
    [ -e $Q/STOP ] && break
    idle=$((idle+1)); [ $idle -gt 120 ] && break
    sleep 5; continue
  fi
  idle=0
  b=$(basename $j); mv $j $Q/done/$b
  echo "[runner] $(date +%T) start $b" >> $L
  SECONDS=0; bash $Q/done/$b >> $L 2>&1; rc=$?
  echo "[runner] $(date +%T) end $b rc=$rc secs=$SECONDS" >> $L
done
echo "[runner] $(date +%T) exit" >> $L
