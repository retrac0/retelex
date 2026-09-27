#!/bin/bash
# runq.sh QUEUEFILE -- run the jobs of a queue file one after another, each
# through ../../../sim.sh (throttled, 3 GB cap) with a wall-clock timeout.
# A line:  NAME|BINARY|TIMEOUT_S|ARGS...   (# comments; a job whose .log has END is skipped)
# A job NAME writes cap2/NAME.log and cap2/NAME.rc (rc, wall secs).
# The queue file is re-read after every job, so lines may be appended while it runs.
F=/home/joel/telco/newimpl/build/flood
D=$F/work/load/cap2
Q=$1
cd $F
while :; do
  job=""
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    name=${line%%|*}
    [[ -f $D/$name.rc || -f $D/$name.running ]] && continue
    job=$line; break
  done < $Q
  [[ -z "$job" ]] && break
  IFS='|' read -r name bin tmo args <<< "$job"
  echo "$(date +%T) start $name" > $D/$name.running
  echo "$(date +%T) START $name: $bin $args" >> $D/runq.out
  s=$(date +%s)
  ./sim.sh bash -c "timeout $tmo $bin $args > $D/$name.log 2>&1"
  rc=$?
  e=$(date +%s)
  echo "rc=$rc wall_s=$((e-s)) bin=$bin args=$args" > $D/$name.rc
  rm -f $D/$name.running
  echo "$(date +%T) DONE $name rc=$rc wall_s=$((e-s))" >> $D/runq.out
done
echo "$(date +%T) queue $Q empty" >> $D/runq.out
