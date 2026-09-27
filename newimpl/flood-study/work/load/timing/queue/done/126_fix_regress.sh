cd /home/joel/telco/newimpl/build/flood
T=work/load/timing
RTLF=$(cat $T/fix/RTL_fix.list)
for b in net chain lnet lchain lfull; do
  SECONDS=0
  timeout 3600 verilator --binary --timing -j 2 -Irtl -Wno-fatal --top-module tb_$b --Mdir $T/fix/obj_$b -o tb_$b $RTLF tb/site_net.v tb/tb_$b.v > $T/fix/vl_$b.log 2>&1
  brc=$?
  rm -f $T/fix/obj_$b/*.gch $T/fix/obj_$b/*.o $T/fix/obj_$b/*.a
  timeout 5400 $T/fix/obj_$b/tb_$b > $T/fix/run_$b.log 2>&1
  rc=$?
  nf=$(grep -c "FAIL" $T/fix/run_$b.log)
  echo "fix-regress $b build=$brc rc=$rc fails=$nf secs=$SECONDS $(grep -E '^ *(PASS|FAIL)' $T/fix/run_$b.log | tail -1)" | tee -a $T/NOTES.md
  rm -rf $T/fix/obj_$b
done
