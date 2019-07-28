#!/bin/bash
# run.sh - run every tests/test_*.sh file and report
cd "`dirname "$0"`" || exit 1

failed=0
for t in test_*.sh; do
    echo "== $t"
    if ! bash "$t"; then
        failed=$((failed + 1))
    fi
done

if [ $failed -ne 0 ]; then
    echo "$failed test file(s) failed"
    exit 1
fi
echo "all test files passed"
