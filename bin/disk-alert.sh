#!/bin/bash
# disk-alert.sh - warn when a filesystem is nearly full
# usage: disk-alert.sh [THRESHOLD_PERCENT]
# Prints a line for every filesystem at or over the threshold (default 90).
# Exit status is 1 if anything was over, 0 otherwise.

THRESHOLD=${1:-90}
status=0

# process substitution instead of a pipe: a piped while loop runs in a
# subshell, so "status" was never updated and the script always exited 0
while read -r fs blocks used avail pct mount; do
    num=${pct%\%}
    if [[ "$num" -ge "$THRESHOLD" ]]; then
        echo "WARNING: $mount is at $pct ($fs)"
        status=1
    fi
done < <(${DF_CMD:-df -P} | tail -n +2)

exit $status
