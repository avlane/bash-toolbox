#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/stale-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

repo="$WORK/repo"
git init -q -b main "$repo"
commit_at() {   # commit_at DATE AUTHOR MESSAGE
    GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$repo" \
        -c user.name="$2" -c user.email="$2@example.com" commit -q --allow-empty -m "$3"
}
commit_at "2020-01-01T12:00:00" ann "base"
git -C "$repo" branch old-merged
git -C "$repo" checkout -q -b old-unmerged
commit_at "2020-02-01T12:00:00" bob "old work"
git -C "$repo" checkout -q main
git -C "$repo" checkout -q -b fresh
commit_at "$(date +%Y-%m-%dT%H:%M:%S)" cy "recent work"
git -C "$repo" checkout -q main

test_lists_old_branches_oldest_first() {
    out=$("$ROOT/bin/git-stale-branches.sh" -d 30 "$repo")
    assert_eq "2020-01-01  ann  old-merged
2020-02-01  bob  old-unmerged" "$out" "stale branches, not the fresh one or the current one"
}

test_current_branch_is_skipped() {
    git -C "$repo" checkout -q old-unmerged
    out=$("$ROOT/bin/git-stale-branches.sh" -d 30 "$repo")
    git -C "$repo" checkout -q main
    case $out in
        *old-unmerged*) assert_eq "not listed" "listed" "current branch is skipped" ;;
        *) assert_eq 1 1 "current branch is skipped" ;;
    esac
}

test_merged_only() {
    out=$("$ROOT/bin/git-stale-branches.sh" -d 30 -m main "$repo")
    assert_eq "2020-01-01  ann  old-merged" "$out" "only the merged branch"
}

test_author_summary() {
    out=$("$ROOT/bin/git-stale-branches.sh" -d 30 -s "$repo")
    case $out in
        *"stale branches per author:"*"  1 ann"*"  1 bob"*|*"stale branches per author:"*"  1 bob"*"  1 ann"*)
            assert_eq 1 1 "per-author counts" ;;
        *) assert_eq "1 ann, 1 bob" "$out" "per-author counts" ;;
    esac
}

test_not_a_repo() {
    assert_status 1 "plain directory" "$ROOT/bin/git-stale-branches.sh" "$WORK"
}

run_tests
