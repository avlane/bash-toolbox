#!/usr/bin/env bash
# git-stale-branches.sh - report local branches nobody has touched for a while
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: git-stale-branches.sh [-d DAYS] [-m BASE] [-i GLOB]... [-s] [-C] [REPO]

List local branches whose last commit is at least DAYS days old (default 90),
oldest first, as "date  author  branch". The current branch is never listed.

options:
  -d DAYS     age threshold in days
  -m BASE     only branches already merged into BASE (for example main)
  -i GLOB     never list branches matching GLOB (repeatable), for example
              -i 'release/*' -i develop
  -C          print CSV (date,author,branch with a header row) instead of text
  -s          also print a count of stale branches per author
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

days=90
base=
summary=0
csv=0
ignore=()
while getopts ':d:m:i:sCh' opt; do
    case $opt in
        d) days=$OPTARG ;;
        m) base=$OPTARG ;;
        s) summary=1 ;;
        i) ignore+=("$OPTARG") ;;
        C) csv=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $days =~ ^[0-9]+$ ]] || tb_usage_error "-d needs a number"
repo=${1:-.}
tb_require_cmd git
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || tb_die "$repo is not a git repository"

limit=$(( $(tb_now) - days * 86400 ))
current=$(git -C "$repo" symbolic-ref --quiet --short HEAD || true)

args=(for-each-ref --sort=committerdate --format='%(committerdate:unix)|%(committerdate:short)|%(authorname)|%(refname:short)' refs/heads)
if [[ -n $base ]]; then
    git -C "$repo" rev-parse --verify --quiet "$base" >/dev/null || tb_die "unknown base: $base"
    args+=(--merged "$base")
fi

tb_readlines rows < <(git -C "$repo" "${args[@]}")

# csv_field TEXT - quote a CSV field when it needs it (RFC 4180)
csv_field() {
    local f=$1
    if [[ $f == *[,\"]* ]]; then
        f=${f//\"/\"\"}
        printf '"%s"' "$f"
    else
        printf '%s' "$f"
    fi
}

ignored() {
    local pat
    for pat in ${ignore[@]+"${ignore[@]}"}; do
        # shellcheck disable=SC2254  # the unquoted pattern is the point
        case $1 in $pat) return 0 ;; esac
    done
    return 1
}

(( ! csv )) || echo "date,author,branch"

authors=()
for row in ${rows[@]+"${rows[@]}"}; do
    IFS='|' read -r ts date author name <<< "$row"
    [[ $name != "$current" ]] || continue
    (( ts <= limit )) || continue
    ! ignored "$name" || continue
    if (( csv )); then
        echo "$date,$(csv_field "$author"),$(csv_field "$name")"
    else
        printf '%s  %s  %s\n' "$date" "$author" "$name"
    fi
    authors+=("$author")
done

if (( summary && ! csv && ${#authors[@]} > 0 )); then
    echo
    echo "stale branches per author:"
    printf '%s\n' "${authors[@]}" | sort | uniq -c | sort -rn | sed 's/^ */  /'
fi
