#!/bin/bash
# House rules checked with grep and bash -n. This is NOT a replacement for
# shellcheck (CI runs that), just a cheap guard that works on a machine without it.
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS=("$ROOT"/bin/*.sh "$ROOT"/lib/*.sh "$ROOT"/tools/*.sh)

test_all_scripts_parse() {
    for f in "${SCRIPTS[@]}" "$ROOT"/tests/*.sh; do
        assert_status 0 "bash -n $(basename "$f")" bash -n "$f"
    done
}

test_scripts_in_bin_are_strict() {
    for f in "$ROOT"/bin/*.sh; do
        assert_eq "1" "$(grep -c '^set -euo pipefail$' "$f")" "$(basename "$f") has set -euo pipefail"
    done
}

test_no_backticks_or_single_bracket_tests() {
    for f in "${SCRIPTS[@]}"; do
        # backticks in comments and quoted strings are fine; look for command substitution
        assert_eq "0" "$(grep -v '^[[:space:]]*#' "$f" | grep -c '[^\]`[a-z]')" "$(basename "$f") uses \$( ) not backticks"
        assert_eq "0" "$(grep -v '^[[:space:]]*#' "$f" | grep -cE '(^|[;&|(] *)\[ ')" "$(basename "$f") uses [[ ]] not [ ]"
    done
}

test_no_gnu_only_commands() {
    for f in "${SCRIPTS[@]}"; do
        assert_eq "0" "$(grep -v '^[[:space:]]*#' "$f" | grep -cE 'readlink -f|date -d |stat -c|sed -i |find .* -printf|\btimeout [0-9]')" "$(basename "$f") avoids GNU-only flags"
    done
}

test_every_function_in_common_has_the_tb_prefix() {
    names=$(grep -E '^[a-z_]+\(\) \{' "$ROOT/lib/common.sh" | sed 's/() {//' | grep -v '^tb_')
    assert_eq "" "$names" "all helpers in lib/common.sh are prefixed tb_"
}

run_tests
