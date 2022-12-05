#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rotbak-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

RB="$ROOT/bin/rotate-backups.sh"

make_files() {   # make_files DIR : two old files, one new, one other type
    mkdir -p "$1"
    touch -t 201901010000 "$1/old one.tar.gz" "$1/old-two.tar.gz" "$1/old.sql"
    touch "$1/new.tar.gz"
}

test_removes_old_matching_files_only() {
    make_files "$WORK/a"
    "$RB" "$WORK/a" 30 >/dev/null
    assert_eq "new.tar.gz
old.sql" "$(ls "$WORK/a")" "old archives gone, new archive and other types kept"
}

test_pattern_option() {
    make_files "$WORK/b"
    touch -t 201901010000 "$WORK/b/older.sql"
    touch "$WORK/b/new.sql"
    "$RB" -p '*.sql' "$WORK/b" 30 >/dev/null 2>&1
    assert_eq "new.sql" "$(ls "$WORK/b" | grep '\.sql$')" "old .sql files rotated, archives untouched"
    assert_eq "3" "$(ls "$WORK/b" | grep -c 'tar.gz')" "all archives kept"
}

test_dry_run() {
    make_files "$WORK/c"
    out=$("$RB" -n "$WORK/c" 30)
    assert_eq "4" "$(ls "$WORK/c" | wc -l | tr -d ' ')" "nothing deleted"
    assert_eq "2" "$(echo "$out" | grep -c '^would remove ')" "two reported"
}

test_never_removes_the_last_match() {
    mkdir -p "$WORK/d"
    touch -t 201901010000 "$WORK/d/only.tar.gz"
    "$RB" "$WORK/d" 1 >/dev/null 2>&1
    assert_file_exists "$WORK/d/only.tar.gz" "the only archive is kept"
}

test_usage_errors() {
    assert_status 2 "missing args" "$RB" "$WORK"
    assert_status 2 "non numeric days" "$RB" "$WORK" soon
    assert_status 1 "not a directory" "$RB" "$WORK/nope" 3
}

run_tests
