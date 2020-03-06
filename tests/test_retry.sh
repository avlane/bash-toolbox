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

run_tests
