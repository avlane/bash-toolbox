#!/bin/bash
. "$(dirname "$0")/harness.sh"

HARNESS="$(cd "$(dirname "$0")" && pwd)/harness.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/harness-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# write a throwaway test file that uses the harness and run it
cat > "$WORK/sample.sh" <<SAMPLE
. "$HARNESS"
test_a_passes() { assert_eq 1 1 "one is one"; }
test_b_fails() { assert_eq 1 2 "one is two"; }
test_c_skips() { skip "not today"; return 0; }
run_tests
SAMPLE

test_reports_each_outcome() {
    out=$(bash "$WORK/sample.sh" || true)
    case $out in *"ok - test_a_passes"*) assert_eq 1 1 "pass is reported" ;; *) assert_eq "ok - test_a_passes" "$out" "pass is reported" ;; esac
    case $out in *"not ok - test_b_fails"*) assert_eq 1 1 "failure is reported" ;; *) assert_eq "not ok - test_b_fails" "$out" "failure is reported" ;; esac
    case $out in *"ok - test_c_skips # SKIP not today"*) assert_eq 1 1 "skip is reported" ;; *) assert_eq "SKIP line" "$out" "skip is reported" ;; esac
    case $out in *"# FAIL: one is two"*) assert_eq 1 1 "failure detail is shown" ;; *) assert_eq "# FAIL: one is two" "$out" "failure detail is shown" ;; esac
}

test_summary_line() {
    out=$(bash "$WORK/sample.sh" | tail -n 1 || true)
    assert_eq "# tests: 3, failed: 1, skipped: 1, assertions passed: 1, failed: 1" "$out" "summary counts"
}

test_exit_status_follows_failures() {
    assert_status 1 "a failing test gives a non-zero status" bash "$WORK/sample.sh"
    printf '. "%s"\ntest_ok() { assert_eq a a x; }\nrun_tests\n' "$HARNESS" > "$WORK/good.sh"
    assert_status 0 "all passing gives zero" bash "$WORK/good.sh"
}

run_tests
