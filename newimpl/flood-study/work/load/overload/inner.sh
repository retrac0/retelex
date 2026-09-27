#!/bin/bash
# inner.sh -- runs INSIDE one sim.sh slot: after the batch that got the slot, keep
# taking queue lines (one at a time, sequentially) until BUDGET_S has elapsed since
# the slot was taken, so a slot is not given up and waited for again between runs.
F=/home/joel/telco/newimpl/build/flood
D=$F/work/load/overload
BUDGET_S=${BUDGET_S:-7200}
T0=$(date +%s)
cd $F
runline() {
  python3 - "$1" "$D" > $D/.cur_batch.sh <<'PY'
import sys
line, D = sys.argv[1], sys.argv[2]
for run in line.split(' ;; '):
    name, binary, tmo, args = run.strip().split('|', 3)
    print(f'echo "q: $(date +%T) start {name}"')
    print(f'SECONDS=0; timeout {tmo} {binary} {args} > {D}/{name}.log 2>&1; echo rc=$? secs=$SECONDS > {D}/{name}.rc')
    print(f'echo "q: $(date +%T) end {name} $(cat {D}/{name}.rc)"')
PY
  bash $D/.cur_batch.sh
}
while :; do
  [ -e $D/STOP ] && { echo "q: inner STOP"; exit 0; }
  el=$(( $(date +%s) - T0 ))
  [ $el -ge $BUDGET_S ] && { echo "q: inner budget used ($el s): releasing the slot"; exit 0; }
  line=$(grep -v '^#' $D/queue.txt | grep -v '^\s*$' | head -1)
  [ -z "$line" ] && { echo "q: inner queue empty"; exit 0; }
  python3 - "$D/queue.txt" "$line" <<'PY'
import sys
p, l = sys.argv[1], sys.argv[2]
ls = open(p).read().split('\n'); ls.remove(l); open(p, 'w').write('\n'.join(ls))
PY
  echo "$line" >> $D/done.txt
  runline "$line"
done
