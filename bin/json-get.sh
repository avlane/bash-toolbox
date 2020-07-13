#!/usr/bin/env bash
# json-get.sh - print one value from a JSON document
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: json-get.sh [-r] KEY [FILE]

Print the value at KEY (a jq path such as .name or .server.port) from FILE, or
from standard input when FILE is omitted or "-". Uses jq.

options:
  -r          raw output: no quotes around strings
  -h, --help  show this help

Exit status: 0 found, 1 missing key or unreadable input, 2 usage error.
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

tb_require_cmd jq

args=(-e)
if (( raw )); then
    args+=(-r)
fi
if [[ $file == - ]]; then
    jq "${args[@]}" "$key"
else
    jq "${args[@]}" "$key" "$file"
fi
