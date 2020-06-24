#!/usr/bin/env bash
# rotate-logs.sh - number-based log rotation (copy, then truncate in place)
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: rotate-logs.sh [-k KEEP] [-n] FILE...

Rotate each FILE: FILE.1 becomes FILE.2, and so on, FILE is copied to FILE.1
and then emptied in place so a process that holds it open keeps writing to the
same file. At most KEEP old copies are kept (default 5). Files that are empty
or missing are skipped.

options:
  -k KEEP     number of rotated copies to keep (default 5)
  -n          dry run
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

keep=5
dry=0
while getopts ':k:nh' opt; do
    case $opt in
        k) keep=$OPTARG ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $keep =~ ^[1-9][0-9]*$ ]] || tb_usage_error "-k needs a positive number"
[[ $# -ge 1 ]] || tb_usage_error "no files given"

rotate_one() {
    local f=$1 i
    if [[ ! -s $f ]]; then
        tb_log "skipping $f (missing or empty)"
        return 0
    fi
    if (( dry )); then
        echo "would rotate $f"
        return 0
    fi
    rm -f -- "$f.$keep"
    # shift from the highest number down, otherwise each mv overwrites the next
    i=$((keep - 1))
    while (( i >= 1 )); do
        if [[ -e $f.$i ]]; then
            mv -- "$f.$i" "$f.$((i + 1))"
        fi
        i=$((i - 1))
    done
    cp -p -- "$f" "$f.1"
    : > "$f"
    echo "rotated $f"
}

for file in "$@"; do
    rotate_one "$file"
done
