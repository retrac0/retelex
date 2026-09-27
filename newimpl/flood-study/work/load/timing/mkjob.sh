#!/bin/bash
# mkjob.sh NNN NAME BIN TIMEOUT_S ARGS...  -> queue/NNN_NAME.sh: run BIN with ARGS,
# log run_NAME.log, analyse into an_NAME.txt, append the ONELINE to NOTES.md
n=$1; name=$2; bin=$3; to=$4; shift 4
f=/home/joel/telco/newimpl/build/flood/work/load/timing/queue/${n}_${name}.sh
cat > $f <<EOT
cd /home/joel/telco/newimpl/build/flood
T=work/load/timing
[ -x $bin ] || { echo "no binary $bin"; exit 3; }
SECONDS=0
timeout $to $bin $* > \$T/run_${name}.log 2>&1
rc=\$?
w=\$SECONDS
python3 \$T/tim_an.py \$T/run_${name}.log --quiet > \$T/an_${name}.txt 2>&1
echo "- RUN ${name} rc=\$rc wall=\${w}s args: $*" >> \$T/NOTES.md
grep ONELINE \$T/an_${name}.txt | sed 's/^/  /' >> \$T/NOTES.md
echo "${name} rc=\$rc wall=\$w"
EOT
echo "queued $f"
