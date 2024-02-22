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

test_targets_file() {
    printf '# services\ntcp db01 5432\n\nhttp http://app.test/health 200\n' > "$WORK/targets"
    export STUB_CODE=200
    out=$(STUB_NC=open PATH="$WORK/bin:$PATH" "$ROOT/bin/healthcheck.sh" -f "$WORK/targets")
    assert_eq "OK db01:5432 (accepting connections)
OK http://app.test/health (status 200)" "$out" "one line per target"
    export STUB_CODE=500
    out=$(STUB_NC=closed PATH="$WORK/bin:$PATH" "$ROOT/bin/healthcheck.sh" -f "$WORK/targets" || true)
    assert_eq "FAIL db01:5432 (not accepting connections)
FAIL http://app.test/health (status 500, expected 200)" "$out" "failures are listed"
    STUB_NC=closed PATH="$WORK/bin:$PATH" assert_status 1 "any failure gives exit 1" "$ROOT/bin/healthcheck.sh" -f "$WORK/targets"
    unset STUB_CODE
}

test_json_output() {
    export STUB_CODE=503
    out=$("$ROOT/bin/healthcheck.sh" -j -u 'http://app.test/say "hi"' || true)
    unset STUB_CODE
    assert_eq '{"target":"http://app.test/say \"hi\"","ok":false,"detail":"status 503"}' "$out" "escaped JSON line"
}

test_bad_targets_file() {
    printf 'ftp host\n' > "$WORK/bad"
    assert_status 1 "unknown check type" "$ROOT/bin/healthcheck.sh" -f "$WORK/bad"
    assert_status 1 "missing file" "$ROOT/bin/healthcheck.sh" -f "$WORK/nope"
}

# stub openssl: s_client prints a fake certificate, x509 answers from STUB_* variables
cat > "$WORK/bin/openssl" <<'STUB'
#!/bin/bash
case $1 in
    s_client) [ "${STUB_NO_CERT:-}" ] && exit 1; echo "-----BEGIN CERTIFICATE-----"; echo "fake"; echo "-----END CERTIFICATE-----" ;;
    x509)
        grep -q fake || exit 1
        case $* in
            *-enddate*) echo "notAfter=Jun  1 12:00:00 2030 GMT" ;;
            *"-checkend 0"*) [ -z "${STUB_EXPIRED:-}" ] ;;
            *-checkend*) [ -z "${STUB_SOON:-}" ] && [ -z "${STUB_EXPIRED:-}" ] ;;
        esac ;;
esac
STUB
chmod +x "$WORK/bin/openssl"

test_tls_valid_certificate() {
    out=$(PATH="$WORK/bin:$PATH" "$ROOT/bin/healthcheck.sh" -s host.test 443)
    assert_eq "OK host.test:443 (tls) (certificate valid until Jun  1 12:00:00 2030 GMT)" "$out" "valid certificate"
}

test_tls_expiring_and_expired() {
    out=$(STUB_SOON=1 PATH="$WORK/bin:$PATH" "$ROOT/bin/healthcheck.sh" -s -x 30 host.test 443 || true)
    assert_eq "FAIL host.test:443 (tls) (certificate expires Jun  1 12:00:00 2030 GMT, less than 30 days away)" "$out" "expiring soon"
    out=$(STUB_EXPIRED=1 PATH="$WORK/bin:$PATH" "$ROOT/bin/healthcheck.sh" -s host.test 443 || true)
    assert_eq "FAIL host.test:443 (tls) (certificate expired on Jun  1 12:00:00 2030 GMT)" "$out" "already expired"
}

test_tls_no_certificate() {
    STUB_NO_CERT=1 PATH="$WORK/bin:$PATH" assert_status 1 "connection without certificate" "$ROOT/bin/healthcheck.sh" -s host.test 443
}

test_tls_line_in_targets_file() {
    printf 'tls host.test 443 90\n' > "$WORK/tlsfile"
    STUB_SOON=1 PATH="$WORK/bin:$PATH" assert_status 1 "days column is honoured" "$ROOT/bin/healthcheck.sh" -f "$WORK/tlsfile"
    PATH="$WORK/bin:$PATH" assert_status 0 "valid certificate in file mode" "$ROOT/bin/healthcheck.sh" -f "$WORK/tlsfile"
}

test_usage_errors() {
    assert_status 2 "no arguments" "$ROOT/bin/healthcheck.sh"
    assert_status 2 "url and host together" "$ROOT/bin/healthcheck.sh" -u http://x/ host 80
    assert_status 2 "bad timeout" "$ROOT/bin/healthcheck.sh" -t soon host 80
}

run_tests
