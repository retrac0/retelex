#!/bin/bash
# waitfor.sh <secs> <file> <pattern>: return when pattern appears in file, or after secs
end=$(( $(date +%s) + $1 ))
while [ $(date +%s) -lt $end ]; do
  grep -q "$3" "$2" 2>/dev/null && { echo "found: $3 in $2"; exit 0; }
  sleep 10
done
echo "timeout waiting for $3 in $2"
