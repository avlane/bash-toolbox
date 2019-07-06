#!/bin/bash
# harness.sh - a tiny test harness, source it from a test file.
#
#   . "$(dirname "$0")/harness.sh"
#   test_something() { assert_eq "a" "a" "letters match"; }
#   run_tests
#
# Every function whose name starts with test_ is run.

PASS=0
FAIL=0

assert_eq() {
    # assert_eq EXPECTED ACTUAL MESSAGE
    if [ "$1" = "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $3"
        echo "    expected: $1"
        echo "    actual:   $2"
    fi
}

assert_status() {
    # assert_status EXPECTED_STATUS MESSAGE COMMAND [ARGS...]
    expected=$1
    message=$2
    shift 2
    "$@" >/dev/null 2>&1
    actual=$?
    assert_eq "$expected" "$actual" "$message"
}

assert_file_exists() {
    if [ -e "$1" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $2 (missing $1)"
    fi
}

run_tests() {
    for t in `declare -F | awk '{print $3}' | grep '^test_'`; do
        echo "- $t"
        $t
    done
    echo "passed: $PASS failed: $FAIL"
    [ "$FAIL" -eq 0 ]
}
