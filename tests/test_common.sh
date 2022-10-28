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

test_readlines_keeps_spaces_and_blank_lines() {
    tb_readlines rows < <(printf 'one\ntwo words\n\nlast without newline')
    assert_eq "4" "${#rows[@]}" "four elements"
    assert_eq "two words" "${rows[1]}" "spaces kept"
    assert_eq "" "${rows[2]}" "blank line kept"
    assert_eq "last without newline" "${rows[3]}" "unterminated last line kept"
}

test_readlines_empty_input() {
    tb_readlines rows < /dev/null
    assert_eq "0" "${#rows[@]}" "empty input gives an empty array"
}

test_readlines_rejects_bad_name() {
    assert_status 1 "bad array name" bash -c '. "$1"; tb_readlines "a b" </dev/null' _ "$ROOT/lib/common.sh"
}

test_quote_args_round_trip() {
    # whatever form the quoting takes, eval must give back the same words
    quoted=$(tb_quote_args 'a b' "it's" '' '$HOME' 'x"y')
    eval "set -- $quoted"
    assert_eq "5" "$#" "five words survive"
    assert_eq "a b" "$1" "space"
    assert_eq "it's" "$2" "single quote"
    assert_eq "" "$3" "empty word"
    assert_eq '$HOME' "$4" "no expansion"
    assert_eq 'x"y' "$5" "double quote"
}

run_tests
