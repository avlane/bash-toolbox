#!/bin/bash
# git-stale-branches.sh - list local branches with no commits for N days
# usage: git-stale-branches.sh [DAYS] [REPO]

DAYS=${1:-90}
REPO=${2:-.}

cd "$REPO" || exit 1

limit=`date -v-${DAYS}d +%s 2>/dev/null || date -d "$DAYS days ago" +%s`

git for-each-ref --format='%(committerdate:unix) %(refname:short)' refs/heads |
while read ts name; do
    if [ "$ts" -lt "$limit" ]; then
        echo "$name (last commit `date -r $ts +%Y-%m-%d 2>/dev/null || date -d @$ts +%Y-%m-%d`)"
    fi
done
