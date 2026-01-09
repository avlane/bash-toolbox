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
    out=$(env -u TB_TEST_QUIET -u TB_TEST_FILTER bash "$WORK/sample.sh" || true)
    assert_contains "$out" "ok - test_a_passes" "pass is reported"
    assert_contains "$out" "not ok - test_b_fails" "failure is reported"
    assert_contains "$out" "ok - test_c_skips # SKIP not today" "skip is reported"
    assert_contains "$out" "# FAIL: one is two" "failure detail is shown"
}

test_contains_and_missing_helpers() {
    cat > "$WORK/helpers.sh" <<HELPERS
. "$HARNESS"
test_present() { assert_contains "hello world" "o w" "substring"; assert_not_contains "hello" "z" "absent"; assert_file_missing /nonexistent/file "no file"; }
test_wrong() { assert_contains "hello" "z" "needle missing"; }
test_wrong_too() { assert_not_contains "hello" "ell" "needle present"; }
test_wrong_file() { assert_file_missing /tmp "tmp exists"; }
run_tests
HELPERS
    out=$(env -u TB_TEST_QUIET -u TB_TEST_FILTER bash "$WORK/helpers.sh" || true)
    assert_contains "$out" "ok - test_present" "positive cases pass"
    assert_contains "$out" "not ok - test_wrong" "assert_contains fails when missing"
    assert_contains "$out" "not ok - test_wrong_too" "assert_not_contains fails when present"
    assert_contains "$out" "not ok - test_wrong_file" "assert_file_missing fails when present"
}

test_summary_line() {
    out=$(env -u TB_TEST_QUIET -u TB_TEST_FILTER bash "$WORK/sample.sh" | tail -n 1 || true)
    assert_eq "# tests: 3, failed: 1, skipped: 1, assertions passed: 1, failed: 1" "$out" "summary counts"
}

test_quiet_and_filter_options() {
    out=$(TB_TEST_QUIET=1 bash "$WORK/sample.sh" || true)
    assert_not_contains "$out" "ok - test_a_passes" "quiet mode hides passing tests"
    assert_contains "$out" "not ok - test_b_fails" "but not failures"
    out=$(TB_TEST_FILTER=passes bash "$WORK/sample.sh" || true)
    assert_contains "$out" "# tests: 1, failed: 0" "filter selects by name"
}

test_exit_status_follows_failures() {
    assert_status 1 "a failing test gives a non-zero status" env -u TB_TEST_QUIET -u TB_TEST_FILTER bash "$WORK/sample.sh"
    printf '. "%s"\ntest_ok() { assert_eq a a x; }\nrun_tests\n' "$HARNESS" > "$WORK/good.sh"
    assert_status 0 "all passing gives zero" env -u TB_TEST_QUIET -u TB_TEST_FILTER bash "$WORK/good.sh"
}

run_tests
