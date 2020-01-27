#!/usr/bin/env bash
# backup.sh - tar up a directory into a dated archive
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: backup.sh [-n] [-x PATTERN]... SOURCE_DIR DEST_DIR

Create DEST_DIR/NAME-YYYYmmdd-HHMMSS.tar.gz from SOURCE_DIR. The archive is
written to a temporary file first and renamed, so a failed run never leaves a
half-written archive behind.

options:
  -x PATTERN  exclude paths matching PATTERN (repeatable, passed to tar)
  -n          dry run: say what would be written, change nothing
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

dry=0
excludes=()
while getopts ':x:nh' opt; do
    case $opt in
        x) excludes+=(--exclude "$OPTARG") ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 2 ]] || tb_usage_error "expected SOURCE_DIR and DEST_DIR"

src=${1%/}
dest=$2
[[ -d $src ]] || tb_die "$src is not a directory"

name=$(basename "$src")
archive="$dest/$name-$(date +%Y%m%d-%H%M%S).tar.gz"

if (( dry )); then
    echo "would write $archive"
    exit 0
fi

mkdir -p "$dest"
tmp=$(mktemp "$dest/.backup.XXXXXX")
trap 'rm -f "$tmp"' EXIT

tar -czf "$tmp" ${excludes[@]+"${excludes[@]}"} -C "$(dirname "$src")" "$name"
mv "$tmp" "$archive"
echo "wrote $archive"
