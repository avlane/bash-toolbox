#!/usr/bin/env bash
# retry.sh - run a command again until it succeeds, backing off between tries
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: retry.sh [-t TRIES] [-d DELAY] [-m MAXDELAY] [-j] [-r CODES] [--] COMMAND [ARGS...]

Run COMMAND until it exits 0. After each failure wait DELAY seconds, doubling
the wait every time up to MAXDELAY. Exits 0 on success, or with the exit status
of the last attempt once TRIES attempts have failed.

options:
  -t TRIES     maximum attempts (default 5)
  -d DELAY     first delay in seconds (default 1)
  -m MAXDELAY  upper bound for the delay (default 60)
  -j           add random jitter of up to half the delay, so many clients
               retrying together do not all hit the server at the same moment
  -r CODES     only retry when the exit status is one of CODES (comma
               separated, for example 1,75); any other status ends the run
               immediately with that status
  -h, --help   show this help

Set TB_SLEEP to a different command to replace sleep (used by the tests).
USAGE
}

tb_handle_help usage "$@"

tries=5
delay=1
maxdelay=60
jitter=0
retry_codes=
while getopts ':t:d:m:jr:h' opt; do
    case $opt in
        t) tries=$OPTARG ;;
        d) delay=$OPTARG ;;
        m) maxdelay=$OPTARG ;;
        j) jitter=1 ;;
        r) retry_codes=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -ge 1 ]] || tb_usage_error "no command given"
for n in "$tries" "$delay" "$maxdelay"; do
    [[ $n =~ ^[0-9]+$ ]] || tb_usage_error "TRIES, DELAY and MAXDELAY must be whole numbers"
done

[[ -z $retry_codes || $retry_codes =~ ^[0-9]+(,[0-9]+)*$ ]] || tb_usage_error "-r needs a comma separated list of exit codes"

attempt=1
started=$(tb_now)
while true; do
    if "$@"; then
        if (( attempt > 1 )); then
            tb_log "succeeded on attempt $attempt after $(( $(tb_now) - started ))s"
        fi
        exit 0
    else
        status=$?
    fi
    if [[ -n $retry_codes && ,$retry_codes, != *,$status,* ]]; then
        tb_log "exit status $status is not in the retry list, not retrying"
        exit "$status"
    fi
    if (( attempt >= tries )); then
        tb_log "giving up after $attempt attempt(s), last exit status $status"
        exit "$status"
    fi
    tb_log "attempt $attempt failed (status $status), retrying in ${delay}s"
    wait_for=$delay
    if (( jitter )); then
        wait_for=$(( delay + RANDOM % (delay / 2 + 1) ))
    fi
    ${TB_SLEEP:-sleep} "$wait_for"
    delay=$((delay * 2))
    (( delay > maxdelay )) && delay=$maxdelay
    attempt=$((attempt + 1))
done
