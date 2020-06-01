#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gitmaint-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

git init -q "$WORK/repo"
git -C "$WORK/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first

test_dry_run_lists_commands() {
    out=$("$ROOT/bin/git-maint.sh" -n "$WORK/repo")
    case $out in
        *"gc --auto"*) assert_eq 1 1 "dry run mentions gc" ;;
        *) assert_eq "gc --auto" "$out" "dry run mentions gc" ;;
    esac
}

test_runs_on_a_real_repo() {
    assert_status 0 "maintenance succeeds" "$ROOT/bin/git-maint.sh" "$WORK/repo"
    assert_status 0 "full gc succeeds" "$ROOT/bin/git-maint.sh" -a "$WORK/repo"
}

test_rejects_non_repo() {
    mkdir -p "$WORK/plain"
    assert_status 1 "plain directory is rejected" "$ROOT/bin/git-maint.sh" "$WORK/plain"
}

run_tests
