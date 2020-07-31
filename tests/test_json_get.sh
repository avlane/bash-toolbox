#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/json-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

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

test_false_is_exit_1() {
    assert_status 1 "false behaves like jq -e" "$ROOT/bin/json-get.sh" debug "$WORK/doc.json"
    assert_eq "false" "$("$ROOT/bin/json-get.sh" debug "$WORK/doc.json" || true)" "false is still printed"
}

test_quoted_string_without_raw() {
    assert_eq '"box"' "$("$ROOT/bin/json-get.sh" name "$WORK/doc.json")" "string keeps quotes"
}

test_usage() {
    assert_status 2 "no key" "$ROOT/bin/json-get.sh"
}

# run everything with jq (if installed) and again with the bash fallback
rc=0
if command -v jq >/dev/null; then
    echo "[jq]"
    run_tests || rc=1
else
    echo "jq not found, skipping the jq pass"
fi
export TB_NO_JQ=1
echo "[bash fallback]"
run_tests || rc=1
exit $rc
