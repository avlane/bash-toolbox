#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/json-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/doc.json" <<'JSON'
{"name": "box", "port": 8080, "debug": false, "server": {"host": "db01", "port": 5432}, "tags": ["a b", "c", 42]}
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

test_escaped_quotes_and_backslashes() {
    cat > "$WORK/esc.json" <<'JSON'
{"q": "say \"hi\" now", "after": "next", "path": "C:\\dir\\", "mix": "a\\\"b"}
JSON
    assert_eq 'say "hi" now' "$("$ROOT/bin/json-get.sh" -r q "$WORK/esc.json")" "escaped quotes inside a string"
    assert_eq 'C:\dir\' "$("$ROOT/bin/json-get.sh" -r path "$WORK/esc.json")" "doubled backslashes, string ending in one"
    assert_eq 'a\"b' "$("$ROOT/bin/json-get.sh" -r mix "$WORK/esc.json")" "backslash followed by an escaped quote"
    assert_eq "next" "$("$ROOT/bin/json-get.sh" -r after "$WORK/esc.json")" "the next key is still found after an escaped quote"
}

test_array_index() {
    assert_eq "a b" "$("$ROOT/bin/json-get.sh" -r '.tags[0]' "$WORK/doc.json")" "first element, string with space"
    assert_eq "42" "$("$ROOT/bin/json-get.sh" 'tags[2]' "$WORK/doc.json")" "number element"
    assert_status 1 "index past the end" "$ROOT/bin/json-get.sh" 'tags[3]' "$WORK/doc.json"
}

test_default_for_missing_and_null() {
    echo '{"a": null, "b": false, "c": "x"}' > "$WORK/nulls.json"
    assert_eq "fallback" "$("$ROOT/bin/json-get.sh" -d fallback missing "$WORK/nulls.json")" "missing key"
    assert_eq "fallback" "$("$ROOT/bin/json-get.sh" -d fallback a "$WORK/nulls.json")" "null value"
    assert_eq "x" "$("$ROOT/bin/json-get.sh" -r -d fallback c "$WORK/nulls.json")" "present value wins"
    assert_status 1 "false is not replaced" "$ROOT/bin/json-get.sh" -d fallback b "$WORK/nulls.json"
    assert_eq "false" "$("$ROOT/bin/json-get.sh" -d fallback b "$WORK/nulls.json" || true)" "false is printed"
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
