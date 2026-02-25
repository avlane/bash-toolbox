#!/usr/bin/env bash
# json-get.sh - print one value from a JSON document
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: json-get.sh [-r] [-d DEFAULT] KEY [FILE]

Print the value at KEY (a jq path such as .name or .server.port) from FILE, or
from standard input when FILE is omitted or "-".

Uses jq when it is installed. Without jq (or with TB_NO_JQ=1) a small bash
fallback is used. The fallback understands plain object keys nested with dots,
and an index into an array of plain values (.tags[1]). It prints strings,
numbers, true, false and null; it does not print objects or arrays and cannot
look inside arrays of objects. In strings, escapes such as backslash-n and
backslash-u00e9 are passed through as written; only backslash-quote and a double
backslash are unescaped (with -r).
Install jq if you need more.

options:
  -r          raw output: no quotes around strings
  -d DEFAULT  print DEFAULT and exit 0 when KEY is missing or null
              (false is a real value and is still reported with status 1)
  -h, --help  show this help

Exit status (like jq -e): 0 found, 1 missing key, null or false, 2 usage error.
USAGE
}

tb_handle_help usage "$@"

raw=0
default=
have_default=0
while getopts ':rd:h' opt; do
    case $opt in
        r) raw=1 ;;
        d) default=$OPTARG; have_default=1 ;;
        h) usage; exit 0 ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -ge 1 && $# -le 2 ]] || tb_usage_error "expected KEY and optionally FILE"
key=$1
file=${2:--}
[[ $key == .* ]] || key=.$key

# json_nth ARRAY_TEXT INDEX - print element INDEX of an array of scalars
# ("[1, \"two\", 3]"); the text up to and including the element is all we need
json_nth() {
    local rest=${1#[} want=$2 i=0 re
    re='^[[:space:]]*("[^"]*"|[^,"[:space:]]+)[[:space:]]*([,]|\])'
    while [[ $rest =~ $re ]]; do
        if (( i == want )); then
            printf '%s' "${BASH_REMATCH[1]}"
            return 0
        fi
        rest=${rest#"${BASH_REMATCH[0]}"}
        i=$((i + 1))
    done
    return 1
}

# json_fallback JSON PATH - the no-jq implementation, see usage
json_fallback() {
    local json=$1 rest=$2 part idx re value
    while [[ -n $rest ]]; do
        part=${rest%%.*}
        if [[ $rest == *.* ]]; then rest=${rest#*.}; else rest=''; fi
        idx=
        if [[ $part =~ ^([A-Za-z0-9_-]+)\[([0-9]+)\]$ ]]; then
            part=${BASH_REMATCH[1]}
            idx=${BASH_REMATCH[2]}
        fi
        [[ $part =~ ^[A-Za-z0-9_-]+$ ]] || tb_die "fallback only supports simple keys, install jq"
        re="\"$part\"[[:space:]]*:[[:space:]]*"
        [[ $json =~ $re ]] || return 1
        json=${json#*"${BASH_REMATCH[0]}"}
        if [[ -n $idx ]]; then
            [[ $json == \[* ]] || return 1
            json=$(json_nth "$json" "$idx") || return 1
            [[ -z $rest ]] || tb_die "fallback cannot look inside array elements, install jq"
        fi
    done
    re='^"(([^"\\]|\\.)*)"'
    if [[ $json =~ $re ]]; then
        value=${BASH_REMATCH[1]}
        if (( raw )); then
            # -r: undo the two escapes that matter for the characters that delimit the
            # string. Doubled backslashes go through a placeholder so that \\" is read
            # as backslash + end of string, not as an escaped quote
            local bs=$'\001'
            value=${value//\\\\/$bs}
            value=${value//\\\"/\"}
            value=${value//$bs/\\}
            printf '%s\n' "$value"
        else
            printf '"%s"\n' "$value"
        fi
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

# run_lookup - print the value, return jq -e style status
run_lookup() {
    if [[ -z ${TB_NO_JQ:-} ]] && command -v jq >/dev/null 2>&1; then
        local args=(-e)
        if (( raw )); then
            args+=(-r)
        fi
        if [[ $file == - ]]; then
            jq "${args[@]}" "$key"
        else
            jq "${args[@]}" "$key" "$file"
        fi
    else
        local json
        if [[ $file == - ]]; then
            json=$(cat)
        else
            json=$(cat "$file")
        fi
        json_fallback "$json" "${key#.}"
    fi
}

if (( have_default )); then
    # the output of a null (or no output at all) means "not there"; false is a value
    status=0
    out=$(run_lookup) || status=$?
    if [[ $status -ne 0 && ( -z $out || $out == null ) ]]; then
        printf '%s\n' "$default"
        exit 0
    fi
    [[ -z $out ]] || printf '%s\n' "$out"
    exit "$status"
fi
run_lookup
