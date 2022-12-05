#!/usr/bin/env bash
# rotate-backups.sh - delete old backup files from a directory
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: rotate-backups.sh [-n] [-p PATTERN] DIR DAYS

Delete files in DIR (not in sub-directories) that match PATTERN and are older
than DAYS days. PATTERN is a shell glob, default '*.tar.gz'. At least one file
that matches is always kept, even if it is old, so a stalled backup job cannot
silently empty the directory.

options:
  -p PATTERN  file name glob to rotate (quote it so your shell does not expand it)
  -n          dry run: list what would be deleted
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

pattern='*.tar.gz'
dry=0
while getopts ':p:nh' opt; do
    case $opt in
        p) pattern=$OPTARG ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 2 ]] || tb_usage_error "expected DIR and DAYS"
dir=$1
days=$2
[[ -d $dir ]] || tb_die "$dir is not a directory"
[[ $days =~ ^[0-9]+$ ]] || tb_usage_error "DAYS must be a whole number"

total=$(find "$dir" -maxdepth 1 -type f -name "$pattern" | wc -l | tr -d ' ')

removed=0
# -print0 and read -d '' keep odd file names intact
while IFS= read -r -d '' f; do
    if (( total - removed <= 1 )); then
        tb_warn "keeping $f, it is the last matching file"
        break
    fi
    if (( dry )); then
        echo "would remove $f"
    else
        rm -f -- "$f"
        echo "removed $f"
    fi
    removed=$((removed + 1))
done < <(find "$dir" -maxdepth 1 -type f -name "$pattern" -mtime "+$days" -print0)
