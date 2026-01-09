#!/bin/bash
# run.sh - run the tests/test_*.sh files and report
#
#   tests/run.sh [-v] [-f TEXT] [FILE_PATTERN...]
#
#   -v          print every "ok - ..." line (by default only failures, skips and
#               one summary line per file are shown)
#   -f TEXT     only run test functions whose name contains TEXT
#   FILE_PATTERN  only run test files whose name contains one of the patterns,
#               for example: tests/run.sh retry backup
#
# Each test file gets its own empty TMPDIR. A file that leaves anything behind in
# it is reported as a leak and counts as a failure, which keeps the tests (and the
# scripts they run) honest about cleaning up after themselves.
cd "$(dirname "$0")" || exit 1

verbose=0
while getopts ':vf:' opt; do
    case $opt in
        v) verbose=1 ;;
        f) export TB_TEST_FILTER=$OPTARG ;;
        *) echo "usage: run.sh [-v] [-f TEXT] [FILE_PATTERN...]" >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
if [ "$verbose" -eq 0 ]; then
    export TB_TEST_QUIET=1
fi

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/toolbox-tests.XXXXXX")
trap 'rm -rf "$sandbox"' EXIT

failed=0
leaked=0
ran=0
for t in test_*.sh; do
    if [ $# -gt 0 ]; then
        match=0
        for pattern in "$@"; do
            case $t in *"$pattern"*) match=1 ;; esac
        done
        [ "$match" -eq 1 ] || continue
    fi
    ran=$((ran + 1))
    echo "== $t"
    mkdir -p "$sandbox/${t%.sh}"
    if ! TMPDIR="$sandbox/${t%.sh}" bash "$t"; then
        failed=$((failed + 1))
    fi
    left=$(ls -A "$sandbox/${t%.sh}")
    if [ -n "$left" ]; then
        echo "LEAK: $t left behind in TMPDIR: $left"
        leaked=$((leaked + 1))
    fi
done

if [ "$ran" -eq 0 ]; then
    echo "no test file matches: $*" >&2
    exit 2
fi

if [ $failed -ne 0 ] || [ $leaked -ne 0 ]; then
    echo "$failed test file(s) failed, $leaked leaked temporary files"
    exit 1
fi
echo "all test files passed"
