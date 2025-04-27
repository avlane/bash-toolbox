#!/usr/bin/env bash
# backup.sh - tar up a directory into a dated archive
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: backup.sh [-n] [-k COUNT] [-x PATTERN]... [-X FILE] SOURCE_DIR DEST_DIR

Create DEST_DIR/NAME-YYYYmmdd-HHMMSS.tar.gz from SOURCE_DIR, plus a
NAME-...tar.gz.sha256 file with its SHA-256 checksum (verify with
restore-backup.sh, or sha256sum -c / shasum -a 256 -c). The archive is written
to a temporary file first and renamed, so a failed run never leaves a
half-written archive behind.

options:
  -k COUNT    afterwards keep only the newest COUNT archives for this source
  -x PATTERN  exclude paths matching PATTERN (repeatable, passed to tar)
  -X FILE     read exclude patterns from FILE, one per line
  -n          dry run: say what would be written, change nothing
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

dry=0
keep=0
excludes=()
while getopts ':x:X:k:nh' opt; do
    case $opt in
        k) keep=$OPTARG ;;
        x) excludes+=(--exclude "$OPTARG") ;;
        X) [[ -r $OPTARG ]] || tb_die "cannot read exclude file $OPTARG"
           excludes+=(--exclude-from "$OPTARG") ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $keep =~ ^[0-9]+$ ]] || tb_usage_error "-k needs a number"
[[ $# -eq 2 ]] || tb_usage_error "expected SOURCE_DIR and DEST_DIR"

src=${1%/}
dest=$2
[[ -d $src ]] || tb_die "$src is not a directory"
# resolve '.', '..' and relative paths so the archive is named after the real directory
src=$(cd "$src" && pwd -P)
[[ $src != / ]] || tb_die "refusing to back up the root directory"

name=$(basename "$src")
archive="$dest/$name-$(date +%Y%m%d-%H%M%S).tar.gz"

if (( dry )); then
    echo "would write $archive"
    exit 0
fi

mkdir -p "$dest"
tmp=$(mktemp "$dest/.backup.XXXXXX")
trap 'rm -f "$tmp"' EXIT

# GNU tar exits 1 for "file changed as we read it" - the archive is still
# complete enough to keep, so that case is a warning there. bsdtar uses 1 for
# real errors, so it is never excused.
rc=0
tar -czf "$tmp" ${excludes[@]+"${excludes[@]}"} -C "$(dirname "$src")" "$name" || rc=$?
if (( rc == 1 )) && tar --version 2>&1 | grep -q 'GNU tar'; then
    tb_warn "some files changed while they were being archived"
elif (( rc != 0 )); then
    tb_die "tar failed with status $rc"
fi

# read the whole archive back before trusting it: this catches a truncated or
# corrupt gzip stream (a full disk, for example) while the source still exists
tar -tzf "$tmp" >/dev/null 2>&1 || tb_die "the new archive cannot be read back, not keeping it"
mv "$tmp" "$archive"
tb_sha256 "$archive" > "$archive.sha256"
echo "wrote $archive"

tb_prune_newest "$keep" "$dest" "$name" .tar.gz
