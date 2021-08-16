#!/usr/bin/env bash
# saferm.sh - move files to a trash directory instead of deleting them
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: saferm.sh [-n] [-v] FILE...
       saferm.sh -P DAYS

Move each FILE (or directory) into the trash directory, $SAFERM_TRASH or
~/.saferm-trash, as NAME.EPOCHSECONDS. Nothing is ever deleted by the first
form, so a mistake can be undone with mv.

options:
  -P DAYS     permanently delete trash entries older than DAYS days
  -n          dry run
  -v          say what was moved
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

trash=${SAFERM_TRASH:-$HOME/.saferm-trash}
dry=0
verbose=0
purge=
while getopts ':P:nvh' opt; do
    case $opt in
        P) purge=$OPTARG ;;
        n) dry=1 ;;
        v) verbose=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

if [[ -n $purge ]]; then
    [[ $purge =~ ^[0-9]+$ ]] || tb_usage_error "-P needs a number of days"
    [[ $# -eq 0 ]] || tb_usage_error "-P does not take file names"
    [[ -d $trash ]] || exit 0
    cutoff=$(( $(tb_now) - purge * 86400 ))
    for entry in "$trash"/*; do
        [[ -e $entry || -L $entry ]] || continue
        stamp=${entry##*.}
        [[ $stamp =~ ^[0-9]+$ ]] || continue
        if (( stamp < cutoff )); then
            if (( dry )); then
                echo "would delete $entry"
            else
                rm -rf -- "$entry"
                echo "deleted $entry"
            fi
        fi
    done
    exit 0
fi

[[ $# -ge 1 ]] || tb_usage_error "no files given"
(( dry )) || mkdir -p "$trash"

status=0
for f in "$@"; do
    if [[ ! -e $f && ! -L $f ]]; then
        tb_warn "$f: no such file"
        status=1
        continue
    fi
    target="$trash/$(basename "$f").$(tb_now)"
    if (( dry )); then
        echo "would move $f to $target"
        continue
    fi
    mv -- "$f" "$target"
    if (( verbose )); then
        echo "moved $f to $target"
    fi
done
exit $status
