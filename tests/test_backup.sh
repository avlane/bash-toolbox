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

run_tests
