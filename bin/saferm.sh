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
~/.saferm-trash, as NAME.EPOCHSECONDS (plus .N if that name is taken). Nothing is ever deleted by the first
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
    # NAME.EPOCHSECONDS, with an optional .N added when that name was taken
    stamp_re='\.([0-9]{9,})(\.[0-9]+)?$'
    cutoff=$(( $(tb_now) - purge * 86400 ))
    for entry in "$trash"/*; do
        [[ -e $entry || -L $entry ]] || continue
        [[ $entry =~ $stamp_re ]] || continue
        stamp=${BASH_REMATCH[1]}
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

# abs_path PATH - physical absolute path of an existing PATH (a final symlink is not followed)
abs_path() {
    local p=$1 dir base
    if [[ -d $p && ! -L $p ]]; then
        (cd "$p" && pwd -P)
        return
    fi
    dir=$(cd "$(dirname "$p")" && pwd -P)
    base=$(basename "$p")
    if [[ $dir == / ]]; then printf '/%s\n' "$base"; else printf '%s/%s\n' "$dir" "$base"; fi
}

home_real=$(cd "$HOME" && pwd -P)
if [[ -d $trash ]]; then trash_real=$(cd "$trash" && pwd -P); else trash_real=$trash; fi

# protected_reason ABS_PATH - say why a path must never be trashed (empty if it is fine)
protected_reason() {
    if [[ $1 == / ]]; then
        echo "it is the root directory"
    elif [[ $1 == "$home_real" ]]; then
        echo "it is your home directory"
    elif [[ $1 == "$trash_real" || $trash_real == "$1"/* ]]; then
        echo "it is, or contains, the trash directory"
    fi
}

status=0
for f in "$@"; do
    if [[ ! -e $f && ! -L $f ]]; then
        tb_warn "$f: no such file"
        status=1
        continue
    fi
    reason=$(protected_reason "$(abs_path "$f")")
    if [[ -n $reason ]]; then
        tb_warn "refusing to trash $f: $reason"
        status=1
        continue
    fi
    target="$trash/$(basename "$f").$(tb_now)"
    n=1
    while [[ -e $target || -L $target ]]; do
        target="$trash/$(basename "$f").$(tb_now).$n"
        n=$((n + 1))
    done
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
