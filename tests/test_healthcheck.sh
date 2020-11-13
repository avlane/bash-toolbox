#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/health-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# stub curl: writes $STUB_BODY to the -o file and prints $STUB_CODE
cat > "$WORK/curl" <<'STUB'
#!/bin/bash
out=
while [ $# -gt 0 ]; do
    if [ "$1" = "-o" ]; then out=$2; shift; fi
    shift
done
printf '%s' "${STUB_BODY:-}" > "$out"
printf '%s' "${STUB_CODE:-200}"
STUB
chmod +x "$WORK/curl"
export CURL_BIN="$WORK/curl"

# stub nc: succeeds or fails depending on STUB_NC
mkdir -p "$WORK/bin"
cat > "$WORK/bin/nc" <<'STUB'
#!/bin/bash
[ "${STUB_NC:-open}" = open ]
STUB
chmod +x "$WORK/bin/nc"

test_http_ok() {
    STUB_CODE=200 assert_status 0 "200 is healthy" "$ROOT/bin/healthcheck.sh" -u http://example.test/
}

test_http_5xx_fails() {
    export STUB_CODE=503
    assert_status 1 "503 is unhealthy" "$ROOT/bin/healthcheck.sh" -u http://example.test/
    unset STUB_CODE
}

test_http_expected_status() {
    export STUB_CODE=404
    assert_status 0 "404 accepted when expected" "$ROOT/bin/healthcheck.sh" -e 404 -u http://example.test/
    assert_status 1 "404 rejected by default" "$ROOT/bin/healthcheck.sh" -u http://example.test/
    unset STUB_CODE
}

test_http_body_match() {
    export STUB_BODY='{"status":"ok"}'
    assert_status 0 "body contains text" "$ROOT/bin/healthcheck.sh" -m '"status":"ok"' -u http://example.test/
    assert_status 1 "body lacks text" "$ROOT/bin/healthcheck.sh" -m degraded -u http://example.test/
    unset STUB_BODY
}

test_tcp_open_and_closed() {
    STUB_NC=open PATH="$WORK/bin:$PATH" assert_status 0 "open port" "$ROOT/bin/healthcheck.sh" db.test 5432
    STUB_NC=closed PATH="$WORK/bin:$PATH" assert_status 1 "closed port" "$ROOT/bin/healthcheck.sh" db.test 5432
}

test_usage_errors() {
    assert_status 2 "no arguments" "$ROOT/bin/healthcheck.sh"
    assert_status 2 "url and host together" "$ROOT/bin/healthcheck.sh" -u http://x/ host 80
    assert_status 2 "bad timeout" "$ROOT/bin/healthcheck.sh" -t soon host 80
}

run_tests
