#!/bin/bash
. "`dirname "$0"`/harness.sh"

ROOT=`cd "\`dirname "$0"\`/.." && pwd`
WORK=`mktemp -d "${TMPDIR:-/tmp}/saferm-test.XXXXXX"`
trap 'rm -rf "$WORK"' EXIT
export SAFERM_TRASH="$WORK/trash"

test_moves_file_to_trash() {
    rm -rf "$SAFERM_TRASH"
    echo hi > "$WORK/a.txt"
    "$ROOT/bin/saferm.sh" "$WORK/a.txt" >/dev/null
    assert_eq "no" "`[ -e "$WORK/a.txt" ] && echo yes || echo no`" "original is gone"
    assert_eq "1" "`ls "$SAFERM_TRASH" | wc -l | tr -d ' '`" "one item in trash"
}

test_handles_spaces() {
    echo hi > "$WORK/my notes.txt"
    "$ROOT/bin/saferm.sh" "$WORK/my notes.txt" >/dev/null
    assert_eq "no" "`[ -e "$WORK/my notes.txt" ] && echo yes || echo no`" "spaced file is gone"
}

test_usage_error() {
    assert_status 2 "no arguments is a usage error" "$ROOT/bin/saferm.sh"
}

test_purge_old_entries_only() {
    rm -rf "$SAFERM_TRASH"; mkdir -p "$SAFERM_TRASH"
    now=$(date +%s)
    echo old > "$SAFERM_TRASH/old.txt.$((now - 40 * 86400))"
    echo new > "$SAFERM_TRASH/new.txt.$((now - 2 * 86400))"
    mkdir "$SAFERM_TRASH/olddir.$((now - 90 * 86400))"
    echo x > "$SAFERM_TRASH/no-timestamp"
    "$ROOT/bin/saferm.sh" -P 30 >/dev/null
    assert_eq "new.txt.$((now - 2 * 86400))
no-timestamp" "$(ls "$SAFERM_TRASH")" "only entries older than 30 days are purged"
}

test_dry_run_moves_nothing() {
    echo keep > "$WORK/keep.txt"
    "$ROOT/bin/saferm.sh" -n "$WORK/keep.txt" >/dev/null
    assert_eq "keep" "$(cat "$WORK/keep.txt")" "file still there after dry run"
}

test_missing_file_is_nonzero() {
    assert_status 1 "missing file" "$ROOT/bin/saferm.sh" "$WORK/not-there"
}

test_same_name_twice_in_one_second() {
    rm -rf "$SAFERM_TRASH"
    mkdir -p "$WORK/d1" "$WORK/d2"
    echo first > "$WORK/d1/notes.txt"
    echo second > "$WORK/d2/notes.txt"
    "$ROOT/bin/saferm.sh" "$WORK/d1/notes.txt" "$WORK/d2/notes.txt"
    assert_eq "2" "$(ls "$SAFERM_TRASH" | wc -l | tr -d ' ')" "both files survive in the trash"
    assert_eq "first
second" "$(cat "$SAFERM_TRASH"/* | sort)" "contents intact"
}

test_refuses_root_home_and_trash() {
    mkdir -p "$WORK/home/docs"
    export SAFERM_TRASH="$WORK/home/.trash"
    mkdir -p "$SAFERM_TRASH"
    for victim in / "$WORK/home" "$WORK/home/" "$SAFERM_TRASH" "$WORK/home/docs/.."; do
        HOME="$WORK/home" assert_status 1 "refuses $victim" "$ROOT/bin/saferm.sh" "$victim"
    done
    assert_file_exists "$WORK/home/docs" "nothing was moved"
    HOME="$WORK/home" assert_status 1 "refuses a directory that contains the trash" "$ROOT/bin/saferm.sh" "$WORK/home/../home"
    export SAFERM_TRASH="$WORK/trash"
}

test_refused_path_does_not_stop_the_rest() {
    mkdir -p "$WORK/home2"
    echo x > "$WORK/home2/keep-me.txt"
    HOME="$WORK/home2" "$ROOT/bin/saferm.sh" / "$WORK/home2/keep-me.txt" >/dev/null 2>&1 || true
    assert_eq "no" "$([ -e "$WORK/home2/keep-me.txt" ] && echo yes || echo no)" "the valid file was still trashed"
}

run_tests
