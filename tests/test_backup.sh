#!/bin/bash
. "`dirname "$0"`/harness.sh"

ROOT=`cd "\`dirname "$0"\`/.." && pwd`
WORK=`mktemp -d "${TMPDIR:-/tmp}/backup-test.XXXXXX"`
trap 'rm -rf "$WORK"' EXIT

test_creates_archive() {
    mkdir -p "$WORK/src/data"
    echo one > "$WORK/src/data/one.txt"
    out=`"$ROOT/bin/backup.sh" "$WORK/src/data" "$WORK/dest"`
    archive=`echo "$out" | sed 's/^wrote //'`
    assert_file_exists "$archive" "archive exists"
    assert_eq "data/one.txt" "`tar -tzf "$archive" | grep one.txt`" "archive lists the file"
}

test_missing_source_fails() {
    assert_status 1 "missing source dir" "$ROOT/bin/backup.sh" "$WORK/nope" "$WORK/dest"
}

test_usage() {
    assert_status 2 "wrong arg count" "$ROOT/bin/backup.sh" onlyone
}

test_exclude_pattern() {
    mkdir -p "$WORK/ex/proj"
    echo keep > "$WORK/ex/proj/keep.txt"
    echo skip > "$WORK/ex/proj/skip.log"
    out=$("$ROOT/bin/backup.sh" -x '*.log' "$WORK/ex/proj" "$WORK/exdest")
    archive=${out#wrote }
    assert_eq "proj/keep.txt" "$(tar -tzf "$archive" | grep -v '/$')" "only keep.txt archived"
}

test_dry_run_writes_nothing() {
    mkdir -p "$WORK/dr/proj"
    out=$("$ROOT/bin/backup.sh" -n "$WORK/dr/proj" "$WORK/drdest")
    assert_eq "no" "$([ -e "$WORK/drdest" ] && echo yes || echo no)" "dest not created"
    assert_eq "would write" "${out%% $WORK*}" "reports what it would do"
}

test_help() {
    assert_status 0 "--help exits 0" "$ROOT/bin/backup.sh" --help
}

run_tests
