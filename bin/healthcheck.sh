#!/bin/bash
# healthcheck.sh - is something listening on HOST:PORT?
# usage: healthcheck.sh HOST PORT
# exit status: 0 = open, 1 = closed or timed out, 2 = bad usage

if [ $# -ne 2 ]; then
    echo "usage: healthcheck.sh HOST PORT"
    exit 2
fi

HOST=$1
PORT=$2

if nc -z -w 3 "$HOST" "$PORT" >/dev/null 2>&1; then
    echo "OK $HOST:$PORT"
    exit 0
else
    echo "FAIL $HOST:$PORT"
    exit 1
fi
