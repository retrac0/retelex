#!/bin/bash
# sim.sh -- run ONE build or simulation, throttled and memory-capped.
#   At most NSLOT (3) sim.sh commands run at once, across every agent; each
#   under a 3 GB cgroup cap with no swap, single-threaded Verilator, TMPDIR
#   under build/ (the /tmp quota).  Usage:  ./sim.sh <command...>
#   e.g.  ./sim.sh make -C /home/joel/telco/newimpl/build/flood net
#         ./sim.sh bash -c 'verilator ... && ./obj/tb_x'
set -u
F=/home/joel/telco/newimpl/build/flood
export TMPDIR=$F/tmp
NSLOT=${NSLOT:-5}
while :; do
  for i in $(seq 1 $NSLOT); do
    exec {fd}>$F/locks/slot$i
    if flock -n $fd; then
      echo "[sim.sh] slot $i: $*" >&2
      systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 "$@"
      rc=$?
      flock -u $fd; exec {fd}>&-
      exit $rc
    fi
    exec {fd}>&-
  done
  sleep 5
done
