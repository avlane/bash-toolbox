#!/usr/bin/env bash
# git-maint.sh - routine housekeeping for a git repository
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: git-maint.sh [-n] [-a] [REPO]

Housekeeping for REPO (default: current directory):
  1. git remote prune <remote>   for every remote (forgets deleted branches)
  2. git worktree prune
  3. git reflog expire --expire=90.days.ago --all
  4. git gc --auto               (or, with -a, git gc --prune=2.weeks.ago)

options:
  -a          run a full gc instead of gc --auto
  -n          dry run: print the commands without running them
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

dry=0
full=0
while getopts ':anh' opt; do
    case $opt in
        a) full=1 ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

repo=${1:-.}
tb_require_cmd git
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || tb_die "$repo is not a git repository"

run() {
    echo "+ $*"
    if (( ! dry )); then
        "$@"
    fi
}

for remote in $(git -C "$repo" remote); do
    run git -C "$repo" remote prune "$remote"
done
run git -C "$repo" worktree prune
run git -C "$repo" reflog expire --expire=90.days.ago --all
if (( full )); then
    run git -C "$repo" gc --prune=2.weeks.ago
else
    run git -C "$repo" gc --auto
fi
