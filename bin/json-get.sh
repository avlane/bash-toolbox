#!/usr/bin/env bash
# json-get.sh - print one value from a JSON document
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: json-get.sh [-r] KEY [FILE]

Print the value at KEY (a jq path such as .name or .server.port) from FILE, or
from standard input when FILE is omitted or "-".

Uses jq when it is installed. Without jq (or with TB_NO_JQ=1) a small bash
fallback is used. The fallback only understands plain object keys, optionally
nested with dots, and prints strings, numbers, true, false and null; it does not
print objects or arrays and it does not handle escaped quotes in strings.
Install jq if you need more.

options:
  -r          raw output: no quotes around strings
  -h, --help  show this help

Exit status (like jq -e): 0 found, 1 missing key, null or false, 2 usage error.
USAGE
}

tb_handle_help usage "$@"

raw=0
while getopts ':rh' opt; do
    case $opt in
        r) raw=1 ;;
        h) usage; exit 0 ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -ge 1 && $# -le 2 ]] || tb_usage_error "expected KEY and optionally FILE"
key=$1
file=${2:--}
[[ $key == .* ]] || key=.$key

# json_fallback JSON PATH - the no-jq implementation, see usage
json_fallback() {
    local json=$1 rest=$2 part re value
    while [[ -n $rest ]]; do
        part=${rest%%.*}
        if [[ $rest == *.* ]]; then rest=${rest#*.}; else rest=''; fi
        [[ $part =~ ^[A-Za-z0-9_-]+$ ]] || tb_die "fallback only supports simple keys, install jq"
        re="\"$part\"[[:space:]]*:[[:space:]]*"
        [[ $json =~ $re ]] || return 1
        json=${json#*"${BASH_REMATCH[0]}"}
    done
    re='^"([^"]*)"'
    if [[ $json =~ $re ]]; then
        value=${BASH_REMATCH[1]}
        if (( raw )); then printf '%s\n' "$value"; else printf '"%s"\n' "$value"; fi
        return 0
    fi
    re='^([^,}[:space:]]+)'
    [[ $json =~ $re ]] || return 1
    value=${BASH_REMATCH[1]}
    case $value in
        '{'*|'['*) tb_die "fallback cannot print objects or arrays, install jq" ;;
        null|false) printf '%s\n' "$value"; return 1 ;;
    esac
    printf '%s\n' "$value"
}

if [[ -z ${TB_NO_JQ:-} ]] && command -v jq >/dev/null 2>&1; then
    args=(-e)
    if (( raw )); then
        args+=(-r)
    fi
    if [[ $file == - ]]; then
        jq "${args[@]}" "$key"
    else
        jq "${args[@]}" "$key" "$file"
    fi
else
    if [[ $file == - ]]; then
        json=$(cat)
    else
        json=$(cat "$file")
    fi
    json_fallback "$json" "${key#.}"
fi
