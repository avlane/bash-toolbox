#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gitmaint-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

git init -q "$WORK/repo"
git -C "$WORK/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first

test_dry_run_lists_commands() {
    out=$("$ROOT/bin/git-maint.sh" -n "$WORK/repo")
    assert_contains "$out" "gc --auto" "dry run mentions gc"
}

test_runs_on_a_real_repo() {
    assert_status 0 "maintenance succeeds" "$ROOT/bin/git-maint.sh" "$WORK/repo"
    assert_status 0 "full gc succeeds" "$ROOT/bin/git-maint.sh" -a "$WORK/repo"
}

test_rejects_non_repo() {
    mkdir -p "$WORK/plain"
    assert_status 1 "plain directory is rejected" "$ROOT/bin/git-maint.sh" "$WORK/plain"
}

test_recursive_mode() {
    mkdir -p "$WORK/tree/a" "$WORK/tree/deep/b"
    git init -q "$WORK/tree/a"
    git init -q "$WORK/tree/deep/b"
    mkdir -p "$WORK/tree/notarepo"
    out=$("$ROOT/bin/git-maint.sh" -r "$WORK/tree")
    assert_eq "2" "$(echo "$out" | grep -c '^== ')" "two repositories found"
    case $out in
        *"before ->"*"KiB  $WORK/tree/a"*"KiB  $WORK/tree/deep/b"*) assert_eq 1 1 "summary table lists both" ;;
        *) assert_eq "table with both repos" "$out" "summary table lists both" ;;
    esac
}

test_recursive_mode_needs_repositories() {
    mkdir -p "$WORK/empty"
    assert_status 1 "no repositories" "$ROOT/bin/git-maint.sh" -r "$WORK/empty"
}

run_tests
