#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)

test_usage_reference_is_current() {
    "$ROOT/tools/gen-usage.sh" > "${TMPDIR:-/tmp}/usage.generated"
    if diff -q "$ROOT/docs/usage.md" "${TMPDIR:-/tmp}/usage.generated" >/dev/null; then
        assert_eq 1 1 "docs/usage.md matches the scripts"
    else
        assert_eq "docs/usage.md up to date" "stale (run tools/gen-usage.sh > docs/usage.md)" "docs/usage.md matches the scripts"
    fi
    rm -f "${TMPDIR:-/tmp}/usage.generated"
}

test_every_script_answers_help() {
    for script in "$ROOT"/bin/*.sh; do
        assert_status 0 "$(basename "$script") --help" "$script" --help
    done
}

test_every_script_is_executable_with_a_shebang() {
    for script in "$ROOT"/bin/*.sh; do
        [ -x "$script" ] || assert_eq "executable" "not executable" "$(basename "$script") is executable"
        assert_eq "#!/usr/bin/env bash" "$(head -n 1 "$script")" "$(basename "$script") shebang"
    done
}

run_tests
