#!/usr/bin/env bash
# saferm.sh - move files to a trash directory instead of deleting them
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: saferm.sh [-n] [-v] FILE...
       saferm.sh -P DAYS
       saferm.sh -l
       saferm.sh [-n] -R NAME

Move each FILE (or directory) into the trash directory, $SAFERM_TRASH or
~/.saferm-trash, as NAME.EPOCHSECONDS (plus .N if that name is taken). Nothing is ever deleted by the first
form, so a mistake can be undone with mv.

  -l lists what is in the trash (age in days, original name, trash entry), and
  -R NAME puts the newest trashed item called NAME back into the current
  directory, refusing to overwrite anything.

options:
  -l          list the trash
  -R NAME     restore the newest trash entry for NAME here
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
list=0
restore=
while getopts ':P:lR:nvh' opt; do
    case $opt in
        P) purge=$OPTARG ;;
        l) list=1 ;;
        R) restore=$OPTARG ;;
        n) dry=1 ;;
        v) verbose=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

# NAME.EPOCHSECONDS, with an optional .N added when that name was taken
stamp_re='\.([0-9]{9,})(\.[0-9]+)?$'

if (( list )); then
    [[ $# -eq 0 ]] || tb_usage_error "-l does not take file names"
    [[ -d $trash ]] || exit 0
    now=$(tb_now)
    for entry in "$trash"/*; do
        [[ -e $entry || -L $entry ]] || continue
        base=$(basename "$entry")
        if [[ $base =~ $stamp_re ]]; then
            printf '%5s days  %s  (%s)\n' $(( (now - BASH_REMATCH[1]) / 86400 )) "${base%"${BASH_REMATCH[0]}"}" "$entry"
        else
            printf '    ? days  %s  (%s)\n' "$base" "$entry"
        fi
    done
    exit 0
fi

if [[ -n $restore ]]; then
    [[ $# -eq 0 ]] || tb_usage_error "-R takes one NAME and no file names"
    [[ $restore != */* ]] || tb_usage_error "-R takes a plain name, not a path"
    best=
    best_stamp=-1
    for entry in "$trash/$restore".*; do
        [[ -e $entry || -L $entry ]] || continue
        base=$(basename "$entry")
        [[ $base =~ $stamp_re ]] || continue
        [[ ${base%"${BASH_REMATCH[0]}"} == "$restore" ]] || continue
        # newest first; of two entries from the same second the later suffix wins
        order=$(( ${BASH_REMATCH[1]} * 1000 + 10#0${BASH_REMATCH[2]#.} ))
        if (( order > best_stamp )); then
            best=$entry
            best_stamp=$order
        fi
    done
    [[ -n $best ]] || tb_die "nothing called $restore in the trash"
    [[ ! -e $restore && ! -L $restore ]] || tb_die "$restore already exists here, not overwriting it"
    if (( dry )); then
        echo "would restore $best as $restore"
    else
        mv -- "$best" "$restore"
        echo "restored $restore"
    fi
    exit 0
fi

if [[ -n $purge ]]; then
    [[ $purge =~ ^[0-9]+$ ]] || tb_usage_error "-P needs a number of days"
    [[ $# -eq 0 ]] || tb_usage_error "-P does not take file names"
    [[ -d $trash ]] || exit 0
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
