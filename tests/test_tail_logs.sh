#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tail-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# run tail-logs.sh for about two seconds, appending a line half way through
run_follow() {
    out=$1
    shift
    "$ROOT/bin/tail-logs.sh" "$@" > "$out" 2>&1 &
    pid=$!
    sleep 1
    echo "live line one" >> "$WORK/a.log"
    echo "debug noise" >> "$WORK/b.log"
    sleep 1
    kill "$pid"
    wait "$pid" 2>/dev/null || true
}

test_prefixes_history_and_new_lines() {
    printf 'old a\n' > "$WORK/a.log"
    printf 'old b\n' > "$WORK/b.log"
    run_follow "$WORK/out1" -n 1 "$WORK/a.log" "$WORK/b.log"
    sort "$WORK/out1" > "$WORK/sorted"
    assert_eq "[a.log] live line one
[a.log] old a
[b.log] debug noise
[b.log] old b" "$(cat "$WORK/sorted")" "each line carries its file name"
}

test_pattern_filters() {
    printf 'old a\n' > "$WORK/a.log"
    printf 'old b\n' > "$WORK/b.log"
    run_follow "$WORK/out2" -n 1 -g 'live|old a' "$WORK/a.log" "$WORK/b.log"
    sort "$WORK/out2" > "$WORK/sorted"
    assert_eq "[a.log] live line one
[a.log] old a" "$(cat "$WORK/sorted")" "only matching lines are shown"
}

test_directory_expands_to_log_files() {
    mkdir -p "$WORK/logs"
    printf 'old a\n' > "$WORK/a.log"
    cp "$WORK/a.log" "$WORK/logs/a.log"
    printf 'other\n' > "$WORK/logs/notes.txt"
    "$ROOT/bin/tail-logs.sh" -n 1 "$WORK/logs" > "$WORK/out3" 2>&1 &
    pid=$!
    sleep 1
    kill "$pid"; wait "$pid" 2>/dev/null || true
    assert_eq "[a.log] old a" "$(cat "$WORK/out3")" "only the .log file is followed"
}

test_empty_directory() {
    mkdir -p "$WORK/emptylogs"
    assert_status 1 "directory without logs" "$ROOT/bin/tail-logs.sh" "$WORK/emptylogs"
}

test_usage_errors() {
    assert_status 2 "no files" "$ROOT/bin/tail-logs.sh"
    assert_status 2 "bad -n" "$ROOT/bin/tail-logs.sh" -n many "$WORK/a.log"
}

run_tests
