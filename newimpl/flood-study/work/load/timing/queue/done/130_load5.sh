cd /home/joel/telco/newimpl/build/flood
T=work/load/timing
[ -x work/load/timing/obj_tim5/tb_tim5 ] || { echo "no binary work/load/timing/obj_tim5/tb_tim5"; exit 3; }
SECONDS=0
timeout 20000 work/load/timing/obj_tim5/tb_tim5 +seed=5 +dest_mode=0 +pnet=700 +idle_ms=50000 +dur_ms=20000 +grace_ms=5000 +drain_ms=8000 +ans_ms=1000 +hold_ms=3000 +prog_ms=5000 > $T/run_load5.log 2>&1
rc=$?
w=$SECONDS
python3 $T/tim_an.py $T/run_load5.log --quiet > $T/an_load5.txt 2>&1
echo "- RUN load5 rc=$rc wall=${w}s args: +seed=5 +dest_mode=0 +pnet=700 +idle_ms=50000 +dur_ms=20000 +grace_ms=5000 +drain_ms=8000 +ans_ms=1000 +hold_ms=3000 +prog_ms=5000" >> $T/NOTES.md
grep ONELINE $T/an_load5.txt | sed 's/^/  /' >> $T/NOTES.md
echo "load5 rc=$rc wall=$w"
