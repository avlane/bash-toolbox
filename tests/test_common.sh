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

test_civil_date_round_trip() {
    assert_eq "0" "$(tb_days_from_civil 1970 01 01)" "epoch day"
    assert_eq "19782" "$(tb_days_from_civil 2024 02 29)" "leap day 2024"
    assert_eq "2024 2 29" "$(tb_civil_from_days 19782)" "and back"
    assert_eq "2000 3 1" "$(tb_civil_from_days "$(tb_days_from_civil 2000 03 01)")" "round trip after a leap February"
    assert_eq "1969 12 31" "$(tb_civil_from_days -1)" "day before the epoch"
}

test_now_can_be_pinned() {
    assert_eq "1700000000" "$(TB_NOW=1700000000 tb_now)" "TB_NOW overrides the clock"
}

test_prune_newest() {
    d=$(mktemp -d "${TMPDIR:-/tmp}/prune-test.XXXXXX")
    for n in 1 2 3 4; do
        touch -t "20190${n}010000" "$d/db-20190${n}01-000000.bak"
        touch "$d/db-20190${n}01-000000.bak.sha256"
    done
    touch "$d/other-20190101-000000.bak"
    tb_prune_newest 2 "$d" db .bak >/dev/null
    assert_eq "db-20190301-000000.bak
db-20190401-000000.bak
other-20190101-000000.bak" "$(ls "$d" | grep -v sha256)" "newest two of db kept, other prefix untouched"
    tb_prune_newest 0 "$d" db .bak >/dev/null
    assert_eq "3" "$(ls "$d" | grep -vc sha256)" "0 means keep everything"
    rm -rf "$d"
}

test_warnings_are_plain_without_a_terminal() {
    out=$(unset TB_FORCE_COLOR NO_COLOR; tb_warn "disk low" 2>&1)
    case $out in
        *"WARNING: disk low") assert_eq 1 1 "plain text when stderr is not a terminal" ;;
        *) assert_eq "... WARNING: disk low" "$out" "plain text when stderr is not a terminal" ;;
    esac
    case $out in *$'\033'*) assert_eq "no escape codes" "has escapes" "no colour without a terminal" ;; *) assert_eq 1 1 "no colour without a terminal" ;; esac
}

test_force_color_and_no_color() {
    out=$(unset NO_COLOR; TB_FORCE_COLOR=1 tb_warn "disk low" 2>&1)
    case $out in *$'\033[33mWARNING: disk low'*) assert_eq 1 1 "forced colour" ;; *) assert_eq "yellow warning" "$out" "forced colour" ;; esac
    out=$(NO_COLOR=1 TB_FORCE_COLOR=1 tb_warn "disk low" 2>&1)
    case $out in *$'\033'*) assert_eq "plain" "coloured" "NO_COLOR wins over TB_FORCE_COLOR" ;; *) assert_eq 1 1 "NO_COLOR wins over TB_FORCE_COLOR" ;; esac
}

test_run_timeout() {
    assert_status 0 "fast command passes through" tb_run_timeout 5 true
    assert_status 3 "exit status is preserved" tb_run_timeout 5 bash -c 'exit 3'
    SECONDS=0
    tb_run_timeout 1 sleep 10
    rc=$?
    assert_eq "124" "$rc" "slow command is killed with status 124"
    if [ "$SECONDS" -lt 5 ]; then
        assert_eq 1 1 "and quickly"
    else
        assert_eq "under 5s" "${SECONDS}s" "and quickly"
    fi
}

run_tests
