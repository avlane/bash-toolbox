#!/usr/bin/env bash
# git-maint.sh - routine housekeeping for a git repository
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: git-maint.sh [-n] [-a] [-g] [REPO]
       git-maint.sh [-n] [-a] [-g] -r DIR

Housekeeping for REPO (default: current directory):
  1. git remote prune <remote>   for every remote (forgets deleted branches)
  2. git worktree prune
  3. git reflog expire --expire=90.days.ago --all
  4. git gc --auto               (or, with -a, git gc --prune=2.weeks.ago)
  5. with -g: git commit-graph write --reachable   (speeds up log and merge-base
     queries on big repositories; skipped with a note on git older than 2.18)

With -r, DIR is searched for repositories (directories containing .git, not
looking inside them) and each one is maintained; a table of .git sizes before
and after is printed at the end.

options:
  -r DIR      maintain every repository below DIR
  -g          also write the commit-graph file
  -a          run a full gc instead of gc --auto
  -n          dry run: print the commands without running them
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

dry=0
full=0
graph=0
root=
while getopts ':agnr:h' opt; do
    case $opt in
        a) full=1 ;;
        g) graph=1 ;;
        n) dry=1 ;;
        r) root=$OPTARG ;;
        h) usage; exit 0 ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

tb_require_cmd git

run() {
    echo "+ $(tb_quote_args "$@")"
    if (( ! dry )); then
        "$@"
    fi
}

# git_at_least MAJOR MINOR - true if the installed git is at least that version.
# "git version 2.39.5 (Apple Git-154)" and "git version 2.43.0" both parse.
git_at_least() {
    local v re='([0-9]+)\.([0-9]+)'
    v=$(git --version)
    [[ $v =~ $re ]] || return 1
    (( BASH_REMATCH[1] > $1 || (BASH_REMATCH[1] == $1 && BASH_REMATCH[2] >= $2) ))
}

# git_kib REPO - size of the repository's .git in KiB
git_kib() {
    du -sk "$1/.git" 2>/dev/null | awk '{print $1}'
}

maintain() {
    local repo=$1 remote
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
    if (( graph )); then
        if git_at_least 2 18; then
            run git -C "$repo" commit-graph write --reachable
        else
            tb_warn "git is older than 2.18, skipping the commit-graph step"
        fi
    fi
}

if [[ -n $root ]]; then
    [[ $# -eq 0 ]] || tb_usage_error "-r takes the place of REPO"
    [[ -d $root ]] || tb_die "$root is not a directory"
    tb_readlines repos < <(find "$root" -name .git -type d -prune | sed 's|/\.git$||' | sort)
    [[ ${#repos[@]} -gt 0 ]] || tb_die "no repositories found below $root"
    summary=()
    for repo in "${repos[@]}"; do
        echo "== $repo"
        before=$(git_kib "$repo")
        maintain "$repo"
        summary+=("$(printf '%8s -> %8s KiB  %s' "$before" "$(git_kib "$repo")" "$repo")")
    done
    echo
    echo "   before ->    after       repository"
    printf '%s\n' "${summary[@]}"
else
    repo=${1:-.}
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || tb_die "$repo is not a git repository"
    maintain "$repo"
fi
