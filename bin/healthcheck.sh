#!/usr/bin/env bash
# healthcheck.sh - check that TCP ports and HTTP endpoints are up
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: healthcheck.sh [-t SECONDS] [-j] HOST PORT
       healthcheck.sh -N [options] HOST PORT | -u URL
       healthcheck.sh [-t SECONDS] [-j] -s [-x DAYS] HOST PORT
       healthcheck.sh [-t SECONDS] [-j] [-e STATUS] [-m TEXT] -u URL
       healthcheck.sh [-t SECONDS] [-j] -f FILE

Without -u or -f, check that something accepts TCP connections on HOST:PORT
(needs nc). With -u, request URL with curl and check the response. With -f,
check every target listed in FILE; lines look like

    tcp db01.example.org 5432
    http https://app.example.org/health 200
    tls app.example.org 443 21

and blank lines and # comments are ignored. For http lines the status is
optional (default: any 2xx or 3xx). For tls lines the number of days is
optional (default 14).

With -s the TLS certificate served on HOST:PORT must be valid for at least DAYS
more days (needs openssl; the certificate chain is not validated, only its
expiry date is checked).

options:
  -u URL      HTTP(S) URL to request
  -e STATUS   expected HTTP status (default: any 2xx or 3xx)
  -m TEXT     the response body must contain TEXT
  -s          check the TLS certificate's expiry instead of just connecting
  -x DAYS     with -s, required remaining validity in days (default 14)
  -f FILE     check all targets in FILE
  -N          monitoring plugin output and exit codes, see below
  -j          print one JSON object per target instead of text
  -t SECONDS  timeout per check (default 5)
  -h, --help  show this help

Exit status: 0 everything healthy, 1 at least one check failed, 2 usage error.

With -N the script behaves as a monitoring plugin (Nagios, Icinga, Sensu and
friends): one line "OK - ... | time=0.012s" or "CRITICAL - ... | time=...", exit
status 0 for OK, 2 for CRITICAL and 3 for UNKNOWN (usage errors). It checks a
single target, so it cannot be combined with -f. On bash 3.2 (macOS) the time
has a resolution of one second.
Set CURL_BIN to use a different curl.
USAGE
}

tb_handle_help usage "$@"

# in plugin mode a usage error is UNKNOWN (3), so look for -N before parsing
case " $* " in *" -N "*) tb_usage_status=3 ;; esac

url=
expect=
match=
file=
json=0
timeout=5
tls=0
tls_days=14
nagios=0
while getopts ':u:e:m:f:t:x:sjNh' opt; do
    case $opt in
        u) url=$OPTARG ;;
        e) expect=$OPTARG ;;
        m) match=$OPTARG ;;
        f) file=$OPTARG ;;
        j) json=1 ;;
        N) nagios=1 ;;
        s) tls=1 ;;
        x) tls_days=$OPTARG ;;
        t) timeout=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $timeout =~ ^[0-9]+$ ]] || tb_usage_error "-t needs a whole number of seconds"
[[ $tls_days =~ ^[0-9]+$ ]] || tb_usage_error "-x needs a whole number of days"
if (( nagios )); then
    [[ -z $file ]] || tb_usage_error "-N checks a single target, it cannot be combined with -f"
    (( ! json )) || tb_usage_error "-N and -j cannot be combined"
fi

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

# check_tls HOST PORT [DAYS] - the certificate must still be valid in DAYS days
check_tls() {
    local host=$1 port=$2 days=${3:-14} out end
    tb_require_cmd openssl
    out=$(mktemp "${TMPDIR:-/tmp}/healthcheck.XXXXXX")
    tb_run_timeout "$timeout" openssl s_client -connect "$host:$port" -servername "$host" </dev/null >"$out" 2>/dev/null || true
    end=$(openssl x509 -noout -enddate <"$out" 2>/dev/null) || {
        detail="no certificate received"
        rm -f "$out"
        return 1
    }
    end=${end#notAfter=}
    if openssl x509 -noout -checkend $((days * 86400)) <"$out" >/dev/null 2>&1; then
        detail="certificate valid until $end"
        rm -f "$out"
    else
        detail="certificate expires $end, less than $days days away"
        if ! openssl x509 -noout -checkend 0 <"$out" >/dev/null 2>&1; then
            detail="certificate expired on $end"
        fi
        rm -f "$out"
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

failures=0

# report LABEL STATUS - print the result of one check and count failures
report() {
    local label=$1 rc=$2 word=OK ok=true ms
    if (( rc != 0 )); then
        word=FAIL
        ok=false
        failures=$((failures + 1))
    fi
    if (( nagios )); then
        ms=$(( $(tb_now_ms) - check_started ))
        (( ms >= 0 )) || ms=0
        if (( rc != 0 )); then word=CRITICAL; fi
        printf '%s - %s: %s | time=%d.%03ds\n' "$word" "$label" "$detail" $((ms / 1000)) $((ms % 1000))
    elif (( json )); then
        printf '{"target":"%s","ok":%s,"detail":"%s"}\n' "$(tb_json_escape "$label")" "$ok" "$(tb_json_escape "$detail")"
    else
        printf '%s %s (%s)\n' "$word" "$label" "$detail"
    fi
}

check_started=0
run_one() {   # run_one KIND ARGS...
    local rc=0 kind=$1
    check_started=$(tb_now_ms)
    shift
    case $kind in
        tcp) check_tcp "$1" "$2" || rc=$?; report "$1:$2" "$rc" ;;
        tls) check_tls "$@" || rc=$?; report "$1:$2 (tls)" "$rc" ;;
        http) check_http "$@" || rc=$?; report "$1" "$rc" ;;
    esac
}

if [[ -n $file ]]; then
    [[ $# -eq 0 && -z $url ]] || tb_usage_error "-f cannot be combined with other targets"
    [[ -r $file ]] || tb_die "cannot read $file"
    while read -r kind a b c _; do
        if [[ -z $kind || $kind == \#* ]]; then
            continue
        fi
        case $kind in
            tcp) [[ -n ${a:-} && -n ${b:-} ]] || tb_die "bad line in $file: $kind $a $b"
                 run_one tcp "$a" "$b" ;;
            tls) [[ -n ${a:-} && -n ${b:-} ]] || tb_die "bad line in $file: $kind $a $b"
                 run_one tls "$a" "$b" "${c:-}" ;;
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
    if (( tls )); then
        run_one tls "$1" "$2" "$tls_days"
    else
        run_one tcp "$1" "$2"
    fi
fi

if (( nagios && failures > 0 )); then
    exit 2
fi
(( failures == 0 ))
