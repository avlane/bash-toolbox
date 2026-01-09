#!/bin/bash
# harness.sh - a tiny test harness, source it from a test file.
#
#   . "$(dirname "$0")/harness.sh"
#   test_something() { assert_eq "a" "a" "letters match"; }
#   test_optional()  { command -v jq >/dev/null || { skip "needs jq"; return 0; }; ... }
#   run_tests
#
# Every function whose name starts with test_ is run, in alphabetical order, in
# the same shell. Output is TAP-like: "ok - name", "not ok - name" (followed by
# "# " detail lines) and "ok - name # SKIP reason", then a summary line.
# run_tests returns non-zero if any test failed.
#
# Environment:
#   TB_TEST_QUIET=1     do not print "ok - ..." lines (failures and the summary stay)
#   TB_TEST_FILTER=TEXT only run test functions whose name contains TEXT

PASS=0         # assertions that passed
FAIL=0         # assertions that failed
TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0
SKIP_REASON=

_fail() {
    # _fail MESSAGE [DETAIL_LINE]... - record a failed assertion
    FAIL=$((FAIL + 1))
    printf '# FAIL: %s\n' "$1"
    shift
    local line
    for line in "$@"; do
        printf '#   %s\n' "$line"
    done
}

assert_eq() {
    # assert_eq EXPECTED ACTUAL MESSAGE
    if [ "$1" = "$2" ]; then
        PASS=$((PASS + 1))
    else
        _fail "$3" "expected: $1" "actual:   $2"
    fi
}

assert_status() {
    # assert_status EXPECTED_STATUS MESSAGE COMMAND [ARGS...]
    local expected=$1 message=$2 actual
    shift 2
    "$@" >/dev/null 2>&1
    actual=$?
    assert_eq "$expected" "$actual" "$message"
}

assert_contains() {
    # assert_contains HAYSTACK NEEDLE MESSAGE - plain substring, not a pattern
    case $1 in
        *"$2"*) PASS=$((PASS + 1)) ;;
        *) _fail "$3" "expected to find: $2" "in: $1" ;;
    esac
}

assert_not_contains() {
    # assert_not_contains HAYSTACK NEEDLE MESSAGE
    case $1 in
        *"$2"*) _fail "$3" "did not expect to find: $2" "in: $1" ;;
        *) PASS=$((PASS + 1)) ;;
    esac
}

assert_file_exists() {
    # assert_file_exists PATH MESSAGE
    if [ -e "$1" ]; then
        PASS=$((PASS + 1))
    else
        _fail "$2" "missing: $1"
    fi
}

assert_file_missing() {
    # assert_file_missing PATH MESSAGE
    if [ -e "$1" ] || [ -L "$1" ]; then
        _fail "$2" "unexpectedly present: $1"
    else
        PASS=$((PASS + 1))
    fi
}

skip() {
    # skip REASON - call from a test, then return
    SKIP_REASON=${*:-skipped}
}

run_tests() {
    local t before names
    names=$(declare -F | awk '{print $3}' | grep '^test_' || true)
    for t in $names; do
        case $t in
            *"${TB_TEST_FILTER:-}"*) ;;
            *) continue ;;
        esac
        TESTS_RUN=$((TESTS_RUN + 1))
        before=$FAIL
        SKIP_REASON=
        "$t"
        if [ -n "$SKIP_REASON" ]; then
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            echo "ok - $t # SKIP $SKIP_REASON"
        elif [ "$FAIL" -ne "$before" ]; then
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "not ok - $t"
        elif [ -z "${TB_TEST_QUIET:-}" ]; then
            echo "ok - $t"
        fi
    done
    echo "# tests: $TESTS_RUN, failed: $TESTS_FAILED, skipped: $TESTS_SKIPPED, assertions passed: $PASS, failed: $FAIL"
    [ "$FAIL" -eq 0 ]
}
