#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

test_now_is_numeric() {
    unset EPOCHSECONDS
    case $(tb_now) in
        *[!0-9]*|'') assert_eq "digits" "$(tb_now)" "date fallback gives digits" ;;
        *) assert_eq 1 1 "date fallback gives digits" ;;
    esac
}

test_now_prefers_epochseconds() {
    # on bash 5 this is a special variable and the assignment is ignored, so
    # compare against the shell's own value there
    EPOCHSECONDS=1234567890
    if [[ $EPOCHSECONDS == 1234567890 ]]; then
        assert_eq "1234567890" "$(tb_now)" "uses EPOCHSECONDS when it is set"
    else
        assert_eq "$EPOCHSECONDS" "$(tb_now)" "uses the shell's EPOCHSECONDS"
    fi
    unset EPOCHSECONDS
}

test_bash_at_least() {
    assert_status 0 "bash is at least 3.0" tb_bash_at_least 3 0
    assert_status 1 "bash is not 99.0" tb_bash_at_least 99 0
}

run_tests
