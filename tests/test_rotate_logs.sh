#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rotlog-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

test_shifts_existing_copies() {
    f="$WORK/app.log"
    echo new > "$f"; echo one > "$f.1"; echo two > "$f.2"; echo three > "$f.3"
    "$ROOT/bin/rotate-logs.sh" -k 4 "$f" >/dev/null
    assert_eq "" "$(cat "$f")" "live file is emptied"
    assert_eq "new" "$(cat "$f.1")" ".1 is the old live file"
    assert_eq "one" "$(cat "$f.2")" ".2 is the old .1"
    assert_eq "two" "$(cat "$f.3")" ".3 is the old .2"
    assert_eq "three" "$(cat "$f.4")" ".4 is the old .3"
}

test_drops_oldest_beyond_keep() {
    f="$WORK/keep.log"
    echo new > "$f"; echo one > "$f.1"; echo two > "$f.2"
    "$ROOT/bin/rotate-logs.sh" -k 2 "$f" >/dev/null
    assert_eq "new" "$(cat "$f.1")" ".1 is the old live file"
    assert_eq "one" "$(cat "$f.2")" ".2 is the old .1"
    assert_eq "no" "$([ -e "$f.3" ] && echo yes || echo no)" "nothing beyond KEEP"
}

test_skips_empty_and_missing() {
    : > "$WORK/empty.log"
    assert_status 0 "empty and missing files are skipped" "$ROOT/bin/rotate-logs.sh" "$WORK/empty.log" "$WORK/gone.log"
    assert_eq "no" "$([ -e "$WORK/empty.log.1" ] && echo yes || echo no)" "no copy of empty file"
}

test_dry_run() {
    f="$WORK/dry.log"; echo data > "$f"
    "$ROOT/bin/rotate-logs.sh" -n "$f" >/dev/null
    assert_eq "data" "$(cat "$f")" "dry run leaves the file alone"
}

run_tests
