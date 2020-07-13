#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/json-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

command -v jq >/dev/null || { echo "jq not found, skipping"; exit 0; }

cat > "$WORK/doc.json" <<'JSON'
{"name": "box", "port": 8080, "debug": false, "server": {"host": "db01", "port": 5432}}
JSON

test_reads_string_raw() {
    assert_eq "box" "$("$ROOT/bin/json-get.sh" -r name "$WORK/doc.json")" "string without quotes"
}

test_reads_nested_key() {
    assert_eq "5432" "$("$ROOT/bin/json-get.sh" .server.port "$WORK/doc.json")" "nested number"
}

test_reads_stdin() {
    assert_eq "8080" "$(cat "$WORK/doc.json" | "$ROOT/bin/json-get.sh" port)" "stdin input"
}

test_missing_key_fails() {
    assert_status 1 "missing key" "$ROOT/bin/json-get.sh" nothere "$WORK/doc.json"
}

test_usage() {
    assert_status 2 "no key" "$ROOT/bin/json-get.sh"
}

run_tests
