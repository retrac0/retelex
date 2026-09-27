#!/bin/bash
# q2.sh -- after the pending slot request (pid given) finishes, keep taking slots
# with inner.sh until the queue is empty or STOP exists.
F=/home/joel/telco/newimpl/build/flood
D=$F/work/load/overload
cd $F
[ -n "$1" ] && while kill -0 $1 2>/dev/null; do sleep 10; done
while :; do
  [ -e $D/STOP ] && { echo "q2: STOP"; exit 0; }
  n=$(grep -v '^#' $D/queue.txt | grep -cv '^\s*$')
  [ "$n" = "0" ] && { echo "q2: queue empty"; exit 0; }
  echo "q2: $(date +%T) waiting for a slot ($n queue lines)"
  ./sim.sh bash $D/inner.sh
done
