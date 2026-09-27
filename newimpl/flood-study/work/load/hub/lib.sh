# lib.sh -- sourced by the queue items.  run NAME TIMEOUT BINARY ARGS...
cd /home/joel/telco/newimpl/build/flood || exit 1
H=work/load/hub; L=$H/logs
run() {
  local n=$1 to=$2 bin=$3; shift 3; local t=$SECONDS
  timeout $to $bin "$@" > $L/$n.log 2>&1
  local rc=$?
  echo "$(date +%H:%M) $n rc=$rc wall_s=$((SECONDS-t)) bin=$bin args=$*" >> $H/runs.rc
  echo "$(date +%H:%M) $n rc=$rc wall_s=$((SECONDS-t))"
}
build() { # MDIR DEFINES...
  local md=$1; shift; local t=$SECONDS
  if [ ! -x $H/$md/tb_hub ]; then
    verilator --binary --timing -j 2 -Irtl -I$H -Wno-fatal "$@" --top-module tb_hub --Mdir $H/$md -o tb_hub \
       $(cat work/RTL.list) tb/site_net.v $H/tb_hub.sv > $H/vl_$md.log 2>&1
    echo "$(date +%H:%M) build $md rc=$? wall_s=$((SECONDS-t)) defs=$*" >> $H/runs.rc
    # keep the binary only: the disk is nearly full
    [ -x $H/$md/tb_hub ] && find $H/$md -type f ! -name tb_hub -delete
  fi
  [ -x $H/$md/tb_hub ]
}
buildf() { # MDIR FILE DEFINES...   (a different topology file, top module tb_hub)
  local md=$1 f=$2; shift 2; local t=$SECONDS
  if [ ! -x $H/$md/tb_hub ]; then
    verilator --binary --timing -j 2 -Irtl -I$H -Wno-fatal "$@" --top-module tb_hub --Mdir $H/$md -o tb_hub \
       $(cat work/RTL.list) tb/site_net.v $H/$f > $H/vl_$md.log 2>&1
    echo "$(date +%H:%M) build $md ($f) rc=$? wall_s=$((SECONDS-t)) defs=$*" >> $H/runs.rc
    [ -x $H/$md/tb_hub ] && find $H/$md -type f ! -name tb_hub -delete
  fi
  [ -x $H/$md/tb_hub ]
}
