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

test_size_limit() {
    f="$WORK/size.log"
    echo small > "$f"
    "$ROOT/bin/rotate-logs.sh" -s 1K "$f" >/dev/null 2>&1
    assert_eq "small" "$(cat "$f")" "small file is not rotated"
    head -c 2048 /dev/zero | tr '\0' 'x' > "$f"
    "$ROOT/bin/rotate-logs.sh" -s 1K "$f" >/dev/null 2>&1
    assert_eq "0" "$(wc -c < "$f" | tr -d ' ')" "large file is rotated"
}

test_age_limit() {
    f="$WORK/age.log"
    echo one > "$f"
    "$ROOT/bin/rotate-logs.sh" -a 7 "$f" >/dev/null 2>&1
    echo two > "$f"
    "$ROOT/bin/rotate-logs.sh" -a 7 "$f" >/dev/null 2>&1
    assert_eq "two" "$(cat "$f")" "second rotation is skipped, .1 is fresh"
    touch -t 201901010000 "$f.1"
    "$ROOT/bin/rotate-logs.sh" -a 7 "$f" >/dev/null 2>&1
    assert_eq "two" "$(cat "$f.1")" "rotates once .1 is old enough"
}

test_compression_and_shifting() {
    f="$WORK/z.log"
    for round in one two three; do
        echo "$round" > "$f"
        "$ROOT/bin/rotate-logs.sh" -z gzip -k 3 "$f" >/dev/null
    done
    assert_eq "three" "$(gzip -dc "$f.1.gz")" ".1.gz is the newest"
    assert_eq "two" "$(gzip -dc "$f.2.gz")" ".2.gz"
    assert_eq "one" "$(gzip -dc "$f.3.gz" 2>/dev/null || true)" "gzip rotation keeps three"
    echo four > "$f"
    "$ROOT/bin/rotate-logs.sh" -z gzip -k 3 "$f" >/dev/null
    assert_eq "no" "$([ -e "$f.4.gz" ] && echo yes || echo no)" "never more than KEEP copies"
}

test_bad_options() {
    assert_status 2 "bad -s" "$ROOT/bin/rotate-logs.sh" -s huge "$WORK/x"
    assert_status 2 "bad -z" "$ROOT/bin/rotate-logs.sh" -z zip "$WORK/x"
}

run_tests
