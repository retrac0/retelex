cd /home/joel/telco/newimpl/build/flood
T=work/load/timing
[ -x work/load/timing/obj_timn/tb_timn ] || { echo "no binary work/load/timing/obj_timn/tb_timn"; exit 3; }
SECONDS=0
timeout 20000 work/load/timing/obj_timn/tb_timn +seed=3 +pairs=A20Z21,B20Z21,A21Z21,B21Z21,A22Z21,B22Z21,A23Z21,B23Z21 +pair_off=0,6,5000,5009,10000,10012,15000,15015 +dur_ms=20000 +dest_mode=4 +burst_ms=20000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3 > $T/run_cvd8.log 2>&1
rc=$?
w=$SECONDS
python3 $T/tim_an.py $T/run_cvd8.log --quiet > $T/an_cvd8.txt 2>&1
echo "- RUN cvd8 rc=$rc wall=${w}s args: +seed=3 +pairs=A20Z21,B20Z21,A21Z21,B21Z21,A22Z21,B22Z21,A23Z21,B23Z21 +pair_off=0,6,5000,5009,10000,10012,15000,15015 +dur_ms=20000 +dest_mode=4 +burst_ms=20000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3" >> $T/NOTES.md
grep ONELINE $T/an_cvd8.txt | sed 's/^/  /' >> $T/NOTES.md
echo "cvd8 rc=$rc wall=$w"
