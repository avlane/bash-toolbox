#!/usr/bin/env bash
# git-stale-branches.sh - report local branches nobody has touched for a while
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: git-stale-branches.sh [-d DAYS] [-m BASE] [-s] [REPO]

List local branches whose last commit is at least DAYS days old (default 90),
oldest first, as "date  author  branch". The current branch is never listed.

options:
  -d DAYS     age threshold in days
  -m BASE     only branches already merged into BASE (for example main)
  -s          also print a count of stale branches per author
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

days=90
base=
summary=0
while getopts ':d:m:sh' opt; do
    case $opt in
        d) days=$OPTARG ;;
        m) base=$OPTARG ;;
        s) summary=1 ;;
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

authors=()
for row in ${rows[@]+"${rows[@]}"}; do
    IFS='|' read -r ts date author name <<< "$row"
    [[ $name != "$current" ]] || continue
    (( ts <= limit )) || continue
    printf '%s  %s  %s\n' "$date" "$author" "$name"
    authors+=("$author")
done

if (( summary && ${#authors[@]} > 0 )); then
    echo
    echo "stale branches per author:"
    printf '%s\n' "${authors[@]}" | sort | uniq -c | sort -rn | sed 's/^ */  /'
fi
