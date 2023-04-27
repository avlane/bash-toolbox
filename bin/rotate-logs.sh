#!/usr/bin/env bash
# rotate-logs.sh - number-based log rotation (copy, then truncate in place)
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: rotate-logs.sh [-k KEEP] [-s SIZE] [-a DAYS] [-z gzip|xz] [-n] FILE...

Rotate each FILE: FILE.1 becomes FILE.2, and so on, FILE is copied to FILE.1
and then emptied in place so a process that holds it open keeps writing to the
same file. At most KEEP old copies are kept (default 5). Files that are empty
or missing are skipped.

options:
  -k KEEP     number of rotated copies to keep (default 5)
  -s SIZE     only rotate files of at least SIZE bytes (suffixes K, M, G allowed)
  -a DAYS     only rotate if the newest rotated copy is at least DAYS days old
              (or there is none); with -s too, both conditions must hold
  -z TOOL     compress rotated copies with gzip or xz (FILE.1.gz, FILE.1.xz)
  -n          dry run
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

keep=5
dry=0
min_size=0
min_age=
compress=
while getopts ':k:s:a:z:nh' opt; do
    case $opt in
        k) keep=$OPTARG ;;
        s) min_size=$OPTARG ;;
        a) min_age=$OPTARG ;;
        z) compress=$OPTARG ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $keep =~ ^[1-9][0-9]*$ ]] || tb_usage_error "-k needs a positive number"
[[ $# -ge 1 ]] || tb_usage_error "no files given"
[[ -z $min_age || $min_age =~ ^[0-9]+$ ]] || tb_usage_error "-a needs a number of days"
case $compress in
    ''|gzip|xz) ;;
    *) tb_usage_error "-z must be gzip or xz" ;;
esac
size_re='^([0-9]+)([KMG]?)$'
[[ $min_size =~ $size_re ]] || tb_usage_error "-s needs a size such as 500000, 64K or 10M"
min_size=${BASH_REMATCH[1]}
case ${BASH_REMATCH[2]} in
    K) min_size=$((min_size * 1024)) ;;
    M) min_size=$((min_size * 1024 * 1024)) ;;
    G) min_size=$((min_size * 1024 * 1024 * 1024)) ;;
esac
[[ -z $compress ]] || tb_require_cmd "$compress"

# recently_rotated FILE - true if FILE.1 (in any compressed form) is newer than -a DAYS
recently_rotated() {
    local f=$1 base found
    base=$(basename "$f")
    found=$(find "$(dirname "$f")" -maxdepth 1 \( -name "$base.1" -o -name "$base.1.gz" -o -name "$base.1.xz" \) -mtime "-$min_age" | head -n 1)
    [[ -n $found ]]
}

rotate_one() {
    local f=$1 i ext
    if [[ ! -s $f ]]; then
        tb_log "skipping $f (missing or empty)"
        return 0
    fi
    if (( $(wc -c < "$f") < min_size )); then
        tb_log "skipping $f (smaller than the -s limit)"
        return 0
    fi
    if [[ -n $min_age ]] && recently_rotated "$f"; then
        tb_log "skipping $f (rotated less than $min_age days ago)"
        return 0
    fi
    if (( dry )); then
        echo "would rotate $f"
        return 0
    fi
    rm -f -- "$f.$keep" "$f.$keep.gz" "$f.$keep.xz"
    # shift from the highest number down, otherwise each mv overwrites the next
    i=$((keep - 1))
    while (( i >= 1 )); do
        for ext in "" .gz .xz; do
            if [[ -e $f.$i$ext ]]; then
                mv -- "$f.$i$ext" "$f.$((i + 1))$ext"
            fi
        done
        i=$((i - 1))
    done
    cp -p -- "$f" "$f.1"
    : > "$f"
    if [[ -n $compress ]]; then
        "$compress" -f -- "$f.1"
    fi
    echo "rotated $f"
}

for file in "$@"; do
    rotate_one "$file"
done
