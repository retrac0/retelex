#!/bin/bash
# runqb.sh QUEUEFILE K -- like runq.sh, but each slot of ../../../sim.sh runs the next K
# pending jobs of the queue one after another (a batch), so a busy throttle is
# queued for once per K jobs.  Each job keeps its own timeout, NAME.log and NAME.rc.
F=/home/joel/telco/newimpl/build/flood
D=$F/work/load/cap2
Q=$1; K=${2:-3}
cd $F
while :; do
  jobs=()
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    name=${line%%|*}
    [[ -f $D/$name.rc || -f $D/$name.running ]] && continue
    jobs+=("$line"); [[ ${#jobs[@]} -ge $K ]] && break
  done < $Q
  [[ ${#jobs[@]} -eq 0 ]] && break
  B=$D/batch_$$_$(date +%s).sh
  echo "#!/bin/bash" > $B; echo "cd $F" >> $B
  for job in "${jobs[@]}"; do
    IFS='|' read -r name bin tmo args <<< "$job"
    echo "$(date +%T) queued $name" > $D/$name.running
    cat >> $B <<EOB
echo "\$(date +%T) START $name" >> $D/runq.out
s=\$(date +%s)
timeout $tmo $bin $args > $D/$name.log 2>&1
rc=\$?
echo "rc=\$rc wall_s=\$((\$(date +%s)-s)) bin=$bin args=$args" > $D/$name.rc
rm -f $D/$name.running
echo "\$(date +%T) DONE $name rc=\$rc wall_s=\$((\$(date +%s)-s))" >> $D/runq.out
EOB
  done
  echo "$(date +%T) BATCH $(basename $B) waiting for a slot: ${#jobs[@]} jobs" >> $D/runq.out
  ./sim.sh bash $B
  rm -f $B
done
echo "$(date +%T) queue $Q empty" >> $D/runq.out
