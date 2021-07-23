#!/usr/bin/env bash
# tail-logs.sh - follow several log files at once, with a prefix per file
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: tail-logs.sh [-n LINES] [-g PATTERN] [-c] [-F] FILE...

Show the last LINES lines (default 10) of every FILE and keep following them,
prefixing each line with the file's base name.

options:
  -n LINES    lines of history to show first (default 10)
  -g PATTERN  only show lines matching the extended regular expression PATTERN
  -c          colour the prefixes (only when writing to a terminal)
  -F          follow by name, so rotated or recreated files keep being read
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

lines=10
pattern=
color=0
follow=-f
while getopts ':n:g:cFh' opt; do
    case $opt in
        n) lines=$OPTARG ;;
        g) pattern=$OPTARG ;;
        c) color=1 ;;
        F) follow=-F ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $lines =~ ^[0-9]+$ ]] || tb_usage_error "-n needs a number"
[[ $# -ge 1 ]] || tb_usage_error "no files given"

[[ -t 1 ]] || color=0
palette=(31 32 33 34 35 36)

pids=()
cleanup() {
    if [[ ${#pids[@]} -gt 0 ]]; then
        kill "${pids[@]}" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

i=0
for f in "$@"; do
    name=$(basename "$f")
    prefix="[$name]"
    if (( color )); then
        prefix=$'\033'"[${palette[i % ${#palette[@]}]}m[$name]"$'\033[0m'
    fi
    # tail itself is the background job, so $! is tail's pid and killing it
    # closes the pipe and ends the filters; with "tail | sed &" $! would be sed's
    # and an idle tail -f would never notice
    if [[ -n $pattern ]]; then
        tail -n "$lines" "$follow" "$f" > >(grep --line-buffered -E -- "$pattern" | sed -u "s|^|$prefix |") &
    else
        tail -n "$lines" "$follow" "$f" > >(sed -u "s|^|$prefix |") &
    fi
    pids+=($!)
    i=$((i + 1))
done
wait
