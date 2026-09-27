cd /home/joel/telco/newimpl/build/flood/work/load/timing
for d in obj_tim5 obj_timn obj_timn4; do
  [ -d $d ] || continue
  find $d -type f \( -name "*.o" -o -name "*.a" -o -name "*.cpp" -o -name "*.h" -o -name "*.d" -o -name "*.dat" -o -name "*.gch" \) -delete
done
du -sh obj_* ; echo clean done
