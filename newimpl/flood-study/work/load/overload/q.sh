#!/bin/bash
# q.sh -- run the overload study's queue through sim.sh, ONE sim at a time.
# queue.txt: one BATCH a line; a batch is one or more runs joined by ' ;; ',
# each run NAME|BINARY|TIMEOUT_S|ARGS...  A batch takes ONE sim.sh slot and runs
# its runs one after another inside it (never two at once).  A line is claimed by
# moving it to done.txt before it runs; lines may be edited/appended meanwhile.
# Stop after the current batch: touch STOP.
F=/home/joel/telco/newimpl/build/flood
D=$F/work/load/overload
cd $F
while :; do
  [ -e $D/STOP ] && { echo "q: STOP"; exit 0; }
  line=$(grep -v '^#' $D/queue.txt | grep -v '^\s*$' | head -1)
  [ -z "$line" ] && { echo "q: empty"; exit 0; }
  python3 - "$D/queue.txt" "$line" <<'EOF'
import sys
p, l = sys.argv[1], sys.argv[2]
ls = open(p).read().split('\n')
ls.remove(l)
open(p, 'w').write('\n'.join(ls))
EOF
  echo "$line" >> $D/done.txt
  S=$D/batch_$(date +%H%M%S).sh
  echo '#!/bin/bash' > $S
  echo "cd $F" >> $S
  python3 - "$line" "$D" >> $S <<'EOF'
import sys
line, D = sys.argv[1], sys.argv[2]
for run in line.split(' ;; '):
    name, binary, tmo, args = run.strip().split('|', 3)
    print(f'echo "q: $(date +%T) start {name}"')
    print(f'SECONDS=0; timeout {tmo} {binary} {args} > {D}/{name}.log 2>&1; echo rc=$? secs=$SECONDS > {D}/{name}.rc')
    print(f'echo "q: $(date +%T) end {name} $(cat {D}/{name}.rc)"')
EOF
  chmod +x $S
  echo "q: $(date +%T) waiting for a slot: $S"
  ./sim.sh bash $S
done
