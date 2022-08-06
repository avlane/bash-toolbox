#!/usr/bin/env bash
# healthcheck.sh - check that TCP ports and HTTP endpoints are up
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: healthcheck.sh [-t SECONDS] [-j] HOST PORT
       healthcheck.sh [-t SECONDS] [-j] [-e STATUS] [-m TEXT] -u URL
       healthcheck.sh [-t SECONDS] [-j] -f FILE

Without -u or -f, check that something accepts TCP connections on HOST:PORT
(needs nc). With -u, request URL with curl and check the response. With -f,
check every target listed in FILE; lines look like

    tcp db01.example.org 5432
    http https://app.example.org/health 200

and blank lines and # comments are ignored. For http lines the status is
optional (default: any 2xx or 3xx).

options:
  -u URL      HTTP(S) URL to request
  -e STATUS   expected HTTP status (default: any 2xx or 3xx)
  -m TEXT     the response body must contain TEXT
  -f FILE     check all targets in FILE
  -j          print one JSON object per target instead of text
  -t SECONDS  timeout per check (default 5)
  -h, --help  show this help

Exit status: 0 everything healthy, 1 at least one check failed, 2 usage error.
Set CURL_BIN to use a different curl.
USAGE
}

tb_handle_help usage "$@"

url=
expect=
match=
file=
json=0
timeout=5
while getopts ':u:e:m:f:t:jh' opt; do
    case $opt in
        u) url=$OPTARG ;;
        e) expect=$OPTARG ;;
        m) match=$OPTARG ;;
        f) file=$OPTARG ;;
        j) json=1 ;;
        t) timeout=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $timeout =~ ^[0-9]+$ ]] || tb_usage_error "-t needs a whole number of seconds"

# Each check sets $detail (a short human readable result) and returns 0 or 1.
detail=

check_tcp() {
    local host=$1 port=$2
    tb_require_cmd nc
    if nc -z -w "$timeout" "$host" "$port" >/dev/null 2>&1; then
        detail="accepting connections"
    else
        detail="not accepting connections"
        return 1
    fi
}

# check_http URL [EXPECTED_STATUS [BODY_TEXT]]
check_http() {
    local target=$1 want=${2:-} text=${3:-} curl=${CURL_BIN:-curl} body code
    body=$(mktemp "${TMPDIR:-/tmp}/healthcheck.XXXXXX")
    code=$("$curl" -s -o "$body" -w '%{http_code}' --max-time "$timeout" "$target") || code=000
    detail="status $code"
    if [[ -n $want ]]; then
        if [[ $code != "$want" ]]; then
            detail="status $code, expected $want"
            rm -f "$body"
            return 1
        fi
    elif ! [[ $code =~ ^[23][0-9][0-9]$ ]]; then
        rm -f "$body"
        return 1
    fi
    if [[ -n $text ]] && ! grep -q -F -- "$text" "$body"; then
        detail="status $code, body does not contain '$text'"
        rm -f "$body"
        return 1
    fi
    rm -f "$body"
}

# json_escape TEXT - escape backslashes and double quotes for a JSON string
json_escape() {
    local s=${1//\\/\\\\}
    printf '%s' "${s//\"/\\\"}"
}

failures=0

# report LABEL STATUS - print the result of one check and count failures
report() {
    local label=$1 rc=$2 word=OK ok=true
    if (( rc != 0 )); then
        word=FAIL
        ok=false
        failures=$((failures + 1))
    fi
    if (( json )); then
        printf '{"target":"%s","ok":%s,"detail":"%s"}\n' "$(json_escape "$label")" "$ok" "$(json_escape "$detail")"
    else
        printf '%s %s (%s)\n' "$word" "$label" "$detail"
    fi
}

run_one() {   # run_one KIND ARGS...
    local rc=0 kind=$1
    shift
    case $kind in
        tcp) check_tcp "$1" "$2" || rc=$?; report "$1:$2" "$rc" ;;
        http) check_http "$@" || rc=$?; report "$1" "$rc" ;;
    esac
}

if [[ -n $file ]]; then
    [[ $# -eq 0 && -z $url ]] || tb_usage_error "-f cannot be combined with other targets"
    [[ -r $file ]] || tb_die "cannot read $file"
    while read -r kind a b _; do
        if [[ -z $kind || $kind == \#* ]]; then
            continue
        fi
        case $kind in
            tcp) [[ -n ${a:-} && -n ${b:-} ]] || tb_die "bad line in $file: $kind $a $b"
                 run_one tcp "$a" "$b" ;;
            http) [[ -n ${a:-} ]] || tb_die "bad line in $file: $kind"
                  run_one http "$a" "$b" ;;
            *) tb_die "unknown check type in $file: $kind" ;;
        esac
    done < "$file"
elif [[ -n $url ]]; then
    [[ $# -eq 0 ]] || tb_usage_error "do not combine -u with HOST PORT"
    run_one http "$url" "$expect" "$match"
else
    [[ $# -eq 2 ]] || tb_usage_error "expected HOST PORT, -u URL or -f FILE"
    run_one tcp "$1" "$2"
fi

(( failures == 0 ))
