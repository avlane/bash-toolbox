#!/bin/bash
# tail-logs.sh - follow several log files at once with a name prefix
# usage: tail-logs.sh FILE...

if [ $# -eq 0 ]; then
    echo "usage: tail-logs.sh FILE..."
    exit 2
fi

pids=""
for f in "$@"; do
    name=`basename "$f"`
    tail -n 5 -f "$f" | sed "s/^/[$name] /" &
    pids="$pids $!"
done

trap "kill $pids 2>/dev/null" INT TERM
wait
