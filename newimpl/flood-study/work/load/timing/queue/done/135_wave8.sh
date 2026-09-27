cd /home/joel/telco/newimpl/build/flood
T=work/load/timing
[ -x work/load/timing/obj_timn/tb_timn ] || { echo "no binary work/load/timing/obj_timn/tb_timn"; exit 3; }
SECONDS=0
timeout 20000 work/load/timing/obj_timn/tb_timn +seed=4 +pairs=A20Z21,C20Z21,E20Z21,G20Z21 +pair_off=0,24,65,106 +dur_ms=10000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3 > $T/run_wave8.log 2>&1
rc=$?
w=$SECONDS
python3 $T/tim_an.py $T/run_wave8.log --quiet > $T/an_wave8.txt 2>&1
echo "- RUN wave8 rc=$rc wall=${w}s args: +seed=4 +pairs=A20Z21,C20Z21,E20Z21,G20Z21 +pair_off=0,24,65,106 +dur_ms=10000 +dest_mode=4 +burst_ms=5000 +pre_ms=200 +idg_ms=300 +idg0_ms=255 +idg0_jit_ms=50 +pd_ms=700 +hup_ms=200 +rest_ms=300 +grace_ms=0 +drain_ms=3000 +prog_ms=5000 +bad_e=4 +bad_b=3" >> $T/NOTES.md
grep ONELINE $T/an_wave8.txt | sed 's/^/  /' >> $T/NOTES.md
echo "wave8 rc=$rc wall=$w"
