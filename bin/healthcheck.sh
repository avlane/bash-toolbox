#!/usr/bin/env bash
# healthcheck.sh - check that a TCP port or an HTTP endpoint is up
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: healthcheck.sh [-t SECONDS] HOST PORT
       healthcheck.sh [-t SECONDS] [-e STATUS] [-m TEXT] -u URL

Without -u, check that something accepts TCP connections on HOST:PORT (needs
nc). With -u, request URL with curl and check the response.

options:
  -u URL      HTTP(S) URL to request
  -e STATUS   expected HTTP status (default: any 2xx or 3xx)
  -m TEXT     the response body must contain TEXT
  -t SECONDS  timeout for the check (default 5)
  -h, --help  show this help

Exit status: 0 healthy, 1 unhealthy, 2 usage error.
Set CURL_BIN to use a different curl.
USAGE
}

tb_handle_help usage "$@"

url=
expect=
match=
timeout=5
while getopts ':u:e:m:t:h' opt; do
    case $opt in
        u) url=$OPTARG ;;
        e) expect=$OPTARG ;;
        m) match=$OPTARG ;;
        t) timeout=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $timeout =~ ^[0-9]+$ ]] || tb_usage_error "-t needs a whole number of seconds"

check_tcp() {
    local host=$1 port=$2
    tb_require_cmd nc
    if nc -z -w "$timeout" "$host" "$port" >/dev/null 2>&1; then
        echo "OK $host:$port"
    else
        echo "FAIL $host:$port is not accepting connections"
        return 1
    fi
}

check_http() {
    local curl=${CURL_BIN:-curl} body code
    body=$(mktemp "${TMPDIR:-/tmp}/healthcheck.XXXXXX")
    trap 'rm -f "$body"' RETURN
    code=$("$curl" -s -o "$body" -w '%{http_code}' --max-time "$timeout" "$url") || code=000
    if [[ -n $expect ]]; then
        [[ $code == "$expect" ]] || { echo "FAIL $url returned $code, expected $expect"; return 1; }
    else
        [[ $code =~ ^[23][0-9][0-9]$ ]] || { echo "FAIL $url returned $code"; return 1; }
    fi
    if [[ -n $match ]] && ! grep -q -F -- "$match" "$body"; then
        echo "FAIL $url response does not contain '$match'"
        return 1
    fi
    echo "OK $url ($code)"
}

if [[ -n $url ]]; then
    [[ $# -eq 0 ]] || tb_usage_error "do not combine -u with HOST PORT"
    check_http
else
    [[ $# -eq 2 ]] || tb_usage_error "expected HOST PORT or -u URL"
    check_tcp "$1" "$2"
fi
