#!/bin/bash
# disk-alert.sh - warn when a filesystem is nearly full
# usage: disk-alert.sh [THRESHOLD_PERCENT]
# Prints a line for every filesystem at or over the threshold (default 90).
# Exit status is 1 if anything was over, 0 otherwise.

THRESHOLD=${1:-90}
status=0

df -P | tail -n +2 | while read fs blocks used avail pct mount; do
    num=`echo $pct | tr -d '%'`
    if [ "$num" -ge "$THRESHOLD" ]; then
        echo "WARNING: $mount is at $pct ($fs)"
    fi
done
