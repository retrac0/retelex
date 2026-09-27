#!/bin/bash
# the queue runner: one slot, one sim at a time.  Runs q/*.sh in name order,
# moving each to qdone/ first; exits when q/ is empty.
cd /home/joel/telco/newimpl/build/flood/work/load/hub || exit 1
while true; do
  f=$(ls q/*.sh 2>/dev/null | sort | head -1)
  [ -z "$f" ] && break
  mv "$f" qdone/
  echo "$(date +%H:%M) start $(basename $f)" >> runs.rc
  bash qdone/$(basename $f)
done
echo "$(date +%H:%M) runner exit" >> runs.rc
