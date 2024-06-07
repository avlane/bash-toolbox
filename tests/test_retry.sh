#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/retry-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export TB_SLEEP=true   # do not really sleep

# a command that fails until it has been called N times: flaky COUNTFILE N
cat > "$WORK/flaky" <<'FLAKY'
#!/bin/bash
n=$(cat "$1" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$1"
[ "$n" -ge "$2" ]
FLAKY
chmod +x "$WORK/flaky"

test_succeeds_after_failures() {
    rm -f "$WORK/count"
    assert_status 0 "third attempt succeeds" "$ROOT/bin/retry.sh" -t 5 "$WORK/flaky" "$WORK/count" 3
    assert_eq "3" "$(cat "$WORK/count")" "ran three times"
}

test_gives_up_with_last_status() {
    rm -f "$WORK/count"
    assert_status 1 "gives up with the command's status" "$ROOT/bin/retry.sh" -t 2 "$WORK/flaky" "$WORK/count" 9
    assert_eq "2" "$(cat "$WORK/count")" "ran exactly TRIES times"
}

test_passes_through_exit_code() {
    assert_status 7 "exit code 7 is preserved" "$ROOT/bin/retry.sh" -t 1 bash -c 'exit 7'
}

test_requires_command() {
    assert_status 2 "no command is a usage error" "$ROOT/bin/retry.sh" -t 3
}

test_delay_doubles_up_to_max() {
    printf '#!/bin/bash\necho "$1" >> "%s/sleeps"\n' "$WORK" > "$WORK/fake-sleep"
    chmod +x "$WORK/fake-sleep"
    rm -f "$WORK/sleeps"
    TB_SLEEP="$WORK/fake-sleep" "$ROOT/bin/retry.sh" -t 5 -d 2 -m 5 false 2>/dev/null || true
    assert_eq "2 4 5 5" "$(tr '\n' ' ' < "$WORK/sleeps" | sed 's/ $//')" "delays 2,4,5,5"
}

test_only_retries_listed_codes() {
    rm -f "$WORK/count"
    cat > "$WORK/exit75" <<'SCRIPT'
#!/bin/bash
echo x >> "$1"
exit 75
SCRIPT
    chmod +x "$WORK/exit75"
    assert_status 75 "listed code is retried then returned" "$ROOT/bin/retry.sh" -t 3 -r 1,75 "$WORK/exit75" "$WORK/count"
    assert_eq "3" "$(wc -l < "$WORK/count" | tr -d ' ')" "retried three times"
    rm -f "$WORK/count"
    assert_status 75 "unlisted code stops at once" "$ROOT/bin/retry.sh" -t 3 -r 1 "$WORK/exit75" "$WORK/count"
    assert_eq "1" "$(wc -l < "$WORK/count" | tr -d ' ')" "ran once"
}

test_rejects_bad_code_list() {
    assert_status 2 "bad -r" "$ROOT/bin/retry.sh" -r one,two true
}

test_jitter_stays_within_bounds() {
    printf '#!/bin/bash\necho "$1" >> "%s/jsleeps"\n' "$WORK" > "$WORK/fake-sleep"
    chmod +x "$WORK/fake-sleep"
    rm -f "$WORK/jsleeps"
    TB_SLEEP="$WORK/fake-sleep" "$ROOT/bin/retry.sh" -t 2 -d 10 -j false 2>/dev/null || true
    d=$(cat "$WORK/jsleeps")
    if [ "$d" -ge 10 ] && [ "$d" -le 15 ]; then
        assert_eq 1 1 "10 <= delay <= 15"
    else
        assert_eq "10..15" "$d" "10 <= delay <= 15"
    fi
}

test_attempt_timeout() {
    SECONDS=0
    assert_status 124 "a hung command is killed and reported as 124" "$ROOT/bin/retry.sh" -T 1 -t 2 sleep 20
    if [ "$SECONDS" -lt 8 ]; then
        assert_eq 1 1 "two one-second attempts do not take long"
    else
        assert_eq "under 8s" "${SECONDS}s" "two one-second attempts do not take long"
    fi
    assert_status 0 "fast commands are unaffected" "$ROOT/bin/retry.sh" -T 5 true
    assert_status 2 "bad -T" "$ROOT/bin/retry.sh" -T 0 true
}

run_tests
