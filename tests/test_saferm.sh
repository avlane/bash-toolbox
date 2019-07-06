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

run_tests
