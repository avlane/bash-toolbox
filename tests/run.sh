#!/bin/bash
# run.sh - run every tests/test_*.sh file and report
#
# Each test file gets its own empty TMPDIR. A file that leaves anything behind in
# it is reported as a leak and counts as a failure, which keeps the tests (and the
# scripts they run) honest about cleaning up after themselves.
cd "$(dirname "$0")" || exit 1

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/toolbox-tests.XXXXXX")
trap 'rm -rf "$sandbox"' EXIT

failed=0
leaked=0
for t in test_*.sh; do
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

if [ $failed -ne 0 ] || [ $leaked -ne 0 ]; then
    echo "$failed test file(s) failed, $leaked leaked temporary files"
    exit 1
fi
echo "all test files passed"
